use crate::emitter::EmitResult;
use serde_json::{Value, Map, json};
use sha2::{Sha256, Digest};
use std::fs;
use std::path::Path;

pub struct Assembler;

impl Assembler {
    pub fn new() -> Self {
        Self
    }

    pub fn assemble(&self, emit_result: &EmitResult, target_dir: &str) -> std::io::Result<Value> {
        let report = &emit_result.compilation_report;
        let semantic_ir = emit_result.semantic_ir.as_ref().expect("Cannot assemble a failed compilation");

        let contracts_ir = semantic_ir.get("contracts").and_then(|c| c.as_array()).expect("semantic_ir lacks contracts");

        let mut contracts = Vec::new();
        let mut contract_ids = Vec::new();
        for c_ir in contracts_ir {
            let modifier = c_ir.get("modifier").and_then(|m| m.as_str()).unwrap_or("pure");
            if modifier == "privileged" {
                let name = c_ir.get("contract_name").and_then(|n| n.as_str()).unwrap_or("");
                let has_token = if let Some(tokens) = semantic_ir.get("capability_tokens").and_then(|t| t.as_array()) {
                    tokens.iter().any(|t| t.as_str() == Some(name))
                } else {
                    false
                };
                if !has_token {
                    return Err(std::io::Error::new(
                        std::io::ErrorKind::InvalidData,
                        format!("OOF-M1: privileged contract '{}' requires matching capability token in manifest", name)
                    ));
                }
            }
            let contract = self.contract_file(c_ir);
            contract_ids.push(contract.get("contract_id").and_then(|id| id.as_str()).unwrap().to_string());
            contracts.push(contract);
        }
        contract_ids.sort();

        let fragment_classes: Vec<String> = contracts.iter()
            .map(|c| c.get("fragment_class").and_then(|f| f.as_str()).unwrap().to_string())
            .collect();
        let fragment_class = if fragment_classes.is_empty() {
            "core".to_string()
        } else {
            let unique: std::collections::HashSet<String> = fragment_classes.iter().cloned().collect();
            if unique.len() == 1 {
                fragment_classes[0].clone()
            } else {
                "mixed".to_string()
            }
        };

        let requirements = self.requirements_for(semantic_ir);
        let classified_ast = self.classified_ast_for(report, semantic_ir, &contract_ids, &fragment_class);
        let diagnostics = json!({ "diagnostics": report.get("diagnostics").cloned().unwrap_or(Value::Array(Vec::new())) });
        let compatibility_metadata = self.compatibility_metadata_for(report, semantic_ir);
        let entrypoint = self.manifest_entrypoint_for(semantic_ir, &contracts);

        let mut artifact_material = Map::new();
        artifact_material.insert("semantic_ir_program".to_string(), semantic_ir.clone());
        artifact_material.insert("contracts".to_string(), json!(contracts));
        artifact_material.insert("compilation_report".to_string(), report.clone());
        artifact_material.insert("requirements".to_string(), requirements.clone());
        artifact_material.insert("diagnostics".to_string(), diagnostics.clone());
        artifact_material.insert("classified_ast".to_string(), classified_ast.clone());
        artifact_material.insert("compatibility_metadata".to_string(), compatibility_metadata.clone());
        if let Some(ep) = &entrypoint {
            artifact_material.insert("entrypoint".to_string(), ep.clone());
        }

        // Sort keys and generate SHA256 canonical hash
        let artifact_hash = self.canonical_hash(&Value::Object(artifact_material));

        // Merge artifact_hash into all contracts
        let mut updated_contracts = Vec::new();
        for mut c in contracts {
            if let Some(obj) = c.as_object_mut() {
                obj.insert("artifact_hash".to_string(), Value::String(artifact_hash.clone()));
            }
            updated_contracts.push(c);
        }

        let fragment_summary = self.fragment_summary_for(&updated_contracts);
        let contract_index = self.contract_index_for(&updated_contracts);

        let mut all_capabilities = Vec::new();
        let mut all_effects = Vec::new();
        for c_ir in contracts_ir {
            if let Some(caps) = c_ir.get("capabilities").and_then(|c| c.as_array()) {
                all_capabilities.extend(caps.clone());
            }
            if let Some(effs) = c_ir.get("effects").and_then(|e| e.as_array()) {
                all_effects.extend(effs.clone());
            }
        }

        let mut manifest = Map::new();
        manifest.insert("capabilities".to_string(), Value::Array(all_capabilities));
        manifest.insert("effects".to_string(), Value::Array(all_effects));
        manifest.insert("kind".to_string(), Value::String("igapp_manifest".to_string()));
        manifest.insert("format_version".to_string(), Value::String("0.1.0".to_string()));
        manifest.insert("format".to_string(), Value::String("igapp_dir".to_string()));
        manifest.insert("program_id".to_string(), semantic_ir.get("program_id").cloned().unwrap_or(Value::Null));
        manifest.insert("artifact_hash".to_string(), Value::String(artifact_hash.clone()));
        manifest.insert("language_version".to_string(), semantic_ir.get("format_version").cloned().unwrap_or(Value::Null));
        manifest.insert("grammar_version".to_string(), semantic_ir.get("grammar_version").cloned().unwrap_or(Value::Null));
        manifest.insert("schema_version".to_string(), Value::String("0.1.0".to_string()));
        manifest.insert("compiled_at".to_string(), Value::String("2026-05-06T00:00:00Z".to_string()));
        manifest.insert("assembler".to_string(), Value::String("igapp-assembler-proof-stage1-v0".to_string()));
        manifest.insert("semantic_ir_ref".to_string(), report.get("semantic_ir_ref").cloned().unwrap_or(Value::Null));
        manifest.insert("compilation_report_ref".to_string(), semantic_ir.get("compilation_report_ref").cloned().unwrap_or(Value::Null));
        manifest.insert("source_hash".to_string(), semantic_ir.get("source_hash").cloned().unwrap_or(Value::Null));
        manifest.insert("source_path".to_string(), semantic_ir.get("source_path").cloned().unwrap_or(Value::Null));
        if let Some(source_units) = semantic_ir.get("source_units") {
            manifest.insert("source_units".to_string(), source_units.clone());
        }
        manifest.insert("contracts".to_string(), json!(contract_ids));

        let mut contract_refs = Map::new();
        for c_ir in contracts_ir {
            let name = c_ir.get("contract_name").and_then(|n| n.as_str()).unwrap().to_string();
            let r = c_ir.get("contract_ref").cloned().unwrap_or(Value::Null);
            contract_refs.insert(name, r);
        }
        manifest.insert("contract_refs".to_string(), Value::Object(contract_refs));
        manifest.insert("fragment_class".to_string(), Value::String(fragment_class));
        manifest.insert("fragment_summary".to_string(), fragment_summary);
        manifest.insert("contract_index".to_string(), contract_index);
        if let Some(ep) = entrypoint {
            manifest.insert("entrypoint".to_string(), ep);
        }
        manifest.insert("schema_descriptor".to_string(), json!({ "trait_bounds": [], "migrations": [] }));
        manifest.insert("warnings".to_string(), Value::Array(Vec::new()));
        manifest.insert("diagnostics".to_string(), report.get("diagnostics").cloned().unwrap_or(Value::Array(Vec::new())));

        // Write files to target_dir
        let base_path = Path::new(target_dir);
        fs::create_dir_all(base_path.join("contracts"))?;

        let module_name = semantic_ir.get("module").and_then(|m| m.as_str()).unwrap_or("");
        let mut specs = Vec::new();
        if let Some(contracts_arr) = semantic_ir.get("contracts").and_then(|c| c.as_array()) {
            for c in contracts_arr {
                if let Some(spec_of) = c.get("specialization_of").and_then(|s| s.as_str()) {
                    let qualified_spec_of = if module_name.is_empty() {
                        spec_of.to_string()
                    } else {
                        format!("{}.{}", module_name, spec_of)
                    };
                    let type_args = c.get("type_args").cloned().unwrap_or(Value::Object(Map::new()));
                    let contract_id = c.get("contract_name").cloned().unwrap_or(Value::Null);
                    let mut spec_item = Map::new();
                    spec_item.insert("template_contract_id".to_string(), Value::String(qualified_spec_of));
                    spec_item.insert("type_args".to_string(), type_args);
                    spec_item.insert("emitted_contract_id".to_string(), contract_id);
                    specs.push(Value::Object(spec_item));
                }
            }
        }

        let mut classified_ast_to_write = classified_ast.clone();

        if !specs.is_empty() {
            let mut spec_manifest = Map::new();
            spec_manifest.insert("kind".to_string(), Value::String("specialization_manifest".to_string()));
            spec_manifest.insert("specializations".to_string(), Value::Array(specs.clone()));
            self.write_json_pretty(&base_path.join("specialization_manifest.json"), &Value::Object(spec_manifest))?;

            let mut template_ids: Vec<String> = specs.iter().map(|s| {
                s.get("template_contract_id").and_then(|t| t.as_str()).unwrap_or("").to_string()
            }).filter(|s| !s.is_empty()).collect();
            template_ids.sort();
            template_ids.dedup();

            manifest.insert("specialization_manifest_ref".to_string(), Value::String("specialization_manifest.json".to_string()));
            manifest.insert("metadata_only_templates".to_string(), Value::Array(
                template_ids.iter().map(|id| Value::String(id.clone())).collect()
            ));

            let mut classified_ast_mut = classified_ast.as_object().unwrap().clone();
            let generic_templates: Vec<Value> = template_ids.iter().map(|id| {
                json!({
                    "template_contract_id": id,
                    "loadable": false
                })
            }).collect();
            classified_ast_mut.insert("generic_templates".to_string(), Value::Array(generic_templates));
            classified_ast_to_write = Value::Object(classified_ast_mut);
        }

        if let Some(tokens) = semantic_ir.get("capability_tokens") {
            manifest.insert("capability_tokens".to_string(), tokens.clone());
        }

        // LAB-SRCMAP-P1: write sourcemap sidecar if available
        if let Some(sm) = &emit_result.source_map {
            self.write_json_pretty(&base_path.join("sourcemap.json"), sm)?;
            manifest.insert("sourcemap_ref".to_string(), Value::String("sourcemap.json".to_string()));
        }

        self.write_json_pretty(&base_path.join("manifest.json"), &Value::Object(manifest.clone()))?;
        self.write_json_pretty(&base_path.join("semantic_ir_program.json"), semantic_ir)?;
        self.write_json_pretty(&base_path.join("compilation_report.json"), report)?;
        self.write_json_pretty(&base_path.join("requirements.json"), &requirements)?;
        self.write_json_pretty(&base_path.join("diagnostics.json"), &diagnostics)?;
        self.write_json_pretty(&base_path.join("classified_ast.json"), &classified_ast_to_write)?;
        self.write_json_pretty(&base_path.join("projections.json"), &json!({ "projections": [] }))?;
        self.write_json_pretty(&base_path.join("compatibility_metadata.json"), &compatibility_metadata)?;

        // Emit passport.json sidecar if capabilities are declared (P7)
        if let Some(caps) = manifest.get("capabilities").and_then(|c| c.as_array()) {
            if !caps.is_empty() {
                let mut required_caps = Map::new();
                let mut capability_bindings = Map::new();
                let effects_arr = manifest.get("effects").and_then(|e| e.as_array());
                
                for cap in caps {
                    if let Some(cap_name) = cap.get("name").and_then(|n| n.as_str()) {
                        let mut cap_info = Map::new();
                        // Explicit sandbox policy source proof_default metadata
                        cap_info.insert("sandbox_dir".to_string(), Value::String("out/sandbox/sub".to_string()));
                        cap_info.insert("allowed_absolute_paths".to_string(), Value::Array(Vec::new()));
                        cap_info.insert("sandbox_policy_source".to_string(), Value::String("proof_default".to_string()));
                        
                        let mut read_allowed = false;
                        let mut write_allowed = false;
                        
                        if let Some(effs) = effects_arr {
                            for eff in effs {
                                if eff.get("capability_ref").and_then(|r| r.as_str()) == Some(cap_name) {
                                    if let Some(eff_name) = eff.get("name").and_then(|n| n.as_str()) {
                                        match eff_name {
                                            "read_file" | "read_json" | "read" => {
                                                read_allowed = true;
                                            }
                                            "write_file" | "write_json" | "write" => {
                                                write_allowed = true;
                                                read_allowed = true; // Writing capability implies read
                                            }
                                            _ => {}
                                        }
                                    }
                                }
                            }
                        }
                        
                        cap_info.insert("read_allowed".to_string(), Value::Bool(read_allowed));
                        cap_info.insert("write_allowed".to_string(), Value::Bool(write_allowed));
                        required_caps.insert(cap_name.to_string(), Value::Object(cap_info));
                        
                        // Explicit capability parameter mapping
                        capability_bindings.insert(cap_name.to_string(), Value::String(cap_name.to_string()));
                    }
                }
                
                let mut passport = Map::new();
                passport.insert("runtime_implementation_id".to_string(), Value::String("igniter.delegated.experimental.io.delegation.v0".to_string()));
                passport.insert("backend_implementation_id".to_string(), Value::String("none".to_string()));
                passport.insert("consumer_surface_id".to_string(), Value::String("igniter-lab".to_string()));
                passport.insert("surface_dimension".to_string(), Value::String("runtime".to_string()));
                passport.insert("artifact_kind".to_string(), Value::String("igapp_dir".to_string()));
                passport.insert("artifact_digest".to_string(), Value::String(artifact_hash.clone()));
                passport.insert("required_capabilities".to_string(), Value::Object(required_caps));
                passport.insert("capability_bindings".to_string(), Value::Object(capability_bindings));
                
                self.write_json_pretty(&base_path.join("passport.json"), &Value::Object(passport))?;
            }
        }

        // Form artifacts
        if let Some(form_table) = &emit_result.form_table {
            self.write_json_pretty(&base_path.join("form_table.json"), form_table)?;
        }
        if let Some(resolved) = &emit_result.resolved_program {
            self.write_json_pretty(&base_path.join("form_resolution_trace.json"), resolved)?;
        }

        for contract in &updated_contracts {
            let cid = contract.get("contract_id").and_then(|id| id.as_str()).unwrap();
            let c_filename = format!("{}.json", self.snake_case(cid));
            self.write_json_pretty(&base_path.join("contracts").join(c_filename), contract)?;
        }

        Ok(Value::Object(manifest))
    }

    fn write_json_pretty(&self, path: &Path, value: &Value) -> std::io::Result<()> {
        let content = serde_json::to_string_pretty(value)?;
        fs::write(path, content + "\n")
    }

    fn contract_file(&self, contract_ir: &Value) -> Value {
        let contract_id = contract_ir.get("contract_name").and_then(|n| n.as_str()).unwrap().to_string();
        let inputs = contract_ir.get("inputs").and_then(|i| i.as_array()).unwrap();
        let outputs = contract_ir.get("outputs").and_then(|o| o.as_array()).unwrap();
        let semantic_nodes = contract_ir.get("nodes").and_then(|n| n.as_array()).unwrap();

        let mut input_ports = Vec::new();
        for port in inputs {
            input_ports.push(json!({
                "name": port.get("name").unwrap(),
                "type_tag": self.type_name(port.get("type").unwrap()),
                "lifecycle": port.get("lifecycle").unwrap(),
                "required": true
            }));
        }

        let mut output_ports = Vec::new();
        for port in outputs {
            output_ports.push(json!({
                "name": port.get("name").unwrap(),
                "type_tag": self.type_name(port.get("type").unwrap()),
                "lifecycle": port.get("lifecycle").unwrap(),
                "required": true
            }));
        }

        let mut compute_nodes = Vec::new();
        let mut temporal_nodes = Vec::new();
        let mut stream_nodes = Vec::new();

        for node in semantic_nodes {
            let kind = node.get("kind").and_then(|k| k.as_str()).unwrap_or_default();
            if self.is_compute_node(node) || kind == "loop" || kind == "service_loop_node" {
                compute_nodes.push(self.assemble_compute_node(node));
            } else if self.is_temporal_node(node) {
                temporal_nodes.push(self.temporal_node_file(node));
            } else if self.is_stream_node(node) {
                stream_nodes.push(self.stream_node_file(node));
            }
        }

        let mut result = Map::new();
        result.insert("contract_id".to_string(), Value::String(contract_id.clone()));
        result.insert("source_contract_ref".to_string(), contract_ir.get("contract_ref").cloned().unwrap_or(Value::Null));
        result.insert("name".to_string(), Value::String(contract_id.clone()));
        result.insert("fragment_class".to_string(), contract_ir.get("fragment_class").cloned().unwrap_or(Value::Null));
        result.insert("modifier".to_string(), contract_ir.get("modifier").cloned().unwrap_or(Value::String("pure".to_string())));
        result.insert("escape_set".to_string(), contract_ir.get("escape_boundaries").cloned().unwrap_or(Value::Array(Vec::new())));
        result.insert("capabilities".to_string(), contract_ir.get("capabilities").cloned().unwrap_or(Value::Array(Vec::new())));
        result.insert("effects".to_string(), contract_ir.get("effects").cloned().unwrap_or(Value::Array(Vec::new())));
        result.insert("lifecycle".to_string(), Value::String("session".to_string()));
        result.insert("input_ports".to_string(), Value::Array(input_ports.clone()));
        result.insert("output_ports".to_string(), Value::Array(output_ports.clone()));
        result.insert("compute_nodes".to_string(), Value::Array(compute_nodes));
        
        let type_signature = json!({
            "inputs": input_ports.iter().map(|p| (p.get("name").unwrap().as_str().unwrap().to_string(), p.get("type_tag").unwrap().clone())).collect::<Map<String, Value>>(),
            "outputs": output_ports.iter().map(|p| (p.get("name").unwrap().as_str().unwrap().to_string(), p.get("type_tag").unwrap().clone())).collect::<Map<String, Value>>()
        });
        result.insert("type_signature".to_string(), type_signature);

        if !temporal_nodes.is_empty() {
            result.insert("temporal_nodes".to_string(), Value::Array(temporal_nodes));
        }
        if !stream_nodes.is_empty() {
            result.insert("stream_nodes".to_string(), Value::Array(stream_nodes));
        }

        Value::Object(result)
    }

    fn manifest_entrypoint_for(&self, semantic_ir: &Value, contracts: &[Value]) -> Option<Value> {
        let entrypoint = semantic_ir.get("entrypoint")?;
        let resolved = entrypoint.get("resolved_contract").and_then(|v| v.as_str()).unwrap_or_default();
        let resolved_id = entrypoint.get("resolved_contract_id").and_then(|v| v.as_str()).unwrap_or_default();
        let contract = contracts.iter().find(|c| {
            c.get("contract_id").and_then(|v| v.as_str()) == Some(resolved) ||
                c.get("contract_id").and_then(|v| v.as_str()) == Some(resolved_id)
        });

        let mut result = Map::new();
        result.insert("kind".to_string(), Value::String("default_entrypoint".to_string()));
        result.insert(
            "declared_target".to_string(),
            entrypoint.get("declared_target")
                .or_else(|| entrypoint.get("target"))
                .cloned()
                .unwrap_or(Value::String(String::new())),
        );
        result.insert(
            "resolved_contract".to_string(),
            entrypoint.get("resolved_contract").cloned().unwrap_or(Value::String(String::new())),
        );
        result.insert("source_span".to_string(), json!({
            "source_path": semantic_ir.get("source_path").cloned().unwrap_or(Value::Null),
            "line": entrypoint.get("source_span").and_then(|s| s.get("line")).cloned().unwrap_or(Value::Null),
            "col": entrypoint.get("source_span").and_then(|s| s.get("col")).cloned().unwrap_or(Value::Null)
        }));

        if let Some(c) = contract {
            if let Some(cref) = c.get("source_contract_ref") {
                result.insert("contract_ref".to_string(), cref.clone());
            }
            if let Some(cid) = c.get("contract_id").and_then(|v| v.as_str()) {
                result.insert("contract_path".to_string(), Value::String(format!("contracts/{}.json", self.snake_case(cid))));
            }
        }

        Some(Value::Object(result))
    }

    fn is_compute_node(&self, node: &Value) -> bool {
        node.get("expr").is_some() && node.get("type").is_some()
    }

    fn assemble_compute_node(&self, node: &Value) -> Value {
        let name = node.get("name").unwrap().as_str().unwrap();
        let kind = node.get("kind").and_then(|k| k.as_str()).unwrap_or("compute");
        
        let mut assembled = Map::new();
        assembled.insert("node_id".to_string(), json!(format!("node_{}", name)));
        assembled.insert("name".to_string(), json!(name));
        assembled.insert("kind".to_string(), json!(kind));
        assembled.insert("fragment_class".to_string(), node.get("fragment").or_else(|| node.get("fragment_class")).cloned().unwrap_or(json!("core")));
        
        if let Some(t) = node.get("type").or_else(|| node.get("type_tag")) {
            assembled.insert("type_tag".to_string(), json!(self.type_name(t)));
        }
        assembled.insert("lifecycle".to_string(), json!("session"));
        assembled.insert("obs_kind".to_string(), json!("value_observation"));
        
        if let Some(deps) = node.get("deps").or_else(|| node.get("dependencies")) {
            if let Some(deps_arr) = deps.as_array() {
                let formatted_deps: Vec<String> = deps_arr.iter()
                    .map(|dep| {
                        let s = dep.as_str().unwrap();
                        if s.starts_with("input:") {
                            s.to_string()
                        } else {
                            format!("input:{}", s)
                        }
                    })
                    .collect();
                assembled.insert("dependencies".to_string(), json!(formatted_deps));
            }
        }

        // For loops, we have expr or expression.
        if let Some(expr) = node.get("expr").or_else(|| node.get("expression")) {
            assembled.insert("expr".to_string(), self.compat_expr(expr));
            assembled.insert("expression".to_string(), self.compat_expr(expr));
        }

        if kind == "loop" {
            if let Some(options) = node.get("options") {
                assembled.insert("options".to_string(), options.clone());
            }
            if let Some(body) = node.get("body_nodes") {
                if let Some(body_arr) = body.as_array() {
                    let assembled_body: Vec<Value> = body_arr.iter()
                        .map(|inner| self.assemble_compute_node(inner))
                        .collect();
                    assembled.insert("body_nodes".to_string(), json!(assembled_body));
                }
            }
        } else if kind == "service_loop_node" {
            if let Some(interval) = node.get("interval") {
                assembled.insert("interval".to_string(), interval.clone());
            }
            if let Some(temp_bind) = node.get("temporal_binding") {
                assembled.insert("temporal_binding".to_string(), temp_bind.clone());
            }
            if let Some(body) = node.get("body_nodes") {
                if let Some(body_arr) = body.as_array() {
                    let assembled_body: Vec<Value> = body_arr.iter()
                        .map(|inner| self.assemble_compute_node(inner))
                        .collect();
                    assembled.insert("body_nodes".to_string(), json!(assembled_body));
                }
            }
        }

        Value::Object(assembled)
    }

    fn is_temporal_node(&self, node: &Value) -> bool {
        let kind = node.get("kind").and_then(|k| k.as_str()).unwrap_or_default();
        kind == "temporal_input_node" || kind == "temporal_access_node"
    }

    fn is_stream_node(&self, node: &Value) -> bool {
        let kind = node.get("kind").and_then(|k| k.as_str()).unwrap_or_default();
        kind == "stream_input_node" || kind == "window_decl_node" || kind == "fold_stream_node"
    }

    fn temporal_node_file(&self, node: &Value) -> Value {
        let name = node.get("name").and_then(|n| n.as_str()).unwrap_or_default();
        let kind = node.get("kind").and_then(|k| k.as_str()).unwrap_or_default();
        let obs_kind = if kind == "temporal_input_node" { "temporal_source_observation" } else { "temporal_access_observation" };
        
        let mut m = Map::new();
        m.insert("node_id".to_string(), Value::String(format!("node_{}", name)));
        m.insert("name".to_string(), Value::String(name.to_string()));
        m.insert("kind".to_string(), Value::String(kind.to_string()));
        
        let fc = node.get("fragment")
            .or_else(|| node.get("node_fragment_class"))
            .cloned()
            .unwrap_or_else(|| Value::String("temporal".to_string()));
        m.insert("fragment_class".to_string(), fc);
        m.insert("node_fragment_class".to_string(), node.get("node_fragment_class").cloned().unwrap_or(Value::Null));
        m.insert("value_fragment_class".to_string(), node.get("value_fragment_class").cloned().unwrap_or(Value::Null));
        m.insert("lifecycle".to_string(), node.get("lifecycle").cloned().unwrap_or_else(|| Value::String("session".to_string())));
        m.insert("obs_kind".to_string(), Value::String(obs_kind.to_string()));

        let deps = node.get("deps").and_then(|d| d.as_array());
        let dep_vals = if let Some(arr) = deps {
            arr.iter().map(|dep| Value::String(format!("input:{}", dep.as_str().unwrap()))).collect()
        } else {
            Vec::new()
        };
        m.insert("dependencies".to_string(), Value::Array(dep_vals));
        m.insert("required_capability".to_string(), node.get("required_capability").cloned().unwrap_or(Value::Null));
        m.insert("required_caps".to_string(), node.get("required_caps").cloned().or_else(|| node.get("required_capability").map(|r| json!(vec![r]))).unwrap_or(Value::Null));
        m.insert("axis".to_string(), node.get("axis").or_else(|| node.get("temporal_axis")).cloned().unwrap_or(Value::Null));

        if let Some(t) = node.get("type") {
            m.insert("type_tag".to_string(), Value::String(self.type_name(t)));
        }
        if let Some(rt) = node.get("result_type") {
            m.insert("result_type_tag".to_string(), Value::String(self.type_name(rt)));
        }
        if let Some(s) = node.get("store_ref") {
            m.insert("store_ref".to_string(), s.clone());
        }
        if let Some(s) = node.get("source_ref") {
            m.insert("source_ref".to_string(), s.clone());
        }
        if let Some(a) = node.get("temporal_axis") {
            m.insert("temporal_axis".to_string(), a.clone());
        }
        if let Some(c) = node.get("coordinate_refs") {
            m.insert("coordinate_refs".to_string(), c.clone());
        }
        if let Some(a) = node.get("as_of_ref") {
            m.insert("as_of_ref".to_string(), a.clone());
        }
        if let Some(v) = node.get("valid_time_ref") {
            m.insert("valid_time_ref".to_string(), v.clone());
        }
        if let Some(t) = node.get("transaction_time_ref") {
            m.insert("transaction_time_ref".to_string(), t.clone());
        }
        if let Some(e) = node.get("evidence_policy") {
            m.insert("evidence_policy".to_string(), e.clone());
        }

        Value::Object(m)
    }

    fn stream_node_file(&self, node: &Value) -> Value {
        let name = node.get("name").or_else(|| node.get("ref")).and_then(|n| n.as_str()).unwrap_or_default();
        let kind = node.get("kind").and_then(|k| k.as_str()).unwrap_or_default();
        let obs_kind = if kind == "window_decl_node" { "stream_window_observation" } else { "stream_replay_metadata" };

        let mut m = Map::new();
        m.insert("node_id".to_string(), Value::String(format!("node_{}", name)));
        m.insert("name".to_string(), Value::String(name.to_string()));
        m.insert("kind".to_string(), Value::String(kind.to_string()));
        
        let fc = node.get("fragment")
            .or_else(|| node.get("result_fragment"))
            .cloned()
            .unwrap_or_else(|| Value::String("stream".to_string()));
        m.insert("fragment_class".to_string(), fc);
        m.insert("lifecycle".to_string(), Value::String("window".to_string()));
        m.insert("obs_kind".to_string(), Value::String(obs_kind.to_string()));

        let deps = node.get("deps").and_then(|d| d.as_array());
        let dep_vals = if let Some(arr) = deps {
            arr.iter().map(|dep| Value::String(format!("input:{}", dep.as_str().unwrap()))).collect()
        } else {
            Vec::new()
        };
        m.insert("dependencies".to_string(), Value::Array(dep_vals));

        if let Some(t) = node.get("type") {
            m.insert("type_tag".to_string(), Value::String(self.type_name(t)));
        }
        if let Some(rt) = node.get("result_type") {
            m.insert("result_type_tag".to_string(), Value::String(self.type_name(rt)));
        }

        let keys = vec![
            "window_ref", "ref", "key", "window_kind", "bounded", "size", "period", "idle", "on_close",
            "stream_ref", "init", "fn_ref", "bound", "event_binding", "escape_capability", "result_fragment"
        ];
        for k in keys {
            if let Some(v) = node.get(k) {
                m.insert(k.to_string(), v.clone());
            }
        }

        Value::Object(m)
    }

    fn fragment_summary_for(&self, contracts: &[Value]) -> Value {
        let mut fragment_classes: Vec<String> = contracts.iter()
            .map(|c| c.get("fragment_class").and_then(|f| f.as_str()).unwrap().to_string())
            .collect();
        fragment_classes.sort();
        fragment_classes.dedup();

        let max = self.max_fragment_class(&fragment_classes);
        json!({
            "fragment_classes": fragment_classes,
            "max_fragment_class": max,
            "precedence_high_to_low": self.fragment_precedence()
        })
    }

    fn max_fragment_class(&self, classes: &[String]) -> String {
        for precedence in self.fragment_precedence() {
            if classes.contains(&precedence) {
                return precedence;
            }
        }
        "core".to_string()
    }

    fn fragment_precedence(&self) -> Vec<String> {
        vec![
            "oof".to_string(),
            "temporal".to_string(),
            "stream".to_string(),
            "escape".to_string(),
            "core".to_string()
        ]
    }

    fn contract_index_for(&self, contracts: &[Value]) -> Value {
        let mut sorted = contracts.to_vec();
        sorted.sort_by_key(|c| c.get("contract_id").and_then(|id| id.as_str()).unwrap().to_string());

        let mut index = Map::new();
        for c in sorted {
            let cid = c.get("contract_id").and_then(|id| id.as_str()).unwrap().to_string();
            let mut entry = Map::new();
            entry.insert("contract_ref".to_string(), c.get("source_contract_ref").cloned().unwrap_or(Value::Null));
            entry.insert("contract_path".to_string(), Value::String(format!("contracts/{}.json", self.snake_case(&cid))));
            
            let fc = c.get("fragment_class").and_then(|f| f.as_str()).unwrap().to_string();
            entry.insert("fragment_class".to_string(), Value::String(fc.clone()));

            if fc == "temporal" {
                entry.insert("temporal".to_string(), self.temporal_contract_index(&c));
            }
            index.insert(cid, Value::Object(entry));
        }
        Value::Object(index)
    }

    fn temporal_contract_index(&self, contract: &Value) -> Value {
        let temporal_nodes = contract.get("temporal_nodes").and_then(|t| t.as_array());
        let mut access_nodes = Vec::new();
        if let Some(nodes) = temporal_nodes {
            for node in nodes {
                if node.get("kind").and_then(|k| k.as_str()) == Some("temporal_access_node") {
                    access_nodes.push(node.clone());
                }
            }
        }

        let mut coordinates = Vec::new();
        for node in &access_nodes {
            coordinates.extend(self.temporal_coordinates_for(contract, node));
        }

        let mut axes: Vec<String> = coordinates.iter()
            .map(|c| c.get("axis").unwrap().as_str().unwrap().to_string())
            .collect();
        axes.sort();
        axes.dedup();

        let mut required_caps = Vec::new();
        if let Some(escapes) = contract.get("escape_set").and_then(|e| e.as_array()) {
            for esc in escapes {
                if let Some(arr) = esc.get("required_caps").and_then(|a| a.as_array()) {
                    for cap in arr {
                        required_caps.push(cap.as_str().unwrap().to_string());
                    }
                }
            }
        }
        if let Some(nodes) = temporal_nodes {
            for node in nodes {
                if let Some(arr) = node.get("required_caps").and_then(|a| a.as_array()) {
                    for cap in arr {
                        required_caps.push(cap.as_str().unwrap().to_string());
                    }
                }
            }
        }
        required_caps.sort();
        required_caps.dedup();

        let mut hint_axes: Vec<String> = access_nodes.iter()
            .filter_map(|node| node.get("axis").or_else(|| node.get("temporal_axis")).and_then(|a| a.as_str()).map(|s| s.to_string()))
            .collect();
        hint_axes.sort();
        hint_axes.dedup();
        let hint_axis = if hint_axes.len() == 1 { hint_axes[0].clone() } else { "mixed".to_string() };

        let coordinate_names: Vec<String> = coordinates.iter()
            .map(|coord| coord.get("name").unwrap().as_str().unwrap().to_string())
            .collect();

        json!({
            "axes": axes,
            "required_capabilities": required_caps,
            "coordinates": coordinates,
            "cache_key_schema_hint": {
                "schema": "runtime-cache-key-v1",
                "fragment": "TEMPORAL",
                "axis": hint_axis,
                "coordinate_names": coordinate_names
            }
        })
    }

    fn temporal_coordinates_for(&self, contract: &Value, access_node: &Value) -> Vec<Value> {
        let mut coords = Vec::new();
        if let Some(refs) = access_node.get("coordinate_refs").and_then(|c| c.as_object()) {
            for (axis_name, input_name_val) in refs {
                let input_name = input_name_val.as_str().unwrap();
                let axis = self.coordinate_axis(access_node, axis_name);
                coords.push(json!({
                    "name": input_name,
                    "axis": axis,
                    "source_ref": format!("input:{}", input_name),
                    "type": self.input_type(contract, input_name)
                }));
            }
        }
        coords.sort_by_key(|c| c.get("axis").unwrap().as_str().unwrap().to_string());
        coords
    }

    fn coordinate_axis(&self, access_node: &Value, axis_name: &str) -> String {
        let access_axis = access_node.get("axis").or_else(|| access_node.get("temporal_axis")).and_then(|a| a.as_str()).unwrap_or("valid_time");
        if access_axis == "bitemporal" {
            axis_name.to_string()
        } else {
            access_axis.to_string()
        }
    }

    fn input_type(&self, contract: &Value, input_name: &str) -> String {
        if let Some(inputs) = contract.get("input_ports").and_then(|i| i.as_array()) {
            for input in inputs {
                if input.get("name").and_then(|n| n.as_str()) == Some(input_name) {
                    return input.get("type_tag").and_then(|t| t.as_str()).unwrap_or("Unknown").to_string();
                }
            }
        }
        "Unknown".to_string()
    }

    fn compat_expr(&self, expr: &Value) -> Value {
        if let Some(map) = expr.as_object() {
            let kind = map.get("kind").and_then(|k| k.as_str()).unwrap_or_default();
            match kind {
                "call" => {
                    let operands = map.get("args").and_then(|args| args.as_array()).unwrap()
                        .iter().map(|arg| self.compat_expr(arg)).collect::<Vec<Value>>();
                    json!({
                        "kind": "apply",
                        "operator": map.get("fn").unwrap(),
                        "operands": operands
                    })
                }
                "ref" => {
                    json!({
                        "kind": "ref",
                        "name": map.get("name").unwrap()
                    })
                }
                "literal" => {
                    json!({
                        "kind": "literal",
                        "value": map.get("value").unwrap(),
                        "type_tag": self.type_name(map.get("resolved_type").or_else(|| map.get("type_tag")).unwrap_or(&Value::String("Unknown".to_string())))
                    })
                }
                "field_access" => {
                    json!({
                        "kind": "field_access",
                        "object": self.compat_expr(map.get("object").unwrap()),
                        "field": map.get("field").unwrap(),
                        "type_tag": self.type_name(map.get("resolved_type").or_else(|| map.get("type_tag")).unwrap_or(&Value::String("Unknown".to_string())))
                    })
                }
                _ => expr.clone()
            }
        } else {
            expr.clone()
        }
    }

    fn type_name(&self, type_val: &Value) -> String {
        if let Some(s) = type_val.as_str() {
            return s.to_string();
        }
        if let Some(map) = type_val.as_object() {
            if let Some(constructor) = map.get("constructor").and_then(|c| c.as_str()) {
                if let Some(element) = map.get("element_type") {
                    return format!("{}[{}]", constructor, self.type_name(element));
                }
                return constructor.to_string();
            }
            if let Some(name) = map.get("name").and_then(|n| n.as_str()) {
                let params = map.get("params").and_then(|p| p.as_array());
                if let Some(params) = params {
                    if params.is_empty() {
                        return name.to_string();
                    }
                    let p_names: Vec<String> = params.iter().map(|p| self.type_name(p)).collect();
                    return format!("{}[{}]", name, p_names.join(","));
                }
                return name.to_string();
            }
        }
        type_val.to_string()
    }

    fn requirements_for(&self, semantic_ir: &Value) -> Value {
        let mut boundaries = Vec::new();
        let mut required_caps = std::collections::HashSet::new();
        let mut effect_kinds = std::collections::HashSet::new();
        let mut fragments = std::collections::HashSet::new();

        if let Some(contracts) = semantic_ir.get("contracts").and_then(|c| c.as_array()) {
            for contract in contracts {
                if let Some(fc) = contract.get("fragment_class").and_then(|f| f.as_str()) {
                    fragments.insert(fc.to_string());
                }
                if let Some(esc) = contract.get("escape_boundaries").and_then(|e| e.as_array()) {
                    for b in esc {
                        boundaries.push(b.clone());
                        if let Some(caps) = b.get("required_caps").and_then(|c| c.as_array()) {
                            for c in caps {
                                required_caps.insert(c.as_str().unwrap().to_string());
                            }
                        }
                        if let Some(prod) = b.get("produces").and_then(|p| p.as_array()) {
                            for p in prod {
                                effect_kinds.insert(p.as_str().unwrap().to_string());
                            }
                        }
                    }
                }
            }
        }

        let mut sorted_caps: Vec<String> = required_caps.into_iter().collect();
        sorted_caps.sort();

        let mut sorted_effects: Vec<String> = effect_kinds.into_iter().collect();
        sorted_effects.sort();

        let mut sorted_frags: Vec<String> = fragments.into_iter().collect();
        sorted_frags.sort();

        let has_history = sorted_caps.iter().any(|c| c == "history_read" || c == "bihistory_read");
        let has_bihistory = sorted_caps.iter().any(|c| c == "bihistory_read");
        let has_stream = sorted_caps.iter().any(|c| c == "stream_input");

        let mut coordinate_refs = Vec::new();
        let mut axes = Vec::new();
        if let Some(contracts) = semantic_ir.get("contracts").and_then(|c| c.as_array()) {
            for contract in contracts {
                if let Some(nodes) = contract.get("nodes").and_then(|n| n.as_array()) {
                    for node in nodes {
                        if self.is_temporal_node(node) {
                            if let Some(axis) = node.get("axis").or_else(|| node.get("temporal_axis")).and_then(|a| a.as_str()) {
                                axes.push(axis.to_string());
                            }
                        }
                        if node.get("kind").and_then(|k| k.as_str()) == Some("temporal_access_node") {
                            coordinate_refs.push(json!({
                                "node": node.get("name").unwrap(),
                                "axis": node.get("axis").or_else(|| node.get("temporal_axis")).unwrap(),
                                "coordinates": node.get("coordinate_refs").unwrap()
                            }));
                        }
                    }
                }
            }
        }
        axes.sort();
        axes.dedup();

        let mut stream_windows = Vec::new();
        if let Some(contracts) = semantic_ir.get("contracts").and_then(|c| c.as_array()) {
            for contract in contracts {
                if let Some(nodes) = contract.get("nodes").and_then(|n| n.as_array()) {
                    for node in nodes {
                        if node.get("kind").and_then(|k| k.as_str()) == Some("window_decl_node") {
                            let mut w = Map::new();
                            w.insert("ref".to_string(), node.get("ref").unwrap().clone());
                            w.insert("kind".to_string(), node.get("window_kind").unwrap().clone());
                            w.insert("bounded".to_string(), node.get("bounded").unwrap().clone());
                            if let Some(size) = node.get("size") {
                                w.insert("size".to_string(), size.clone());
                            }
                            if let Some(on_close) = node.get("on_close") {
                                w.insert("on_close".to_string(), on_close.clone());
                            }
                            stream_windows.push(Value::Object(w));
                        }
                    }
                }
            }
        }

        json!({
            "temporal": {
                "requires_as_of": has_history,
                "requires_valid_time": has_history,
                "requires_transaction_time": has_bihistory,
                "requires_replay": has_bihistory,
                "requires_snapshot": false,
                "min_consistency": "strong",
                "axes": axes,
                "coordinate_refs": coordinate_refs,
                "windows": stream_windows,
                "slices": []
            },
            "lifecycle": {
                "min_lifecycle": "local",
                "has_audit": has_history,
                "has_window": has_stream
            },
            "fragments": sorted_frags,
            "capabilities": {
                "required_caps": sorted_caps,
                "effect_kinds": sorted_effects
            },
            "effects": [],
            "ffi": [],
            "required_tbackend_caps": {
                "read_as_of": has_history,
                "append_atomic": false,
                "replay_enabled": has_bihistory,
                "snapshot_enabled": false,
                "compact_enabled": false,
                "subscribe_enabled": false,
                "consistency": "strong"
            }
        })
    }

    fn classified_ast_for(&self, report: &Value, semantic_ir: &Value, contract_ids: &[String], fragment_class: &str) -> Value {
        json!({
            "kind": "classified_program",
            "format_version": "0.1.0",
            "program_id": semantic_ir.get("program_id").unwrap(),
            "source_hash": semantic_ir.get("source_hash").unwrap(),
            "source_path": semantic_ir.get("source_path").unwrap(),
            "pass_result": report.get("pass_result").unwrap(),
            "semantic_ir_ref": report.get("semantic_ir_ref").unwrap(),
            "compilation_report_ref": semantic_ir.get("compilation_report_ref").unwrap(),
            "fragment_class": fragment_class,
            "oof_count": 0,
            "contracts": contract_ids,
            "loadable_contracts": contract_ids
        })
    }

    fn compatibility_metadata_for(&self, report: &Value, semantic_ir: &Value) -> Value {
        let has_temporal = self.temporal_artifact(semantic_ir);
        
        let mut notes = vec![
            "semantic_ir_program.json preserves PROP-019.1 envelope".to_string(),
            "RuntimeMachine proof loader reads semantic_ir_program.json directly".to_string()
        ];
        
        let mut m = Map::new();
        m.insert("kind".to_string(), Value::String("igapp_compatibility_metadata".to_string()));
        m.insert("format_version".to_string(), Value::String("0.1.0".to_string()));
        m.insert("canonical_semantic_ir_ref".to_string(), semantic_ir.get("program_id").unwrap().clone());
        m.insert("compilation_report_ref".to_string(), report.get("program_id").unwrap().clone());
        m.insert("loader_shape".to_string(), Value::String("runtime_machine_memory_proof.prop0191_direct_v0".to_string()));
        m.insert("canonical_artifact".to_string(), Value::String("semantic_ir_program.json".to_string()));
        m.insert("runtime_compatibility_artifact".to_string(), Value::Null);

        if has_temporal {
            let mut re = Map::new();
            re.insert("status".to_string(), Value::String("unsupported".to_string()));
            re.insert("guard_policy".to_string(), Value::String("load_accept_evaluate_refuse".to_string()));
            re.insert("guard_at".to_string(), Value::String("evaluate".to_string()));
            
            let mut l = Map::new();
            l.insert("decision".to_string(), Value::String("accept_for_inspection".to_string()));
            l.insert("requires_contract_index".to_string(), Value::Bool(true));
            re.insert("load".to_string(), Value::Object(l));
            
            let mut ev = Map::new();
            ev.insert("decision".to_string(), Value::String("refuse_temporal_contract".to_string()));
            ev.insert("reason_code".to_string(), Value::String("runtime.temporal_execution_unsupported".to_string()));
            re.insert("evaluate".to_string(), Value::Object(ev));
            re.insert("reason".to_string(), Value::String("temporal SemanticIR assembly proof preserves artifact shape only; RuntimeMachine temporal execution is out of scope".to_string()));
            
            m.insert("runtime_execution".to_string(), Value::Object(re));
            
            notes.push("temporal_input_node and temporal_access_node are preserved as non-compute contract nodes".to_string());
            notes.push("temporal runtime execution requires a separate RuntimeMachine temporal adapter/hook slice".to_string());
        }

        m.insert("notes".to_string(), json!(notes));
        Value::Object(m)
    }

    fn temporal_artifact(&self, semantic_ir: &Value) -> bool {
        if let Some(contracts) = semantic_ir.get("contracts").and_then(|c| c.as_array()) {
            for contract in contracts {
                if let Some(nodes) = contract.get("nodes").and_then(|n| n.as_array()) {
                    for node in nodes {
                        if self.is_temporal_node(node) {
                            return true;
                        }
                    }
                }
            }
        }
        false
    }

    fn snake_case(&self, value: &str) -> String {
        let mut result = String::new();
        let chars: Vec<char> = value.chars().collect();
        for i in 0..chars.len() {
            let c = chars[i];
            if c.is_uppercase() {
                if i > 0 && chars[i-1].is_lowercase() {
                    result.push('_');
                }
                result.push(c.to_lowercase().next().unwrap());
            } else {
                result.push(c);
            }
        }
        result
    }

    fn canonical_hash(&self, value: &Value) -> String {
        let canonical = serde_json::to_string(value).unwrap();
        let mut hasher = Sha256::new();
        hasher.update(canonical.as_bytes());
        format!("sha256:{:x}", hasher.finalize())
    }
}
