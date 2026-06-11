use crate::typechecker::{TypedProgram, TypedContract, TypedDecl};
use crate::classifier::ClassifierDiagnostic;
use crate::parser::{Expr, SpanEntry};
use serde_json::{Value, Map, json};
use sha2::{Sha256, Digest};
use std::collections::{HashMap, HashSet};

pub struct EmitResult {
    pub semantic_ir: Option<Value>,
    pub compilation_report: Value,
    pub form_table: Option<Value>,
    pub resolved_program: Option<Value>,
    /// LAB-SRCMAP-P1: source-map artifact built from parser span_table.
    pub source_map: Option<Value>,
}

pub struct Emitter {
    version: String,
    current_type_args: std::cell::RefCell<Option<HashMap<String, String>>>,
}

impl Emitter {
    pub fn new() -> Self {
        Self {
            version: "0.1.0".to_string(),
            current_type_args: std::cell::RefCell::new(None),
        }
    }

    pub fn emit_typed(&self, typed: &TypedProgram) -> EmitResult {
        let diagnostics = &typed.type_errors;
        let ok = diagnostics.is_empty();

        let semantic_ir = if ok {
            Some(self.typed_semantic_ir_program(typed))
        } else {
            None
        };

        let compilation_report = self.typed_compilation_report(typed, diagnostics, &semantic_ir);

        EmitResult {
            semantic_ir,
            compilation_report,
            form_table: None,
            resolved_program: None,
            source_map: None,
        }
    }

    pub fn apply_form_lowering(&self, emit_result: &mut EmitResult) {
        if let (Some(semantic_ir), Some(resolved_program)) =
            (emit_result.semantic_ir.as_mut(), emit_result.resolved_program.as_ref())
        {
            self.lower_resolved_forms(semantic_ir, resolved_program);
        }
    }

    fn typed_semantic_ir_program(&self, typed: &TypedProgram) -> Value {
        let report_id = self.typed_compilation_report_id(typed);
        let mut contracts_ir = Vec::new();
        for contract in &typed.contracts {
            contracts_ir.push(self.typed_contract_ir(contract));
        }

        let mut result = Map::new();
        result.insert("kind".to_string(), Value::String("semantic_ir_program".to_string()));
        result.insert("format_version".to_string(), Value::String(self.version.clone()));
        result.insert("program_id".to_string(), Value::String(self.typed_program_id(typed)));
        result.insert("grammar_version".to_string(), Value::String(typed.grammar_version.clone()));
        result.insert("source_hash".to_string(), Value::String(typed.source_hash.clone().unwrap_or_default()));
        result.insert("source_path".to_string(), Value::String(self.source_path(typed)));
        result.insert("module".to_string(), Value::String(typed.module.clone().unwrap_or_default()));
        result.insert("compilation_report_ref".to_string(), Value::String(report_id));
        result.insert("contracts".to_string(), Value::Array(contracts_ir));
        if let Some(entrypoint) = self.semantic_entrypoint(typed, result.get("contracts").and_then(|c| c.as_array())) {
            result.insert("entrypoint".to_string(), entrypoint);
        }

        let mut shape_descriptors = Map::new();
        if let Some(contracts_arr) = result.get("contracts").and_then(|c| c.as_array()) {
            for c in contracts_arr {
                if let Some(shapes) = c.get("shapes").and_then(|s| s.as_object()) {
                    for (k, v) in shapes {
                        shape_descriptors.insert(k.clone(), v.clone());
                    }
                }
            }
        }
        if !shape_descriptors.is_empty() {
            result.insert("shape_descriptors".to_string(), Value::Object(shape_descriptors));
            result.insert("lowering_invariants".to_string(), json!([
                "SIR-1:no_type_variables",
                "SIR-2:no_unresolved_trait_method_calls",
                "SIR-3:no_generic_contractir",
                "SIR-4:concrete_resolved_impl"
            ]));
        }

        if let Some(assumptions) = self.typed_assumption_registry(typed) {
            result.insert("assumption_registry".to_string(), assumptions);
        }
        if let Some(olaps) = &typed.olap_points {
            result.insert("olap_points".to_string(), Value::Array(olaps.clone()));
        }

        let invariants = self.typed_program_invariants(&result.get("contracts").cloned().unwrap_or(Value::Null));
        if !invariants.is_empty() {
            result.insert("invariants".to_string(), Value::Array(invariants));
        }

        // PROP-044 P6: emit variant_declarations when present
        // LAB-SRCMAP-P1: enrich each variant_declaration with a node_id for sourcemap linkage
        if !typed.variant_declarations.is_empty() {
            let enriched: Vec<Value> = typed.variant_declarations.iter().map(|v| {
                let mut v2 = v.clone();
                if let Some(obj) = v2.as_object_mut() {
                    if let Some(name) = obj.get("name").and_then(|n| n.as_str()).map(|s| s.to_string()) {
                        obj.insert("node_id".to_string(), Value::String(format!("variant:{}", name)));
                    }
                }
                v2
            }).collect();
            result.insert("variant_declarations".to_string(), Value::Array(enriched));
        }

        Value::Object(result)
    }

    fn semantic_entrypoint(&self, typed: &TypedProgram, contracts: Option<&Vec<Value>>) -> Option<Value> {
        let entrypoint = typed.entrypoint.as_ref()?;
        let contract_ref = contracts
            .and_then(|items| items.iter().find(|c| {
                c.get("contract_name").and_then(|v| v.as_str()) == Some(entrypoint.resolved_contract.as_str())
            }))
            .and_then(|c| c.get("contract_ref"))
            .cloned();

        let mut result = Map::new();
        result.insert("kind".to_string(), Value::String("entrypoint_decl".to_string()));
        result.insert("target".to_string(), Value::String(entrypoint.target.clone()));
        result.insert("declared_target".to_string(), Value::String(entrypoint.target.clone()));
        result.insert("qualified".to_string(), Value::Bool(entrypoint.qualified));
        result.insert("resolved_contract".to_string(), Value::String(entrypoint.resolved_contract.clone()));
        result.insert("resolved_contract_id".to_string(), Value::String(entrypoint.resolved_contract_id.clone()));
        result.insert("contract_fragment_class".to_string(), Value::String(entrypoint.contract_fragment_class.clone()));
        result.insert("source_span".to_string(), json!({
            "line": entrypoint.source_span.line,
            "col": entrypoint.source_span.col
        }));
        if let Some(cref) = contract_ref {
            result.insert("contract_ref".to_string(), cref);
        }
        Some(Value::Object(result))
    }

    fn typed_compilation_report(&self, typed: &TypedProgram, diagnostics: &[ClassifierDiagnostic], semantic_ir: &Option<Value>) -> Value {
        let ok = diagnostics.is_empty();
        let mut report = Map::new();
        report.insert("kind".to_string(), Value::String("compilation_report".to_string()));
        report.insert("format_version".to_string(), Value::String(self.version.clone()));
        report.insert("program_id".to_string(), Value::String(self.typed_compilation_report_id(typed)));
        report.insert("grammar_version".to_string(), Value::String(typed.grammar_version.clone()));
        report.insert("source_hash".to_string(), Value::String(typed.source_hash.clone().unwrap_or_default()));
        report.insert("source_path".to_string(), Value::String(self.source_path(typed)));
        report.insert("pass_result".to_string(), Value::String(if ok { "ok" } else { "oof" }.to_string()));

        let mut stages = Map::new();
        stages.insert("parse".to_string(), Value::String("ok".to_string()));
        stages.insert("classify".to_string(), Value::String("ok".to_string()));
        stages.insert("typecheck".to_string(), Value::String(if ok { "ok" } else { "oof" }.to_string()));
        stages.insert("emit".to_string(), Value::String(if ok { "ok" } else { "skipped" }.to_string()));
        report.insert("stages".to_string(), Value::Object(stages));

        let diag_vals: Vec<Value> = diagnostics.iter().map(|d| {
            let mut m = Map::new();
            m.insert("rule".to_string(), Value::String(d.rule.clone()));
            m.insert("severity".to_string(), Value::String("error".to_string()));
            m.insert("message".to_string(), Value::String(d.message.clone()));
            m.insert("node".to_string(), Value::String(d.node.clone()));
            m.insert("line".to_string(), d.line.map_or(Value::Null, |l| Value::Number(l.into())));
            Value::Object(m)
        }).collect();
        report.insert("diagnostics".to_string(), Value::Array(diag_vals));

        let semantic_ir_ref = semantic_ir.as_ref()
            .and_then(|ir| ir.get("program_id"))
            .cloned()
            .unwrap_or(Value::Null);
        report.insert("semantic_ir_ref".to_string(), semantic_ir_ref);

        let coverage = self.typed_invariant_coverage(semantic_ir);
        if !coverage.is_empty() {
            report.insert("invariant_coverage".to_string(), Value::Array(coverage));
        }

        Value::Object(report)
    }

    fn typed_program_id(&self, typed: &TypedProgram) -> String {
        let hash = typed.source_hash.as_deref().unwrap_or("sha256:hand_authored_no_source")
            .trim_start_matches("sha256:");
        let prefix = if hash.len() >= 16 { &hash[0..16] } else { hash };
        format!("semanticir/{}", prefix)
    }

    fn typed_compilation_report_id(&self, typed: &TypedProgram) -> String {
        let hash = typed.source_hash.as_deref().unwrap_or("sha256:hand_authored_no_source")
            .trim_start_matches("sha256:");
        let prefix = if hash.len() >= 16 { &hash[0..16] } else { hash };
        format!("compilation_report/{}", prefix)
    }

    fn source_path(&self, typed: &TypedProgram) -> String {
        let path = typed.source_path.as_deref().unwrap_or("source/add.ig");
        path.trim_start_matches("igniter-lang/").to_string()
    }

    // ── LAB-SRCMAP-P1: source map building ───────────────────────────────────

    /// Build the `.sourcemap.json` artifact from the parser's span_table.
    /// v0 stability: declaration spans exact; expression spans best-effort token-start.
    pub fn build_sourcemap(&self, typed: &TypedProgram, span_table: &[SpanEntry]) -> Value {
        let source_file = typed.source_path.as_deref().unwrap_or("unknown").to_string();
        let module = typed.module.clone().unwrap_or_default();

        let mut seen_ids: std::collections::HashSet<String> = std::collections::HashSet::new();
        let mut nodes = Vec::new();
        for entry in span_table {
            // De-duplicate: first occurrence wins (matches parse order)
            if seen_ids.contains(&entry.node_id) {
                continue;
            }
            seen_ids.insert(entry.node_id.clone());

            let sir_path = self.span_entry_sir_path(entry);
            let mut span = Map::new();
            span.insert("start_line".to_string(), Value::Number(entry.start_line.into()));
            span.insert("start_col".to_string(), Value::Number(entry.start_col.into()));
            if entry.end_line > 0 {
                span.insert("end_line".to_string(), Value::Number(entry.end_line.into()));
                span.insert("end_col".to_string(), Value::Number(entry.end_col.into()));
            }
            let mut node = Map::new();
            node.insert("node_id".to_string(), Value::String(entry.node_id.clone()));
            node.insert("kind".to_string(), Value::String(entry.kind.clone()));
            node.insert("sir_path".to_string(), Value::String(sir_path));
            node.insert("source_span".to_string(), Value::Object(span));
            nodes.push(Value::Object(node));
        }

        json!({
            "schema_version": "srcmap-v0",
            "source_file": source_file,
            "module": module,
            "nodes": nodes,
            "provenance_note": "v0: declaration spans exact (token-start of name); expression spans best-effort (token-start of delimiter); end positions absent (not tracked in v0)"
        })
    }

    fn span_entry_sir_path(&self, entry: &SpanEntry) -> String {
        let id = &entry.node_id;

        if let Some(name) = id.strip_prefix("contract:") {
            return format!("$.contracts[?(@.contract_name=='{}')]", name);
        }
        if let Some(name) = id.strip_prefix("type:") {
            return format!("$.type_env['{}']", name);
        }
        if let Some(name) = id.strip_prefix("variant:") {
            return format!("$.variant_declarations[?(@.name=='{}')]", name);
        }
        if let Some(rest) = id.strip_prefix("input:") {
            if let Some(dot) = rest.find('.') {
                let (c, n) = (&rest[..dot], &rest[dot+1..]);
                return format!("$.contracts[?(@.contract_name=='{}')].inputs[?(@.name=='{}')]", c, n);
            }
        }
        if let Some(rest) = id.strip_prefix("output:") {
            if let Some(dot) = rest.find('.') {
                let (c, n) = (&rest[..dot], &rest[dot+1..]);
                return format!("$.contracts[?(@.contract_name=='{}')].outputs[?(@.name=='{}')]", c, n);
            }
        }
        if let Some(rest) = id.strip_prefix("compute:") {
            // Strip @L suffix if present (expression nodes reuse compute prefix)
            let rest = rest.split('@').next().unwrap_or(rest);
            if let Some(dot) = rest.find('.') {
                let (c, n) = (&rest[..dot], &rest[dot+1..]);
                return format!("$.contracts[?(@.contract_name=='{}')].nodes[?(@.name=='{}')]", c, n);
            }
        }
        // Expression nodes: "record_literal:Contract.Decl@L12", "field_access:...", etc.
        if let Some(at) = id.find('@') {
            let base = &id[..at];
            if let Some(colon) = base.find(':') {
                let kind = &base[..colon];
                let path = &base[colon+1..];
                if let Some(dot) = path.find('.') {
                    let (c, d) = (&path[..dot], &path[dot+1..]);
                    return format!("$.contracts[?(@.contract_name=='{}')].nodes[?(@.name=='{}')].expr.{}", c, d, kind);
                }
            }
        }
        "$.unknown".to_string()
    }

    // ── end LAB-SRCMAP-P1 ─────────────────────────────────────────────────────

    fn typed_contract_ir(&self, contract: &TypedContract) -> Value {
        *self.current_type_args.borrow_mut() = contract.type_args.clone();
        let mut contract_ir = Map::new();
        contract_ir.insert("kind".to_string(), Value::String("contract_ir".to_string()));
        contract_ir.insert("contract_ref".to_string(), Value::Null);
        contract_ir.insert("contract_name".to_string(), Value::String(contract.name.clone()));
        contract_ir.insert("modifier".to_string(), Value::String(contract.modifier.clone()));
        
        let spec_val = match &contract.specialization_of {
            Some(spec) => Value::String(spec.clone()),
            None => Value::Null,
        };
        contract_ir.insert("specialization_of".to_string(), spec_val);

        let mut targs_map = Map::new();
        if let Some(targs) = &contract.type_args {
            for (k, v) in targs {
                targs_map.insert(k.clone(), Value::String(v.clone()));
            }
        }
        contract_ir.insert("type_args".to_string(), Value::Object(targs_map));

        contract_ir.insert("fragment_class".to_string(), Value::String(contract.fragment_class.clone()));
        contract_ir.insert("inputs".to_string(), self.typed_ports(contract, "input"));
        contract_ir.insert("outputs".to_string(), self.typed_ports(contract, "output"));
        contract_ir.insert("nodes".to_string(), self.typed_nodes(contract));
        contract_ir.insert("escape_boundaries".to_string(), self.typed_escape_boundaries(contract));

        let mut capabilities = Vec::new();
        let mut effects = Vec::new();
        for decl in &contract.declarations {
            if decl.kind == "capability" {
                capabilities.push(json!({
                    "name": decl.name,
                    "type": decl.type_info
                }));
            } else if decl.kind == "effect" {
                effects.push(json!({
                    "name": decl.name,
                    "capability_ref": decl.required_capability
                }));
            }
        }
        contract_ir.insert("capabilities".to_string(), Value::Array(capabilities));
        contract_ir.insert("effects".to_string(), Value::Array(effects));

        if let Some(targs) = &contract.type_args {
            if !targs.is_empty() {
                if let Some(node) = &contract.implements {
                    let shape_name = if node.type_args.is_empty() {
                        node.name.clone()
                    } else {
                        let arg_strs: Vec<String> = node.type_args.iter().map(type_ref_to_string).collect();
                        format!("{}[{}]", node.name, arg_strs.join(","))
                    };
                    
                    let inputs = contract_ir.get("inputs").unwrap().as_array().unwrap();
                    let outputs = contract_ir.get("outputs").unwrap().as_array().unwrap();
                    
                    let input_ports: Vec<Value> = inputs.iter().map(|p| {
                        json!({
                            "name": p.get("name").unwrap(),
                            "type_tag": p.get("type").unwrap().get("name").unwrap()
                        })
                    }).collect();
                    
                    let output_ports: Vec<Value> = outputs.iter().map(|p| {
                        json!({
                            "name": p.get("name").unwrap(),
                            "type_tag": p.get("type").unwrap().get("name").unwrap()
                        })
                    }).collect();
                    
                    let mut shape_desc = Map::new();
                    shape_desc.insert("input_ports".to_string(), Value::Array(input_ports));
                    shape_desc.insert("output_ports".to_string(), Value::Array(output_ports));
                    
                    let mut shapes = Map::new();
                    shapes.insert(shape_name.clone(), Value::Object(shape_desc));
                    contract_ir.insert("shapes".to_string(), Value::Object(shapes));
                    
                    let implements = json!([
                        {
                            "shape": shape_name,
                            "check": "passed"
                        }
                    ]);
                    contract_ir.insert("implements".to_string(), implements);
                }
            }
        }

        if let Some(refs) = &contract.assumption_refs {
            if !refs.is_empty() {
                contract_ir.insert("assumption_refs".to_string(), json!(refs));
            }
        }

        // PROP-042 T3 / PROP-041 T2 / PROP-039 OOF-R3: emit termination evidence.
        // Priority chain:
        //   T3 path (numeric_measure_v0) — decreases_variant_t3 set by typechecker
        //   T2 path (structural_size_v1) — decreases_variant_t2 set by typechecker
        //   T1 path (syntactic_v0)       — byte-for-byte preserved
        // NOTE: T3/T2 are compiler-controlled evidence — NOT full termination proofs.
        if contract.modifier == "recursive" {
            if let Some(ref dv_t3) = contract.decreases_variant_t3 {
                // T3: numeric_measure_v0
                let evidence = contract.numeric_measure_evidence.as_ref();
                let fn_name  = evidence.and_then(|e| e.get("fn")).and_then(|v| v.as_str()).unwrap_or("unknown");
                let arg      = evidence.and_then(|e| e.get("arg")).and_then(|v| v.as_str()).unwrap_or("unknown");
                let trust    = evidence.and_then(|e| e.get("trust")).and_then(|v| v.as_str()).unwrap_or("unknown");
                let source   = evidence.and_then(|e| e.get("source")).and_then(|v| v.as_str()).unwrap_or("unknown");
                let mut term = Map::new();
                term.insert("decreases".to_string(),     Value::String(dv_t3.clone()));
                term.insert("variant_check".to_string(), Value::String("numeric_measure_v0".to_string()));
                let mut nm_obj = Map::new();
                nm_obj.insert("fn".to_string(),     Value::String(fn_name.to_string()));
                nm_obj.insert("arg".to_string(),    Value::String(arg.to_string()));
                nm_obj.insert("trust".to_string(),  Value::String(trust.to_string()));
                nm_obj.insert("source".to_string(), Value::String(source.to_string()));
                term.insert("numeric_measure".to_string(), Value::Object(nm_obj));
                contract_ir.insert("termination".to_string(), Value::Object(term));
            } else if let Some(ref dv_t2) = contract.decreases_variant_t2 {
                let accessor = dv_t2.splitn(2, '.').nth(1).unwrap_or(dv_t2.as_str());
                let evidence = contract.size_relation_evidence.as_ref();
                let trust  = evidence.and_then(|e| e.get("trust")).and_then(|v| v.as_str()).unwrap_or("user_assumed");
                let source = evidence.and_then(|e| e.get("source")).and_then(|v| v.as_str()).unwrap_or("unknown");
                let mut term = Map::new();
                term.insert("decreases".to_string(), Value::String(dv_t2.clone()));
                term.insert("variant_check".to_string(), Value::String("structural_size_v1".to_string()));
                let mut sr_obj = Map::new();
                sr_obj.insert("accessor".to_string(), Value::String(accessor.to_string()));
                sr_obj.insert("trust".to_string(), Value::String(trust.to_string()));
                sr_obj.insert("source".to_string(), Value::String(source.to_string()));
                term.insert("size_relation".to_string(), Value::Object(sr_obj));
                contract_ir.insert("termination".to_string(), Value::Object(term));
            } else if let Some(ref dv) = contract.decreases_variant {
                let mut term = Map::new();
                term.insert("decreases".to_string(), Value::String(dv.clone()));
                term.insert("variant_check".to_string(), Value::String("syntactic_v0".to_string()));
                contract_ir.insert("termination".to_string(), Value::Object(term));
            }
        }

        let cref = self.contract_ref(&Value::Object(contract_ir.clone()));
        contract_ir.insert("contract_ref".to_string(), Value::String(cref));

        *self.current_type_args.borrow_mut() = None;
        Value::Object(contract_ir)
    }

    fn typed_ports(&self, contract: &TypedContract, kind: &str) -> Value {
        let mut ports = Vec::new();
        for decl in &contract.declarations {
            if decl.kind == kind {
                let mut port = Map::new();
                // LAB-SRCMAP-P1: stable node_id for sourcemap linkage
                port.insert("node_id".to_string(), Value::String(
                    format!("{}:{}.{}", kind, contract.name, decl.name)));
                port.insert("name".to_string(), Value::String(decl.name.clone()));
                port.insert("type".to_string(), decl.type_info.clone());
                
                let default_lifecycle = if kind == "input" { "local" } else { "session" };
                let lifecycle = decl.lifecycle.as_deref().unwrap_or(default_lifecycle);
                port.insert("lifecycle".to_string(), Value::String(lifecycle.to_string()));

                if kind == "output" {
                    if let Some(warnings) = &decl.warnings_from {
                        port.insert("warnings_from".to_string(), json!(warnings));
                    }
                    if let Some(uncertain) = &decl.uncertain_from {
                        port.insert("uncertain_from".to_string(), json!(uncertain));
                    }
                    if let Some(metrics) = &decl.metrics_from {
                        port.insert("metrics_from".to_string(), json!(metrics));
                    }
                }

                ports.push(Value::Object(port));
            }
        }
        Value::Array(ports)
    }

    fn typed_nodes(&self, contract: &TypedContract) -> Value {
        let mut nodes = Vec::new();
        for decl in &contract.declarations {
            if let Some(node) = self.typed_node(decl, &contract.declarations, &contract.name) {
                nodes.push(node);
            }
        }
        Value::Array(nodes)
    }

    fn typed_node(&self, decl: &TypedDecl, declarations: &[TypedDecl], contract_name: &str) -> Option<Value> {
        if let Some(node) = &decl.semantic_node {
            return Some(node.clone());
        }

        match decl.kind.as_str() {
            "stream" => Some(self.stream_input_node(decl, declarations)),
            "window" => Some(self.window_decl_node(decl)),
            "fold_stream" => Some(self.fold_stream_node(decl, declarations)),
            "uses_assumptions" => Some(self.assumption_ref_node(decl)),
            "invariant" => Some(self.invariant_node(decl)),
            "loop" => Some(self.loop_node(decl, declarations)),
            "service_loop" => Some(self.service_loop_node(decl, declarations)),
            "read" => {
                if decl.node_fragment_class.as_deref() == Some("temporal") {
                    Some(self.temporal_input_node(decl))
                } else {
                    None
                }
            }
            "compute" => {
                if let Some(tnode) = self.temporal_access_node(decl) {
                    Some(tnode)
                } else {
                    let mut node = Map::new();
                    node.insert("kind".to_string(), Value::String("compute".to_string()));
                    // LAB-SRCMAP-P1: stable node_id for sourcemap linkage
                    node.insert("node_id".to_string(), Value::String(
                        format!("compute:{}.{}", contract_name, decl.name)));
                    node.insert("name".to_string(), Value::String(decl.name.clone()));
                    // PROP-044 P6: use annotated_expr (variant_construct/match_node) if present,
                    // otherwise fall back to the standard semantic_expr pipeline.
                    let lowered_expr = if let Some(ae) = &decl.annotated_expr {
                        self.lower_annotated_expr(ae)
                    } else {
                        // PROP-039 gate 5: intercept recur() calls to emit recur_call sub-nodes
                        let return_type_str = decl.type_info.get("name")
                            .and_then(|n| n.as_str())
                            .unwrap_or("Unknown")
                            .to_string();
                        self.semantic_expr_for_compute(&json!(decl.expr), &return_type_str)
                    };
                    node.insert("expr".to_string(), lowered_expr);
                    node.insert("type".to_string(), decl.type_info.clone());
                    node.insert("deps".to_string(), json!(decl.deps));
                    node.insert("fragment".to_string(), Value::String(decl.fragment_class.clone()));
                    Some(Value::Object(node))
                }
            }
            _ => None,
        }
    }

    fn typed_assumption_registry(&self, typed: &TypedProgram) -> Option<Value> {
        let registry = typed.assumption_registry.as_ref()?;
        if registry.is_empty() {
            return None;
        }

        let mut list = Vec::new();
        for entry in registry {
            let mut m = Map::new();
            m.insert("kind".to_string(), Value::String("assumption_ir".to_string()));
            m.insert("name".to_string(), entry.get("name").cloned().unwrap_or(Value::Null));
            m.insert("fields".to_string(), entry.get("fields").cloned().unwrap_or_else(|| Value::Object(Map::new())));
            if let Some(dec) = entry.get("declared_in_module") {
                m.insert("declared_in_module".to_string(), dec.clone());
            }
            list.push(Value::Object(m));
        }
        Some(Value::Array(list))
    }

    fn assumption_ref_node(&self, decl: &TypedDecl) -> Value {
        let mut m = Map::new();
        m.insert("kind".to_string(), Value::String("assumption_ref_node".to_string()));
        m.insert("name".to_string(), Value::String(decl.name.clone()));
        m.insert("assumption_ref".to_string(), Value::String(decl.name.clone()));
        m.insert("type".to_string(), decl.type_info.clone());
        m.insert("fragment".to_string(), Value::String("epistemic".to_string()));
        Value::Object(m)
    }

    fn typed_program_invariants(&self, contracts: &Value) -> Vec<Value> {
        let mut invariants = Vec::new();
        if let Some(arr) = contracts.as_array() {
            for c in arr {
                if let Some(nodes) = c.get("nodes").and_then(|n| n.as_array()) {
                    for node in nodes {
                        if node.get("kind").and_then(|k| k.as_str()) == Some("invariant_node") {
                            invariants.push(node.clone());
                        }
                    }
                }
            }
        }
        invariants
    }

    fn semantic_expr(&self, val: &Value) -> Value {
        if let Some(opt) = self.try_optimize_map_reduce(val) {
            return opt;
        }
        match val {
            Value::Object(map) => {
                // PROP-039 gate 5: recur() call → recur_call sub-expression node
                if map.get("kind").and_then(|k| k.as_str()) == Some("call")
                    && map.get("fn").and_then(|f| f.as_str()) == Some("recur")
                {
                    let args: Vec<Value> = map.get("args")
                        .and_then(|a| a.as_array())
                        .map(|arr| arr.iter().map(|a| self.semantic_expr(a)).collect())
                        .unwrap_or_default();
                    let mut node = Map::new();
                    node.insert("kind".to_string(), Value::String("recur_call".to_string()));
                    node.insert("args".to_string(), Value::Array(args));
                    node.insert("return_type".to_string(), Value::String("Unknown".to_string()));
                    return Value::Object(node);
                }
                if map.get("kind").and_then(|k| k.as_str()) == Some("call") && map.get("fn").and_then(|f| f.as_str()) == Some("stdlib.numeric.add") {
                    let type_args_borrow = self.current_type_args.borrow();
                    let concrete_type = type_args_borrow
                        .as_ref()
                        .and_then(|m| m.get("T"))
                        .cloned()
                        .unwrap_or_else(|| "Integer".to_string());
                    
                    let op_name = match concrete_type.as_str() {
                        "Integer" => "stdlib.integer.add",
                        "Float" => "stdlib.float.add",
                        _ => "stdlib.numeric.add",
                    };
                    
                    let mut operands = Vec::new();
                    if let Some(args) = map.get("args").and_then(|a| a.as_array()) {
                        for arg in args {
                            operands.push(self.semantic_expr(arg));
                        }
                    }
                    
                    let mut new_map = Map::new();
                    new_map.insert("kind".to_string(), Value::String("apply".to_string()));
                    new_map.insert("operator".to_string(), Value::String(op_name.to_string()));
                    new_map.insert("resolved_impl".to_string(), Value::String(format!("Additive[{}]", concrete_type)));
                    new_map.insert("type_args".to_string(), json!(vec![concrete_type]));
                    new_map.insert("operands".to_string(), Value::Array(operands));
                    return Value::Object(new_map);
                }
                // igniter-string-core-units-and-pure-stdlib-boundary-v0:
                // (A) Rewrite unambiguous text stdlib bare names to stdlib.text.* + attach resolved_type.
                // (B) For already-qualified stdlib.text.* names (from typechecker concat rewrite),
                //     attach resolved_type so the IR is fully annotated.
                {
                    const TEXT_STDLIB_OPS: &[&str] = &[
                        "trim", "contains", "starts_with", "ends_with", "split",
                        "replace", "replace_all",
                        "byte_length", "rune_length", "grapheme_length",
                        "byte_slice", "rune_slice", "grapheme_slice",
                    ];
                    fn text_return_type(fn_name: &str) -> serde_json::Value {
                        let name = match fn_name {
                            "concat" | "trim" | "replace" | "replace_all" |
                            "byte_slice" | "rune_slice" | "grapheme_slice" => "Text",
                            "contains" | "starts_with" | "ends_with" => "Bool",
                            "byte_length" | "rune_length" | "grapheme_length" => "Integer",
                            "split" => "Collection",
                            _ => "Unknown",
                        };
                        if name == "Collection" {
                            let mut col = serde_json::Map::new();
                            col.insert("name".to_string(), serde_json::Value::String("Collection".to_string()));
                            let mut inner = serde_json::Map::new();
                            inner.insert("name".to_string(), serde_json::Value::String("Text".to_string()));
                            inner.insert("params".to_string(), serde_json::Value::Array(Vec::new()));
                            col.insert("params".to_string(), serde_json::Value::Array(vec![serde_json::Value::Object(inner)]));
                            serde_json::Value::Object(col)
                        } else {
                            let mut m = serde_json::Map::new();
                            m.insert("name".to_string(), serde_json::Value::String(name.to_string()));
                            m.insert("params".to_string(), serde_json::Value::Array(Vec::new()));
                            serde_json::Value::Object(m)
                        }
                    }
                    if map.get("kind").and_then(|k| k.as_str()) == Some("call") {
                        if let Some(fn_val) = map.get("fn").and_then(|f| f.as_str()) {
                            if TEXT_STDLIB_OPS.contains(&fn_val) {
                                // (A) bare name → qualify + attach resolved_type
                                let qualified = format!("stdlib.text.{}", fn_val);
                                let resolved_type = text_return_type(fn_val);
                                let args: Vec<serde_json::Value> = map.get("args")
                                    .and_then(|a| a.as_array())
                                    .map(|arr| arr.iter().map(|a| self.semantic_expr(a)).collect())
                                    .unwrap_or_default();
                                let mut new_map = serde_json::Map::new();
                                new_map.insert("kind".to_string(), serde_json::Value::String("call".to_string()));
                                new_map.insert("fn".to_string(), serde_json::Value::String(qualified));
                                new_map.insert("args".to_string(), serde_json::Value::Array(args));
                                new_map.insert("resolved_type".to_string(), resolved_type);
                                return serde_json::Value::Object(new_map);
                            }
                            // (B) already-qualified stdlib.text.* (from typechecker concat rewrite)
                            // — attach resolved_type if not already present.
                            if fn_val.starts_with("stdlib.text.") || fn_val == "stdlib.collection.concat" {
                                if !map.contains_key("resolved_type") {
                                    let base = fn_val.strip_prefix("stdlib.text.").unwrap_or("concat");
                                    let resolved_type = if fn_val == "stdlib.collection.concat" {
                                        // Collection[T] — use first arg's param if knowable, else Unknown
                                        let mut col = serde_json::Map::new();
                                        col.insert("name".to_string(), serde_json::Value::String("Collection".to_string()));
                                        col.insert("params".to_string(), serde_json::Value::Array(Vec::new()));
                                        serde_json::Value::Object(col)
                                    } else {
                                        text_return_type(base)
                                    };
                                    let args: Vec<serde_json::Value> = map.get("args")
                                        .and_then(|a| a.as_array())
                                        .map(|arr| arr.iter().map(|a| self.semantic_expr(a)).collect())
                                        .unwrap_or_default();
                                    let mut new_map = serde_json::Map::new();
                                    new_map.insert("kind".to_string(), serde_json::Value::String("call".to_string()));
                                    new_map.insert("fn".to_string(), serde_json::Value::String(fn_val.to_string()));
                                    new_map.insert("args".to_string(), serde_json::Value::Array(args));
                                    new_map.insert("resolved_type".to_string(), resolved_type);
                                    return serde_json::Value::Object(new_map);
                                }
                            }
                        }
                    }
                }
                if map.get("kind").and_then(|k| k.as_str()) == Some("if_expr") {
                    let mut new_map = Map::new();
                    new_map.insert("kind".to_string(), Value::String("if_expr".to_string()));
                    new_map.insert("condition".to_string(), self.semantic_expr(map.get("cond").unwrap_or(&Value::Null)));
                    
                    let then_expr = map.get("then")
                        .and_then(|t| t.get("return_expr").or_else(|| t.get("expr")))
                        .unwrap_or(&Value::Null);
                    new_map.insert("then_branch".to_string(), self.semantic_expr(then_expr));
                    
                    let else_expr = map.get("else")
                        .and_then(|e| e.get("return_expr").or_else(|| e.get("expr")))
                        .unwrap_or(&Value::Null);
                    new_map.insert("else_branch".to_string(), self.semantic_expr(else_expr));
                    
                    if let Some(rt) = map.get("resolved_type") {
                        new_map.insert("resolved_type".to_string(), rt.clone());
                    }
                    Value::Object(new_map)
                } else {
                    let mut new_map = Map::new();
                    for (k, v) in map {
                        if k != "deps" {
                            new_map.insert(k.clone(), self.semantic_expr(v));
                        }
                    }
                    Value::Object(new_map)
                }
            }
            Value::Array(arr) => {
                Value::Array(arr.iter().map(|item| self.semantic_expr(item)).collect())
            }
            _ => val.clone(),
        }
    }

    // ── PROP-044 P6: variant_construct / match_node SIR lowering ─────────────────

    /// Lower an annotated_expr (from TypeChecker PROP-044 P5) to final SIR form.
    /// - `variant_construct` → pass through (fields already annotated)
    /// - `match_expr` → rename to `match_node` (SemanticIR convention)
    fn lower_annotated_expr(&self, val: &Value) -> Value {
        match val.get("kind").and_then(|k| k.as_str()) {
            Some("variant_construct") => {
                // Fields are already annotated with resolved_type; pass through as-is.
                val.clone()
            }
            Some("match_expr") => {
                // Rename kind to "match_node" for SemanticIR (mirrors Ruby semantic_match_node).
                let mut m = val.as_object().cloned().unwrap_or_default();
                m.insert("kind".to_string(), Value::String("match_node".to_string()));
                Value::Object(m)
            }
            _ => val.clone(),
        }
    }

    /// PROP-039 gate 5: like semantic_expr but intercepts recur() calls to emit
    /// recur_call sub-expression nodes with return_type hint. Used when lowering
    /// compute node expressions where we know the result type.
    fn semantic_expr_for_compute(&self, val: &Value, return_type: &str) -> Value {
        if let Some(map) = val.as_object() {
            if map.get("kind").and_then(|k| k.as_str()) == Some("call")
                && map.get("fn").and_then(|f| f.as_str()) == Some("recur")
            {
                let args: Vec<Value> = map.get("args")
                    .and_then(|a| a.as_array())
                    .map(|arr| arr.iter().map(|a| self.semantic_expr(a)).collect())
                    .unwrap_or_default();
                let mut node = Map::new();
                node.insert("kind".to_string(), Value::String("recur_call".to_string()));
                node.insert("args".to_string(), Value::Array(args));
                node.insert("return_type".to_string(), Value::String(return_type.to_string()));
                return Value::Object(node);
            }
            // For non-recur expressions, recurse but still intercept nested recur() calls
            // We don't know their return_type in nested position, so use "Unknown"
            if map.get("kind").and_then(|k| k.as_str()) == Some("if_expr") {
                return self.semantic_expr(val);
            }
            // igniter-string-core: delegate text stdlib calls to semantic_expr for
            // stdlib.text.* rewrite + resolved_type annotation.
            // Covers both bare names (trim, contains, ...) and already-qualified names
            // (stdlib.text.concat, stdlib.collection.concat) from the typechecker rewrite.
            {
                const TEXT_STDLIB_OPS_C: &[&str] = &[
                    "trim", "contains", "starts_with", "ends_with", "split",
                    "replace", "replace_all",
                    "byte_length", "rune_length", "grapheme_length",
                    "byte_slice", "rune_slice", "grapheme_slice",
                ];
                if map.get("kind").and_then(|k| k.as_str()) == Some("call") {
                    if let Some(fn_val) = map.get("fn").and_then(|f| f.as_str()) {
                        if TEXT_STDLIB_OPS_C.contains(&fn_val)
                            || fn_val.starts_with("stdlib.text.")
                            || fn_val == "stdlib.collection.concat"
                        {
                            return self.semantic_expr(val);
                        }
                    }
                }
            }
            let mut new_map = Map::new();
            for (k, v) in map {
                if k != "deps" {
                    new_map.insert(k.clone(), self.semantic_expr_for_compute(v, return_type));
                }
            }
            return Value::Object(new_map);
        }
        if let Value::Array(arr) = val {
            return Value::Array(arr.iter().map(|item| self.semantic_expr_for_compute(item, return_type)).collect());
        }
        self.semantic_expr(val)
    }

    fn lower_resolved_forms(&self, semantic_ir: &mut Value, resolved_program: &Value) {
        let targets = self.resolved_form_targets(resolved_program);
        if targets.is_empty() {
            return;
        }

        let Some(contracts) = semantic_ir.get_mut("contracts").and_then(|value| value.as_array_mut()) else {
            return;
        };

        for contract in contracts {
            let contract_name = contract
                .get("contract_name")
                .and_then(|value| value.as_str())
                .unwrap_or("")
                .to_string();
            let Some(nodes) = contract.get_mut("nodes").and_then(|value| value.as_array_mut()) else {
                continue;
            };

            for node in nodes {
                let node_name = node
                    .get("name")
                    .and_then(|value| value.as_str())
                    .unwrap_or("")
                    .to_string();
                let contract_decl = format!("{}::{}", contract_name, node_name);
                let Some(node_targets) = targets.get(&contract_decl) else {
                    continue;
                };
                if let Some(expr) = node.get_mut("expr") {
                    let lowered = self.lower_expr_for_targets(expr, node_targets);
                    *expr = lowered;
                }
            }
        }
    }

    fn resolved_form_targets(&self, resolved_program: &Value) -> HashMap<String, Vec<Value>> {
        let mut targets: HashMap<String, Vec<Value>> = HashMap::new();
        let Some(resolved_forms) = resolved_program.get("resolved_forms").and_then(|value| value.as_array()) else {
            return targets;
        };

        for form in resolved_forms {
            let Some(contract_decl) = form.get("contract_decl").and_then(|value| value.as_str()) else {
                continue;
            };
            targets.entry(contract_decl.to_string()).or_default().push(form.clone());
        }
        targets
    }

    fn lower_expr_for_targets(&self, expr: &Value, targets: &[Value]) -> Value {
        // LAB-COMPILER-LIVENESS-P2: non-fatal depth counter (RAII — auto-decrements on all exits)
        let _depth_guard = crate::liveness::EmLowerGuard::enter();
        let Some(map) = expr.as_object() else {
            return expr.clone();
        };
        let kind = map.get("kind").and_then(|value| value.as_str()).unwrap_or("");

        if kind == "binary_op" {
            let op = map.get("op").and_then(|value| value.as_str()).unwrap_or("");
            if let Some(target) = targets.iter().find(|target| {
                target.get("original_kind").and_then(|value| value.as_str()) == Some("binary_op") &&
                    target.get("trigger").and_then(|value| value.as_str()) == Some(op)
            }) {
                let left = map.get("left").cloned().unwrap_or(Value::Null);
                let right = map.get("right").cloned().unwrap_or(Value::Null);
                return self.lowered_form_call(target, vec![
                    self.lower_expr_for_targets(&left, targets),
                    self.lower_expr_for_targets(&right, targets),
                ]);
            }
        }

        if kind == "unary_op" {
            let op = map.get("op").and_then(|value| value.as_str()).unwrap_or("");
            if let Some(target) = targets.iter().find(|target| {
                target.get("original_kind").and_then(|value| value.as_str()) == Some("unary_op") &&
                    target.get("trigger").and_then(|value| value.as_str()) == Some(op)
            }) {
                let operand = map.get("operand").cloned().unwrap_or(Value::Null);
                return self.lowered_form_call(target, vec![self.lower_expr_for_targets(&operand, targets)]);
            }
        }

        let mut lowered = Map::new();
        for (key, value) in map {
            lowered.insert(key.clone(), match value {
                Value::Array(items) => Value::Array(items.iter().map(|item| self.lower_expr_for_targets(item, targets)).collect()),
                Value::Object(_) => self.lower_expr_for_targets(value, targets),
                _ => value.clone(),
            });
        }
        Value::Object(lowered)
    }

    fn lowered_form_call(&self, target: &Value, args: Vec<Value>) -> Value {
        let resolved_to = target.get("resolved_to").cloned().unwrap_or(Value::Null);
        let mut metadata = Map::new();
        metadata.insert("authority".to_string(), Value::String("proof_local_lab_only".to_string()));
        metadata.insert("source_kind".to_string(), target.get("original_kind").cloned().unwrap_or(Value::Null));
        metadata.insert("trigger".to_string(), target.get("trigger").cloned().unwrap_or(Value::Null));
        metadata.insert("form_id".to_string(), target.get("form_id").cloned().unwrap_or(Value::Null));
        metadata.insert("contract_decl".to_string(), target.get("contract_decl").cloned().unwrap_or(Value::Null));
        metadata.insert("typed_operands".to_string(), target.get("typed_operands").cloned().unwrap_or_else(|| Value::Array(Vec::new())));
        metadata.insert("typed_result".to_string(), target.get("typed_result").cloned().unwrap_or(Value::Null));
        metadata.insert("runtime_dispatch_required".to_string(), Value::Bool(false));
        metadata.insert("vm_linker_required".to_string(), Value::Bool(false));
        metadata.insert("stable_semanticir_node".to_string(), Value::Bool(false));

        let mut call = Map::new();
        call.insert("kind".to_string(), Value::String("call".to_string()));
        call.insert("fn".to_string(), resolved_to);
        call.insert("args".to_string(), Value::Array(args));
        call.insert("lowered_from_form".to_string(), Value::Object(metadata));
        call
            .get("fn")
            .and_then(|value| value.as_str())
            .map(|fn_name| format!("call:{}", fn_name))
            .map(|target| call.insert("lowering_target".to_string(), Value::String(target)));

        Value::Object(call)
    }

    fn typed_invariant_coverage(&self, semantic_ir: &Option<Value>) -> Vec<Value> {
        let mut coverages = Vec::new();
        if let Some(ir) = semantic_ir {
            let invariants = self.typed_program_invariants(ir.get("contracts").unwrap_or(&Value::Null));
            for node in invariants {
                let mut cov = Map::new();
                cov.insert("name".to_string(), node.get("name").cloned().unwrap_or(Value::Null));
                cov.insert("severity".to_string(), node.get("severity").cloned().unwrap_or(Value::Null));
                cov.insert("label".to_string(), node.get("label").cloned().unwrap_or(Value::Null));
                cov.insert("message".to_string(), node.get("message").cloned().unwrap_or(Value::Null));
                
                let is_error = node.get("severity").and_then(|s| s.as_str()) == Some("error");
                cov.insert("output_policy".to_string(), Value::String(if is_error { "blocking" } else { "non_blocking" }.to_string()));
                cov.insert("output_effect".to_string(), node.get("output_effect").cloned().unwrap_or(Value::Null));
                
                if let Some(meta) = node.get("source_metadata") {
                    cov.insert("source_metadata".to_string(), meta.clone());
                }
                coverages.push(Value::Object(cov));
            }
        }
        coverages
    }

    fn typed_escape_boundaries(&self, contract: &TypedContract) -> Value {
        let mut caps = HashSet::new();
        let mut has_stream = false;

        for decl in &contract.declarations {
            if decl.node_fragment_class.as_deref() == Some("temporal") {
                if let Some(cap) = &decl.required_capability {
                    caps.insert(cap.clone());
                }
            }
            if decl.kind == "stream" {
                has_stream = true;
            }
        }

        let mut sorted_caps: Vec<String> = caps.into_iter().collect();
        sorted_caps.sort();

        let mut boundaries = Vec::new();
        for cap in sorted_caps {
            let mut b = Map::new();
            b.insert("name".to_string(), Value::String(cap.clone()));
            b.insert("required_caps".to_string(), json!(vec![cap.clone()]));
            
            let observation = if cap == "bihistory_read" {
                "bihistory_access_observation"
            } else {
                "history_access_observation"
            };
            b.insert("produces".to_string(), json!(vec![observation]));
            boundaries.push(Value::Object(b));
        }

        if has_stream {
            let mut b = Map::new();
            b.insert("name".to_string(), Value::String("stream_input".to_string()));
            b.insert("required_caps".to_string(), json!(vec!["stream_input"]));
            b.insert("produces".to_string(), json!(vec!["stream_window_observation"]));
            boundaries.push(Value::Object(b));
        }

        Value::Array(boundaries)
    }

    fn temporal_input_node(&self, decl: &TypedDecl) -> Value {
        let mut m = Map::new();
        m.insert("kind".to_string(), Value::String("temporal_input_node".to_string()));
        m.insert("name".to_string(), Value::String(decl.name.clone()));
        m.insert("type".to_string(), self.temporal_type(&decl.type_info));
        m.insert("store_ref".to_string(), decl.from.as_ref().map_or(Value::Null, |f| Value::String(f.clone())));
        m.insert("lifecycle".to_string(), Value::String(decl.lifecycle.as_deref().unwrap_or("durable").to_string()));
        m.insert("axis".to_string(), decl.temporal_axis.as_ref().map_or(Value::Null, |a| Value::String(a.clone())));
        m.insert("node_fragment_class".to_string(), decl.node_fragment_class.as_ref().map_or(Value::Null, |n| Value::String(n.clone())));
        m.insert("value_fragment_class".to_string(), decl.value_fragment_class.as_ref().map_or(Value::Null, |v| Value::String(v.clone())));
        m.insert("required_capability".to_string(), decl.required_capability.as_ref().map_or(Value::Null, |r| Value::String(r.clone())));
        m.insert("required_caps".to_string(), json!(decl.required_capability.as_ref().map_or(Vec::new(), |r| vec![r.clone()])));
        m.insert("fragment".to_string(), Value::String(decl.fragment_class.clone()));
        Value::Object(m)
    }

    fn temporal_access_node(&self, decl: &TypedDecl) -> Option<Value> {
        let expr = decl.expr.as_ref()?;
        if let Expr::Call { fn_name, args } = expr {
            match fn_name.as_str() {
                "history_at" => {
                    let source_ref = self.ref_name(&args[0])?;
                    let as_of_ref = self.ref_name(&args[1])?;
                    
                    let mut m = Map::new();
                    m.insert("kind".to_string(), Value::String("temporal_access_node".to_string()));
                    m.insert("name".to_string(), Value::String(decl.name.clone()));
                    m.insert("source_ref".to_string(), Value::String(source_ref));
                    m.insert("access".to_string(), Value::String("point".to_string()));
                    m.insert("temporal_axis".to_string(), Value::String("valid_time".to_string()));
                    m.insert("axis".to_string(), Value::String("valid_time".to_string()));
                    m.insert("as_of_ref".to_string(), Value::String(as_of_ref.clone()));
                    m.insert("coordinate_refs".to_string(), json!({ "as_of": as_of_ref }));
                    m.insert("result_type".to_string(), decl.type_info.clone());
                    m.insert("node_fragment_class".to_string(), Value::String("temporal".to_string()));
                    m.insert("value_fragment_class".to_string(), Value::String("core".to_string()));
                    m.insert("required_capability".to_string(), Value::String("history_read".to_string()));
                    m.insert("required_caps".to_string(), json!(vec!["history_read"]));
                    m.insert("evidence_policy".to_string(), Value::String("link_selected_append_observation".to_string()));
                    m.insert("fragment".to_string(), Value::String("temporal".to_string()));
                    Some(Value::Object(m))
                }
                "bihistory_at" => {
                    let source_ref = self.ref_name(&args[0])?;
                    let vt_ref = self.ref_name(&args[1])?;
                    let tt_ref = self.ref_name(&args[2])?;
                    
                    let mut m = Map::new();
                    m.insert("kind".to_string(), Value::String("temporal_access_node".to_string()));
                    m.insert("name".to_string(), Value::String(decl.name.clone()));
                    m.insert("source_ref".to_string(), Value::String(source_ref));
                    m.insert("access".to_string(), Value::String("point".to_string()));
                    m.insert("temporal_axis".to_string(), Value::String("bitemporal".to_string()));
                    m.insert("axis".to_string(), Value::String("bitemporal".to_string()));
                    m.insert("valid_time_ref".to_string(), Value::String(vt_ref.clone()));
                    m.insert("transaction_time_ref".to_string(), Value::String(tt_ref.clone()));
                    m.insert("coordinate_refs".to_string(), json!({ "valid_time": vt_ref, "transaction_time": tt_ref }));
                    m.insert("result_type".to_string(), decl.type_info.clone());
                    m.insert("node_fragment_class".to_string(), Value::String("temporal".to_string()));
                    m.insert("value_fragment_class".to_string(), Value::String("core".to_string()));
                    m.insert("required_capability".to_string(), Value::String("bihistory_read".to_string()));
                    m.insert("required_caps".to_string(), json!(vec!["bihistory_read"]));
                    m.insert("evidence_policy".to_string(), Value::String("link_selected_event_observation".to_string()));
                    m.insert("fragment".to_string(), Value::String("temporal".to_string()));
                    Some(Value::Object(m))
                }
                _ => None
            }
        } else {
            None
        }
    }

    fn ref_name(&self, expr: &Expr) -> Option<String> {
        if let Expr::Ref { name } = expr {
            Some(name.clone())
        } else {
            None
        }
    }

    fn temporal_type(&self, type_info: &Value) -> Value {
        if let Some(map) = type_info.as_object() {
            let constructor = map.get("name").or_else(|| map.get("constructor")).cloned().unwrap_or(Value::Null);
            let params = map.get("params").and_then(|p| p.as_array());
            let element_type = if let Some(params) = params {
                if !params.is_empty() {
                    Value::String(self.type_display(&params[0]))
                } else {
                    Value::String("Unknown".to_string())
                }
            } else {
                Value::String("Unknown".to_string())
            };
            
            let mut m = Map::new();
            m.insert("constructor".to_string(), constructor);
            m.insert("element_type".to_string(), element_type);
            Value::Object(m)
        } else {
            type_info.clone()
        }
    }

    fn invariant_node(&self, decl: &TypedDecl) -> Value {
        let severity = decl.severity.as_deref().unwrap_or("error");
        let output_effect = decl.output_effect.clone().unwrap_or_else(|| self.invariant_output_effect(severity));
        
        let mut m = Map::new();
        m.insert("kind".to_string(), Value::String("invariant_node".to_string()));
        m.insert("name".to_string(), Value::String(decl.name.clone()));
        m.insert("predicate".to_string(), decl.predicate_ref.as_ref().map_or(Value::Null, |p| Value::String(p.clone())));
        m.insert("predicate_ref".to_string(), decl.predicate_ref.as_ref().map_or(Value::Null, |p| Value::String(p.clone())));
        m.insert("predicate_type".to_string(), Value::String("Bool".to_string()));
        m.insert("severity".to_string(), Value::String(severity.to_string()));
        m.insert("label".to_string(), decl.label.as_ref().map_or(Value::Null, |l| Value::String(l.clone())));
        m.insert("message".to_string(), decl.message.as_ref().map_or(Value::Null, |msg| Value::String(msg.clone())));
        m.insert("overridable_with".to_string(), decl.overridable_with.as_ref().map_or(Value::Null, |o| Value::String(o.clone())));
        m.insert("output_effect".to_string(), Value::String(output_effect));
        m.insert("deps".to_string(), json!(decl.deps));
        m.insert("fragment".to_string(), Value::String(decl.fragment_class.clone()));
        Value::Object(m)
    }

    fn invariant_output_effect(&self, severity: &str) -> String {
        match severity {
            "error" => "blocks".to_string(),
            "warn" => "warns".to_string(),
            "soft" => "uncertain".to_string(),
            "metric" => "metric".to_string(),
            _ => "blocks".to_string(),
        }
    }

    fn stream_input_node(&self, decl: &TypedDecl, declarations: &[TypedDecl]) -> Value {
        let mut m = Map::new();
        m.insert("kind".to_string(), Value::String("stream_input_node".to_string()));
        m.insert("name".to_string(), Value::String(decl.name.clone()));
        m.insert("type".to_string(), Value::String(self.type_display(&decl.type_info)));
        m.insert("window_ref".to_string(), Value::String(self.first_window_ref(declarations)));
        m.insert("escape_capability".to_string(), Value::String("stream_input".to_string()));
        m.insert("fragment".to_string(), Value::String(decl.fragment_class.clone()));
        Value::Object(m)
    }

    fn first_window_ref(&self, declarations: &[TypedDecl]) -> String {
        for decl in declarations {
            if decl.kind == "window" {
                return decl.name.clone();
            }
        }
        "integer/{device_id}".to_string()
    }

    fn window_decl_node(&self, decl: &TypedDecl) -> Value {
        let mut m = Map::new();
        m.insert("kind".to_string(), Value::String("window_decl_node".to_string()));
        m.insert("ref".to_string(), Value::String(decl.name.clone()));
        m.insert("key".to_string(), Value::String(decl.name.clone()));

        let mut kind = "count".to_string();
        let mut size = None;
        let mut on_close = "snapshot".to_string();

        if let Some(opts) = &decl.options {
            if let Some(crate::parser::WindowValue::Str(k)) = opts.get("kind") {
                kind = k.clone();
            }
            if let Some(crate::parser::WindowValue::Int(s)) = opts.get("size") {
                size = Some(*s);
            }
            if let Some(crate::parser::WindowValue::Str(o)) = opts.get("on_close") {
                on_close = o.clone();
            }
        }

        m.insert("window_kind".to_string(), Value::String(kind));
        m.insert("on_close".to_string(), Value::String(on_close));
        if let Some(s) = size {
            m.insert("size".to_string(), Value::Number(s.into()));
        }
        
        let bounded = size.is_some() || decl.options.as_ref().map_or(false, |o| o.contains_key("period") || o.contains_key("idle"));
        m.insert("bounded".to_string(), Value::Bool(bounded));
        
        Value::Object(m)
    }

    fn fold_stream_node(&self, decl: &TypedDecl, declarations: &[TypedDecl]) -> Value {
        let mut stream_ref = "readings".to_string();
        let mut init = json!({ "kind": "integer_literal", "value": 0 });
        let mut fn_ref = "integer_sum_lambda".to_string();
        let mut event_binding = json!({
            "event_ref": "event",
            "value_ref": "reading",
            "value_path": ["value"]
        });

        if let Some(Expr::Call { args, .. }) = &decl.expr {
            if args.len() >= 1 {
                if let Expr::Ref { name } = &args[0] {
                    stream_ref = name.clone();
                }
            }
            if args.len() >= 2 {
                if let Expr::Literal { value, type_tag } = &args[1] {
                    init = json!({
                        "kind": format!("{}_literal", type_tag.to_lowercase()),
                        "value": value
                    });
                }
            }
            if args.len() >= 3 {
                if let Expr::Lambda { params, body } = &args[2] {
                    if self.is_expr_integer_sum_lambda(&args[2]) {
                        fn_ref = "integer_sum_lambda".to_string();
                    } else {
                        // Generate lambda hash
                        let val = json!(args[2]);
                        let hash = blake3::hash(serde_json::to_string(&val).unwrap().as_bytes());
                        fn_ref = format!("lambda/{}", &hash.to_string()[0..16]);
                    }
                    if params.len() >= 2 {
                        event_binding = json!({
                            "event_ref": "event",
                            "value_ref": params[1],
                            "value_path": ["value"]
                        });
                    }
                }
            }
        }

        let bound = json!({
            "kind": "window_bounded",
            "window_ref": self.first_window_ref(declarations)
        });

        let mut m = Map::new();
        m.insert("kind".to_string(), Value::String("fold_stream_node".to_string()));
        m.insert("name".to_string(), Value::String(decl.name.clone()));
        m.insert("stream_ref".to_string(), Value::String(stream_ref));
        m.insert("init".to_string(), init);
        m.insert("fn_ref".to_string(), Value::String(fn_ref));
        m.insert("bound".to_string(), bound);
        m.insert("event_binding".to_string(), event_binding);
        m.insert("result_type".to_string(), decl.type_info.clone());
        m.insert("escape_capability".to_string(), Value::String("stream_input".to_string()));
        m.insert("result_fragment".to_string(), Value::String(decl.fragment_class.clone()));
        Value::Object(m)
    }

    fn is_expr_integer_sum_lambda(&self, expr: &Expr) -> bool {
        if let Expr::Lambda { params, body } = expr {
            if params.is_empty() {
                return false;
            }
            let param0 = &params[0];
            match body.as_ref() {
                crate::parser::ExprOrBlock::Expr(Expr::BinaryOp { op, left, right }) => {
                    if op == "+" {
                        if let Expr::Ref { name } = left.as_ref() {
                            return name == param0;
                        }
                    }
                }
                _ => {}
            }
        }
        false
    }

    fn type_display(&self, type_val: &Value) -> String {
        type_display(type_val)
    }

    fn contract_ref(&self, contract_ir: &Value) -> String {
        let mut body = contract_ir.as_object().cloned().unwrap_or_default();
        body.remove("contract_ref");
        body.remove("diagnostics");
        let canonical = serde_json::to_string(&Value::Object(body)).unwrap();
        let mut hasher = Sha256::new();
        hasher.update(canonical.as_bytes());
        let hash = format!("{:x}", hasher.finalize());
        let cname = contract_ir.get("contract_name").and_then(|n| n.as_str()).unwrap_or("Unknown");
        format!("contract/{}/sha256:{}", cname, &hash[0..24])
    }

    fn try_optimize_map_reduce(&self, val: &Value) -> Option<Value> {
        let map = val.as_object()?;
        if map.get("kind").and_then(|k| k.as_str()) != Some("call") {
            return None;
        }
        let fn_name = map.get("fn").and_then(|f| f.as_str())?;
        let args = map.get("args").and_then(|a| a.as_array())?;

        if !matches!(fn_name, "count" | "first" | "last" | "fold" | "sum" | "avg" | "min" | "max") {
            return None;
        }

        if args.is_empty() {
            return None;
        }

        let mut pipeline = Vec::new();
        let source;

        match fn_name {
            "count" => {
                let inner_coll = &args[0];
                source = self.build_pipeline(inner_coll, &mut pipeline);
                pipeline.push(json!({
                    "kind": "count"
                }));
            }
            "first" | "last" => {
                let inner_coll = &args[0];
                source = self.build_pipeline(inner_coll, &mut pipeline);
                pipeline.push(json!({
                    "kind": fn_name
                }));
            }
            "sum" | "avg" | "min" | "max" => {
                if args.len() < 2 {
                    return None;
                }
                let inner_coll = &args[0];
                let field = &args[1];
                let field_name = match field.get("value").and_then(|v| v.as_str()) {
                    Some(s) => s.to_string(),
                    None => return None,
                };
                source = self.build_pipeline(inner_coll, &mut pipeline);
                pipeline.push(json!({
                    "kind": fn_name,
                    "field": field_name
                }));
            }
            "fold" => {
                if args.len() < 3 {
                    return None;
                }
                let inner_coll = &args[0];
                let init = &args[1];
                let lambda = &args[2];

                let param_acc = lambda.get("params")
                    .and_then(|p| p.as_array())
                    .and_then(|p| p.get(0))
                    .and_then(|p| p.as_str())
                    .unwrap_or("acc")
                    .to_string();

                let param_val = lambda.get("params")
                    .and_then(|p| p.as_array())
                    .and_then(|p| p.get(1))
                    .and_then(|p| p.as_str())
                    .unwrap_or("x")
                    .to_string();

                let body = lambda.get("body").unwrap_or(&Value::Null);

                source = self.build_pipeline(inner_coll, &mut pipeline);
                pipeline.push(json!({
                    "kind": "fold",
                    "param_acc": param_acc,
                    "param_val": param_val,
                    "init": self.semantic_expr(init),
                    "body": self.semantic_expr(body)
                }));
            }
            _ => unreachable!(),
        }

        let is_range = source.as_object()
            .and_then(|s| s.get("kind"))
            .and_then(|k| k.as_str()) == Some("range");

        if pipeline.len() > 1 || is_range {
            Some(json!({
                "kind": "map_reduce_aggregate",
                "source": source,
                "pipeline": pipeline
            }))
        } else {
            None
        }
    }

    fn build_pipeline(&self, current: &Value, pipeline: &mut Vec<Value>) -> Value {
        // LAB-COMPILER-LIVENESS-P2: non-fatal depth counter (RAII — auto-decrements on all exits)
        let _depth_guard = crate::liveness::EmPipelineGuard::enter();
        if let Some(map) = current.as_object() {
            if map.get("kind").and_then(|k| k.as_str()) == Some("call") {
                if let Some(fn_name) = map.get("fn").and_then(|f| f.as_str()) {
                    let args = map.get("args").and_then(|a| a.as_array());
                    match fn_name {
                        "filter" => {
                            if let Some(args) = args {
                                if args.len() >= 2 {
                                    let inner_coll = &args[0];
                                    let lambda = &args[1];
                                    let param = lambda.get("params")
                                        .and_then(|p| p.as_array())
                                        .and_then(|p| p.get(0))
                                        .and_then(|p| p.as_str())
                                        .unwrap_or("x")
                                        .to_string();
                                    let body = lambda.get("body").unwrap_or(&Value::Null);
                                    
                                    let source = self.build_pipeline(inner_coll, pipeline);
                                    pipeline.push(json!({
                                        "kind": "filter",
                                        "param": param,
                                        "body": self.semantic_expr(body)
                                    }));
                                    return source;
                                }
                            }
                        }
                        "map" => {
                            if let Some(args) = args {
                                if args.len() >= 2 {
                                    let inner_coll = &args[0];
                                    let lambda = &args[1];
                                    let param = lambda.get("params")
                                        .and_then(|p| p.as_array())
                                        .and_then(|p| p.get(0))
                                        .and_then(|p| p.as_str())
                                        .unwrap_or("x")
                                        .to_string();
                                    let body = lambda.get("body").unwrap_or(&Value::Null);
                                    
                                    let source = self.build_pipeline(inner_coll, pipeline);
                                    pipeline.push(json!({
                                        "kind": "map",
                                        "param": param,
                                        "body": self.semantic_expr(body)
                                    }));
                                    return source;
                                }
                            }
                        }
                        "range" => {
                            if let Some(args) = args {
                                if args.len() >= 2 {
                                    return json!({
                                        "kind": "range",
                                        "start": self.semantic_expr(&args[0]),
                                        "end": self.semantic_expr(&args[1])
                                    });
                                }
                            }
                        }
                        _ => {}
                    }
                }
            }
        }
        self.semantic_expr(current)
    }

    fn loop_node(&self, decl: &TypedDecl, declarations: &[TypedDecl]) -> Value {
        let mut node = Map::new();
        // G3c: canon SemanticIR shape — kind="loop_node" (was "loop")
        node.insert("kind".to_string(), Value::String("loop_node".to_string()));
        node.insert("name".to_string(), Value::String(decl.name.clone()));

        // G3b/G3c: loop_class from classifier options ("finite" | "budgeted")
        let loop_class = decl.options.as_ref()
            .and_then(|o| o.get("loop_class"))
            .and_then(|v| if let crate::parser::WindowValue::Str(s) = v { Some(s.as_str()) } else { None })
            .unwrap_or("budgeted");
        node.insert("loop_class".to_string(), Value::String(loop_class.to_string()));

        // termination evidence — canon SemanticIR field
        let termination = if loop_class == "finite" {
            "collection_exhaustion"
        } else {
            "budget_exhaustion"
        };
        node.insert("termination".to_string(), Value::String(termination.to_string()));

        // source_ref: collection name (canon SemanticIR field)
        if let Some(crate::parser::Expr::Ref { name: ref ref_name }) = decl.expr {
            node.insert("source_ref".to_string(), Value::String(ref_name.clone()));
        }

        // G1: item variable
        if let Some(item_var) = decl.options.as_ref()
            .and_then(|o| o.get("item"))
            .and_then(|v| if let crate::parser::WindowValue::Str(s) = v { Some(s.clone()) } else { None })
        {
            node.insert("item".to_string(), Value::String(item_var));
        }

        // max_steps at top level for budgeted loops (canon + VM compat)
        if let Some(max_steps_val) = decl.options.as_ref()
            .and_then(|o| o.get("max_steps"))
            .and_then(|v| if let crate::parser::WindowValue::Int(n) = v { Some(*n) } else { None })
        {
            node.insert("max_steps".to_string(), Value::Number(max_steps_val.into()));
        }

        node.insert("fragment".to_string(), Value::String(decl.fragment_class.clone()));

        // Keep full options for downstream consumers (VM compiler reads max_steps here too)
        if let Some(options) = &decl.options {
            node.insert("options".to_string(), serde_json::to_value(options).unwrap());
        }

        // expr for VM compiler backward compat
        node.insert("expr".to_string(), self.semantic_expr(&json!(decl.expr)));

        // PROP-039 gate 8: item_type from collection element type
        if let Some(item_type_val) = decl.options.as_ref()
            .and_then(|o| o.get("item_type"))
            .and_then(|v| if let crate::parser::WindowValue::Str(s) = v { Some(s.clone()) } else { None })
        {
            node.insert("item_type".to_string(), Value::String(item_type_val));
        }

        // PROP-039 gate 8: body_nodes (VM execution — compute only) and body (canon typed IR)
        let mut body_nodes_vm = Vec::new();
        let mut canon_body = Vec::new();
        if let Some(nodes) = &decl.body_nodes {
            for inner in nodes {
                if inner.kind == "lead" {
                    // lead_node for canon body
                    let type_str = inner.type_info.get("name")
                        .and_then(|v| v.as_str())
                        .map(|s| s.to_string())
                        .or_else(|| inner.type_info.as_str().map(|s| s.to_string()))
                        .unwrap_or_else(|| "Unknown".to_string());
                    canon_body.push(json!({
                        "kind": "lead_node",
                        "name": inner.name,
                        "type": type_str,
                        "initial": self.semantic_expr(&json!(inner.expr))
                    }));
                } else if inner.kind == "compute" {
                    // compute_node for canon body
                    canon_body.push(json!({
                        "kind": "compute_node",
                        "name": inner.name,
                        "expr": self.semantic_expr(&json!(inner.expr))
                    }));
                    // Also emit to body_nodes for VM backward compat
                    if let Some(val) = self.typed_node(inner, declarations, "") {
                        body_nodes_vm.push(val);
                    }
                } else if let Some(val) = self.typed_node(inner, declarations, "") {
                    body_nodes_vm.push(val);
                }
            }
        }
        // body_nodes: lab-local VM execution field (compute nodes only — backward compat)
        node.insert("body_nodes".to_string(), Value::Array(body_nodes_vm));
        // body: canon gate 8 typed IR (lead_node + compute_node)
        node.insert("body".to_string(), Value::Array(canon_body));
        Value::Object(node)
    }

    fn service_loop_node(&self, decl: &TypedDecl, declarations: &[TypedDecl]) -> Value {
        let mut node = Map::new();
        node.insert("kind".to_string(), Value::String("service_loop_node".to_string()));
        node.insert("name".to_string(), Value::String(decl.name.clone()));
        
        let mut interval_map = Map::new();
        if let Some(options) = &decl.options {
            if let Some(crate::parser::WindowValue::Int(v)) = options.get("interval_value") {
                interval_map.insert("value".to_string(), json!(v));
            }
            if let Some(crate::parser::WindowValue::Str(u)) = options.get("interval_unit") {
                interval_map.insert("unit".to_string(), json!(u));
            }
        }
        node.insert("interval".to_string(), Value::Object(interval_map));
        node.insert("fragment".to_string(), Value::String("escape".to_string()));
        node.insert("temporal_binding".to_string(), Value::String(format!("{}.time", decl.name)));
        
        let mut body_nodes = Vec::new();
        if let Some(nodes) = &decl.body_nodes {
            for inner in nodes {
                if let Some(val) = self.typed_node(inner, declarations, "") {
                    body_nodes.push(val);
                }
            }
        }
        node.insert("body_nodes".to_string(), Value::Array(body_nodes));
        Value::Object(node)
    }
}


fn type_display(type_val: &Value) -> String {
    match type_val {
        Value::String(s) => s.clone(),
        Value::Object(map) => {
            let name = map.get("name").and_then(|n| n.as_str()).unwrap_or("Unknown");
            let params = map.get("params").and_then(|p| p.as_array());
            if let Some(params) = params {
                if params.is_empty() {
                    name.to_string()
                } else {
                    let param_strs: Vec<String> = params.iter().map(|p| type_display(p)).collect();
                    format!("{}[{}]", name, param_strs.join(", "))
                }
            } else {
                name.to_string()
            }
        }
        _ => "Unknown".to_string(),
    }
}

fn type_ref_to_string(tr: &crate::parser::TypeRef) -> String {
    match tr {
        crate::parser::TypeRef::Simple(s) => s.clone(),
        crate::parser::TypeRef::Structured { name, params, .. } => {
            if params.is_empty() {
                name.clone()
            } else {
                let param_strs: Vec<String> = params.iter().map(type_ref_to_string).collect();
                format!("{}[{}]", name, param_strs.join(","))
            }
        }
        crate::parser::TypeRef::DimsRecord { dims, .. } => {
            let mut parts: Vec<String> = dims.iter().map(|(k, v)| format!("{}:{}", k, type_ref_to_string(v))).collect();
            parts.sort();
            format!("Dims[{}]", parts.join(","))
        }
    }
}
