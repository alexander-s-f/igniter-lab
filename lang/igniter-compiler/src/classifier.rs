use crate::parser::{
    AssumptionDecl, BodyDecl, ContractDecl, EntrypointDecl, Expr, ExprOrBlock, OlapPointDecl,
    SizeRelationDecl, SourceFile, StepDecl, TypeDecl, TypeRef, VariantDecl, WindowValue,
};
use sha2::{Digest, Sha256};
use std::collections::{HashMap, HashSet};

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ClassifiedProgram {
    pub kind: String, // "classified_program"
    pub classifier_version: String,
    pub program_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source_path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source_hash: Option<String>,
    pub grammar_version: String,
    pub module: Option<String>,
    pub type_declarations: Vec<ClassifiedTypeDecl>,
    pub contracts: Vec<ClassifiedContract>,
    pub oof_log: Vec<ClassifierDiagnostic>,
    pub semantic_ir_ref: serde_json::Value,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub assumption_registry: Option<Vec<serde_json::Value>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub olap_points: Option<Vec<OlapPointDecl>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub entrypoint: Option<EntrypointDecl>,
    pub pass_result: String,
    /// PROP-041 T2: module-level size_relation declarations passed through for TypeChecker registry
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub size_relations: Vec<SizeRelationDecl>,
    /// PROP-044 P3: module-level variant declarations passed through for TypeChecker variant_shapes
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub variant_declarations: Vec<VariantDecl>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ClassifiedTypeDecl {
    pub kind: String, // "type"
    pub name: String,
    pub fields: Vec<ClassifiedFieldDecl>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ClassifiedFieldDecl {
    pub name: String,
    pub type_annotation: serde_json::Value,
    pub optional: bool,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ClassifiedContract {
    pub kind: String, // "classified_contract"
    pub contract_id: String,
    pub name: String,
    pub modifier: String,
    pub fragment_class: String,
    pub symbols: Vec<ClassifiedSymbol>,
    pub declarations: Vec<ClassifiedDecl>,
    pub dependency_graph: DependencyGraph,
    pub oof_log: Vec<ClassifierDiagnostic>,
    /// PROP-039 OOF-R3: named decreases variant extracted for TypeChecker gate.
    /// None for fuel_bounded, decreases fuel, or contracts without a decreases declaration.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub decreases_variant: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub assumption_refs: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub specialization_of: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub type_args: Option<HashMap<String, String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub implements: Option<crate::parser::TypeRefNode>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ClassifiedSymbol {
    pub name: String,
    pub kind: String,
    pub fragment_class: String,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ClassifiedDecl {
    pub decl_id: String,
    pub kind: String,
    pub name: String,
    pub fragment_class: String,
    pub deps: Vec<String>,
    pub missing_refs: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub type_annotation: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub expr_kind: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub expr: Option<Expr>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub options: Option<HashMap<String, WindowValue>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub node_fragment_class: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub value_fragment_class: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub required_capability: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub temporal_axis: Option<String>,
    // Invariant fields:
    #[serde(skip_serializing_if = "Option::is_none")]
    pub predicate_ref: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub severity: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub label: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub overridable_with: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub lifecycle: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub body_nodes: Option<Vec<ClassifiedDecl>>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct DependencyGraph {
    pub nodes: Vec<String>,
    pub edges: Vec<DependencyEdge>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct DependencyEdge {
    pub from: String,
    pub to: String,
    pub kind: String,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ClassifierDiagnostic {
    pub rule: String,
    pub message: String,
    pub node: String,
    pub line: Option<usize>,
}

pub struct Classifier {
    version: String,
}

impl Classifier {
    pub fn new() -> Self {
        Self {
            version: "classifier-pass-executable-proof-v0".to_string(),
        }
    }

    pub fn classify(
        &self,
        parsed: &SourceFile,
        sample_input: &serde_json::Value,
    ) -> ClassifiedProgram {
        let registry = self.build_assumption_registry(parsed);
        let mut contracts = Vec::new();
        let mut oof_log = Vec::new();

        for contract in &parsed.contracts {
            let mut classified_c =
                self.classify_contract(parsed, contract, sample_input, &registry);
            oof_log.append(&mut classified_c.oof_log.clone());
            contracts.push(classified_c);
        }

        let type_declarations = parsed
            .types
            .iter()
            .map(|t| ClassifiedTypeDecl {
                kind: "type".to_string(),
                name: t.name.clone(),
                fields: t
                    .fields
                    .iter()
                    .map(|f| ClassifiedFieldDecl {
                        name: f.name.clone(),
                        type_annotation: serde_json::to_value(&f.type_annotation).unwrap(),
                        optional: f.optional,
                    })
                    .collect(),
            })
            .collect();

        let pass_result = if oof_log
            .iter()
            .any(|d| d.rule.starts_with("OOF-") || d.rule.starts_with("E-IO-"))
        {
            "oof".to_string()
        } else {
            "ok".to_string()
        };

        let source_path = parsed.source_path.as_deref().unwrap_or("");
        let source_hash = parsed.source_hash.as_deref().unwrap_or("");
        let seed = format!(
            "{}|{}|{}|{}",
            source_path, parsed.grammar_version, source_hash, self.version
        );
        let program_id = format!("classifier_pass/{:x}", Sha256::digest(seed.as_bytes()));

        ClassifiedProgram {
            kind: "classified_program".to_string(),
            classifier_version: self.version.clone(),
            program_id: program_id[0..32].to_string(),
            source_path: parsed.source_path.clone(),
            source_hash: parsed.source_hash.clone(),
            grammar_version: parsed.grammar_version.clone(),
            module: parsed.module.clone(),
            type_declarations,
            contracts,
            oof_log,
            semantic_ir_ref: serde_json::Value::Null,
            assumption_registry: if registry.is_empty() {
                None
            } else {
                Some(registry.values().cloned().collect())
            },
            olap_points: if parsed.olap_points.is_empty() {
                None
            } else {
                Some(parsed.olap_points.clone())
            },
            entrypoint: parsed.entrypoint.clone(),
            pass_result,
            // PROP-041 T2: pass-through size_relation declarations for TypeChecker registry
            size_relations: parsed.size_relations.clone(),
            // PROP-044 P3: pass-through variant declarations for TypeChecker variant_shapes
            variant_declarations: parsed.variants.clone(),
        }
    }

    fn build_assumption_registry(&self, parsed: &SourceFile) -> HashMap<String, serde_json::Value> {
        let mut map = HashMap::new();
        for a in &parsed.assumptions {
            let mut entry = serde_json::Map::new();
            entry.insert(
                "kind".to_string(),
                serde_json::Value::String("assumption_entry".to_string()),
            );
            entry.insert(
                "name".to_string(),
                serde_json::Value::String(a.name.clone()),
            );
            entry.insert(
                "fields".to_string(),
                serde_json::to_value(&a.fields).unwrap(),
            );
            entry.insert(
                "declared_in_module".to_string(),
                serde_json::to_value(&parsed.module).unwrap(),
            );
            map.insert(a.name.clone(), serde_json::Value::Object(entry));
        }
        map
    }

    fn classify_contract(
        &self,
        parsed: &SourceFile,
        contract: &ContractDecl,
        sample_input: &serde_json::Value,
        registry: &HashMap<String, serde_json::Value>,
    ) -> ClassifiedContract {
        let mut diagnostics = Vec::new();
        let mut declarations = Vec::new();
        let mut assumption_refs = Vec::new();
        let mut symbol_fragments = HashMap::new();
        let mut symbol_kinds = HashMap::new();
        let mut compute_exprs = HashMap::new();
        let mut window_declarations = Vec::new();
        let mut fold_stream_stream_refs: HashMap<String, Vec<String>> = HashMap::new();

        // Populate OLAP points:
        for point in &parsed.olap_points {
            symbol_fragments.insert(point.name.clone(), "escape".to_string());
            symbol_kinds.insert(point.name.clone(), "olap_point".to_string());
        }

        // First pass: populate symbol table
        for node in &contract.body {
            match node {
                BodyDecl::Input { name, .. } => {
                    symbol_fragments.insert(name.clone(), "core".to_string());
                    symbol_kinds.insert(name.clone(), "input".to_string());
                }
                BodyDecl::Stream { name, .. } => {
                    symbol_fragments.insert(name.clone(), "escape".to_string());
                    symbol_kinds.insert(name.clone(), "stream".to_string());
                }
                BodyDecl::Read {
                    name,
                    type_annotation,
                    ..
                } => {
                    let is_temp = self.is_temporal_type(type_annotation);
                    let fragment = if is_temp {
                        "temporal".to_string()
                    } else {
                        "escape".to_string()
                    };
                    symbol_fragments.insert(
                        name.clone(),
                        if is_temp {
                            "core".to_string()
                        } else {
                            "escape".to_string()
                        },
                    );
                    symbol_kinds.insert(
                        name.clone(),
                        if is_temp {
                            "temporal_read".to_string()
                        } else {
                            "read".to_string()
                        },
                    );
                }
                BodyDecl::UsesAssumptions { name } => {
                    symbol_fragments.insert(name.clone(), "core".to_string());
                    symbol_kinds.insert(name.clone(), "assumption".to_string());
                }
                BodyDecl::FoldStream { name, bound, .. } => {
                    let is_bounded = bound.is_some();
                    symbol_fragments.insert(
                        name.clone(),
                        if is_bounded {
                            "core".to_string()
                        } else {
                            "oof".to_string()
                        },
                    );
                    symbol_kinds.insert(name.clone(), "fold_stream".to_string());
                }
                BodyDecl::Compute { name, .. } => {
                    symbol_kinds.insert(name.clone(), "compute".to_string());
                }
                BodyDecl::Capability { name, .. } => {
                    symbol_fragments.insert(name.clone(), "escape".to_string());
                    symbol_kinds.insert(name.clone(), "capability".to_string());
                }
                BodyDecl::Effect { name, .. } => {
                    symbol_fragments.insert(name.clone(), "escape".to_string());
                    symbol_kinds.insert(name.clone(), "effect".to_string());
                }
                BodyDecl::Loop {
                    name,
                    body: loop_body,
                    ..
                } => {
                    symbol_fragments.insert(name.clone(), "core".to_string());
                    symbol_kinds.insert(name.clone(), "loop".to_string());
                    for inner in loop_body {
                        match inner {
                            BodyDecl::Compute {
                                name: inner_name, ..
                            } => {
                                symbol_kinds.insert(inner_name.clone(), "compute".to_string());
                            }
                            BodyDecl::Lead {
                                name: lead_name, ..
                            } => {
                                symbol_kinds.insert(lead_name.clone(), "lead".to_string());
                            }
                            _ => {}
                        }
                    }
                }
                BodyDecl::ServiceLoop {
                    name,
                    body: loop_body,
                    ..
                } => {
                    symbol_fragments.insert(name.clone(), "escape".to_string());
                    symbol_kinds.insert(name.clone(), "service_loop".to_string());
                    for inner in loop_body {
                        if let BodyDecl::Compute {
                            name: inner_name, ..
                        } = inner
                        {
                            symbol_kinds.insert(inner_name.clone(), "compute".to_string());
                            symbol_fragments.insert(inner_name.clone(), "escape".to_string());
                        }
                    }
                }
                _ => {}
            }
        }

        // Build capability/effect maps for I/O checking (two-pass validation)
        let mut capabilities = HashMap::new();
        let mut effects = HashMap::new();

        // Pass 1: Gather declared capabilities
        for node in &contract.body {
            if let BodyDecl::Capability {
                name,
                type_annotation,
            } = node
            {
                capabilities.insert(name.clone(), type_annotation.clone());
            }
        }

        // Pass 2: Process and validate effects
        for node in &contract.body {
            if let BodyDecl::Effect {
                name,
                capability_ref,
            } = node
            {
                // LANG-EFFECT-NAME-PARITY-P2: effect names are LABELS/verbs, NOT authority
                // selectors. The host keys execution by the capability TYPE + passport, never by
                // the effect verb. So ANY well-formed effect name is accepted (matching Ruby) — a
                // malformed name already fails at parse. Authority lives in the capability binding
                // validated just below (E-IO-CAP-UNKNOWN). (Was: a hardcoded read/write allowlist
                // emitting E-IO-EFFECT-UNKNOWN, stricter than the host's authority model.)
                if !capabilities.contains_key(capability_ref) {
                    diagnostics.push(ClassifierDiagnostic {
                        rule: "E-IO-CAP-UNKNOWN".to_string(),
                        message: format!("Capability '{}' referenced in effect '{}' is undeclared in contract '{}'", capability_ref, name, contract.name),
                        node: contract.name.clone(),
                        line: None,
                    });
                }

                effects.insert(capability_ref.clone(), name.clone());
            }
        }

        // Pass 3: Validate that every declared capability has a matching effect
        for cap_name in capabilities.keys() {
            if !effects.contains_key(cap_name) {
                diagnostics.push(ClassifierDiagnostic {
                    rule: "E-IO-EFFECT-UNDECLARED".to_string(),
                    message: format!("Capability '{}' is declared but has no matching effect declaration in contract '{}'", cap_name, contract.name),
                    node: contract.name.clone(),
                    line: None,
                });
            }
        }

        // Run capability-bound I/O verification on all expressions in the contract body
        let is_pure = contract.modifier == "pure";
        for node in &contract.body {
            match node {
                BodyDecl::Compute { expr, .. } | BodyDecl::Snapshot { expr, .. } => {
                    check_expr_io(
                        expr,
                        &capabilities,
                        &effects,
                        &contract.name,
                        is_pure,
                        &mut diagnostics,
                    );
                }
                BodyDecl::FoldStream { expr, .. } => {
                    check_expr_io(
                        expr,
                        &capabilities,
                        &effects,
                        &contract.name,
                        is_pure,
                        &mut diagnostics,
                    );
                }
                BodyDecl::Loop {
                    collection,
                    body: loop_body,
                    ..
                } => {
                    check_expr_io(
                        collection,
                        &capabilities,
                        &effects,
                        &contract.name,
                        is_pure,
                        &mut diagnostics,
                    );
                    for inner in loop_body {
                        if let BodyDecl::Compute { expr, .. } = inner {
                            check_expr_io(
                                expr,
                                &capabilities,
                                &effects,
                                &contract.name,
                                is_pure,
                                &mut diagnostics,
                            );
                        }
                    }
                }
                BodyDecl::ServiceLoop {
                    body: loop_body, ..
                } => {
                    for inner in loop_body {
                        if let BodyDecl::Compute { expr, .. } = inner {
                            check_expr_io(
                                expr,
                                &capabilities,
                                &effects,
                                &contract.name,
                                is_pure,
                                &mut diagnostics,
                            );
                        }
                    }
                }
                _ => {}
            }
        }

        // Second pass: classify nodes & check OOFs
        for node in &contract.body {
            match node {
                BodyDecl::Capability {
                    name,
                    type_annotation,
                } => {
                    declarations.push(ClassifiedDecl {
                        decl_id: format!("capability:{}", name),
                        kind: "capability".to_string(),
                        name: name.clone(),
                        fragment_class: "escape".to_string(),
                        deps: Vec::new(),
                        missing_refs: Vec::new(),
                        type_annotation: Some(serde_json::to_value(type_annotation).unwrap()),
                        expr_kind: None,
                        expr: None,
                        options: None,
                        node_fragment_class: None,
                        value_fragment_class: None,
                        required_capability: None,
                        temporal_axis: None,
                        predicate_ref: None,
                        severity: None,
                        label: None,
                        message: None,
                        overridable_with: None,
                        lifecycle: None,
                        body_nodes: None,
                    });
                }
                BodyDecl::Effect {
                    name,
                    capability_ref,
                } => {
                    let mut missing = Vec::new();
                    if !symbol_fragments.contains_key(capability_ref) {
                        missing.push(capability_ref.clone());
                    }
                    declarations.push(ClassifiedDecl {
                        decl_id: format!("effect:{}", name),
                        kind: "effect".to_string(),
                        name: name.clone(),
                        fragment_class: "escape".to_string(),
                        deps: vec![capability_ref.clone()],
                        missing_refs: missing,
                        type_annotation: None,
                        expr_kind: None,
                        expr: None,
                        options: None,
                        node_fragment_class: None,
                        value_fragment_class: None,
                        required_capability: Some(capability_ref.clone()),
                        temporal_axis: None,
                        predicate_ref: None,
                        severity: None,
                        label: None,
                        message: None,
                        overridable_with: None,
                        lifecycle: None,
                        body_nodes: None,
                    });
                }
                BodyDecl::Input {
                    name,
                    type_annotation,
                } => {
                    declarations.push(ClassifiedDecl {
                        decl_id: format!("input:{}", name),
                        kind: "input".to_string(),
                        name: name.clone(),
                        fragment_class: "core".to_string(),
                        deps: Vec::new(),
                        missing_refs: Vec::new(),
                        type_annotation: Some(serde_json::to_value(type_annotation).unwrap()),
                        expr_kind: None,
                        expr: None,
                        options: None,
                        node_fragment_class: None,
                        value_fragment_class: None,
                        required_capability: None,
                        temporal_axis: None,
                        predicate_ref: None,
                        severity: None,
                        label: None,
                        message: None,
                        overridable_with: None,
                        lifecycle: None,
                        body_nodes: None,
                    });
                }
                BodyDecl::Escape { name } => {
                    declarations.push(ClassifiedDecl {
                        decl_id: format!("escape:{}", name),
                        kind: "escape".to_string(),
                        name: name.clone(),
                        fragment_class: "escape".to_string(),
                        deps: Vec::new(),
                        missing_refs: Vec::new(),
                        type_annotation: None,
                        expr_kind: None,
                        expr: None,
                        options: None,
                        node_fragment_class: None,
                        value_fragment_class: None,
                        required_capability: None,
                        temporal_axis: None,
                        predicate_ref: None,
                        severity: None,
                        label: None,
                        message: None,
                        overridable_with: None,
                        lifecycle: None,
                        body_nodes: None,
                    });
                }
                BodyDecl::Stream {
                    name,
                    type_annotation,
                    fragment_class,
                    escape_capability,
                } => {
                    declarations.push(ClassifiedDecl {
                        decl_id: format!("stream:{}", name),
                        kind: "stream".to_string(),
                        name: name.clone(),
                        fragment_class: fragment_class.clone(),
                        deps: Vec::new(),
                        missing_refs: Vec::new(),
                        type_annotation: Some(serde_json::to_value(type_annotation).unwrap()),
                        expr_kind: None,
                        expr: None,
                        options: None,
                        node_fragment_class: None,
                        value_fragment_class: None,
                        required_capability: Some(escape_capability.clone()),
                        temporal_axis: None,
                        predicate_ref: None,
                        severity: None,
                        label: None,
                        message: None,
                        overridable_with: None,
                        lifecycle: None,
                        body_nodes: None,
                    });
                }
                BodyDecl::Read {
                    name,
                    type_annotation,
                    from,
                    lifecycle,
                    scoped_by,
                    cardinality,
                    schema_version,
                    tenant_free,
                } => {
                    let is_temp = self.is_temporal_type(type_annotation);
                    let fragment = if is_temp {
                        "temporal".to_string()
                    } else {
                        "escape".to_string()
                    };

                    let mut decl = ClassifiedDecl {
                        decl_id: format!("read:{}", name),
                        kind: "read".to_string(),
                        name: name.clone(),
                        fragment_class: fragment.clone(),
                        deps: Vec::new(),
                        missing_refs: Vec::new(),
                        type_annotation: Some(serde_json::to_value(type_annotation).unwrap()),
                        expr_kind: None,
                        expr: None,
                        options: None,
                        node_fragment_class: None,
                        value_fragment_class: None,
                        required_capability: None,
                        temporal_axis: None,
                        predicate_ref: None,
                        severity: None,
                        label: None,
                        message: None,
                        overridable_with: None,
                        lifecycle: lifecycle.clone(),
                        body_nodes: None,
                    };

                    if is_temp {
                        let t_name = self.normalize_type(type_annotation);
                        decl.node_fragment_class = Some("temporal".to_string());
                        decl.value_fragment_class = Some("core".to_string());
                        decl.required_capability = Some(if t_name == "BiHistory" {
                            "bihistory_read".to_string()
                        } else {
                            "history_read".to_string()
                        });
                        decl.temporal_axis = Some(if t_name == "BiHistory" {
                            "bitemporal".to_string()
                        } else {
                            "valid_time".to_string()
                        });
                    }

                    declarations.push(decl);
                }
                BodyDecl::Window { label, options } => {
                    window_declarations.push(node.clone());
                    declarations.push(ClassifiedDecl {
                        decl_id: format!("window:{}", label),
                        kind: "window".to_string(),
                        name: label.clone(),
                        fragment_class: "escape".to_string(),
                        deps: Vec::new(),
                        missing_refs: Vec::new(),
                        type_annotation: None,
                        expr_kind: None,
                        expr: None,
                        options: Some(options.clone()),
                        node_fragment_class: None,
                        value_fragment_class: None,
                        required_capability: None,
                        temporal_axis: None,
                        predicate_ref: None,
                        severity: None,
                        label: None,
                        message: None,
                        overridable_with: None,
                        lifecycle: None,
                        body_nodes: None,
                    });
                }
                BodyDecl::UsesAssumptions { name } => {
                    assumption_refs.push(name.clone());
                    let has_entry = registry.contains_key(name);
                    let mut missing = Vec::new();
                    if !has_entry {
                        missing.push(name.clone());
                        diagnostics.push(ClassifierDiagnostic {
                            rule: "OOF-A1".to_string(),
                            message: format!("contract '{}' uses assumptions '{}' but no assumption named '{}' is declared in this module", contract.name, name, name),
                            node: format!("uses_assumptions:{}", name),
                            line: None,
                        });
                    }

                    declarations.push(ClassifiedDecl {
                        decl_id: format!("uses_assumptions:{}", name),
                        kind: "uses_assumptions".to_string(),
                        name: name.clone(),
                        fragment_class: "epistemic".to_string(),
                        deps: Vec::new(),
                        missing_refs: missing,
                        type_annotation: None,
                        expr_kind: None,
                        expr: None,
                        options: None,
                        node_fragment_class: None,
                        value_fragment_class: None,
                        required_capability: None,
                        temporal_axis: None,
                        predicate_ref: None,
                        severity: None,
                        label: None,
                        message: None,
                        overridable_with: None,
                        lifecycle: None,
                        body_nodes: None,
                    });
                }
                BodyDecl::FoldStream {
                    name,
                    expr,
                    bound,
                    type_annotation,
                } => {
                    let deps = self.expr_refs(expr);
                    for dep in &deps {
                        if symbol_kinds.get(dep).map(|s| s.as_str()) == Some("stream") {
                            fold_stream_stream_refs
                                .entry(dep.clone())
                                .or_default()
                                .push(name.clone());
                        }
                    }

                    let is_bounded = bound.is_some();
                    let fragment = if is_bounded {
                        "core".to_string()
                    } else {
                        "oof".to_string()
                    };
                    symbol_fragments.insert(name.clone(), fragment.clone());

                    declarations.push(ClassifiedDecl {
                        decl_id: format!("fold_stream:{}", name),
                        kind: "fold_stream".to_string(),
                        name: name.clone(),
                        fragment_class: fragment,
                        deps,
                        missing_refs: Vec::new(),
                        type_annotation: type_annotation
                            .as_ref()
                            .map(|t| serde_json::to_value(t).unwrap()),
                        expr_kind: Some("call".to_string()),
                        expr: Some(expr.clone()),
                        options: None,
                        node_fragment_class: None,
                        value_fragment_class: None,
                        required_capability: None,
                        temporal_axis: None,
                        predicate_ref: None,
                        severity: None,
                        label: None,
                        message: None,
                        overridable_with: None,
                        lifecycle: None,
                        body_nodes: None,
                    });
                }
                BodyDecl::Invariant {
                    name,
                    predicate_ref,
                    severity,
                    label,
                    message,
                    overridable_with,
                } => {
                    let mut missing = Vec::new();
                    if !symbol_fragments.contains_key(predicate_ref) {
                        missing.push(predicate_ref.clone());
                        diagnostics.push(ClassifierDiagnostic {
                            rule: "OOF-P1".to_string(),
                            message: format!("Unresolved symbol: {}", predicate_ref),
                            node: name.clone(),
                            line: None,
                        });
                    }

                    let fragment = if missing.is_empty() {
                        "core".to_string()
                    } else {
                        "oof".to_string()
                    };

                    declarations.push(ClassifiedDecl {
                        decl_id: format!("invariant:{}", name),
                        kind: "invariant".to_string(),
                        name: name.clone(),
                        fragment_class: fragment,
                        deps: vec![predicate_ref.clone()],
                        missing_refs: missing,
                        type_annotation: None,
                        expr_kind: None,
                        expr: None,
                        options: None,
                        node_fragment_class: None,
                        value_fragment_class: None,
                        required_capability: None,
                        temporal_axis: None,
                        predicate_ref: Some(predicate_ref.clone()),
                        severity: Some(severity.clone()),
                        label: label.clone(),
                        message: message.clone(),
                        overridable_with: overridable_with.clone(),
                        lifecycle: None,
                        body_nodes: None,
                    });
                }
                BodyDecl::Compute {
                    name,
                    expr,
                    type_annotation,
                } => {
                    let deps = self.expr_refs(expr);
                    let mut missing = Vec::new();
                    for dep in &deps {
                        if !symbol_fragments.contains_key(dep)
                            && symbol_kinds.get(dep).map(|s| s.as_str()) != Some("compute")
                        {
                            missing.push(dep.clone());
                            diagnostics.push(ClassifierDiagnostic {
                                rule: "OOF-P1".to_string(),
                                message: format!("Unresolved symbol: {}", dep),
                                node: name.clone(),
                                line: None,
                            });
                        }
                    }

                    for dep in &deps {
                        if symbol_kinds.get(dep).map(|s| s.as_str()) == Some("stream") {
                            diagnostics.push(ClassifierDiagnostic {
                                rule: "OOF-S4".to_string(),
                                message: format!(
                                    "Direct use of stream '{}' is OOF - use fold_stream instead",
                                    dep
                                ),
                                node: name.clone(),
                                line: None,
                            });
                        }
                    }

                    let upstream_oof = deps
                        .iter()
                        .any(|dep| symbol_fragments.get(dep).map(|s| s.as_str()) == Some("oof"));
                    let mut fragment = if missing.is_empty() && !upstream_oof {
                        "core".to_string()
                    } else {
                        "oof".to_string()
                    };
                    if fragment != "oof" && expr_has_io_call(expr) {
                        fragment = "escape".to_string();
                    }

                    symbol_fragments.insert(name.clone(), fragment.clone());
                    compute_exprs.insert(name.clone(), expr.clone());

                    declarations.push(ClassifiedDecl {
                        decl_id: format!("compute:{}", name),
                        kind: "compute".to_string(),
                        name: name.clone(),
                        fragment_class: fragment,
                        deps,
                        missing_refs: missing,
                        type_annotation: type_annotation
                            .as_ref()
                            .map(|t| serde_json::to_value(t).unwrap()),
                        expr_kind: Some(self.expr_kind(expr)),
                        expr: Some(expr.clone()),
                        options: None,
                        node_fragment_class: None,
                        value_fragment_class: None,
                        required_capability: None,
                        temporal_axis: None,
                        predicate_ref: None,
                        severity: None,
                        label: None,
                        message: None,
                        overridable_with: None,
                        lifecycle: None,
                        body_nodes: None,
                    });
                }
                BodyDecl::Snapshot {
                    name,
                    expr,
                    lifecycle,
                } => {
                    let deps = self.expr_refs(expr);
                    let mut missing = Vec::new();
                    for dep in &deps {
                        if !symbol_fragments.contains_key(dep)
                            && symbol_kinds.get(dep).map(|s| s.as_str()) != Some("compute")
                        {
                            missing.push(dep.clone());
                            diagnostics.push(ClassifierDiagnostic {
                                rule: "OOF-P1".to_string(),
                                message: format!("Unresolved symbol: {}", dep),
                                node: name.clone(),
                                line: None,
                            });
                        }
                    }

                    let fragment = if missing.is_empty() {
                        "core".to_string()
                    } else {
                        "oof".to_string()
                    };
                    symbol_fragments.insert(name.clone(), fragment.clone());

                    declarations.push(ClassifiedDecl {
                        decl_id: format!("snapshot:{}", name),
                        kind: "snapshot".to_string(),
                        name: name.clone(),
                        fragment_class: fragment,
                        deps,
                        missing_refs: missing,
                        type_annotation: None,
                        expr_kind: Some(self.expr_kind(expr)),
                        expr: Some(expr.clone()),
                        options: None,
                        node_fragment_class: None,
                        value_fragment_class: None,
                        required_capability: None,
                        temporal_axis: None,
                        predicate_ref: None,
                        severity: None,
                        label: None,
                        message: None,
                        overridable_with: None,
                        lifecycle: lifecycle.clone(),
                        body_nodes: None,
                    });
                }
                BodyDecl::Output {
                    name,
                    type_annotation,
                    lifecycle,
                    evidence,
                } => {
                    let mut missing = Vec::new();
                    if !symbol_fragments.contains_key(name)
                        && symbol_kinds.get(name).map(|s| s.as_str()) != Some("compute")
                    {
                        missing.push(name.clone());
                        diagnostics.push(ClassifierDiagnostic {
                            rule: "OOF-P1".to_string(),
                            message: format!("Unresolved output source: {}", name),
                            node: name.clone(),
                            line: None,
                        });
                    }

                    let src_fragment = symbol_fragments
                        .get(name)
                        .map(|s| s.as_str())
                        .unwrap_or("oof");
                    let mut fragment = if missing.is_empty() && src_fragment == "core" {
                        "core".to_string()
                    } else {
                        "oof".to_string()
                    };

                    // OOF-CE4 check:
                    if self.normalize_type(type_annotation) == "Bool" {
                        if let Some(expr) = compute_exprs.get(name) {
                            if self.is_confidence_label_expr(expr) {
                                diagnostics.push(ClassifierDiagnostic {
                                    rule: "OOF-CE4".to_string(),
                                    message: "ConfidenceLabel cannot be used as Bool".to_string(),
                                    node: name.clone(),
                                    line: None,
                                });
                                fragment = "oof".to_string();
                            }
                        }
                    }

                    declarations.push(ClassifiedDecl {
                        decl_id: format!("output:{}", name),
                        kind: "output".to_string(),
                        name: name.clone(),
                        fragment_class: fragment,
                        deps: vec![name.clone()],
                        missing_refs: missing,
                        type_annotation: Some(serde_json::to_value(type_annotation).unwrap()),
                        expr_kind: None,
                        expr: None,
                        options: None,
                        node_fragment_class: None,
                        value_fragment_class: None,
                        required_capability: None,
                        temporal_axis: None,
                        predicate_ref: None,
                        severity: None,
                        label: None,
                        message: None,
                        overridable_with: None,
                        lifecycle: lifecycle.clone(),
                        body_nodes: None,
                    });
                }
                BodyDecl::Loop {
                    name,
                    item,
                    collection,
                    max_steps,
                    body: loop_body,
                } => {
                    let mut deps = self.expr_refs(collection);
                    let mut missing = Vec::new();
                    for dep in &deps {
                        if !symbol_fragments.contains_key(dep)
                            && symbol_kinds.get(dep).map(|s| s.as_str()) != Some("compute")
                        {
                            missing.push(dep.clone());
                            diagnostics.push(ClassifierDiagnostic {
                                rule: "OOF-P1".to_string(),
                                message: format!("Unresolved symbol: {}", dep),
                                node: name.clone(),
                                line: None,
                            });
                        }
                    }

                    // G1: explicit item variable from canon grammar (`loop Name item in source`).
                    // If absent (old form), fall back to singularize(collection).
                    let var_name = if !item.is_empty() {
                        item.clone()
                    } else if let Some(ref_name) = collection.get_name() {
                        singularize(ref_name)
                    } else {
                        "item".to_string()
                    };

                    // Register loop variable so typechecker/body nodes can reference it
                    symbol_fragments.insert(var_name.clone(), "core".to_string());
                    // Also keep "item" as generic alias so old body patterns still resolve
                    symbol_fragments.insert("item".to_string(), "core".to_string());

                    // Snapshot outer contract symbols for OOF-L8 shadow check (before body pre-scan registers body targets)
                    let outer_symbol_keys: std::collections::HashSet<String> =
                        symbol_fragments.keys().cloned().collect();

                    // Collect deps from loop body compute nodes
                    let mut body_deps = Vec::new();
                    for body_node in loop_body {
                        if let BodyDecl::Compute {
                            expr,
                            name: inner_name,
                            ..
                        } = body_node
                        {
                            let inner_deps = self.expr_refs(expr);
                            for d in &inner_deps {
                                if d != &var_name && d != "item" {
                                    body_deps.push(d.clone());
                                }
                            }
                            let fragment = if expr_has_io_call(expr) {
                                "escape".to_string()
                            } else {
                                "core".to_string()
                            };
                            symbol_fragments.insert(inner_name.clone(), fragment);
                        }
                    }
                    deps.extend(body_deps);
                    deps.sort();
                    deps.dedup();

                    let upstream_oof = deps
                        .iter()
                        .any(|dep| symbol_fragments.get(dep).map(|s| s.as_str()) == Some("oof"));
                    let mut fragment = if missing.is_empty() && !upstream_oof {
                        "core".to_string()
                    } else {
                        "oof".to_string()
                    };
                    if fragment != "oof" {
                        let mut has_escape = deps.iter().any(|dep| {
                            symbol_fragments.get(dep).map(|s| s.as_str()) == Some("escape")
                        });
                        for body_node in loop_body {
                            if let BodyDecl::Compute { expr, .. } = body_node {
                                if expr_has_io_call(expr) {
                                    has_escape = true;
                                }
                            }
                        }
                        if has_escape {
                            fragment = "escape".to_string();
                        }
                    }

                    // We serialize loop collection ref in Expr
                    let expr_val = if let Some(ref_name) = collection.get_name() {
                        Some(Expr::Ref {
                            name: ref_name.to_string(),
                        })
                    } else {
                        None
                    };

                    let mut loop_options = HashMap::new();
                    if let Some(steps) = max_steps {
                        loop_options
                            .insert("max_steps".to_string(), WindowValue::Int(*steps as i64));
                    }
                    // G3b: loop_class for emitter IR shape (finite = no budget, budgeted = max_steps)
                    let loop_class = if max_steps.is_some() {
                        "budgeted"
                    } else {
                        "finite"
                    };
                    loop_options.insert(
                        "loop_class".to_string(),
                        WindowValue::Str(loop_class.to_string()),
                    );
                    // G1: store resolved item variable name for downstream stages
                    loop_options.insert("item".to_string(), WindowValue::Str(var_name.clone()));

                    let mut inner_classified = Vec::new();
                    let mut lead_names: Vec<String> = Vec::new();
                    for inner_decl in loop_body {
                        match inner_decl {
                            BodyDecl::Compute {
                                name: inner_name,
                                expr: inner_expr,
                                type_annotation: inner_type_annotation,
                            } => {
                                let inner_deps = self.expr_refs(inner_expr);
                                let mut inner_missing = Vec::new();
                                for dep in &inner_deps {
                                    if dep != &var_name
                                        && dep != "item"
                                        && !symbol_fragments.contains_key(dep)
                                        && symbol_kinds.get(dep).map(|s| s.as_str())
                                            != Some("compute")
                                    {
                                        inner_missing.push(dep.clone());
                                        diagnostics.push(ClassifierDiagnostic {
                                            rule: "OOF-P1".to_string(),
                                            message: format!("Unresolved symbol: {}", dep),
                                            node: inner_name.clone(),
                                            line: None,
                                        });
                                    }
                                }
                                let upstream_oof = inner_deps.iter().any(|dep| {
                                    dep != &var_name
                                        && dep != "item"
                                        && symbol_fragments.get(dep).map(|s| s.as_str())
                                            == Some("oof")
                                });
                                let mut inner_fragment =
                                    if inner_missing.is_empty() && !upstream_oof {
                                        "core".to_string()
                                    } else {
                                        "oof".to_string()
                                    };
                                if inner_fragment != "oof" && expr_has_io_call(inner_expr) {
                                    inner_fragment = "escape".to_string();
                                }

                                symbol_fragments.insert(inner_name.clone(), inner_fragment.clone());

                                inner_classified.push(ClassifiedDecl {
                                    decl_id: format!("compute:{}", inner_name),
                                    kind: "compute".to_string(),
                                    name: inner_name.clone(),
                                    fragment_class: inner_fragment,
                                    deps: inner_deps,
                                    missing_refs: inner_missing,
                                    type_annotation: inner_type_annotation
                                        .as_ref()
                                        .map(|t| serde_json::to_value(t).unwrap()),
                                    expr_kind: Some(self.expr_kind(inner_expr)),
                                    expr: Some(inner_expr.clone()),
                                    options: None,
                                    node_fragment_class: None,
                                    value_fragment_class: None,
                                    required_capability: None,
                                    temporal_axis: None,
                                    predicate_ref: None,
                                    severity: None,
                                    label: None,
                                    message: None,
                                    overridable_with: None,
                                    lifecycle: None,
                                    body_nodes: None,
                                });
                            }
                            // PROP-039 gate 8: lead binding inside loop body
                            BodyDecl::Lead {
                                name: lead_name,
                                type_annotation: lead_type,
                                initial: lead_initial,
                            } => {
                                // OOF-L8: lead must not shadow outer contract symbols or loop item variable
                                // Use outer_symbol_keys snapshot (before body targets were pre-registered)
                                if outer_symbol_keys.contains(lead_name.as_str())
                                    && !lead_names.contains(lead_name)
                                {
                                    if lead_name == &var_name || lead_name == "item" {
                                        diagnostics.push(ClassifierDiagnostic {
                                            rule: "OOF-L8".to_string(),
                                            message: format!("lead '{}' in loop '{}' shadows loop item variable '{}'", lead_name, name, var_name),
                                            node: name.clone(),
                                            line: None,
                                        });
                                    } else {
                                        diagnostics.push(ClassifierDiagnostic {
                                            rule: "OOF-L8".to_string(),
                                            message: format!("lead '{}' in loop '{}' shadows outer contract symbol", lead_name, name),
                                            node: name.clone(),
                                            line: None,
                                        });
                                    }
                                }
                                // Register lead name so subsequent compute nodes can reference it
                                symbol_fragments.insert(lead_name.clone(), "core".to_string());
                                lead_names.push(lead_name.clone());
                                inner_classified.push(ClassifiedDecl {
                                    decl_id: format!("lead:{}", lead_name),
                                    kind: "lead".to_string(),
                                    name: lead_name.clone(),
                                    fragment_class: "core".to_string(),
                                    deps: Vec::new(),
                                    missing_refs: Vec::new(),
                                    type_annotation: Some(serde_json::to_value(lead_type).unwrap()),
                                    expr_kind: Some("literal".to_string()),
                                    expr: Some(lead_initial.clone()),
                                    options: None,
                                    node_fragment_class: None,
                                    value_fragment_class: None,
                                    required_capability: None,
                                    temporal_axis: None,
                                    predicate_ref: None,
                                    severity: None,
                                    label: None,
                                    message: None,
                                    overridable_with: None,
                                    lifecycle: None,
                                    body_nodes: None,
                                });
                            }
                            // PROP-039 gate 8: nested loops in body are OOF-L5 (v0 restriction)
                            BodyDecl::Loop {
                                name: nested_name, ..
                            }
                            | BodyDecl::ServiceLoop {
                                name: nested_name, ..
                            } => {
                                diagnostics.push(ClassifierDiagnostic {
                                    rule: "OOF-L5".to_string(),
                                    message: format!(
                                        "nested loop '{}' in loop body '{}' is not supported in v0",
                                        nested_name, name
                                    ),
                                    node: name.clone(),
                                    line: None,
                                });
                            }
                            _ => {}
                        }
                    }

                    declarations.push(ClassifiedDecl {
                        decl_id: format!("loop:{}", name),
                        kind: "loop".to_string(),
                        name: name.clone(),
                        fragment_class: fragment,
                        deps,
                        missing_refs: missing,
                        type_annotation: None,
                        expr_kind: Some("loop".to_string()),
                        expr: expr_val,
                        options: Some(loop_options),
                        node_fragment_class: None,
                        value_fragment_class: None,
                        required_capability: None,
                        temporal_axis: None,
                        predicate_ref: None,
                        severity: None,
                        label: None,
                        message: None,
                        overridable_with: None,
                        lifecycle: None,
                        body_nodes: Some(inner_classified),
                    });
                }
                // G2: decreases/max_steps are structural meta-declarations for recursive/fuel_bounded
                // contracts. No ClassifiedDecl produced; used only for contract-level OOF checks.
                BodyDecl::Decreases { .. } | BodyDecl::MaxSteps { .. } => {}
                // PROP-039 gate 8: lead at contract level is OOF-L5 (only valid inside loop body)
                BodyDecl::Lead { name, .. } => {
                    diagnostics.push(ClassifierDiagnostic {
                        rule: "OOF-L5".to_string(),
                        message: format!(
                            "lead declaration '{}' is only valid inside a loop body",
                            name
                        ),
                        node: name.clone(),
                        line: None,
                    });
                    // Do NOT add to declarations — it's an error node
                }
                BodyDecl::ServiceLoop {
                    name,
                    interval,
                    body: loop_body,
                } => {
                    // Service loops are always ESCAPE
                    symbol_fragments.insert(name.clone(), "escape".to_string());
                    symbol_kinds.insert(name.clone(), "service_loop".to_string());

                    // Register symbols from loop body
                    for inner_decl in loop_body {
                        if let BodyDecl::Compute {
                            name: inner_name, ..
                        } = inner_decl
                        {
                            symbol_kinds.insert(inner_name.clone(), "compute".to_string());
                            symbol_fragments.insert(inner_name.clone(), "escape".to_string());
                        }
                    }

                    let mut options = HashMap::new();
                    options.insert(
                        "interval_value".to_string(),
                        WindowValue::Int(interval.value as i64),
                    );
                    options.insert(
                        "interval_unit".to_string(),
                        WindowValue::Str(interval.unit.clone()),
                    );

                    let mut inner_classified = Vec::new();
                    for inner_decl in loop_body {
                        if let BodyDecl::Compute {
                            name: inner_name,
                            expr: inner_expr,
                            type_annotation: inner_type_annotation,
                        } = inner_decl
                        {
                            let inner_deps = self.expr_refs(inner_expr);
                            let mut inner_missing = Vec::new();
                            for dep in &inner_deps {
                                if dep != name
                                    && !symbol_fragments.contains_key(dep)
                                    && symbol_kinds.get(dep).map(|s| s.as_str()) != Some("compute")
                                {
                                    inner_missing.push(dep.clone());
                                    diagnostics.push(ClassifierDiagnostic {
                                        rule: "OOF-P1".to_string(),
                                        message: format!("Unresolved symbol: {}", dep),
                                        node: inner_name.clone(),
                                        line: None,
                                    });
                                }
                            }
                            let upstream_oof = inner_deps.iter().any(|dep| {
                                dep != name
                                    && symbol_fragments.get(dep).map(|s| s.as_str()) == Some("oof")
                            });
                            let inner_fragment = if inner_missing.is_empty() && !upstream_oof {
                                "escape".to_string()
                            } else {
                                "oof".to_string()
                            };

                            symbol_fragments.insert(inner_name.clone(), inner_fragment.clone());

                            inner_classified.push(ClassifiedDecl {
                                decl_id: format!("compute:{}", inner_name),
                                kind: "compute".to_string(),
                                name: inner_name.clone(),
                                fragment_class: inner_fragment,
                                deps: inner_deps,
                                missing_refs: inner_missing,
                                type_annotation: inner_type_annotation
                                    .as_ref()
                                    .map(|t| serde_json::to_value(t).unwrap()),
                                expr_kind: Some(self.expr_kind(inner_expr)),
                                expr: Some(inner_expr.clone()),
                                options: None,
                                node_fragment_class: None,
                                value_fragment_class: None,
                                required_capability: None,
                                temporal_axis: None,
                                predicate_ref: None,
                                severity: None,
                                label: None,
                                message: None,
                                overridable_with: None,
                                lifecycle: None,
                                body_nodes: None,
                            });
                        }
                    }

                    declarations.push(ClassifiedDecl {
                        decl_id: format!("service_loop:{}", name),
                        kind: "service_loop".to_string(),
                        name: name.clone(),
                        fragment_class: "escape".to_string(),
                        deps: Vec::new(),
                        missing_refs: Vec::new(),
                        type_annotation: None,
                        expr_kind: Some("service_loop".to_string()),
                        expr: None,
                        options: Some(options),
                        node_fragment_class: Some("escape".to_string()),
                        value_fragment_class: Some("escape".to_string()),
                        required_capability: Some("clock_tick".to_string()),
                        temporal_axis: Some("valid_time".to_string()),
                        predicate_ref: None,
                        severity: None,
                        label: None,
                        message: None,
                        overridable_with: None,
                        lifecycle: None,
                        body_nodes: Some(inner_classified),
                    });
                }
            }
        }

        // Cycle check: OOF-P4
        let mut cyclic_nodes = HashSet::new();
        self.detect_cycles(&declarations, &mut cyclic_nodes);
        for node_name in &cyclic_nodes {
            diagnostics.push(ClassifierDiagnostic {
                rule: "OOF-P4".to_string(),
                message: format!("Compute cycle detected involving '{}'", node_name),
                node: node_name.clone(),
                line: None,
            });
            let decl_id = format!("compute:{}", node_name);
            if let Some(decl) = declarations.iter_mut().find(|d| d.decl_id == decl_id) {
                decl.fragment_class = "oof".to_string();
            }
        }

        // Stream window check: OOF-S2
        if window_declarations.is_empty() {
            for stream_name in fold_stream_stream_refs.keys() {
                diagnostics.push(ClassifierDiagnostic {
                    rule: "OOF-S2".to_string(),
                    message: format!(
                        "stream '{}' has no window - every stream must declare a window",
                        stream_name
                    ),
                    node: stream_name.clone(),
                    line: None,
                });
            }
        }

        // Escape checks on pure/observed/irreversible contracts
        let modifier = contract.modifier.clone();

        // G3a (PROP-039 conformance): OOF-R2/R4 — recursive/fuel_bounded structural checks
        {
            let has_decreases = contract
                .body
                .iter()
                .any(|d| matches!(d, BodyDecl::Decreases { .. }));
            let has_max_steps_body = contract
                .body
                .iter()
                .any(|d| matches!(d, BodyDecl::MaxSteps { .. }));
            let decreases_fuel = contract.body.iter().any(|d| {
                if let BodyDecl::Decreases { variant } = d {
                    variant == "fuel"
                } else {
                    false
                }
            });

            if modifier == "recursive" && !has_decreases {
                diagnostics.push(ClassifierDiagnostic {
                    rule: "OOF-R2".to_string(),
                    message: format!(
                        "recursive contract '{}' is missing a decreases declaration",
                        contract.name
                    ),
                    node: contract.name.clone(),
                    line: None,
                });
            }
            if (modifier == "fuel_bounded" && !has_max_steps_body)
                || (modifier == "recursive" && decreases_fuel && !has_max_steps_body)
            {
                diagnostics.push(ClassifierDiagnostic {
                    rule: "OOF-R4".to_string(),
                    message: format!(
                        "contract '{}' is missing a max_steps declaration",
                        contract.name
                    ),
                    node: contract.name.clone(),
                    line: None,
                });
            }
        }

        // PROP-039 OOF-R3: extract named decreases variant for TypeChecker gate.
        // Only for recursive contracts; fuel variant is auto-managed (exempt from OOF-R3).
        let decreases_variant_extracted: Option<String> = if modifier == "recursive" {
            contract.body.iter().find_map(|d| {
                if let BodyDecl::Decreases { variant } = d {
                    if variant != "fuel" && !variant.is_empty() {
                        Some(variant.clone())
                    } else {
                        None
                    }
                } else {
                    None
                }
            })
        } else {
            None
        };
        if modifier == "pure" {
            if declarations
                .iter()
                .any(|d| d.fragment_class == "escape" && d.kind != "service_loop")
            {
                diagnostics.push(ClassifierDiagnostic {
                    rule: "OOF-M1".to_string(),
                    message: format!("pure contract '{}' cannot declare escape capabilities; use 'observed' for read-only external access", contract.name),
                    node: contract.name.clone(),
                    line: None,
                });
            }
        }

        if modifier == "observed" {
            for d in &declarations {
                if has_write_nodes(d) {
                    diagnostics.push(ClassifierDiagnostic {
                        rule: "OOF-M1".to_string(),
                        message: format!("observed contract '{}' cannot perform write operations; observed contracts are read-only", contract.name),
                        node: contract.name.clone(),
                        line: None,
                    });
                    break;
                }
            }
        }

        if modifier == "irreversible" {
            for d in &declarations {
                if has_compensation_nodes(d) {
                    diagnostics.push(ClassifierDiagnostic {
                        rule: "OOF-M1".to_string(),
                        message: format!(
                            "irreversible contract '{}' cannot define compensations",
                            contract.name
                        ),
                        node: contract.name.clone(),
                        line: None,
                    });
                    break;
                }
            }
        }

        let contract_fragment = self.contract_fragment_for(&declarations, &diagnostics, &modifier);

        let dependency_graph = self.build_dependency_graph(&declarations);

        ClassifiedContract {
            kind: "classified_contract".to_string(),
            contract_id: format!(
                "{}.{}",
                parsed.module.clone().unwrap_or_default(),
                contract.name
            ),
            name: contract.name.clone(),
            modifier,
            fragment_class: contract_fragment,
            symbols: self.symbol_table(&symbol_kinds, &symbol_fragments),
            declarations,
            dependency_graph,
            oof_log: diagnostics,
            decreases_variant: decreases_variant_extracted,
            assumption_refs: if assumption_refs.is_empty() {
                None
            } else {
                Some(assumption_refs)
            },
            specialization_of: contract.specialization_of.clone(),
            type_args: contract.type_args.clone(),
            implements: contract.implements.clone(),
        }
    }

    fn detect_cycles(&self, declarations: &[ClassifiedDecl], cyclic_nodes: &mut HashSet<String>) {
        let mut adj = HashMap::new();
        for d in declarations {
            if d.kind == "compute" || d.kind == "input" {
                adj.insert(d.name.clone(), d.deps.clone());
            }
        }

        let mut visited = HashSet::new();
        let mut rec_stack = HashSet::new();

        for node in adj.keys() {
            self.dfs_cycle(node, &adj, &mut visited, &mut rec_stack, cyclic_nodes);
        }
    }

    fn dfs_cycle(
        &self,
        node: &String,
        adj: &HashMap<String, Vec<String>>,
        visited: &mut HashSet<String>,
        rec_stack: &mut HashSet<String>,
        cyclic_nodes: &mut HashSet<String>,
    ) -> bool {
        if rec_stack.contains(node) {
            cyclic_nodes.insert(node.clone());
            return true;
        }
        if visited.contains(node) {
            return false;
        }

        visited.insert(node.clone());
        rec_stack.insert(node.clone());

        if let Some(neighbors) = adj.get(node) {
            for neighbor in neighbors {
                if self.dfs_cycle(neighbor, adj, visited, rec_stack, cyclic_nodes) {
                    cyclic_nodes.insert(node.clone());
                    rec_stack.remove(node);
                    return true;
                }
            }
        }

        rec_stack.remove(node);
        false
    }

    fn is_temporal_type(&self, type_ref: &TypeRef) -> bool {
        let name = self.normalize_type(type_ref);
        name == "History" || name == "BiHistory"
    }

    fn normalize_type(&self, type_ref: &TypeRef) -> String {
        match type_ref {
            TypeRef::Simple(s) => s.clone(),
            TypeRef::Structured { name, .. } => name.clone(),
            TypeRef::DimsRecord { .. } => "DimsRecord".to_string(),
        }
    }

    fn is_confidence_label_expr(&self, expr: &Expr) -> bool {
        match expr {
            Expr::FieldAccess { field, .. } => field == "confidence_label",
            _ => false,
        }
    }

    fn expr_kind(&self, expr: &Expr) -> String {
        match expr {
            Expr::Literal { .. } => "literal".to_string(),
            Expr::Ref { .. } => "ref".to_string(),
            Expr::BinaryOp { .. } => "binary_op".to_string(),
            Expr::UnaryOp { .. } => "unary_op".to_string(),
            Expr::FieldAccess { .. } => "field_access".to_string(),
            Expr::IndexAccess { .. } => "index_access".to_string(),
            Expr::SliceRecord { .. } => "slice_record".to_string(),
            Expr::Call { .. } => "call".to_string(),
            Expr::IfExpr { .. } => "if_expr".to_string(),
            Expr::Lambda { .. } => "lambda".to_string(),
            Expr::ArrayLiteral { .. } => "array_literal".to_string(),
            Expr::RecordLiteral { .. } => "record_literal".to_string(),
            Expr::RecordSpread { .. } => "record_spread".to_string(),
            Expr::Symbol { .. } => "symbol".to_string(),
            Expr::Error { .. } => "error".to_string(),
            Expr::VariantConstruct { .. } => "variant_construct".to_string(),
            Expr::MatchExpr { .. } => "match_expr".to_string(),
            Expr::Block(_) => "block".to_string(),
        }
    }

    fn expr_refs(&self, expr: &Expr) -> Vec<String> {
        let mut refs = Vec::new();
        self.collect_expr_refs(expr, &mut refs);
        refs.sort();
        refs.dedup();
        refs
    }

    fn collect_expr_refs(&self, expr: &Expr, refs: &mut Vec<String>) {
        match expr {
            Expr::Ref { name } => {
                refs.push(name.clone());
            }
            Expr::FieldAccess { object, .. } => {
                self.collect_expr_refs(object, refs);
            }
            Expr::IndexAccess { object, index } => {
                self.collect_expr_refs(object, refs);
                self.collect_expr_refs(index, refs);
            }
            Expr::SliceRecord { fields } => {
                for v in fields.values() {
                    self.collect_expr_refs(v, refs);
                }
            }
            Expr::BinaryOp { left, right, .. } => {
                self.collect_expr_refs(left, refs);
                self.collect_expr_refs(right, refs);
            }
            Expr::UnaryOp { operand, .. } => {
                self.collect_expr_refs(operand, refs);
            }
            Expr::Call { args, .. } => {
                for arg in args {
                    self.collect_expr_refs(arg, refs);
                }
            }
            Expr::IfExpr {
                cond,
                then,
                else_block,
            } => {
                self.collect_expr_refs(cond, refs);
                // LAB-LANG-MATCH-ARM-BINDINGS-P2: a block's `let`-bound names are block-LOCAL — they are
                // definitions, not external deps, so they must be excluded from collected refs (mirrors
                // the lambda-`params` exclusion below). Without this, `{ let a = x  a }` reports `a` as an
                // unresolved symbol.
                self.collect_block_refs(then, refs);
                if let Some(eb) = else_block {
                    self.collect_block_refs(eb, refs);
                }
            }
            Expr::Block(b) => {
                self.collect_block_refs(b, refs);
            }
            Expr::Lambda { params, body } => {
                let mut temp_refs = Vec::new();
                match body.as_ref() {
                    ExprOrBlock::Expr(e) => self.collect_expr_refs(e, &mut temp_refs),
                    ExprOrBlock::Block(b) => {
                        for s in &b.stmts {
                            match s {
                                crate::parser::Stmt::Let { expr, .. } => {
                                    self.collect_expr_refs(&expr, &mut temp_refs)
                                }
                                crate::parser::Stmt::ExprStmt { expr } => {
                                    self.collect_expr_refs(&expr, &mut temp_refs)
                                }
                            }
                        }
                        if let Some(re) = &b.return_expr {
                            self.collect_expr_refs(re, &mut temp_refs);
                        }
                    }
                }
                for r in temp_refs {
                    if !params.contains(&r) {
                        refs.push(r);
                    }
                }
            }
            Expr::ArrayLiteral { items } => {
                for item in items {
                    self.collect_expr_refs(item, refs);
                }
            }
            Expr::RecordLiteral { fields } => {
                for v in fields.values() {
                    self.collect_expr_refs(v, refs);
                }
            }
            // LAB-LANG-RECORD-SPREAD-P2: spread source + explicit fields are all refs.
            Expr::RecordSpread { spread, fields } => {
                self.collect_expr_refs(spread, refs);
                for v in fields.values() {
                    self.collect_expr_refs(v, refs);
                }
            }
            _ => {}
        }
    }

    /// Collect external refs from a block body, EXCLUDING names bound by the block's own `let`
    /// statements (block-local definitions, not external deps). LAB-LANG-MATCH-ARM-BINDINGS-P2.
    fn collect_block_refs(&self, block: &crate::parser::BlockBody, refs: &mut Vec<String>) {
        let mut local: Vec<String> = Vec::new();
        let mut inner: Vec<String> = Vec::new();
        for s in &block.stmts {
            match s {
                crate::parser::Stmt::Let { name, expr } => {
                    self.collect_expr_refs(expr, &mut inner);
                    local.push(name.clone());
                }
                crate::parser::Stmt::ExprStmt { expr } => self.collect_expr_refs(expr, &mut inner),
            }
        }
        if let Some(re) = &block.return_expr {
            self.collect_expr_refs(re, &mut inner);
        }
        for r in inner {
            if !local.contains(&r) {
                refs.push(r);
            }
        }
    }

    fn contract_fragment_for(
        &self,
        declarations: &[ClassifiedDecl],
        diagnostics: &[ClassifierDiagnostic],
        modifier: &str,
    ) -> String {
        if !diagnostics.is_empty() {
            return "oof".to_string();
        }
        if declarations.iter().all(|d| d.fragment_class == "core") {
            return "core".to_string();
        }
        if declarations.iter().any(|d| d.fragment_class == "oof") {
            return "oof".to_string();
        }
        if declarations.iter().any(|d| d.fragment_class == "temporal") {
            return "temporal".to_string();
        }
        if modifier != "pure" || declarations.iter().any(|d| d.fragment_class == "escape") {
            return "escape".to_string();
        }
        if declarations.iter().any(|d| d.fragment_class == "epistemic") {
            return "epistemic".to_string();
        }
        "oof".to_string()
    }

    fn symbol_table(
        &self,
        kinds: &HashMap<String, String>,
        fragments: &HashMap<String, String>,
    ) -> Vec<ClassifiedSymbol> {
        let mut keys: Vec<&String> = kinds.keys().collect();
        keys.sort();
        keys.iter()
            .map(|name| ClassifiedSymbol {
                name: (*name).clone(),
                kind: kinds.get(*name).unwrap().clone(),
                fragment_class: fragments.get(*name).unwrap_or(&"oof".to_string()).clone(),
            })
            .collect()
    }

    fn build_dependency_graph(&self, declarations: &[ClassifiedDecl]) -> DependencyGraph {
        let declaration_ids: Vec<String> = declarations.iter().map(|d| d.decl_id.clone()).collect();
        let mut symbol_producers = HashMap::new();
        for d in declarations {
            if d.kind == "input" || d.kind == "compute" {
                symbol_producers.insert(d.name.clone(), d.decl_id.clone());
            }
        }

        let mut edges = Vec::new();
        for d in declarations {
            for dep in &d.deps {
                if let Some(from) = symbol_producers.get(dep) {
                    edges.push(DependencyEdge {
                        from: from.clone(),
                        to: d.decl_id.clone(),
                        kind: "symbol".to_string(),
                    });
                }
            }
        }

        DependencyGraph {
            nodes: declaration_ids,
            edges,
        }
    }
}

pub fn singularize(s: &str) -> String {
    let s_lower = s.to_lowercase();
    if s_lower.ends_with("s") {
        let mut base = s_lower[0..s_lower.len() - 1].to_string();
        if base.ends_with("_lead") {
            return "lead".to_string();
        }
        if base.starts_with("pending_") {
            base = base["pending_".len()..].to_string();
        }
        base
    } else {
        s_lower
    }
}

fn has_write_nodes(decl: &ClassifiedDecl) -> bool {
    if decl.kind == "emit_observation" || decl.kind == "compensation" {
        return true;
    }
    if let Some(expr) = &decl.expr {
        if expr_has_write(expr) {
            return true;
        }
    }
    if let Some(body_nodes) = &decl.body_nodes {
        for node in body_nodes {
            if has_write_nodes(node) {
                return true;
            }
        }
    }
    false
}

fn expr_has_write(expr: &Expr) -> bool {
    match expr {
        Expr::Call { fn_name, args } => {
            if fn_name == "emit_observation" {
                return true;
            }
            for arg in args {
                if expr_has_write(arg) {
                    return true;
                }
            }
        }
        Expr::BinaryOp { left, right, .. } => {
            if expr_has_write(left) || expr_has_write(right) {
                return true;
            }
        }
        Expr::UnaryOp { operand, .. } => {
            if expr_has_write(operand) {
                return true;
            }
        }
        Expr::FieldAccess { object, .. } => {
            if expr_has_write(object) {
                return true;
            }
        }
        Expr::IndexAccess { object, index } => {
            if expr_has_write(object) || expr_has_write(index) {
                return true;
            }
        }
        Expr::SliceRecord { fields } => {
            for v in fields.values() {
                if expr_has_write(v) {
                    return true;
                }
            }
        }
        Expr::IfExpr {
            cond,
            then,
            else_block,
        } => {
            if expr_has_write(cond) {
                return true;
            }
            for s in &then.stmts {
                match s {
                    crate::parser::Stmt::Let { expr, .. } => {
                        if expr_has_write(expr) {
                            return true;
                        }
                    }
                    crate::parser::Stmt::ExprStmt { expr } => {
                        if expr_has_write(expr) {
                            return true;
                        }
                    }
                }
            }
            if let Some(re) = &then.return_expr {
                if expr_has_write(re) {
                    return true;
                }
            }
            if let Some(eb) = else_block {
                for s in &eb.stmts {
                    match s {
                        crate::parser::Stmt::Let { expr, .. } => {
                            if expr_has_write(expr) {
                                return true;
                            }
                        }
                        crate::parser::Stmt::ExprStmt { expr } => {
                            if expr_has_write(expr) {
                                return true;
                            }
                        }
                    }
                }
                if let Some(re) = &eb.return_expr {
                    if expr_has_write(re) {
                        return true;
                    }
                }
            }
        }
        Expr::Lambda { body, .. } => match &**body {
            crate::parser::ExprOrBlock::Expr(e) => {
                if expr_has_write(e) {
                    return true;
                }
            }
            crate::parser::ExprOrBlock::Block(b) => {
                for s in &b.stmts {
                    match s {
                        crate::parser::Stmt::Let { expr, .. } => {
                            if expr_has_write(expr) {
                                return true;
                            }
                        }
                        crate::parser::Stmt::ExprStmt { expr } => {
                            if expr_has_write(expr) {
                                return true;
                            }
                        }
                    }
                }
                if let Some(re) = &b.return_expr {
                    if expr_has_write(re) {
                        return true;
                    }
                }
            }
        },
        Expr::ArrayLiteral { items } => {
            for item in items {
                if expr_has_write(item) {
                    return true;
                }
            }
        }
        Expr::RecordLiteral { fields } => {
            for v in fields.values() {
                if expr_has_write(v) {
                    return true;
                }
            }
        }
        Expr::RecordSpread { spread, fields } => {
            if expr_has_write(spread) {
                return true;
            }
            for v in fields.values() {
                if expr_has_write(v) {
                    return true;
                }
            }
        }
        _ => {}
    }
    false
}

fn has_compensation_nodes(decl: &ClassifiedDecl) -> bool {
    if decl.kind == "compensation" {
        return true;
    }
    if let Some(body_nodes) = &decl.body_nodes {
        for node in body_nodes {
            if has_compensation_nodes(node) {
                return true;
            }
        }
    }
    false
}

fn expr_has_io_call(expr: &Expr) -> bool {
    match expr {
        Expr::Call { fn_name, args } => {
            if fn_name.starts_with("stdlib.IO.") {
                return true;
            }
            for arg in args {
                if expr_has_io_call(arg) {
                    return true;
                }
            }
        }
        Expr::BinaryOp { left, right, .. } => {
            if expr_has_io_call(left) || expr_has_io_call(right) {
                return true;
            }
        }
        Expr::UnaryOp { operand, .. } => {
            if expr_has_io_call(operand) {
                return true;
            }
        }
        Expr::FieldAccess { object, .. } => {
            if expr_has_io_call(object) {
                return true;
            }
        }
        Expr::IndexAccess { object, index } => {
            if expr_has_io_call(object) || expr_has_io_call(index) {
                return true;
            }
        }
        Expr::SliceRecord { fields } => {
            for v in fields.values() {
                if expr_has_io_call(v) {
                    return true;
                }
            }
        }
        Expr::IfExpr {
            cond,
            then,
            else_block,
        } => {
            if expr_has_io_call(cond) {
                return true;
            }
            for s in &then.stmts {
                match s {
                    crate::parser::Stmt::Let { expr, .. } => {
                        if expr_has_io_call(expr) {
                            return true;
                        }
                    }
                    crate::parser::Stmt::ExprStmt { expr } => {
                        if expr_has_io_call(expr) {
                            return true;
                        }
                    }
                }
            }
            if let Some(re) = &then.return_expr {
                if expr_has_io_call(re) {
                    return true;
                }
            }
            if let Some(eb) = else_block {
                for s in &eb.stmts {
                    match s {
                        crate::parser::Stmt::Let { expr, .. } => {
                            if expr_has_io_call(expr) {
                                return true;
                            }
                        }
                        crate::parser::Stmt::ExprStmt { expr } => {
                            if expr_has_io_call(expr) {
                                return true;
                            }
                        }
                    }
                }
                if let Some(re) = &eb.return_expr {
                    if expr_has_io_call(re) {
                        return true;
                    }
                }
            }
        }
        Expr::Lambda { body, .. } => match &**body {
            crate::parser::ExprOrBlock::Expr(e) => {
                if expr_has_io_call(e) {
                    return true;
                }
            }
            crate::parser::ExprOrBlock::Block(b) => {
                for s in &b.stmts {
                    match s {
                        crate::parser::Stmt::Let { expr, .. } => {
                            if expr_has_io_call(expr) {
                                return true;
                            }
                        }
                        crate::parser::Stmt::ExprStmt { expr } => {
                            if expr_has_io_call(expr) {
                                return true;
                            }
                        }
                    }
                }
                if let Some(re) = &b.return_expr {
                    if expr_has_io_call(re) {
                        return true;
                    }
                }
            }
        },
        Expr::ArrayLiteral { items } => {
            for item in items {
                if expr_has_io_call(item) {
                    return true;
                }
            }
        }
        Expr::RecordLiteral { fields } => {
            for v in fields.values() {
                if expr_has_io_call(v) {
                    return true;
                }
            }
        }
        Expr::RecordSpread { spread, fields } => {
            if expr_has_io_call(spread) {
                return true;
            }
            for v in fields.values() {
                if expr_has_io_call(v) {
                    return true;
                }
            }
        }
        _ => {}
    }
    false
}

fn check_expr_io(
    expr: &Expr,
    capabilities: &HashMap<String, TypeRef>,
    effects: &HashMap<String, String>,
    contract_name: &str,
    is_pure: bool,
    diagnostics: &mut Vec<ClassifierDiagnostic>,
) {
    match expr {
        Expr::Call { fn_name, args } => {
            if fn_name.starts_with("stdlib.IO.") {
                if is_pure {
                    diagnostics.push(ClassifierDiagnostic {
                        rule: "E-IO-AMBIENT-BLOCKED".to_string(),
                        message: format!(
                            "I/O calls are blocked in pure contract '{}'",
                            contract_name
                        ),
                        node: contract_name.to_string(),
                        line: None,
                    });
                } else if capabilities.is_empty() {
                    diagnostics.push(ClassifierDiagnostic {
                        rule: "E-IO-AMBIENT-BLOCKED".to_string(),
                        message: format!("Ambient call to standard I/O function '{}' is blocked without capability context", fn_name),
                        node: contract_name.to_string(),
                        line: None,
                    });
                } else {
                    let min_args =
                        if fn_name == "stdlib.IO.write_text" || fn_name == "stdlib.IO.write_json" {
                            3
                        } else {
                            2
                        };
                    if args.len() < min_args {
                        diagnostics.push(ClassifierDiagnostic {
                            rule: "E-IO-CAP-MISSING".to_string(),
                            message: format!(
                                "I/O call to '{}' is missing capability argument",
                                fn_name
                            ),
                            node: contract_name.to_string(),
                            line: None,
                        });
                    } else {
                        let cap_arg = &args[args.len() - 1];
                        if let Expr::Ref { name: cap_ref } = cap_arg {
                            if !capabilities.contains_key(cap_ref) {
                                diagnostics.push(ClassifierDiagnostic {
                                    rule: "E-IO-CAP-UNKNOWN".to_string(),
                                    message: format!(
                                        "Capability '{}' referenced in I/O call is undeclared",
                                        cap_ref
                                    ),
                                    node: contract_name.to_string(),
                                    line: None,
                                });
                            } else {
                                if !effects.contains_key(cap_ref) {
                                    diagnostics.push(ClassifierDiagnostic {
                                        rule: "E-IO-EFFECT-UNDECLARED".to_string(),
                                        message: format!("Capability '{}' is declared but has no matching effect declaration in contract '{}'", cap_ref, contract_name),
                                        node: contract_name.to_string(),
                                        line: None,
                                    });
                                }
                                let is_write_fn = fn_name == "stdlib.IO.write_text"
                                    || fn_name == "stdlib.IO.write_json";
                                if is_write_fn {
                                    if !cap_ref.contains("write") {
                                        diagnostics.push(ClassifierDiagnostic {
                                            rule: "E-IO-CAP-WRONG-MODE".to_string(),
                                            message: format!("Write operation '{}' requires write capability, but '{}' was passed", fn_name, cap_ref),
                                            node: contract_name.to_string(),
                                            line: None,
                                        });
                                    }
                                } else {
                                    if !cap_ref.contains("read") {
                                        diagnostics.push(ClassifierDiagnostic {
                                            rule: "E-IO-CAP-WRONG-MODE".to_string(),
                                            message: format!("Read operation '{}' requires read capability, but '{}' was passed", fn_name, cap_ref),
                                            node: contract_name.to_string(),
                                            line: None,
                                        });
                                    }
                                }
                            }
                        } else {
                            diagnostics.push(ClassifierDiagnostic {
                                rule: "E-IO-CAP-MISSING".to_string(),
                                message: format!("I/O call to '{}' requires a valid capability reference, got malformed expression", fn_name),
                                node: contract_name.to_string(),
                                line: None,
                            });
                        }
                    }
                }
            }
            for arg in args {
                check_expr_io(
                    arg,
                    capabilities,
                    effects,
                    contract_name,
                    is_pure,
                    diagnostics,
                );
            }
        }
        Expr::BinaryOp { left, right, .. } => {
            check_expr_io(
                left,
                capabilities,
                effects,
                contract_name,
                is_pure,
                diagnostics,
            );
            check_expr_io(
                right,
                capabilities,
                effects,
                contract_name,
                is_pure,
                diagnostics,
            );
        }
        Expr::UnaryOp { operand, .. } => {
            check_expr_io(
                operand,
                capabilities,
                effects,
                contract_name,
                is_pure,
                diagnostics,
            );
        }
        Expr::FieldAccess { object, .. } => {
            check_expr_io(
                object,
                capabilities,
                effects,
                contract_name,
                is_pure,
                diagnostics,
            );
        }
        Expr::IndexAccess { object, index } => {
            check_expr_io(
                object,
                capabilities,
                effects,
                contract_name,
                is_pure,
                diagnostics,
            );
            check_expr_io(
                index,
                capabilities,
                effects,
                contract_name,
                is_pure,
                diagnostics,
            );
        }
        Expr::SliceRecord { fields } => {
            for v in fields.values() {
                check_expr_io(
                    v,
                    capabilities,
                    effects,
                    contract_name,
                    is_pure,
                    diagnostics,
                );
            }
        }
        Expr::IfExpr {
            cond,
            then,
            else_block,
        } => {
            check_expr_io(
                cond,
                capabilities,
                effects,
                contract_name,
                is_pure,
                diagnostics,
            );
            for s in &then.stmts {
                match s {
                    crate::parser::Stmt::Let { expr, .. } => {
                        check_expr_io(
                            expr,
                            capabilities,
                            effects,
                            contract_name,
                            is_pure,
                            diagnostics,
                        );
                    }
                    crate::parser::Stmt::ExprStmt { expr } => {
                        check_expr_io(
                            expr,
                            capabilities,
                            effects,
                            contract_name,
                            is_pure,
                            diagnostics,
                        );
                    }
                }
            }
            if let Some(re) = &then.return_expr {
                check_expr_io(
                    re,
                    capabilities,
                    effects,
                    contract_name,
                    is_pure,
                    diagnostics,
                );
            }
            if let Some(eb) = else_block {
                for s in &eb.stmts {
                    match s {
                        crate::parser::Stmt::Let { expr, .. } => {
                            check_expr_io(
                                expr,
                                capabilities,
                                effects,
                                contract_name,
                                is_pure,
                                diagnostics,
                            );
                        }
                        crate::parser::Stmt::ExprStmt { expr } => {
                            check_expr_io(
                                expr,
                                capabilities,
                                effects,
                                contract_name,
                                is_pure,
                                diagnostics,
                            );
                        }
                    }
                }
                if let Some(re) = &eb.return_expr {
                    check_expr_io(
                        re,
                        capabilities,
                        effects,
                        contract_name,
                        is_pure,
                        diagnostics,
                    );
                }
            }
        }
        Expr::Lambda { body, .. } => match &**body {
            crate::parser::ExprOrBlock::Expr(e) => {
                check_expr_io(
                    e,
                    capabilities,
                    effects,
                    contract_name,
                    is_pure,
                    diagnostics,
                );
            }
            crate::parser::ExprOrBlock::Block(b) => {
                for s in &b.stmts {
                    match s {
                        crate::parser::Stmt::Let { expr, .. } => {
                            check_expr_io(
                                expr,
                                capabilities,
                                effects,
                                contract_name,
                                is_pure,
                                diagnostics,
                            );
                        }
                        crate::parser::Stmt::ExprStmt { expr } => {
                            check_expr_io(
                                expr,
                                capabilities,
                                effects,
                                contract_name,
                                is_pure,
                                diagnostics,
                            );
                        }
                    }
                }
                if let Some(re) = &b.return_expr {
                    check_expr_io(
                        re,
                        capabilities,
                        effects,
                        contract_name,
                        is_pure,
                        diagnostics,
                    );
                }
            }
        },
        Expr::ArrayLiteral { items } => {
            for item in items {
                check_expr_io(
                    item,
                    capabilities,
                    effects,
                    contract_name,
                    is_pure,
                    diagnostics,
                );
            }
        }
        Expr::RecordLiteral { fields } => {
            for v in fields.values() {
                check_expr_io(
                    v,
                    capabilities,
                    effects,
                    contract_name,
                    is_pure,
                    diagnostics,
                );
            }
        }
        Expr::RecordSpread { spread, fields } => {
            check_expr_io(spread, capabilities, effects, contract_name, is_pure, diagnostics);
            for v in fields.values() {
                check_expr_io(
                    v,
                    capabilities,
                    effects,
                    contract_name,
                    is_pure,
                    diagnostics,
                );
            }
        }
        _ => {}
    }
}
