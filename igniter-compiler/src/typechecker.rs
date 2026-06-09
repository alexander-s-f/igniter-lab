use crate::parser::{Expr, TypeRef, WindowValue, Stmt, ExprOrBlock, OlapPointDecl, FunctionDecl, Param};
use crate::classifier::{ClassifiedProgram, ClassifiedContract, ClassifiedDecl, ClassifiedSymbol, DependencyGraph, ClassifierDiagnostic};
use std::collections::{HashMap, HashSet};

// ── PROP-041 T2: structural-size relation ────────────────────────────────────

/// Registry entry for a structural-size relation.
/// NOT a full termination proof — structural evidence with trust metadata only.
#[derive(Debug, Clone)]
pub struct T2RegistryEntry {
    pub trust: String,  // "stdlib_certified" | "user_assumed"
    pub source: String, // "compiler_builtin" | module name
}

/// T2 context for a contract currently being typechecked.
#[derive(Debug, Clone)]
pub struct T2Context {
    pub kind: T2Kind,
    pub dv: String,      // dotted-path variant, e.g. "items.tail"
    pub subject: String, // e.g. "items"
    pub accessor: String,// e.g. "tail"
    pub trust: String,
    pub source: String,
}

#[derive(Debug, Clone, PartialEq)]
pub enum T2Kind {
    T2Pass, // registered relation — SIR structural_size_v1
    T2R8,   // missing relation — OOF-R8
    T2R3,   // numeric accessor — OOF-R3
}

/// Build STDLIB_SIZE_REGISTRY: hardcoded stdlib_certified entries.
/// Only Collection.tail and Collection.rest are certified in v1.
fn stdlib_size_registry() -> HashMap<(String, String), T2RegistryEntry> {
    let mut m = HashMap::new();
    m.insert(
        ("Collection".to_string(), "tail".to_string()),
        T2RegistryEntry { trust: "stdlib_certified".to_string(), source: "compiler_builtin".to_string() },
    );
    m.insert(
        ("Collection".to_string(), "rest".to_string()),
        T2RegistryEntry { trust: "stdlib_certified".to_string(), source: "compiler_builtin".to_string() },
    );
    m
}

/// Numeric accessors are T3 territory — route to OOF-R3, not OOF-R8.
/// Closed list in v1; not user-extensible.
const NUMERIC_ACCESSORS: &[&str] = &["count", "length", "size", "total_count", "num_items", "num_elements"];

// ── end PROP-041 T2 ──────────────────────────────────────────────────────────

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct TypedProgram {
    pub kind: String, // "typed_program"
    pub typechecker_version: String,
    pub program_id: String,
    pub classified_program_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source_path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source_hash: Option<String>,
    pub grammar_version: String,
    pub module: Option<String>,
    pub type_env: HashMap<String, HashMap<String, serde_json::Value>>,
    pub contracts: Vec<TypedContract>,
    pub type_errors: Vec<ClassifierDiagnostic>,
    pub semantic_ir_ref: serde_json::Value,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub assumption_registry: Option<Vec<serde_json::Value>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub olap_points: Option<Vec<serde_json::Value>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub type_warnings: Option<Vec<ClassifierDiagnostic>>,
    pub pass_result: String,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct TypedContract {
    pub kind: String, // "typed_contract"
    pub contract_id: String,
    pub name: String,
    pub modifier: String,
    pub status: String, // "accepted" or "blocked"
    pub fragment_class: String,
    pub symbols: Vec<TypedSymbol>,
    pub declarations: Vec<TypedDecl>,
    pub type_errors: Vec<ClassifierDiagnostic>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub type_warnings: Option<Vec<ClassifierDiagnostic>>,
    /// PROP-039 OOF-R3: clean (non-dotted) decreases variant propagated to SemanticIR emitter.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub decreases_variant: Option<String>,
    /// PROP-041 T2: dotted-path decreases variant when a registered size_relation passes.
    /// Present only when T2 dispatch succeeds; mutually exclusive with decreases_variant for the same contract.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub decreases_variant_t2: Option<String>,
    /// PROP-041 T2: trust/source evidence for structural_size_v1 SemanticIR emission.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub size_relation_evidence: Option<serde_json::Value>,
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
pub struct TypedSymbol {
    pub name: String,
    pub type_info: serde_json::Value, // "type" in json
    pub resolved: bool,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct TypedDecl {
    pub decl_id: String,
    pub kind: String,
    pub name: String,
    pub fragment_class: String,
    pub type_info: serde_json::Value, // "type" in json
    pub deps: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub expr: Option<Expr>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub semantic_node: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub node_fragment_class: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub value_fragment_class: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub required_capability: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub temporal_axis: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub from: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub lifecycle: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub options: Option<HashMap<String, WindowValue>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub window_ref: Option<String>,
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
    pub output_effect: Option<String>,
    // Output propagation effects:
    #[serde(skip_serializing_if = "Option::is_none")]
    pub warnings_from: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub uncertain_from: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub metrics_from: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub body_nodes: Option<Vec<TypedDecl>>,
}

pub struct TypeChecker {
    version: String,
}

impl TypeChecker {
    pub fn new() -> Self {
        Self {
            version: "typed-pass-executable-proof-v0".to_string(),
        }
    }

    pub fn typecheck(&self, classified: &ClassifiedProgram, functions: &[crate::parser::FunctionDecl]) -> TypedProgram {
        let type_shapes = self.build_type_shapes(classified);
        let mut typed_contracts = Vec::new();
        let mut type_errors = Vec::new();
        let mut type_warnings = Vec::new();

        // Build OLAP points environment
        let olap_env = self.build_olap_env(classified.olap_points.as_ref().unwrap_or(&Vec::new()));

        // PROP-041 T2: build size-relation registry (stdlib + user-declared).
        // Built once before the contracts loop so all contracts share the same registry.
        let size_registry = self.build_size_registry(classified);

        for contract in &classified.contracts {
            let mut tc = self.typecheck_contract(contract, &type_shapes, &olap_env, classified.assumption_registry.as_ref().unwrap_or(&Vec::new()), functions, &size_registry);
            type_errors.append(&mut tc.type_errors.clone());
            if let Some(mut w) = tc.type_warnings.clone() {
                type_warnings.append(&mut w);
            }
            typed_contracts.push(tc);
        }

        // Validate recursive functions specify decreases fuel: T1.5
        for f in functions {
            if is_recursive(&f.body, &f.name) {
                if f.decreases.as_deref() != Some("fuel") {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-L4".to_string(),
                        message: format!("Recursive function '{}' must specify 'decreases fuel'", f.name),
                        node: f.name.clone(),
                        line: None,
                    });
                }
            }
        }

        // Validate now() is completely forbidden in user functions (Postulate 1)
        for f in functions {
            if block_has_now(&f.body) {
                type_errors.push(ClassifierDiagnostic {
                    rule: "OOF-L2".to_string(),
                    message: format!("now() is forbidden in function '{}' — use explicit as_of binding or tick.time", f.name),
                    node: f.name.clone(),
                    line: None,
                });
            }
        }

        // Validate now() is forbidden in contract expressions (compute/loop/service loop bodies)
        for contract in &classified.contracts {
            for node in &contract.declarations {
                if let Some(expr) = &node.expr {
                    if expr_has_now(expr) {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-L2".to_string(),
                            message: format!("now() is forbidden in contract '{}' node '{}' — use explicit as_of binding or tick.time", contract.name, node.name),
                            node: node.name.clone(),
                            line: None,
                        });
                    }
                }
                if let Some(body_nodes) = &node.body_nodes {
                    for inner in body_nodes {
                        if let Some(expr) = &inner.expr {
                            if expr_has_now(expr) {
                                type_errors.push(ClassifierDiagnostic {
                                    rule: "OOF-L2".to_string(),
                                    message: format!("now() is forbidden in contract '{}' loop/service node '{}' — use explicit as_of binding or tick.time", contract.name, inner.name),
                                    node: inner.name.clone(),
                                    line: None,
                                });
                            }
                        }
                    }
                }
            }
        }

        let program_id = format!("typed_pass/{}", blake3::hash(format!("{}|{}", classified.program_id, self.version).as_bytes()));

        let pass_result = if type_errors.iter().any(|d| d.rule.starts_with("OOF-")) {
            "oof".to_string()
        } else {
            "ok".to_string()
        };

        TypedProgram {
            kind: "typed_program".to_string(),
            typechecker_version: self.version.clone(),
            program_id: program_id[0..24].to_string(),
            classified_program_id: classified.program_id.clone(),
            source_path: classified.source_path.clone(),
            source_hash: classified.source_hash.clone(),
            grammar_version: classified.grammar_version.clone(),
            module: classified.module.clone(),
            type_env: type_shapes,
            contracts: typed_contracts,
            type_errors: self.dedupe_errors(&type_errors),
            semantic_ir_ref: serde_json::Value::Null,
            assumption_registry: classified.assumption_registry.clone(),
            olap_points: if olap_env.is_empty() { None } else { Some(olap_env.values().map(|v| v.get("semantic_node").unwrap().clone()).collect()) },
            type_warnings: if type_warnings.is_empty() { None } else { Some(self.dedupe_errors(&type_warnings)) },
            pass_result,
        }
    }

    fn build_type_shapes(&self, classified: &ClassifiedProgram) -> HashMap<String, HashMap<String, serde_json::Value>> {
        let mut map = HashMap::new();
        for t in &classified.type_declarations {
            let mut fields = HashMap::new();
            for f in &t.fields {
                fields.insert(f.name.clone(), self.type_ir(&f.type_annotation));
            }
            map.insert(t.name.clone(), fields);
        }
        map
    }

    fn build_olap_env(&self, olaps: &[OlapPointDecl]) -> HashMap<String, HashMap<String, serde_json::Value>> {
        let mut env = HashMap::new();
        for point in olaps {
            let mut entry = HashMap::new();
            let name = point.name.clone();

            let dimensions: HashMap<String, serde_json::Value> = point.dimensions.iter().map(|(k, v)| {
                (k.clone(), self.type_ir(&serde_json::to_value(v).unwrap()))
            }).collect();

            let measure_type = self.type_ir(&serde_json::to_value(&point.measure).unwrap());

            // Build structural OLAP type: OLAPPoint[Measure, DimsRecord[Dimensions]]
            let mut olap_type = serde_json::Map::new();
            olap_type.insert("name".to_string(), serde_json::Value::String("OLAPPoint".to_string()));
            let mut params = Vec::new();
            params.push(measure_type.clone());

            let mut dims_record = serde_json::Map::new();
            dims_record.insert("name".to_string(), serde_json::Value::String("DimsRecord".to_string()));
            dims_record.insert("params".to_string(), serde_json::Value::Array(Vec::new()));
            dims_record.insert("dims".to_string(), serde_json::to_value(&dimensions).unwrap());

            params.push(serde_json::Value::Object(dims_record));
            olap_type.insert("params".to_string(), serde_json::Value::Array(params));

            let mut semantic_node = serde_json::Map::new();
            semantic_node.insert("kind".to_string(), serde_json::Value::String("olap_point_decl".to_string()));
            semantic_node.insert("name".to_string(), serde_json::Value::String(name.clone()));
            semantic_node.insert("dimensions".to_string(), serde_json::to_value(&point.dimensions).unwrap());
            semantic_node.insert("measure_type".to_string(), serde_json::to_value(&point.measure).unwrap());
            semantic_node.insert("granularity".to_string(), serde_json::to_value(&point.granularity).unwrap());
            semantic_node.insert("indexed".to_string(), serde_json::to_value(&point.indexed).unwrap());

            entry.insert("name".to_string(), serde_json::Value::String(name.clone()));
            entry.insert("type".to_string(), serde_json::Value::Object(olap_type));
            entry.insert("dimensions".to_string(), serde_json::to_value(dimensions).unwrap());
            entry.insert("measure_type".to_string(), measure_type);
            entry.insert("granularity".to_string(), serde_json::to_value(&point.granularity).unwrap());
            entry.insert("indexed".to_string(), serde_json::to_value(&point.indexed).unwrap());
            entry.insert("semantic_node".to_string(), serde_json::Value::Object(semantic_node));

            env.insert(name, entry);
        }
        env
    }

    fn typecheck_contract(
        &self,
        classified: &ClassifiedContract,
        type_shapes: &HashMap<String, HashMap<String, serde_json::Value>>,
        olap_env: &HashMap<String, HashMap<String, serde_json::Value>>,
        assumptions: &[serde_json::Value],
        functions: &[crate::parser::FunctionDecl],
        size_registry: &HashMap<(String, String), T2RegistryEntry>,
    ) -> TypedContract {
        let mut type_errors = classified.oof_log.clone();
        let mut type_warnings = Vec::new();
        let mut symbol_types = HashMap::new();
        let mut typed_decls = Vec::new();
        let mut invariant_effects: Vec<(String, String)> = Vec::new();

        // Register assumptions in type shapes if any present
        let mut local_type_shapes = type_shapes.clone();
        if !assumptions.is_empty() || classified.assumption_refs.is_some() {
            let mut fields = HashMap::new();
            fields.insert("kind".to_string(), self.type_ir(&serde_json::Value::String("Symbol".to_string())));
            fields.insert("statement".to_string(), self.type_ir(&serde_json::Value::String("String".to_string())));
            fields.insert("strength".to_string(), self.type_ir(&serde_json::Value::String("Decimal".to_string())));
            fields.insert("source".to_string(), self.type_ir(&serde_json::Value::String("String".to_string())));
            local_type_shapes.insert("Assumption".to_string(), fields);
        }
        let mut clock_tick_fields = HashMap::new();
        clock_tick_fields.insert("time".to_string(), self.type_ir(&serde_json::Value::String("Integer".to_string())));
        local_type_shapes.insert("ClockTick".to_string(), clock_tick_fields);

        // Validate assumptions strength at typecheck stage: TASSUMP-1
        for entry in assumptions {
            if let Some(fields) = entry.get("fields") {
                if let Some(strength_val) = fields.get("strength") {
                    if let Some(strength) = strength_val.as_f64() {
                        if strength < 0.0 || strength > 1.0 {
                            type_errors.push(ClassifierDiagnostic {
                                rule: "TASSUMP-1".to_string(),
                                message: "assumption strength must be between 0.0 and 1.0".to_string(),
                                node: format!("assumption:{}", entry.get("name").and_then(|n| n.as_str()).unwrap_or_default()),
                                line: None,
                            });
                        }
                    }
                }
            }
        }

        // PROP-039 gate 5: recur() context for validation
        let contract_modifier = classified.modifier.as_str();
        let recur_authorized = matches!(contract_modifier, "recursive" | "fuel_bounded");
        // Inputs in declaration order for positional arg mapping
        let recur_input_names: Vec<String> = classified.declarations.iter()
            .filter(|d| d.kind == "input")
            .map(|d| d.name.clone())
            .collect();
        let recur_output_count = classified.declarations.iter()
            .filter(|d| d.kind == "output")
            .count();
        // The single output type (for recur() return-type inference)
        let recur_output_type: Option<serde_json::Value> = if recur_output_count == 1 {
            classified.declarations.iter()
                .find(|d| d.kind == "output")
                .and_then(|d| d.type_annotation.as_ref())
                .map(|ta| self.type_ir(ta))
        } else {
            None
        };

        // PROP-039 OOF-R3 / PROP-041 T2: decreases variant dispatch
        // Dotted-path: T2 registry lookup (numeric → OOF-R3, registered → T2, missing → OOF-R8).
        // Simple identifier: kept as-is for OOF-R3 call-site checks.
        let t2_context: Option<T2Context>;
        let clean_decreases_variant: Option<String> = match &classified.decreases_variant {
            Some(v) if v.contains('.') => {
                // PROP-041 T2 dispatch
                let ctx = self.handle_t2_variant(v, classified, &mut type_errors, size_registry);
                t2_context = ctx;
                None  // dotted-path never kept as a raw variant in @recur_context
            }
            Some(v) => {
                t2_context = None;
                Some(v.clone())
            }
            None => {
                t2_context = None;
                None
            }
        };
        // Positional index of the decreases variant in the input list
        let decreases_variant_pos: Option<usize> = clean_decreases_variant.as_ref()
            .and_then(|v| recur_input_names.iter().position(|n| n == v));

        for decl in &classified.declarations {
            match decl.kind.as_str() {
                "input" | "read" | "stream" => {
                    let ty = self.type_ir(decl.type_annotation.as_ref().unwrap());
                    symbol_types.insert(decl.name.clone(), ty.clone());
                    typed_decls.push(self.typed_decl(decl, ty, None, Vec::new()));
                }
                "capability" => {
                    let ty = self.type_ir(decl.type_annotation.as_ref().unwrap());
                    symbol_types.insert(decl.name.clone(), ty.clone());
                    typed_decls.push(self.typed_decl(decl, ty, None, Vec::new()));
                }
                "effect" => {
                    let ty = self.type_ir(&serde_json::Value::String("Effect".to_string()));
                    symbol_types.insert(decl.name.clone(), ty.clone());
                    typed_decls.push(self.typed_decl(decl, ty, None, Vec::new()));
                }
                "window" => {
                    let ty = self.type_ir(&serde_json::Value::String("Window".to_string()));
                    typed_decls.push(self.typed_decl(decl, ty, None, Vec::new()));
                }
                "uses_assumptions" => {
                    let ty = self.type_ir(&serde_json::Value::String("Assumption".to_string()));
                    symbol_types.insert(decl.name.clone(), ty.clone());
                    typed_decls.push(self.typed_decl(decl, ty, None, Vec::new()));
                }
                "loop" => {
                    let ty = self.type_ir(&serde_json::Value::String("Nil".to_string()));
                    symbol_types.insert(decl.name.clone(), ty.clone());
                    
                    // G6 (PROP-039 canon OOF-L1): FiniteLoop (`for`) source must be Collection[T].
                    // Canon: OOF-L1 fires in TypeChecker when for_loop source is not Collection[T].
                    let loop_class_opt = decl.options.as_ref()
                        .and_then(|o| o.get("loop_class"))
                        .and_then(|v| if let crate::parser::WindowValue::Str(s) = v { Some(s.clone()) } else { None });
                    let is_finite_loop = loop_class_opt.as_deref() == Some("finite");

                    let mut loop_var_types = HashMap::new();
                    if let Some(Expr::Ref { name: ref_name }) = &decl.expr {
                        let item_ty = if let Some(coll_ty) = symbol_types.get(ref_name) {
                            let ty_name = self.type_name(coll_ty);
                            if ty_name == "Array" || ty_name == "Collection" {
                                let param_val = coll_ty.get("params")
                                    .and_then(|p| p.as_array())
                                    .and_then(|arr| arr.first())
                                    .cloned()
                                    .unwrap_or_else(|| serde_json::Value::String("Unknown".to_string()));
                                self.type_ir(&param_val)
                            } else {
                                // G6: for FiniteLoop, non-Collection source is an OOF-L1 (canon meaning)
                                if is_finite_loop {
                                    type_errors.push(crate::classifier::ClassifierDiagnostic {
                                        rule: "OOF-L1".to_string(),
                                        message: format!(
                                            "for loop '{}': source '{}' has type '{}' — must be Collection[T] (canon OOF-L1)",
                                            decl.name, ref_name, ty_name
                                        ),
                                        node: decl.name.clone(),
                                        line: None,
                                    });
                                }
                                self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                            }
                        } else {
                            self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                        };

                        // G1: prefer explicit item variable from classifier options.
                        // Falls back to singularize(collection) for backward compat.
                        let item_var = decl.options.as_ref()
                            .and_then(|o| o.get("item"))
                            .and_then(|v| if let crate::parser::WindowValue::Str(s) = v { Some(s.clone()) } else { None })
                            .unwrap_or_else(|| crate::classifier::singularize(ref_name));

                        let singular_loop = crate::classifier::singularize(&decl.name);

                        loop_var_types.insert(item_var, item_ty.clone());
                        loop_var_types.insert(singular_loop, item_ty.clone());
                        loop_var_types.insert("item".to_string(), item_ty);
                    }
                    
                    let mut body_symbol_types = symbol_types.clone();
                    for (k, v) in loop_var_types {
                        body_symbol_types.insert(k, v);
                    }
                    
                    let mut typed_body_nodes = Vec::new();
                    let mut lead_names: Vec<String> = Vec::new();

                    // Derive item_type string for gate 8 canon body
                    // Use body_symbol_types["item"] which has the element type already resolved
                    let item_type_str = {
                        let item_var = decl.options.as_ref()
                            .and_then(|o| o.get("item"))
                            .and_then(|v| if let crate::parser::WindowValue::Str(s) = v { Some(s.clone()) } else { None })
                            .unwrap_or_else(|| "item".to_string());
                        body_symbol_types.get(&item_var)
                            .or_else(|| body_symbol_types.get("item"))
                            .and_then(|ty| ty.get("name").and_then(|n| n.as_str()).map(|s| s.to_string()))
                            .unwrap_or_else(|| "Unknown".to_string())
                    };

                    if let Some(body_nodes) = &decl.body_nodes {
                        // Extract item variable name for OOF-L7 checks
                        let item_var = decl.options.as_ref()
                            .and_then(|o| o.get("item"))
                            .and_then(|v| if let crate::parser::WindowValue::Str(s) = v { Some(s.clone()) } else { None })
                            .unwrap_or_else(|| "item".to_string());

                        // PROP-039 gate 8: OOF-L7/OOF-L5 target checks only apply when the body
                        // has at least one `lead` binding (gate-8 mode). Without lead, the old
                        // accumulation pattern (compute outer_symbol = ...) remains valid for VM compat.
                        let is_gate8_body = body_nodes.iter().any(|n| n.kind == "lead");

                        for inner_decl in body_nodes {
                            match inner_decl.kind.as_str() {
                                "lead" => {
                                    // PROP-039 gate 8: validate lead initial is a literal
                                    let is_literal = inner_decl.expr.as_ref()
                                        .map(|e| matches!(e, Expr::Literal { .. }))
                                        .unwrap_or(false);
                                    if !is_literal {
                                        type_errors.push(crate::classifier::ClassifierDiagnostic {
                                            rule: "OOF-L5".to_string(),
                                            message: format!(
                                                "lead '{}' in loop '{}': initial value must be a static literal in v0",
                                                inner_decl.name, decl.name
                                            ),
                                            node: decl.name.clone(),
                                            line: None,
                                        });
                                    }
                                    lead_names.push(inner_decl.name.clone());
                                    // Derive type from annotation (stored in classifier as JSON)
                                    let lead_type_ir = inner_decl.type_annotation.as_ref()
                                        .map(|t| self.type_ir(t))
                                        .unwrap_or_else(|| self.type_ir(&serde_json::Value::String("Unknown".to_string())));
                                    let type_str = lead_type_ir.get("name")
                                        .and_then(|v| v.as_str())
                                        .unwrap_or("Unknown")
                                        .to_string();
                                    // Add lead to body symbol types for subsequent computes
                                    body_symbol_types.insert(
                                        inner_decl.name.clone(),
                                        self.type_ir(&serde_json::Value::String(type_str))
                                    );
                                    typed_body_nodes.push(self.typed_decl(inner_decl, lead_type_ir, inner_decl.expr.clone(), inner_decl.deps.clone()));
                                }
                                "compute" => {
                                    // PROP-039 gate 8: OOF-L7/OOF-L5 target checks (gate-8 mode only)
                                    let target = &inner_decl.name;
                                    if is_gate8_body {
                                        if target == &item_var || target == "item" {
                                            type_errors.push(crate::classifier::ClassifierDiagnostic {
                                                rule: "OOF-L7".to_string(),
                                                message: format!(
                                                    "body compute in loop '{}' targets loop item '{}' — item is read-only",
                                                    decl.name, target
                                                ),
                                                node: decl.name.clone(),
                                                line: None,
                                            });
                                        } else if symbol_types.contains_key(target.as_str()) && !lead_names.contains(target) {
                                            type_errors.push(crate::classifier::ClassifierDiagnostic {
                                                rule: "OOF-L7".to_string(),
                                                message: format!(
                                                    "body compute in loop '{}' targets outer contract symbol '{}' — outer state is read-only",
                                                    decl.name, target
                                                ),
                                                node: decl.name.clone(),
                                                line: None,
                                            });
                                        } else if !lead_names.contains(target) && !symbol_types.contains_key(target.as_str()) && target != &item_var && target != "item" {
                                            type_errors.push(crate::classifier::ClassifierDiagnostic {
                                                rule: "OOF-L5".to_string(),
                                                message: format!(
                                                    "body compute in loop '{}' targets '{}' which is not a declared lead binding",
                                                    decl.name, target
                                                ),
                                                node: decl.name.clone(),
                                                line: None,
                                            });
                                        }
                                    }

                                    let typed_expr = self.infer_expr(inner_decl.expr.as_ref().unwrap(), &body_symbol_types, olap_env, &local_type_shapes, &mut type_errors, &mut type_warnings, &inner_decl.name, functions);
                                    body_symbol_types.insert(inner_decl.name.clone(), typed_expr.resolved_type.clone());
                                    typed_body_nodes.push(self.typed_decl(inner_decl, typed_expr.resolved_type, inner_decl.expr.clone(), inner_decl.deps.clone()));
                                    // PROP-039 gate 5: recur() in loop body is always OOF-R1
                                    if let Some(expr) = &inner_decl.expr {
                                        self.check_recur_in_expr(
                                            expr,
                                            false, // loop body is never a recur-authorized context
                                            &[],
                                            0,
                                            &body_symbol_types,
                                            olap_env,
                                            &local_type_shapes,
                                            &mut type_errors,
                                            &mut type_warnings,
                                            &decl.name,
                                            functions,
                                            None,
                                            None,
                                        );
                                    }
                                }
                                _ => {}
                            }
                        }
                    }

                    let mut typed_loop_decl = self.typed_decl(decl, ty, decl.expr.clone(), decl.deps.clone());
                    // Store item_type in options for gate 8 emitter
                    if let Some(opts) = &mut typed_loop_decl.options {
                        opts.insert("item_type".to_string(), crate::parser::WindowValue::Str(item_type_str));
                    }
                    typed_loop_decl.body_nodes = Some(typed_body_nodes);
                    typed_decls.push(typed_loop_decl);
                }
                "service_loop" => {
                    let ty = self.type_ir(&serde_json::Value::String("Nil".to_string()));
                    symbol_types.insert(decl.name.clone(), ty.clone());
                    
                    let tick_ty = self.type_ir(&serde_json::Value::String("ClockTick".to_string()));
                    
                    let mut body_symbol_types = symbol_types.clone();
                    body_symbol_types.insert(decl.name.clone(), tick_ty);
                    
                    let mut typed_body_nodes = Vec::new();
                    if let Some(body_nodes) = &decl.body_nodes {
                        for inner_decl in body_nodes {
                            if inner_decl.kind == "compute" {
                                let mut typed_expr = self.infer_expr(inner_decl.expr.as_ref().unwrap(), &body_symbol_types, olap_env, &local_type_shapes, &mut type_errors, &mut type_warnings, &inner_decl.name, functions);
                                body_symbol_types.insert(inner_decl.name.clone(), typed_expr.resolved_type.clone());
                                typed_body_nodes.push(self.typed_decl(inner_decl, typed_expr.resolved_type, inner_decl.expr.clone(), inner_decl.deps.clone()));
                            }
                        }
                    }
                    
                    let mut typed_loop_decl = self.typed_decl(decl, ty, None, decl.deps.clone());
                    typed_loop_decl.body_nodes = Some(typed_body_nodes);
                    typed_decls.push(typed_loop_decl);
                }
                "fold_stream" => {
                    // fold_stream result type defaults to init arg type
                    let mut res_type = self.type_ir(&serde_json::Value::String("Unknown".to_string()));
                    if let Some(Expr::Call { args, .. }) = &decl.expr {
                        if args.len() >= 2 {
                            if let Expr::Literal { type_tag, .. } = &args[1] {
                                res_type = self.type_ir(&serde_json::Value::String(type_tag.clone()));
                            }
                        }
                    }

                    // OOF-S3 Check: check for escape (stream) refs inside fold accumulator lambda
                    if let Some(Expr::Call { args, .. }) = &decl.expr {
                        if args.len() >= 3 {
                            if let Expr::Lambda { params, body } = &args[2] {
                                let mut stream_symbols = HashSet::new();
                                for s in &classified.symbols {
                                    if s.kind == "stream" {
                                        stream_symbols.insert(s.name.clone());
                                    }
                                }
                                let mut lambda_params: HashSet<String> = params.iter().cloned().collect();
                                let mut escape_refs = Vec::new();
                                self.collect_escape_refs(body, &stream_symbols, &mut lambda_params, &mut escape_refs);
                                for ref_name in escape_refs {
                                    type_errors.push(ClassifierDiagnostic {
                                        rule: "OOF-S3".to_string(),
                                        message: format!("fold_stream accumulator must be CORE - found ESCAPE: {}", ref_name),
                                        node: decl.name.clone(),
                                        line: None,
                                    });
                                }
                            }
                        }
                    }

                    symbol_types.insert(decl.name.clone(), res_type.clone());
                    typed_decls.push(self.typed_decl(decl, res_type, decl.expr.clone(), decl.deps.clone()));
                }
                "invariant" => {
                    let predicate_ref = decl.predicate_ref.clone().unwrap_or_default();
                    let severity = decl.severity.clone().unwrap_or_else(|| "error".to_string());
                    let pred_type = symbol_types.get(&predicate_ref).cloned().unwrap_or_else(|| self.type_ir(&serde_json::Value::String("Unknown".to_string())));

                    // TC-INV-1: invariant predicate must be Bool
                    if self.type_name(&pred_type) != "Bool" && self.type_name(&pred_type) != "Unknown" {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-IV3".to_string(),
                            message: format!("invariant predicate must be Bool, got {}", self.type_name(&pred_type)),
                            node: decl.name.clone(),
                            line: None,
                        });
                    }

                    // TC-INV-2: overridable on error is OOF-I4 (dynamic/inferred case)
                    if decl.overridable_with.is_some() && severity == "error" {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-I4".to_string(),
                            message: ":error invariants cannot be overridden".to_string(),
                            node: decl.name.clone(),
                            line: None,
                        });
                    }

                    // TC-INV-3: calculate output effect
                    let effect = match severity.as_str() {
                        "error" => "blocks".to_string(),
                        "warn" => "warns".to_string(),
                        "soft" => "uncertain".to_string(),
                        "metric" => "metric".to_string(),
                        _ => "blocks".to_string(),
                    };
                    if ["warns", "uncertain", "metric"].contains(&effect.as_str()) {
                        invariant_effects.push((decl.name.clone(), effect));
                    }

                    typed_decls.push(TypedDecl {
                        decl_id: decl.decl_id.clone(),
                        kind: "invariant".to_string(),
                        name: decl.name.clone(),
                        fragment_class: decl.fragment_class.clone(),
                        type_info: self.type_ir(&serde_json::Value::String("Bool".to_string())),
                        deps: decl.deps.clone(),
                        expr: None,
                        semantic_node: None,
                        node_fragment_class: None,
                        value_fragment_class: None,
                        required_capability: None,
                        temporal_axis: None,
                        from: None,
                        lifecycle: None,
                        options: None,
                        window_ref: None,
                        predicate_ref: Some(predicate_ref),
                        severity: Some(severity),
                        label: decl.label.clone(),
                        message: decl.message.clone(),
                        overridable_with: decl.overridable_with.clone(),
                        output_effect: Some(self.invariant_output_effect(&decl.severity.clone().unwrap_or_default())),
                        warnings_from: None,
                        uncertain_from: None,
                        metrics_from: None,
                        body_nodes: None,
                    });
                }
                "compute" | "snapshot" => {
                    let mut typed_expr = self.infer_expr(decl.expr.as_ref().unwrap(), &symbol_types, olap_env, &local_type_shapes, &mut type_errors, &mut type_warnings, &decl.name, functions);
                    // PROP-039 gate 5: if recur_authorized and expr contains recur(),
                    // use the contract output type to resolve the compute node's type.
                    // This prevents a spurious OOF-TY0 at the output check when recur()
                    // is used (infer_expr returns Unknown for recur()).
                    if recur_authorized {
                        if let Some(expr) = &decl.expr {
                            if expr_has_call(expr, "recur") {
                                if let Some(ref ot) = recur_output_type {
                                    typed_expr.resolved_type = ot.clone();
                                }
                            }
                        }
                    }
                    symbol_types.insert(decl.name.clone(), typed_expr.resolved_type.clone());
                    // igniter-string-core: rewrite concat calls before storing expr in TypedDecl.
                    // This resolves the Collection/Text ambiguity so the emitter emits the
                    // correct qualified fn name (stdlib.text.concat / stdlib.collection.concat).
                    let rewritten_expr = decl.expr.as_ref()
                        .map(|e| self.rewrite_concat_calls(e, &symbol_types));
                    typed_decls.push(self.typed_decl(decl, typed_expr.resolved_type, rewritten_expr, decl.deps.clone()));
                    // PROP-039 gate 5: validate recur() calls in compute expressions
                    if let Some(expr) = &decl.expr {
                        self.check_recur_in_expr(
                            expr,
                            recur_authorized,
                            &recur_input_names,
                            recur_output_count,
                            &symbol_types,
                            olap_env,
                            &local_type_shapes,
                            &mut type_errors,
                            &mut type_warnings,
                            &decl.name,
                            functions,
                            clean_decreases_variant.as_deref(),
                            decreases_variant_pos,
                        );
                        // PROP-041 T2: OOF-R9 call-site structural-size check
                        if let Some(ctx) = &t2_context {
                            if ctx.kind == T2Kind::T2Pass {
                                self.check_t2_callsite_in_expr(expr, &mut type_errors, &decl.name, ctx, &recur_input_names);
                            }
                        }
                    }
                }
                "output" => {
                    let expected = self.type_ir(decl.type_annotation.as_ref().unwrap());
                    let actual = symbol_types.get(&decl.name).cloned().unwrap_or_else(|| self.type_ir(&serde_json::Value::String("Unknown".to_string())));

                    // LAB-RACK-P9: Unknown actual type is treated as compatible with any
                    // declared output type. call_contract returns Unknown (callee output type
                    // is not verifiable at compile time in v0), and the VM enforces correctness
                    // at runtime. Without this guard the TypeChecker would reject every contract
                    // that forwards a call_contract result as an output.
                    if self.type_name(&actual) != self.type_name(&expected)
                        && self.type_name(&actual) != "Unknown"
                        && !self.blocking_rule_present(&type_errors) {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-TY0".to_string(),
                            message: format!("Type mismatch: expected {}, got {}", self.type_name(&expected), self.type_name(&actual)),
                            node: decl.name.clone(),
                            line: None,
                        });
                    }

                    // TINV-4: propagate invariant output effects to output nodes
                    let mut warnings_from = Vec::new();
                    let mut uncertain_from = Vec::new();
                    let mut metrics_from = Vec::new();
                    for (inv_name, effect) in &invariant_effects {
                        match effect.as_str() {
                            "warns" => warnings_from.push(inv_name.clone()),
                            "uncertain" => uncertain_from.push(inv_name.clone()),
                            "metric" => metrics_from.push(inv_name.clone()),
                            _ => {}
                        }
                    }

                    typed_decls.push(TypedDecl {
                        decl_id: decl.decl_id.clone(),
                        kind: "output".to_string(),
                        name: decl.name.clone(),
                        fragment_class: decl.fragment_class.clone(),
                        type_info: expected,
                        deps: decl.deps.clone(),
                        expr: None,
                        semantic_node: None,
                        node_fragment_class: None,
                        value_fragment_class: None,
                        required_capability: None,
                        temporal_axis: None,
                        from: None,
                        lifecycle: decl.lifecycle.clone(),
                        options: None,
                        window_ref: None,
                        predicate_ref: None,
                        severity: None,
                        label: None,
                        message: None,
                        overridable_with: None,
                        output_effect: None,
                        warnings_from: if warnings_from.is_empty() { None } else { Some(warnings_from) },
                        uncertain_from: if uncertain_from.is_empty() { None } else { Some(uncertain_from) },
                        metrics_from: if metrics_from.is_empty() { None } else { Some(metrics_from) },
                        body_nodes: None,
                    });
                }
                _ => {}
            }
        }

        let status = if type_errors.iter().any(|d| d.rule.starts_with("OOF-") || d.rule.starts_with("E-IO-")) {
            "blocked".to_string()
        } else {
            "accepted".to_string()
        };

        TypedContract {
            kind: "typed_contract".to_string(),
            contract_id: classified.contract_id.clone(),
            name: classified.name.clone(),
            modifier: classified.modifier.clone(),
            status,
            fragment_class: classified.fragment_class.clone(),
            symbols: {
                let mut sorted_keys: Vec<&String> = symbol_types.keys().collect();
                sorted_keys.sort();
                sorted_keys.into_iter().map(|name| TypedSymbol {
                    name: name.clone(),
                    type_info: symbol_types.get(name).unwrap().clone(),
                    resolved: self.type_name(symbol_types.get(name).unwrap()) != "Unknown",
                }).collect()
            },
            declarations: typed_decls,
            type_errors: self.dedupe_errors(&type_errors),
            type_warnings: if type_warnings.is_empty() { None } else { Some(self.dedupe_errors(&type_warnings)) },
            decreases_variant: clean_decreases_variant,
            // PROP-041 T2: propagate structural-size evidence for SemanticIR structural_size_v1 emission
            decreases_variant_t2: t2_context.as_ref().and_then(|ctx| {
                if ctx.kind == T2Kind::T2Pass { Some(ctx.dv.clone()) } else { None }
            }),
            size_relation_evidence: t2_context.as_ref().and_then(|ctx| {
                if ctx.kind == T2Kind::T2Pass {
                    Some(serde_json::json!({
                        "trust": ctx.trust,
                        "source": ctx.source
                    }))
                } else {
                    None
                }
            }),
            assumption_refs: classified.assumption_refs.clone(),
            specialization_of: classified.specialization_of.clone(),
            type_args: classified.type_args.clone(),
            implements: classified.implements.clone(),
        }
    }

    // ── PROP-041 T2: private helpers ────────────────────────────────────────────

    /// Build the per-typecheck size registry: STDLIB entries + user-declared entries.
    /// Keys are (TypeName, accessor); values are trust/source metadata.
    /// Source for user entries = module name (mirrors Ruby build_size_registry).
    fn build_size_registry(&self, classified: &ClassifiedProgram) -> HashMap<(String, String), T2RegistryEntry> {
        let mut registry = stdlib_size_registry();
        let mod_name = classified.module.clone().unwrap_or_else(|| "unknown".to_string());
        for sr in &classified.size_relations {
            registry.insert(
                (sr.type_name.clone(), sr.accessor.clone()),
                T2RegistryEntry { trust: "user_assumed".to_string(), source: mod_name.clone() },
            );
        }
        registry
    }

    /// T2 dotted-path dispatch: fires OOF-R3/R8 or returns a T2Pass context.
    /// NOT a full termination proof — structural evidence with trust metadata only.
    fn handle_t2_variant(
        &self,
        dv: &str,
        classified: &ClassifiedContract,
        type_errors: &mut Vec<ClassifierDiagnostic>,
        size_registry: &HashMap<(String, String), T2RegistryEntry>,
    ) -> Option<T2Context> {
        let dot_pos = match dv.find('.') {
            Some(p) => p,
            None => return None,
        };
        let subject  = &dv[..dot_pos];
        let accessor = &dv[dot_pos + 1..];

        // Numeric accessor → OOF-R3 (design decision 4: not T2 territory)
        if NUMERIC_ACCESSORS.contains(&accessor) {
            type_errors.push(ClassifierDiagnostic {
                rule: "OOF-R3".to_string(),
                message: format!(
                    "recur() decreases variant '{}' in '{}' — numeric accessor '{}' is not a structural-size relation; \
                     use a simple numeric identifier as the decreases variant",
                    dv, classified.name, accessor
                ),
                node: classified.name.clone(),
                line: None,
            });
            return Some(T2Context {
                kind: T2Kind::T2R3,
                dv: dv.to_string(),
                subject: subject.to_string(),
                accessor: accessor.to_string(),
                trust: String::new(),
                source: String::new(),
            });
        }

        // Resolve the subject's declared type from input declarations.
        // type_annotation is a type_ir hash: {"kind":"type_ref","name":"Collection","params":[...]}
        let type_name_str: String = classified.declarations.iter()
            .find(|d| d.kind == "input" && d.name == subject)
            .and_then(|d| d.type_annotation.as_ref())
            .map(|ta| {
                if let Some(obj) = ta.as_object() {
                    obj.get("name").and_then(|n| n.as_str()).unwrap_or("Unknown").to_string()
                } else if let Some(s) = ta.as_str() {
                    s.split('[').next().unwrap_or("Unknown").trim().to_string()
                } else {
                    "Unknown".to_string()
                }
            })
            .unwrap_or_else(|| "Unknown".to_string());

        // Registry lookup: (TypeName, accessor)
        if let Some(entry) = size_registry.get(&(type_name_str.clone(), accessor.to_string())) {
            Some(T2Context {
                kind: T2Kind::T2Pass,
                dv: dv.to_string(),
                subject: subject.to_string(),
                accessor: accessor.to_string(),
                trust: entry.trust.clone(),
                source: entry.source.clone(),
            })
        } else {
            // OOF-R8: missing structural size relation
            type_errors.push(ClassifierDiagnostic {
                rule: "OOF-R8".to_string(),
                message: format!(
                    "Missing structural size relation for '{}' in '{}' — \
                     no size_relation declaration for {}.{}; \
                     add 'size_relation {} {}' at module level",
                    dv, classified.name, type_name_str, accessor, type_name_str, accessor
                ),
                node: classified.name.clone(),
                line: None,
            });
            Some(T2Context {
                kind: T2Kind::T2R8,
                dv: dv.to_string(),
                subject: subject.to_string(),
                accessor: accessor.to_string(),
                trust: String::new(),
                source: String::new(),
            })
        }
    }

    /// T2 call-site check: walks an expression tree looking for recur() calls.
    /// When found, checks that the variant-position arg is exactly `subject.accessor`.
    /// Fires OOF-R9 on mismatch.
    fn check_t2_callsite_in_expr(
        &self,
        expr: &Expr,
        type_errors: &mut Vec<ClassifierDiagnostic>,
        node_name: &str,
        ctx: &T2Context,
        input_names: &[String],
    ) {
        match expr {
            Expr::Call { fn_name, args } if fn_name == "recur" => {
                if let Some(subject_pos) = input_names.iter().position(|n| n == &ctx.subject) {
                    if subject_pos < args.len() {
                        let variant_arg = &args[subject_pos];
                        if !self.t2_structural_arg(variant_arg, &ctx.subject, &ctx.accessor) {
                            let arg_desc = syntactic_arg_desc(variant_arg);
                            type_errors.push(ClassifierDiagnostic {
                                rule: "OOF-R9".to_string(),
                                message: format!(
                                    "recur() in '{}' — structural size call-site mismatch: \
                                     expected '{}.{}' at argument position {}, got: {}; \
                                     the recur() argument must be the declared structural accessor",
                                    node_name, ctx.subject, ctx.accessor, subject_pos + 1, arg_desc
                                ),
                                node: node_name.to_string(),
                                line: None,
                            });
                        }
                    }
                }
            }
            Expr::Call { fn_name: _, args } => {
                for arg in args {
                    self.check_t2_callsite_in_expr(arg, type_errors, node_name, ctx, input_names);
                }
            }
            Expr::BinaryOp { left, right, .. } => {
                self.check_t2_callsite_in_expr(left, type_errors, node_name, ctx, input_names);
                self.check_t2_callsite_in_expr(right, type_errors, node_name, ctx, input_names);
            }
            Expr::UnaryOp { operand, .. } => {
                self.check_t2_callsite_in_expr(operand, type_errors, node_name, ctx, input_names);
            }
            Expr::FieldAccess { object, .. } => {
                self.check_t2_callsite_in_expr(object, type_errors, node_name, ctx, input_names);
            }
            Expr::IndexAccess { object, index } => {
                self.check_t2_callsite_in_expr(object, type_errors, node_name, ctx, input_names);
                self.check_t2_callsite_in_expr(index, type_errors, node_name, ctx, input_names);
            }
            // IfExpr: walk cond + then/else_block bodies.
            // Symmetric with check_recur_in_expr IfExpr handling — mirrors stmts + return_expr walk.
            Expr::IfExpr { cond, then, else_block } => {
                self.check_t2_callsite_in_expr(cond, type_errors, node_name, ctx, input_names);
                // then block
                for stmt in &then.stmts {
                    if let Stmt::Let { expr, .. } = stmt {
                        self.check_t2_callsite_in_expr(expr, type_errors, node_name, ctx, input_names);
                    }
                }
                if let Some(re) = &then.return_expr {
                    self.check_t2_callsite_in_expr(re, type_errors, node_name, ctx, input_names);
                }
                // else block
                if let Some(eb) = else_block {
                    for stmt in &eb.stmts {
                        if let Stmt::Let { expr, .. } = stmt {
                            self.check_t2_callsite_in_expr(expr, type_errors, node_name, ctx, input_names);
                        }
                    }
                    if let Some(re) = &eb.return_expr {
                        self.check_t2_callsite_in_expr(re, type_errors, node_name, ctx, input_names);
                    }
                }
            }
            _ => {}
        }
    }

    /// True when `expr` is exactly `subject.accessor` (field access on a ref).
    fn t2_structural_arg(&self, expr: &Expr, subject: &str, accessor: &str) -> bool {
        if let Expr::FieldAccess { object, field } = expr {
            if field != accessor { return false; }
            if let Expr::Ref { name } = object.as_ref() {
                return name == subject;
            }
        }
        false
    }

    // ── end PROP-041 T2 private helpers ─────────────────────────────────────────

    fn collect_escape_refs(&self, body: &ExprOrBlock, stream_symbols: &HashSet<String>, lambda_params: &mut HashSet<String>, escape_refs: &mut Vec<String>) {
        match body {
            ExprOrBlock::Expr(e) => self.collect_expr_escape_refs(e, stream_symbols, lambda_params, escape_refs),
            ExprOrBlock::Block(b) => {
                for s in &b.stmts {
                    match s {
                        Stmt::Let { expr, .. } => self.collect_expr_escape_refs(expr, stream_symbols, lambda_params, escape_refs),
                        Stmt::ExprStmt { expr } => self.collect_expr_escape_refs(expr, stream_symbols, lambda_params, escape_refs),
                    }
                }
                if let Some(re) = &b.return_expr {
                    self.collect_expr_escape_refs(re, stream_symbols, lambda_params, escape_refs);
                }
            }
        }
    }

    fn collect_expr_escape_refs(&self, expr: &Expr, stream_symbols: &HashSet<String>, lambda_params: &mut HashSet<String>, escape_refs: &mut Vec<String>) {
        match expr {
            Expr::Ref { name } => {
                if stream_symbols.contains(name) && !lambda_params.contains(name) {
                    escape_refs.push(name.clone());
                }
            }
            Expr::FieldAccess { object, .. } => {
                self.collect_expr_escape_refs(object, stream_symbols, lambda_params, escape_refs);
            }
            Expr::IndexAccess { object, index } => {
                self.collect_expr_escape_refs(object, stream_symbols, lambda_params, escape_refs);
                self.collect_expr_escape_refs(index, stream_symbols, lambda_params, escape_refs);
            }
            Expr::SliceRecord { fields } => {
                for v in fields.values() {
                    self.collect_expr_escape_refs(v, stream_symbols, lambda_params, escape_refs);
                }
            }
            Expr::BinaryOp { left, right, .. } => {
                self.collect_expr_escape_refs(left, stream_symbols, lambda_params, escape_refs);
                self.collect_expr_escape_refs(right, stream_symbols, lambda_params, escape_refs);
            }
            Expr::UnaryOp { operand, .. } => {
                self.collect_expr_escape_refs(operand, stream_symbols, lambda_params, escape_refs);
            }
            Expr::Call { args, .. } => {
                for arg in args {
                    self.collect_expr_escape_refs(arg, stream_symbols, lambda_params, escape_refs);
                }
            }
            Expr::IfExpr { cond, then, else_block } => {
                self.collect_expr_escape_refs(cond, stream_symbols, lambda_params, escape_refs);
                for s in &then.stmts {
                    match s {
                        Stmt::Let { expr, .. } => self.collect_expr_escape_refs(expr, stream_symbols, lambda_params, escape_refs),
                        Stmt::ExprStmt { expr } => self.collect_expr_escape_refs(expr, stream_symbols, lambda_params, escape_refs),
                    }
                }
                if let Some(re) = &then.return_expr {
                    self.collect_expr_escape_refs(re, stream_symbols, lambda_params, escape_refs);
                }
                if let Some(eb) = else_block {
                    for s in &eb.stmts {
                        match s {
                            Stmt::Let { expr, .. } => self.collect_expr_escape_refs(expr, stream_symbols, lambda_params, escape_refs),
                            Stmt::ExprStmt { expr } => self.collect_expr_escape_refs(expr, stream_symbols, lambda_params, escape_refs),
                        }
                    }
                    if let Some(re) = &eb.return_expr {
                        self.collect_expr_escape_refs(re, stream_symbols, lambda_params, escape_refs);
                    }
                }
            }
            Expr::Lambda { params, body } => {
                let mut inner_params = lambda_params.clone();
                for p in params {
                    inner_params.insert(p.clone());
                }
                self.collect_escape_refs(body, stream_symbols, &mut inner_params, escape_refs);
            }
            Expr::ArrayLiteral { items } => {
                for item in items {
                    self.collect_expr_escape_refs(item, stream_symbols, lambda_params, escape_refs);
                }
            }
            Expr::RecordLiteral { fields } => {
                for v in fields.values() {
                    self.collect_expr_escape_refs(v, stream_symbols, lambda_params, escape_refs);
                }
            }
            _ => {}
        }
    }

    fn typed_decl(&self, decl: &ClassifiedDecl, type_info: serde_json::Value, expr: Option<Expr>, deps: Vec<String>) -> TypedDecl {
        TypedDecl {
            decl_id: decl.decl_id.clone(),
            kind: decl.kind.clone(),
            name: decl.name.clone(),
            fragment_class: decl.fragment_class.clone(),
            type_info,
            deps,
            expr,
            semantic_node: None,
            node_fragment_class: decl.node_fragment_class.clone(),
            value_fragment_class: decl.value_fragment_class.clone(),
            required_capability: decl.required_capability.clone(),
            temporal_axis: decl.temporal_axis.clone(),
            from: None,
            lifecycle: None,
            options: decl.options.clone(),
            window_ref: None,
            predicate_ref: None,
            severity: None,
            label: None,
            message: None,
            overridable_with: None,
            output_effect: None,
            warnings_from: None,
            uncertain_from: None,
            metrics_from: None,
            body_nodes: None,
        }
    }

    /// PROP-039 gate 5 + OOF-R3: walk an expression tree looking for recur() calls and
    /// validate their context, arity, argument types, and syntactic variant decrease.
    fn check_recur_in_expr(
        &self,
        expr: &Expr,
        recur_authorized: bool,
        recur_input_names: &[String],
        recur_output_count: usize,
        symbol_types: &HashMap<String, serde_json::Value>,
        olap_env: &HashMap<String, HashMap<String, serde_json::Value>>,
        type_shapes: &HashMap<String, HashMap<String, serde_json::Value>>,
        type_errors: &mut Vec<ClassifierDiagnostic>,
        type_warnings: &mut Vec<ClassifierDiagnostic>,
        node_name: &str,
        functions: &[crate::parser::FunctionDecl],
        decreases_variant: Option<&str>,
        decreases_variant_pos: Option<usize>,
    ) {
        match expr {
            Expr::Call { fn_name, args } if fn_name == "recur" => {
                if !recur_authorized {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-R1".to_string(),
                        message: format!(
                            "recur() in '{}' — invalid recur context: recur() is only valid inside a recursive or fuel_bounded contract",
                            node_name
                        ),
                        node: node_name.to_string(),
                        line: None,
                    });
                    return;
                }
                if recur_output_count != 1 {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-R7".to_string(),
                        message: format!(
                            "recur() in '{}' — contract must have exactly one output (has {}); multi-output recur() deferred to v1",
                            node_name, recur_output_count
                        ),
                        node: node_name.to_string(),
                        line: None,
                    });
                    return;
                }
                if args.len() != recur_input_names.len() {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-R5".to_string(),
                        message: format!(
                            "recur() arity mismatch in '{}' — {} arg(s) given, {} input(s) expected",
                            node_name, args.len(), recur_input_names.len()
                        ),
                        node: node_name.to_string(),
                        line: None,
                    });
                } else {
                    for (idx, (arg, input_name)) in args.iter().zip(recur_input_names.iter()).enumerate() {
                        let expected_type = symbol_types.get(input_name)
                            .cloned()
                            .unwrap_or_else(|| serde_json::json!({"name": "Unknown", "params": []}));
                        let mut dummy_errors = Vec::new();
                        let mut dummy_warnings = Vec::new();
                        let arg_typed = self.infer_expr(
                            arg, symbol_types, olap_env, type_shapes,
                            &mut dummy_errors, &mut dummy_warnings,
                            node_name, functions,
                        );
                        let actual = self.type_name(&arg_typed.resolved_type);
                        let expected = self.type_name(&expected_type);
                        if actual != "Unknown" && expected != "Unknown" && actual != expected {
                            type_errors.push(ClassifierDiagnostic {
                                rule: "OOF-R6".to_string(),
                                message: format!(
                                    "recur() arg {} type mismatch in '{}' — expected {}, got {}",
                                    idx + 1, node_name, expected, actual
                                ),
                                node: node_name.to_string(),
                                line: None,
                            });
                        }
                    }

                    // OOF-R3: variant-position arg must syntactically decrease the decreases variant
                    if let (Some(dv), Some(pos)) = (decreases_variant, decreases_variant_pos) {
                        if pos < args.len() {
                            let variant_arg = &args[pos];
                            if !syntactic_decrease(variant_arg, dv) {
                                let arg_desc = syntactic_arg_desc(variant_arg);
                                type_errors.push(ClassifierDiagnostic {
                                    rule: "OOF-R3".to_string(),
                                    message: format!(
                                        "recur() in '{}' — variant '{}' (position {}) does not syntactically decrease: {}; \
                                         expected '{} - N', '{}.tail', or '{}.rest'",
                                        node_name, dv, pos + 1, arg_desc, dv, dv, dv
                                    ),
                                    node: node_name.to_string(),
                                    line: None,
                                });
                            }
                        }
                    }
                }
            }
            // Recurse into sub-expressions
            Expr::Call { fn_name: _, args } => {
                for arg in args {
                    self.check_recur_in_expr(arg, recur_authorized, recur_input_names, recur_output_count, symbol_types, olap_env, type_shapes, type_errors, type_warnings, node_name, functions, decreases_variant, decreases_variant_pos);
                }
            }
            Expr::BinaryOp { left, right, .. } => {
                self.check_recur_in_expr(left, recur_authorized, recur_input_names, recur_output_count, symbol_types, olap_env, type_shapes, type_errors, type_warnings, node_name, functions, decreases_variant, decreases_variant_pos);
                self.check_recur_in_expr(right, recur_authorized, recur_input_names, recur_output_count, symbol_types, olap_env, type_shapes, type_errors, type_warnings, node_name, functions, decreases_variant, decreases_variant_pos);
            }
            Expr::UnaryOp { operand, .. } => {
                self.check_recur_in_expr(operand, recur_authorized, recur_input_names, recur_output_count, symbol_types, olap_env, type_shapes, type_errors, type_warnings, node_name, functions, decreases_variant, decreases_variant_pos);
            }
            Expr::FieldAccess { object, .. } => {
                self.check_recur_in_expr(object, recur_authorized, recur_input_names, recur_output_count, symbol_types, olap_env, type_shapes, type_errors, type_warnings, node_name, functions, decreases_variant, decreases_variant_pos);
            }
            Expr::IndexAccess { object, index } => {
                self.check_recur_in_expr(object, recur_authorized, recur_input_names, recur_output_count, symbol_types, olap_env, type_shapes, type_errors, type_warnings, node_name, functions, decreases_variant, decreases_variant_pos);
                self.check_recur_in_expr(index, recur_authorized, recur_input_names, recur_output_count, symbol_types, olap_env, type_shapes, type_errors, type_warnings, node_name, functions, decreases_variant, decreases_variant_pos);
            }
            Expr::IfExpr { cond, then, else_block } => {
                self.check_recur_in_expr(cond, recur_authorized, recur_input_names, recur_output_count, symbol_types, olap_env, type_shapes, type_errors, type_warnings, node_name, functions, decreases_variant, decreases_variant_pos);
                // then/else_block are BlockBody — walk stmts and return_expr
                for stmt in &then.stmts {
                    if let Stmt::Let { expr, .. } = stmt {
                        self.check_recur_in_expr(expr, recur_authorized, recur_input_names, recur_output_count, symbol_types, olap_env, type_shapes, type_errors, type_warnings, node_name, functions, decreases_variant, decreases_variant_pos);
                    }
                }
                if let Some(re) = &then.return_expr {
                    self.check_recur_in_expr(re, recur_authorized, recur_input_names, recur_output_count, symbol_types, olap_env, type_shapes, type_errors, type_warnings, node_name, functions, decreases_variant, decreases_variant_pos);
                }
                if let Some(eb) = else_block {
                    for stmt in &eb.stmts {
                        if let Stmt::Let { expr, .. } = stmt {
                            self.check_recur_in_expr(expr, recur_authorized, recur_input_names, recur_output_count, symbol_types, olap_env, type_shapes, type_errors, type_warnings, node_name, functions, decreases_variant, decreases_variant_pos);
                        }
                    }
                    if let Some(re) = &eb.return_expr {
                        self.check_recur_in_expr(re, recur_authorized, recur_input_names, recur_output_count, symbol_types, olap_env, type_shapes, type_errors, type_warnings, node_name, functions, decreases_variant, decreases_variant_pos);
                    }
                }
            }
            _ => {}
        }
    }

    fn type_ir(&self, annotation: &serde_json::Value) -> serde_json::Value {
        if let Some(obj) = annotation.as_object() {
            if obj.contains_key("name") {
                return annotation.clone();
            }
        }

        let name = if let Some(s) = annotation.as_str() {
            s.to_string()
        } else {
            "Unknown".to_string()
        };

        let mut ir = serde_json::Map::new();
        ir.insert("name".to_string(), serde_json::Value::String(name));
        ir.insert("params".to_string(), serde_json::Value::Array(Vec::new()));
        serde_json::Value::Object(ir)
    }

    fn get_param(&self, type_info: &serde_json::Value, index: usize) -> Option<serde_json::Value> {
        type_info.get("params")
            .and_then(|p| p.as_array())
            .and_then(|arr| arr.get(index))
            .map(|val| self.type_ir(val))
    }

    fn type_name(&self, type_info: &serde_json::Value) -> String {
        type_info.get("name").and_then(|n| n.as_str()).unwrap_or("Unknown").to_string()
    }

    // igniter-string-core-units-and-pure-stdlib-boundary-v0 helpers ----------

    /// v0 compat rule: "Text" positions accept both "Text" and "String" literals.
    fn text_arg_compatible(&self, actual: &str, expected: &str) -> bool {
        if expected == "Text" {
            actual == "Text" || actual == "String"
        } else {
            actual == expected
        }
    }

    /// Collection[Text] return type for split.
    fn collection_text_type(&self) -> serde_json::Value {
        let text_inner = self.type_ir(&serde_json::Value::String("Text".to_string()));
        let mut col = serde_json::Map::new();
        col.insert("name".to_string(), serde_json::Value::String("Collection".to_string()));
        col.insert("params".to_string(), serde_json::Value::Array(vec![text_inner]));
        serde_json::Value::Object(col)
    }

    /// Canonical return type for a stdlib.text.* op name.
    fn text_stdlib_return_type(&self, fn_name: &str) -> serde_json::Value {
        match fn_name {
            "concat" | "trim" | "replace" | "replace_all" |
            "byte_slice" | "rune_slice" | "grapheme_slice" => {
                self.type_ir(&serde_json::Value::String("Text".to_string()))
            }
            "contains" | "starts_with" | "ends_with" => {
                self.type_ir(&serde_json::Value::String("Bool".to_string()))
            }
            "byte_length" | "rune_length" | "grapheme_length" => {
                self.type_ir(&serde_json::Value::String("Integer".to_string()))
            }
            "split" => self.collection_text_type(),
            _ => self.type_ir(&serde_json::Value::String("Unknown".to_string())),
        }
    }

    /// Type-check a stdlib.text.* call.
    /// OOF-TY0 message format matches canon:
    ///   arity:  "stdlib.text.{fn}: expected N argument(s), got M"
    ///   type:   "stdlib.text.{fn} arg N: expected T, got ActualT"
    fn check_text_stdlib_call(
        &self,
        fn_name: &str,
        typed_args: &[TypedExpression],
        expected_arg_types: &[&str],
        type_errors: &mut Vec<ClassifierDiagnostic>,
        node_name: &str,
    ) -> serde_json::Value {
        let expected_count = expected_arg_types.len();
        let return_type = self.text_stdlib_return_type(fn_name);
        if typed_args.len() != expected_count {
            type_errors.push(ClassifierDiagnostic {
                rule: "OOF-TY0".to_string(),
                message: format!(
                    "stdlib.text.{}: expected {} argument(s), got {}",
                    fn_name, expected_count, typed_args.len()
                ),
                node: node_name.to_string(),
                line: None,
            });
            return return_type;
        }
        for (idx, (typed_arg, &expected)) in
            typed_args.iter().zip(expected_arg_types.iter()).enumerate()
        {
            let actual = self.type_name(&typed_arg.resolved_type);
            if actual != "Unknown" && !self.text_arg_compatible(&actual, expected) {
                type_errors.push(ClassifierDiagnostic {
                    rule: "OOF-TY0".to_string(),
                    message: format!(
                        "stdlib.text.{} arg {}: expected {}, got {}",
                        fn_name, idx + 1, expected, actual
                    ),
                    node: node_name.to_string(),
                    line: None,
                });
            }
        }
        return_type
    }

    /// Infer the surface type name of an expression without a full type-inference pass.
    /// Used only to distinguish Collection vs Text for concat disambiguation.
    fn quick_arg_type(&self, expr: &Expr, symbol_types: &HashMap<String, serde_json::Value>) -> String {
        match expr {
            Expr::Ref { name } => {
                symbol_types.get(name)
                    .map(|t| self.type_name(t))
                    .unwrap_or_else(|| "Unknown".to_string())
            }
            Expr::Literal { type_tag, .. } => type_tag.clone(),
            Expr::Call { fn_name, .. } => {
                // Collection-producing fns
                if matches!(fn_name.as_str(), "split" | "range" | "filter" | "map" | "flat_map"
                    | "zip" | "take" | "stdlib.collection.concat") {
                    "Collection".to_string()
                } else if fn_name.starts_with("stdlib.text.") {
                    "Text".to_string()
                } else {
                    "Unknown".to_string()
                }
            }
            _ => "Unknown".to_string(),
        }
    }

    /// Recursively rewrite `concat` calls in an expression tree:
    ///   - first arg type is Collection  → fn_name = "stdlib.collection.concat"
    ///   - otherwise (Text/String/Unknown) → fn_name = "stdlib.text.concat"
    /// All other ops are left untouched.
    fn rewrite_concat_calls(
        &self,
        expr: &Expr,
        symbol_types: &HashMap<String, serde_json::Value>,
    ) -> Expr {
        match expr {
            Expr::Call { fn_name, args } => {
                let rewritten_args: Vec<Expr> = args.iter()
                    .map(|a| self.rewrite_concat_calls(a, symbol_types))
                    .collect();
                let new_fn = if fn_name == "concat" {
                    let first_type = args.first()
                        .map(|a| self.quick_arg_type(a, symbol_types))
                        .unwrap_or_else(|| "Unknown".to_string());
                    if first_type == "Collection" {
                        "stdlib.collection.concat".to_string()
                    } else {
                        "stdlib.text.concat".to_string()
                    }
                } else {
                    fn_name.clone()
                };
                Expr::Call { fn_name: new_fn, args: rewritten_args }
            },
            Expr::BinaryOp { op, left, right } => Expr::BinaryOp {
                op: op.clone(),
                left: Box::new(self.rewrite_concat_calls(left, symbol_types)),
                right: Box::new(self.rewrite_concat_calls(right, symbol_types)),
            },
            Expr::UnaryOp { op, operand } => Expr::UnaryOp {
                op: op.clone(),
                operand: Box::new(self.rewrite_concat_calls(operand, symbol_types)),
            },
            Expr::FieldAccess { object, field } => Expr::FieldAccess {
                object: Box::new(self.rewrite_concat_calls(object, symbol_types)),
                field: field.clone(),
            },
            Expr::IndexAccess { object, index } => Expr::IndexAccess {
                object: Box::new(self.rewrite_concat_calls(object, symbol_types)),
                index: Box::new(self.rewrite_concat_calls(index, symbol_types)),
            },
            Expr::IfExpr { cond, then, else_block } => {
                use crate::parser::{BlockBody, Stmt};
                fn rewrite_block(
                    tc: &TypeChecker,
                    block: &BlockBody,
                    sym: &HashMap<String, serde_json::Value>,
                ) -> BlockBody {
                    let stmts = block.stmts.iter().map(|s| match s {
                        Stmt::Let { name, expr } => Stmt::Let {
                            name: name.clone(),
                            expr: tc.rewrite_concat_calls(expr, sym),
                        },
                        Stmt::ExprStmt { expr } => Stmt::ExprStmt {
                            expr: tc.rewrite_concat_calls(expr, sym),
                        },
                    }).collect();
                    let return_expr = block.return_expr.as_ref()
                        .map(|e| Box::new(tc.rewrite_concat_calls(e, sym)));
                    BlockBody { stmts, return_expr }
                }
                Expr::IfExpr {
                    cond: Box::new(self.rewrite_concat_calls(cond, symbol_types)),
                    then: rewrite_block(self, then, symbol_types),
                    else_block: else_block.as_ref().map(|b| rewrite_block(self, b, symbol_types)),
                }
            },
            Expr::ArrayLiteral { items } => Expr::ArrayLiteral {
                items: items.iter().map(|i| self.rewrite_concat_calls(i, symbol_types)).collect(),
            },
            Expr::RecordLiteral { fields } => Expr::RecordLiteral {
                fields: fields.iter().map(|(k, v)| {
                    (k.clone(), self.rewrite_concat_calls(v, symbol_types))
                }).collect(),
            },
            // Leaf nodes: clone as-is
            _ => expr.clone(),
        }
    }

    // ---- end igniter-string-core helpers ------------------------------------

    fn blocking_rule_present(&self, errors: &[ClassifierDiagnostic]) -> bool {
        let blocking = ["OOF-P1", "OOF-CE4", "OOF-OS2", "OOF-H1", "OOF-BT1", "OOF-BT2", "OOF-BT3", "OOF-BT4", "OOF-TM1", "OOF-TM3", "OOF-TM4", "OOF-TM5", "OOF-TM6", "OOF-S3", "OOF-O3", "OOF-O4", "OOF-O5", "OOF-IV3"];
        errors.iter().any(|e| blocking.contains(&e.rule.as_str()))
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

    fn infer_expr(
        &self,
        expr: &Expr,
        symbol_types: &HashMap<String, serde_json::Value>,
        olap_env: &HashMap<String, HashMap<String, serde_json::Value>>,
        type_shapes: &HashMap<String, HashMap<String, serde_json::Value>>,
        type_errors: &mut Vec<ClassifierDiagnostic>,
        type_warnings: &mut Vec<ClassifierDiagnostic>,
        node_name: &str,
        functions: &[crate::parser::FunctionDecl],
    ) -> TypedExpression {
        // LAB-COMPILER-LIVENESS-P2: non-fatal depth counter (RAII — auto-decrements on all exits)
        let _depth_guard = crate::liveness::TcInferGuard::enter();
        match expr {
            Expr::Literal { value, type_tag } => {
                let ty = self.type_ir(&serde_json::Value::String(type_tag.clone()));
                TypedExpression {
                    resolved_type: ty,
                    deps: Vec::new(),
                }
            }
            Expr::Symbol { value } => {
                let ty = self.type_ir(&serde_json::Value::String("Symbol".to_string()));
                TypedExpression {
                    resolved_type: ty,
                    deps: Vec::new(),
                }
            }
            Expr::Ref { name } => {
                let in_symbols = symbol_types.contains_key(name);
                let in_olap    = olap_env.contains_key(name);
                let ty = symbol_types.get(name).cloned()
                    .or_else(|| olap_env.get(name).and_then(|o| o.get("type")).cloned())
                    .unwrap_or_else(|| self.type_ir(&serde_json::Value::String("Unknown".to_string())));
                // OOF-P1 fires only when the symbol is truly undeclared (not in symbol_types
                // or olap_env). A declared symbol with Unknown type is acceptable — it is
                // opaque (e.g. returned by call_contract), not missing.
                // LAB-RACK-P9: suppressed for symbols declared with Unknown type so that
                // compute nodes that use call_contract results are not falsely rejected.
                if !in_symbols && !in_olap {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-P1".to_string(),
                        message: format!("Unresolved symbol: {}", name),
                        node: node_name.to_string(),
                        line: None,
                    });
                }
                TypedExpression {
                    resolved_type: ty,
                    deps: vec![name.clone()],
                }
            }
            Expr::FieldAccess { object, field } => {
                let obj_typed = self.infer_expr(object, symbol_types, olap_env, type_shapes, type_errors, type_warnings, node_name, functions);
                let obj_type = self.type_name(&obj_typed.resolved_type);

                // OOF-R3 v0 whitelist: Collection.tail / Collection.rest return Collection[T]
                // This is the structural decrease pattern; no type error for whitelisted accessors.
                if obj_type == "Collection" && (field == "tail" || field == "rest") {
                    return TypedExpression {
                        resolved_type: obj_typed.resolved_type.clone(),
                        deps: obj_typed.deps,
                    };
                }

                let field_type = type_shapes.get(&obj_type)
                    .and_then(|fields| fields.get(field))
                    .cloned()
                    .unwrap_or_else(|| self.type_ir(&serde_json::Value::String("Unknown".to_string())));

                if self.type_name(&field_type) == "Unknown" {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-P1".to_string(),
                        message: format!("Unresolved field: {}.{}", obj_type, field),
                        node: node_name.to_string(),
                        line: None,
                    });
                }

                TypedExpression {
                    resolved_type: field_type,
                    deps: obj_typed.deps,
                }
            }
            Expr::BinaryOp { op, left, right } => {
                let left_typed = self.infer_expr(left, symbol_types, olap_env, type_shapes, type_errors, type_warnings, node_name, functions);
                let right_typed = self.infer_expr(right, symbol_types, olap_env, type_shapes, type_errors, type_warnings, node_name, functions);
                let (resolved_op, res_type) = self.operator_type(op, &left_typed.resolved_type, &right_typed.resolved_type, type_errors, node_name);

                let mut deps = left_typed.deps;
                deps.append(&mut right_typed.deps.clone());

                TypedExpression {
                    resolved_type: res_type,
                    deps,
                }
            }
            Expr::IfExpr { cond, then, else_block } => {
                // cond must be Bool (OOF-IF1)
                let cond_typed = self.infer_expr(cond, symbol_types, olap_env, type_shapes, type_errors, type_warnings, node_name, functions);
                if self.type_name(&cond_typed.resolved_type) != "Bool" && self.type_name(&cond_typed.resolved_type) != "Unknown" {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-IF1".to_string(),
                        message: format!("if_expr condition must be Bool, got {}", self.type_name(&cond_typed.resolved_type)),
                        node: node_name.to_string(),
                        line: None,
                    });
                }

                // OOF-IF2 check: else block is required
                if else_block.is_none() {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-IF2".to_string(),
                        message: "if_expr requires an else branch".to_string(),
                        node: node_name.to_string(),
                        line: None,
                    });
                    return TypedExpression {
                        resolved_type: self.type_ir(&serde_json::Value::String("Unknown".to_string())),
                        deps: cond_typed.deps,
                    };
                }

                let then_final = then.return_expr.as_ref();
                let else_final = else_block.as_ref().unwrap().return_expr.as_ref();

                // OOF-IF4 check: empty final expression
                if then_final.is_none() || else_final.is_none() {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-IF4".to_string(),
                        message: "if_expr branches must be value-producing".to_string(),
                        node: node_name.to_string(),
                        line: None,
                    });
                    return TypedExpression {
                        resolved_type: self.type_ir(&serde_json::Value::String("Unknown".to_string())),
                        deps: cond_typed.deps,
                    };
                }

                let then_typed = self.infer_expr(then_final.unwrap(), symbol_types, olap_env, type_shapes, type_errors, type_warnings, node_name, functions);
                let else_typed = self.infer_expr(else_final.unwrap(), symbol_types, olap_env, type_shapes, type_errors, type_warnings, node_name, functions);

                let then_name = self.type_name(&then_typed.resolved_type);
                let else_name = self.type_name(&else_typed.resolved_type);

                // OOF-IF3 check: then/else branch types must exact-match
                let resolved_type = if then_name != "Unknown" && else_name != "Unknown" && then_name != else_name {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-IF3".to_string(),
                        message: format!("if_expr branch types must match: then={}, else={}", then_name, else_name),
                        node: node_name.to_string(),
                        line: None,
                    });
                    self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                } else if then_name == "Unknown" {
                    else_typed.resolved_type
                } else {
                    then_typed.resolved_type
                };

                let mut deps = cond_typed.deps;
                deps.append(&mut then_typed.deps.clone());
                deps.append(&mut else_typed.deps.clone());
                deps.sort();
                deps.dedup();

                TypedExpression {
                    resolved_type,
                    deps,
                }
            }
            Expr::Call { fn_name, args } => {
                if fn_name == "history_at" {
                    if args.len() < 2 {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-TM1".to_string(),
                            message: "history_at requires as_of argument".to_string(),
                            node: node_name.to_string(),
                            line: None,
                        });
                        return TypedExpression { resolved_type: self.type_ir(&serde_json::Value::String("Unknown".to_string())), deps: Vec::new() };
                    }
                    let history_typed = self.infer_expr(&args[0], symbol_types, olap_env, type_shapes, type_errors, type_warnings, node_name, functions);
                    let as_of_typed = self.infer_expr(&args[1], symbol_types, olap_env, type_shapes, type_errors, type_warnings, node_name, functions);

                    if self.type_name(&as_of_typed.resolved_type) != "DateTime" && self.type_name(&as_of_typed.resolved_type) != "Unknown" {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-TM3".to_string(),
                            message: format!("history_at: as_of must be DateTime, got {}", self.type_name(&as_of_typed.resolved_type)),
                            node: node_name.to_string(),
                            line: None,
                        });
                    }

                    // Option[Inner] where Inner is history parameter
                    let mut inner = "Unknown".to_string();
                    if let Some(param) = self.get_param(&history_typed.resolved_type, 0) {
                        inner = self.type_name(&param);
                    }

                    let mut opt = serde_json::Map::new();
                    opt.insert("name".to_string(), serde_json::Value::String("Option".to_string()));
                    let mut inner_ty = serde_json::Map::new();
                    inner_ty.insert("name".to_string(), serde_json::Value::String(inner));
                    inner_ty.insert("params".to_string(), serde_json::Value::Array(Vec::new()));
                    opt.insert("params".to_string(), serde_json::Value::Array(vec![serde_json::Value::Object(inner_ty)]));

                    let mut deps = history_typed.deps;
                    deps.append(&mut as_of_typed.deps.clone());

                    TypedExpression {
                        resolved_type: serde_json::Value::Object(opt),
                        deps,
                    }
                } else if fn_name == "bihistory_at" {
                    if args.len() < 2 {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-TM4".to_string(),
                            message: "bihistory_at requires valid_time (vt) argument".to_string(),
                            node: node_name.to_string(),
                            line: None,
                        });
                        return TypedExpression { resolved_type: self.type_ir(&serde_json::Value::String("Unknown".to_string())), deps: Vec::new() };
                    }
                    if args.len() < 3 {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-TM5".to_string(),
                            message: "bihistory_at requires transaction_time (tt) argument".to_string(),
                            node: node_name.to_string(),
                            line: None,
                        });
                        return TypedExpression { resolved_type: self.type_ir(&serde_json::Value::String("Unknown".to_string())), deps: Vec::new() };
                    }
                    let history_typed = self.infer_expr(&args[0], symbol_types, olap_env, type_shapes, type_errors, type_warnings, node_name, functions);
                    let vt_typed = self.infer_expr(&args[1], symbol_types, olap_env, type_shapes, type_errors, type_warnings, node_name, functions);
                    let tt_typed = self.infer_expr(&args[2], symbol_types, olap_env, type_shapes, type_errors, type_warnings, node_name, functions);

                    for (idx, axis_ref) in [&vt_typed, &tt_typed].iter().enumerate() {
                        let axis_name = if idx == 0 { "valid_time" } else { "transaction_time" };
                        if self.type_name(&axis_ref.resolved_type) != "DateTime" && self.type_name(&axis_ref.resolved_type) != "Unknown" {
                            type_errors.push(ClassifierDiagnostic {
                                rule: "OOF-TM6".to_string(),
                                message: format!("bihistory_at: {} must be DateTime, got {}", axis_name, self.type_name(&axis_ref.resolved_type)),
                                node: node_name.to_string(),
                                line: None,
                            });
                        }
                    }

                    let mut inner = "Unknown".to_string();
                    if let Some(param) = self.get_param(&history_typed.resolved_type, 0) {
                        inner = self.type_name(&param);
                    }

                    let mut opt = serde_json::Map::new();
                    opt.insert("name".to_string(), serde_json::Value::String("Option".to_string()));
                    let mut inner_ty = serde_json::Map::new();
                    inner_ty.insert("name".to_string(), serde_json::Value::String(inner));
                    inner_ty.insert("params".to_string(), serde_json::Value::Array(Vec::new()));
                    opt.insert("params".to_string(), serde_json::Value::Array(vec![serde_json::Value::Object(inner_ty)]));

                    let mut deps = history_typed.deps;
                    deps.append(&mut vt_typed.deps.clone());
                    deps.append(&mut tt_typed.deps.clone());

                    TypedExpression {
                        resolved_type: serde_json::Value::Object(opt),
                        deps,
                    }
                } else {
                    let mut is_resolved = false;
                    let mut resolved_type = self.type_ir(&serde_json::Value::String("Unknown".to_string()));
                    let mut deps = Vec::new();

                    let mut typed_args = Vec::new();
                    for arg in args {
                        let arg_typed = self.infer_expr(arg, symbol_types, olap_env, type_shapes, type_errors, type_warnings, node_name, functions);
                        deps.extend(arg_typed.deps.clone());
                        typed_args.push(arg_typed);
                    }
                    deps.sort();
                    deps.dedup();

                    // Check user-defined functions
                    for f in functions {
                        if f.name == *fn_name {
                            is_resolved = true;
                            resolved_type = self.type_ir(&serde_json::to_value(&f.return_type).unwrap());
                            break;
                        }
                    }

                    if !is_resolved {
                        match fn_name.as_str() {
                            "mul" => {
                                is_resolved = true;
                                if typed_args.len() >= 2 {
                                    let left = &typed_args[0].resolved_type;
                                    let right = &typed_args[1].resolved_type;
                                    let left_name = self.type_name(left);
                                    let right_name = self.type_name(right);
                                    if left_name == "Decimal" && right_name == "Decimal" {
                                        let left_scale_val = self.get_param(left, 0)
                                            .and_then(|p| p.get("name").and_then(|n| n.as_str()).map(|s| s.to_string()))
                                            .unwrap_or_else(|| "0".to_string());
                                        let right_scale_val = self.get_param(right, 0)
                                            .and_then(|p| p.get("name").and_then(|n| n.as_str()).map(|s| s.to_string()))
                                            .unwrap_or_else(|| "0".to_string());
                                        let l_s = left_scale_val.parse::<i64>().unwrap_or(0);
                                        let r_s = right_scale_val.parse::<i64>().unwrap_or(0);
                                        let sum_scale = l_s + r_s;
                                        let mut sum_type = serde_json::Map::new();
                                        sum_type.insert("name".to_string(), serde_json::Value::String("Decimal".to_string()));
                                        let mut inner = serde_json::Map::new();
                                        inner.insert("name".to_string(), serde_json::Value::String(sum_scale.to_string()));
                                        inner.insert("params".to_string(), serde_json::Value::Array(Vec::new()));
                                        sum_type.insert("params".to_string(), serde_json::Value::Array(vec![serde_json::Value::Object(inner)]));
                                        resolved_type = serde_json::Value::Object(sum_type);
                                    } else {
                                        resolved_type = self.type_ir(&serde_json::Value::String("Decimal".to_string()));
                                    }
                                } else {
                                    resolved_type = self.type_ir(&serde_json::Value::String("Decimal".to_string()));
                                }
                            }
                            "div" | "sub" | "add" => {
                                is_resolved = true;
                                resolved_type = self.type_ir(&serde_json::Value::String("Decimal".to_string()));
                            }
                            "stdlib.numeric.add" => {
                                is_resolved = true;
                                if !typed_args.is_empty() {
                                    resolved_type = typed_args[0].resolved_type.clone();
                                } else {
                                    resolved_type = self.type_ir(&serde_json::Value::String("Integer".to_string()));
                                }
                            }
                            "stdlib.option.wrap" => {
                                is_resolved = true;
                                let mut opt = serde_json::Map::new();
                                opt.insert("name".to_string(), serde_json::Value::String("Option".to_string()));
                                let inner_ty = if !typed_args.is_empty() {
                                    typed_args[0].resolved_type.clone()
                                } else {
                                    self.type_ir(&serde_json::Value::String("Integer".to_string()))
                                };
                                opt.insert("params".to_string(), serde_json::Value::Array(vec![inner_ty]));
                                resolved_type = serde_json::Value::Object(opt);
                            }
                            "count" => {
                                is_resolved = true;
                                resolved_type = self.type_ir(&serde_json::Value::String("Integer".to_string()));
                            }
                            "first" | "last" => {
                                is_resolved = true;
                                let mut inner_ty = serde_json::Value::Null;
                                if !typed_args.is_empty() {
                                    if let Some(param) = self.get_param(&typed_args[0].resolved_type, 0) {
                                        inner_ty = param;
                                    }
                                }
                                if inner_ty.is_null() || (inner_ty.is_object() && inner_ty.as_object().unwrap().is_empty()) {
                                    let mut default_ty = serde_json::Map::new();
                                    default_ty.insert("name".to_string(), serde_json::Value::String("Unknown".to_string()));
                                    default_ty.insert("params".to_string(), serde_json::Value::Array(Vec::new()));
                                    inner_ty = serde_json::Value::Object(default_ty);
                                }
                                let mut opt = serde_json::Map::new();
                                opt.insert("name".to_string(), serde_json::Value::String("Option".to_string()));
                                opt.insert("params".to_string(), serde_json::Value::Array(vec![inner_ty]));
                                resolved_type = serde_json::Value::Object(opt);
                            }
                            "sum" => {
                                is_resolved = true;
                                let mut resolved = self.type_ir(&serde_json::Value::String("Decimal".to_string()));
                                if args.len() >= 2 {
                                    let mut field_name = String::new();
                                    if let Expr::Symbol { value } = &args[1] {
                                        field_name = value.clone();
                                    }
                                    if let Some(param) = self.get_param(&typed_args[0].resolved_type, 0) {
                                        let inner_type_name = self.type_name(&param);
                                        if let Some(fields) = type_shapes.get(&inner_type_name) {
                                            if let Some(field_ty) = fields.get(&field_name) {
                                                resolved = field_ty.clone();
                                            }
                                        }
                                    }
                                }
                                resolved_type = resolved;
                            }
                            "zip" => {
                                is_resolved = true;
                                let mut inner_a = serde_json::Map::new();
                                inner_a.insert("name".to_string(), serde_json::Value::String("Unknown".to_string()));
                                inner_a.insert("params".to_string(), serde_json::Value::Array(Vec::new()));
                                let mut inner_b = serde_json::Map::new();
                                inner_b.insert("name".to_string(), serde_json::Value::String("Unknown".to_string()));
                                inner_b.insert("params".to_string(), serde_json::Value::Array(Vec::new()));

                                if typed_args.len() >= 2 {
                                    if let Some(param_a) = self.get_param(&typed_args[0].resolved_type, 0) {
                                        inner_a = param_a.as_object().cloned().unwrap_or(inner_a);
                                    }
                                    if let Some(param_b) = self.get_param(&typed_args[1].resolved_type, 0) {
                                        inner_b = param_b.as_object().cloned().unwrap_or(inner_b);
                                    }
                                }

                                let mut pair = serde_json::Map::new();
                                pair.insert("name".to_string(), serde_json::Value::String("Pair".to_string()));
                                pair.insert("params".to_string(), serde_json::Value::Array(vec![
                                    serde_json::Value::Object(inner_a),
                                    serde_json::Value::Object(inner_b)
                                ]));

                                let mut col = serde_json::Map::new();
                                col.insert("name".to_string(), serde_json::Value::String("Collection".to_string()));
                                col.insert("params".to_string(), serde_json::Value::Array(vec![serde_json::Value::Object(pair)]));
                                resolved_type = serde_json::Value::Object(col);
                            }
                            "unwrap_or" | "or_else" => {
                                is_resolved = true;
                                if typed_args.len() >= 2 {
                                    resolved_type = typed_args[1].resolved_type.clone();
                                } else {
                                    resolved_type = self.type_ir(&serde_json::Value::String("Unknown".to_string()));
                                }
                            }
                            "range" => {
                                is_resolved = true;
                                let mut col = serde_json::Map::new();
                                col.insert("name".to_string(), serde_json::Value::String("Collection".to_string()));
                                let mut inner_ty = serde_json::Map::new();
                                inner_ty.insert("name".to_string(), serde_json::Value::String("Integer".to_string()));
                                inner_ty.insert("params".to_string(), serde_json::Value::Array(Vec::new()));
                                col.insert("params".to_string(), serde_json::Value::Array(vec![serde_json::Value::Object(inner_ty)]));
                                resolved_type = serde_json::Value::Object(col);
                            }
                            "filter" | "take" => {
                                is_resolved = true;
                                if !typed_args.is_empty() {
                                    resolved_type = typed_args[0].resolved_type.clone();
                                } else {
                                    resolved_type = self.type_ir(&serde_json::Value::String("Collection".to_string()));
                                }
                            }
                            "map" => {
                                is_resolved = true;
                                let first_arg_type = if !typed_args.is_empty() {
                                    typed_args[0].resolved_type.clone()
                                } else {
                                    self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                                };
                                let first_arg_name = self.type_name(&first_arg_type);
                                
                                let mut lambda_return_type = self.type_ir(&serde_json::Value::String("Unknown".to_string()));
                                if args.len() >= 2 {
                                    if let Expr::Lambda { params, body } = &args[1] {
                                        let mut local_symbols = symbol_types.clone();
                                        for p in params {
                                            local_symbols.insert(p.clone(), self.type_ir(&serde_json::Value::String("Integer".to_string())));
                                        }
                                        let mut temp_errors = Vec::new();
                                        lambda_return_type = match body.as_ref() {
                                            ExprOrBlock::Expr(e) => {
                                                let body_typed = self.infer_expr(e, &local_symbols, olap_env, type_shapes, &mut temp_errors, type_warnings, node_name, functions);
                                                body_typed.resolved_type
                                            }
                                            ExprOrBlock::Block(block) => {
                                                let mut last_type = self.type_ir(&serde_json::Value::String("Unknown".to_string()));
                                                for stmt in &block.stmts {
                                                    match stmt {
                                                        Stmt::Let { name, expr } => {
                                                            local_symbols.insert(name.clone(), self.type_ir(&serde_json::Value::String("Unknown".to_string())));
                                                            let stmt_typed = self.infer_expr(expr, &local_symbols, olap_env, type_shapes, &mut temp_errors, type_warnings, node_name, functions);
                                                            last_type = stmt_typed.resolved_type;
                                                        }
                                                        Stmt::ExprStmt { expr } => {
                                                            let stmt_typed = self.infer_expr(expr, &local_symbols, olap_env, type_shapes, &mut temp_errors, type_warnings, node_name, functions);
                                                            last_type = stmt_typed.resolved_type;
                                                        }
                                                    }
                                                }
                                                if let Some(re) = &block.return_expr {
                                                    let re_typed = self.infer_expr(re, &local_symbols, olap_env, type_shapes, &mut temp_errors, type_warnings, node_name, functions);
                                                    last_type = re_typed.resolved_type;
                                                }
                                                last_type
                                            }
                                        };
                                    }
                                }

                                if first_arg_name == "Option" {
                                    let mut opt = serde_json::Map::new();
                                    opt.insert("name".to_string(), serde_json::Value::String("Option".to_string()));
                                    opt.insert("params".to_string(), serde_json::Value::Array(vec![lambda_return_type]));
                                    resolved_type = serde_json::Value::Object(opt);
                                } else if first_arg_name == "Result" {
                                    let err_type = self.get_param(&first_arg_type, 1)
                                        .unwrap_or_else(|| self.type_ir(&serde_json::Value::String("Unknown".to_string())));
                                    let mut res = serde_json::Map::new();
                                    res.insert("name".to_string(), serde_json::Value::String("Result".to_string()));
                                    res.insert("params".to_string(), serde_json::Value::Array(vec![lambda_return_type, err_type]));
                                    resolved_type = serde_json::Value::Object(res);
                                } else {
                                    let mut col = serde_json::Map::new();
                                    col.insert("name".to_string(), serde_json::Value::String("Collection".to_string()));
                                    col.insert("params".to_string(), serde_json::Value::Array(vec![lambda_return_type]));
                                    resolved_type = serde_json::Value::Object(col);
                                }
                            }
                            "flat_map" | "and_then" => {
                                is_resolved = true;
                                let first_arg_type = if !typed_args.is_empty() {
                                    typed_args[0].resolved_type.clone()
                                } else {
                                    self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                                };
                                let first_arg_name = self.type_name(&first_arg_type);
                                
                                let mut lambda_return_type = self.type_ir(&serde_json::Value::String("Unknown".to_string()));
                                if args.len() >= 2 {
                                    if let Expr::Lambda { params, body } = &args[1] {
                                        let mut local_symbols = symbol_types.clone();
                                        for p in params {
                                            local_symbols.insert(p.clone(), self.type_ir(&serde_json::Value::String("Integer".to_string())));
                                        }
                                        let mut temp_errors = Vec::new();
                                        lambda_return_type = match body.as_ref() {
                                            ExprOrBlock::Expr(e) => {
                                                let body_typed = self.infer_expr(e, &local_symbols, olap_env, type_shapes, &mut temp_errors, type_warnings, node_name, functions);
                                                body_typed.resolved_type
                                            }
                                            ExprOrBlock::Block(block) => {
                                                let mut last_type = self.type_ir(&serde_json::Value::String("Unknown".to_string()));
                                                for stmt in &block.stmts {
                                                    match stmt {
                                                        Stmt::Let { name, expr } => {
                                                            local_symbols.insert(name.clone(), self.type_ir(&serde_json::Value::String("Unknown".to_string())));
                                                            let stmt_typed = self.infer_expr(expr, &local_symbols, olap_env, type_shapes, &mut temp_errors, type_warnings, node_name, functions);
                                                            last_type = stmt_typed.resolved_type;
                                                        }
                                                        Stmt::ExprStmt { expr } => {
                                                            let stmt_typed = self.infer_expr(expr, &local_symbols, olap_env, type_shapes, &mut temp_errors, type_warnings, node_name, functions);
                                                            last_type = stmt_typed.resolved_type;
                                                        }
                                                    }
                                                }
                                                if let Some(re) = &block.return_expr {
                                                    let re_typed = self.infer_expr(re, &local_symbols, olap_env, type_shapes, &mut temp_errors, type_warnings, node_name, functions);
                                                    last_type = re_typed.resolved_type;
                                                }
                                                last_type
                                            }
                                        };
                                    }
                                }

                                let inner_u = self.get_param(&lambda_return_type, 0)
                                    .unwrap_or_else(|| self.type_ir(&serde_json::Value::String("Unknown".to_string())));

                                if first_arg_name == "Option" {
                                    let mut opt = serde_json::Map::new();
                                    opt.insert("name".to_string(), serde_json::Value::String("Option".to_string()));
                                    opt.insert("params".to_string(), serde_json::Value::Array(vec![inner_u]));
                                    resolved_type = serde_json::Value::Object(opt);
                                } else if first_arg_name == "Result" {
                                    let err_type = self.get_param(&lambda_return_type, 1)
                                        .or_else(|| self.get_param(&first_arg_type, 1))
                                        .unwrap_or_else(|| self.type_ir(&serde_json::Value::String("Unknown".to_string())));
                                    let mut res = serde_json::Map::new();
                                    res.insert("name".to_string(), serde_json::Value::String("Result".to_string()));
                                    res.insert("params".to_string(), serde_json::Value::Array(vec![inner_u, err_type]));
                                    resolved_type = serde_json::Value::Object(res);
                                } else {
                                    let mut col = serde_json::Map::new();
                                    col.insert("name".to_string(), serde_json::Value::String("Collection".to_string()));
                                    col.insert("params".to_string(), serde_json::Value::Array(vec![inner_u]));
                                    resolved_type = serde_json::Value::Object(col);
                                }
                            }
                            "some" => {
                                is_resolved = true;
                                let inner_ty = if !typed_args.is_empty() {
                                    typed_args[0].resolved_type.clone()
                                } else {
                                    self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                                };
                                let mut opt = serde_json::Map::new();
                                opt.insert("name".to_string(), serde_json::Value::String("Option".to_string()));
                                opt.insert("params".to_string(), serde_json::Value::Array(vec![inner_ty]));
                                resolved_type = serde_json::Value::Object(opt);
                            }
                            "none" => {
                                is_resolved = true;
                                let mut opt = serde_json::Map::new();
                                opt.insert("name".to_string(), serde_json::Value::String("Option".to_string()));
                                opt.insert("params".to_string(), serde_json::Value::Array(vec![self.type_ir(&serde_json::Value::String("Unknown".to_string()))]));
                                resolved_type = serde_json::Value::Object(opt);
                            }
                            "ok" => {
                                is_resolved = true;
                                let inner_ty = if !typed_args.is_empty() {
                                    typed_args[0].resolved_type.clone()
                                } else {
                                    self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                                };
                                let mut res = serde_json::Map::new();
                                res.insert("name".to_string(), serde_json::Value::String("Result".to_string()));
                                res.insert("params".to_string(), serde_json::Value::Array(vec![
                                    inner_ty,
                                    self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                                ]));
                                resolved_type = serde_json::Value::Object(res);
                            }
                            "err" => {
                                is_resolved = true;
                                let inner_ty = if !typed_args.is_empty() {
                                    typed_args[0].resolved_type.clone()
                                } else {
                                    self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                                };
                                let mut res = serde_json::Map::new();
                                res.insert("name".to_string(), serde_json::Value::String("Result".to_string()));
                                res.insert("params".to_string(), serde_json::Value::Array(vec![
                                    self.type_ir(&serde_json::Value::String("Unknown".to_string())),
                                    inner_ty
                                ]));
                                resolved_type = serde_json::Value::Object(res);
                            }
                            "is_some" | "is_none" | "some?" | "none?" | "is_ok" | "is_err" | "ok?" | "err?" => {
                                is_resolved = true;
                                resolved_type = self.type_ir(&serde_json::Value::String("Bool".to_string()));
                            }
                            // igniter-string-core-units-and-pure-stdlib-boundary-v0 text ops
                            "length" => {
                                // held/legacy — ambiguous length; accept Text or String, return Integer
                                is_resolved = true;
                                // call the helper only for its side-effect (OOF-TY0 on arity/type mismatch)
                                let _ = self.check_text_stdlib_call(
                                    "length", &typed_args, &["Text"], type_errors, node_name,
                                );
                                resolved_type = self.type_ir(&serde_json::Value::String("Integer".to_string()));
                            }
                            "trim" => {
                                is_resolved = true;
                                resolved_type = self.check_text_stdlib_call(
                                    "trim", &typed_args, &["Text"], type_errors, node_name,
                                );
                            }
                            "concat" => {
                                is_resolved = true;
                                if typed_args.len() != 2 {
                                    type_errors.push(ClassifierDiagnostic {
                                        rule: "OOF-TY0".to_string(),
                                        message: format!(
                                            "stdlib.text.concat: expected 2 argument(s), got {}",
                                            typed_args.len()
                                        ),
                                        node: node_name.to_string(),
                                        line: None,
                                    });
                                    resolved_type = self.type_ir(&serde_json::Value::String("Unknown".to_string()));
                                } else {
                                    let first_name = self.type_name(&typed_args[0].resolved_type);
                                    if first_name == "Collection" {
                                        // Collection concat: preserve element type (lab-local behavior)
                                        let inner_ty = self.get_param(&typed_args[0].resolved_type, 0)
                                            .unwrap_or_else(|| self.type_ir(&serde_json::Value::String("Unknown".to_string())));
                                        let mut col = serde_json::Map::new();
                                        col.insert("name".to_string(), serde_json::Value::String("Collection".to_string()));
                                        col.insert("params".to_string(), serde_json::Value::Array(vec![inner_ty]));
                                        resolved_type = serde_json::Value::Object(col);
                                    } else {
                                        // stdlib.text.concat: accepts Text or String (v0 compat)
                                        resolved_type = self.check_text_stdlib_call(
                                            "concat", &typed_args, &["Text", "Text"],
                                            type_errors, node_name,
                                        );
                                    }
                                }
                            }
                            "split" => {
                                is_resolved = true;
                                resolved_type = self.check_text_stdlib_call(
                                    "split", &typed_args, &["Text", "Text"], type_errors, node_name,
                                );
                            }
                            "contains" | "starts_with" | "ends_with" => {
                                is_resolved = true;
                                resolved_type = self.check_text_stdlib_call(
                                    fn_name, &typed_args, &["Text", "Text"], type_errors, node_name,
                                );
                            }
                            "replace" | "replace_all" => {
                                is_resolved = true;
                                resolved_type = self.check_text_stdlib_call(
                                    fn_name, &typed_args, &["Text", "Text", "Text"], type_errors, node_name,
                                );
                            }
                            "byte_length" | "rune_length" | "grapheme_length" => {
                                is_resolved = true;
                                resolved_type = self.check_text_stdlib_call(
                                    fn_name, &typed_args, &["Text"], type_errors, node_name,
                                );
                            }
                            "byte_slice" | "rune_slice" | "grapheme_slice" => {
                                is_resolved = true;
                                resolved_type = self.check_text_stdlib_call(
                                    fn_name, &typed_args, &["Text", "Integer", "Integer"],
                                    type_errors, node_name,
                                );
                            }
                            "find" => {
                                is_resolved = true;
                                if typed_args.len() != 2 {
                                    type_errors.push(ClassifierDiagnostic {
                                        rule: "OOF-TM1".to_string(),
                                        message: format!("find expects exactly 2 arguments, got {}", typed_args.len()),
                                        node: node_name.to_string(),
                                        line: None,
                                    });
                                }
                                let inner_ty = if !typed_args.is_empty() {
                                    self.get_param(&typed_args[0].resolved_type, 0)
                                        .unwrap_or_else(|| self.type_ir(&serde_json::Value::String("Unknown".to_string())))
                                } else {
                                    self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                                };
                                let mut opt = serde_json::Map::new();
                                opt.insert("name".to_string(), serde_json::Value::String("Option".to_string()));
                                opt.insert("params".to_string(), serde_json::Value::Array(vec![inner_ty]));
                                resolved_type = serde_json::Value::Object(opt);
                            }
                            "any" | "all" => {
                                is_resolved = true;
                                if typed_args.len() != 2 {
                                    type_errors.push(ClassifierDiagnostic {
                                        rule: "OOF-TM1".to_string(),
                                        message: format!("{} expects exactly 2 arguments, got {}", fn_name, typed_args.len()),
                                        node: node_name.to_string(),
                                        line: None,
                                    });
                                }
                                resolved_type = self.type_ir(&serde_json::Value::String("Bool".to_string()));
                            }
                            "try_catch" | "propagate" => {
                                // try_catch(res, handler) -> T
                                // propagate(res) -> T
                                // Extract inner ok-type T from Result[T, E]
                                is_resolved = true;
                                resolved_type = if !typed_args.is_empty() {
                                    self.get_param(&typed_args[0].resolved_type, 0)
                                        .unwrap_or_else(|| self.type_ir(&serde_json::Value::String("Unknown".to_string())))
                                } else {
                                    self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                                };
                            }
                            "validate" => {
                                // validate(val, predicate, error) -> Result[T, E]
                                // T from arg 0, E from arg 2
                                is_resolved = true;
                                let t_type = if !typed_args.is_empty() {
                                    typed_args[0].resolved_type.clone()
                                } else {
                                    self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                                };
                                let e_type = if typed_args.len() >= 3 {
                                    typed_args[2].resolved_type.clone()
                                } else {
                                    self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                                };
                                let mut result_map = serde_json::Map::new();
                                result_map.insert("name".to_string(), serde_json::Value::String("Result".to_string()));
                                result_map.insert("params".to_string(), serde_json::Value::Array(vec![t_type, e_type]));
                                resolved_type = serde_json::Value::Object(result_map);
                            }
                            "diff_seconds" => {
                                is_resolved = true;
                                if typed_args.len() != 2 {
                                    type_errors.push(ClassifierDiagnostic {
                                        rule: "OOF-TM1".to_string(),
                                        message: format!("diff_seconds expects exactly 2 arguments, got {}", typed_args.len()),
                                        node: node_name.to_string(),
                                        line: None,
                                    });
                                } else {
                                    for arg_typed in &typed_args {
                                        let arg_type = &arg_typed.resolved_type;
                                        let arg_name = self.type_name(arg_type);
                                        if arg_name != "DateTime" && arg_name != "Unknown" {
                                            type_errors.push(ClassifierDiagnostic {
                                                rule: "OOF-TY0".to_string(),
                                                message: format!("Type mismatch: expected DateTime, got {}", arg_name),
                                                node: node_name.to_string(),
                                                line: None,
                                            });
                                        }
                                    }
                                }
                                resolved_type = self.type_ir(&serde_json::Value::String("Integer".to_string()));
                            }
                            "add_seconds" => {
                                is_resolved = true;
                                if typed_args.len() != 2 {
                                    type_errors.push(ClassifierDiagnostic {
                                        rule: "OOF-TM1".to_string(),
                                        message: format!("add_seconds expects exactly 2 arguments, got {}", typed_args.len()),
                                        node: node_name.to_string(),
                                        line: None,
                                    });
                                } else {
                                    let arg0_name = self.type_name(&typed_args[0].resolved_type);
                                    if arg0_name != "DateTime" && arg0_name != "Unknown" {
                                        type_errors.push(ClassifierDiagnostic {
                                            rule: "OOF-TY0".to_string(),
                                            message: format!("Type mismatch: expected DateTime, got {}", arg0_name),
                                            node: node_name.to_string(),
                                            line: None,
                                        });
                                    }
                                    let arg1_name = self.type_name(&typed_args[1].resolved_type);
                                    if arg1_name != "Integer" && arg1_name != "Unknown" {
                                        type_errors.push(ClassifierDiagnostic {
                                            rule: "OOF-TY0".to_string(),
                                            message: format!("Type mismatch: expected Integer, got {}", arg1_name),
                                            node: node_name.to_string(),
                                            line: None,
                                        });
                                    }
                                }
                                resolved_type = self.type_ir(&serde_json::Value::String("DateTime".to_string()));
                            }
                            "parse_datetime" => {
                                is_resolved = true;
                                if typed_args.len() != 2 {
                                    type_errors.push(ClassifierDiagnostic {
                                        rule: "OOF-TM1".to_string(),
                                        message: format!("parse_datetime expects exactly 2 arguments, got {}", typed_args.len()),
                                        node: node_name.to_string(),
                                        line: None,
                                    });
                                } else {
                                    for arg_typed in &typed_args {
                                        let arg_type = &arg_typed.resolved_type;
                                        let arg_name = self.type_name(arg_type);
                                        if arg_name != "String" && arg_name != "Unknown" {
                                            type_errors.push(ClassifierDiagnostic {
                                                rule: "OOF-TY0".to_string(),
                                                message: format!("Type mismatch: expected String, got {}", arg_name),
                                                node: node_name.to_string(),
                                                line: None,
                                            });
                                        }
                                    }
                                }
                                let mut opt = serde_json::Map::new();
                                opt.insert("name".to_string(), serde_json::Value::String("Option".to_string()));
                                let dt_type = self.type_ir(&serde_json::Value::String("DateTime".to_string()));
                                opt.insert("params".to_string(), serde_json::Value::Array(vec![dt_type]));
                                resolved_type = serde_json::Value::Object(opt);
                            }
                            "format_datetime" => {
                                is_resolved = true;
                                if typed_args.len() != 2 {
                                    type_errors.push(ClassifierDiagnostic {
                                        rule: "OOF-TM1".to_string(),
                                        message: format!("format_datetime expects exactly 2 arguments, got {}", typed_args.len()),
                                        node: node_name.to_string(),
                                        line: None,
                                    });
                                } else {
                                    let arg0_name = self.type_name(&typed_args[0].resolved_type);
                                    if arg0_name != "DateTime" && arg0_name != "Unknown" {
                                        type_errors.push(ClassifierDiagnostic {
                                            rule: "OOF-TY0".to_string(),
                                            message: format!("Type mismatch: expected DateTime, got {}", arg0_name),
                                            node: node_name.to_string(),
                                            line: None,
                                        });
                                    }
                                    let arg1_name = self.type_name(&typed_args[1].resolved_type);
                                    if arg1_name != "String" && arg1_name != "Unknown" {
                                        type_errors.push(ClassifierDiagnostic {
                                            rule: "OOF-TY0".to_string(),
                                            message: format!("Type mismatch: expected String, got {}", arg1_name),
                                            node: node_name.to_string(),
                                            line: None,
                                        });
                                    }
                                }
                                resolved_type = self.type_ir(&serde_json::Value::String("String".to_string()));
                            }
                            "is_before" | "is_after" => {
                                is_resolved = true;
                                if typed_args.len() != 2 {
                                    type_errors.push(ClassifierDiagnostic {
                                        rule: "OOF-TM1".to_string(),
                                        message: format!("{} expects exactly 2 arguments, got {}", fn_name, typed_args.len()),
                                        node: node_name.to_string(),
                                        line: None,
                                    });
                                } else {
                                    for arg_typed in &typed_args {
                                        let arg_type = &arg_typed.resolved_type;
                                        let arg_name = self.type_name(arg_type);
                                        if arg_name != "DateTime" && arg_name != "Unknown" {
                                            type_errors.push(ClassifierDiagnostic {
                                                rule: "OOF-TY0".to_string(),
                                                message: format!("Type mismatch: expected DateTime, got {}", arg_name),
                                                node: node_name.to_string(),
                                                line: None,
                                            });
                                        }
                                    }
                                }
                                resolved_type = self.type_ir(&serde_json::Value::String("Bool".to_string()));
                            }
                            "unwrap" => {
                                is_resolved = true;
                                let mut inner_ty = self.type_ir(&serde_json::Value::String("Unknown".to_string()));
                                if !typed_args.is_empty() {
                                    if let Some(param) = self.get_param(&typed_args[0].resolved_type, 0) {
                                        inner_ty = param;
                                    }
                                }
                                resolved_type = inner_ty;
                            }
                            "fold" => {
                                is_resolved = true;
                                if typed_args.len() >= 2 {
                                    resolved_type = typed_args[1].resolved_type.clone();
                                } else {
                                    resolved_type = self.type_ir(&serde_json::Value::String("Unknown".to_string()));
                                }
                            }
                            "avg" | "min" | "max" => {
                                is_resolved = true;
                                let mut resolved = self.type_ir(&serde_json::Value::String("Decimal".to_string()));
                                if args.len() >= 2 {
                                    let mut field_name = String::new();
                                    if let Expr::Symbol { value } = &args[1] {
                                        field_name = value.clone();
                                    }
                                    if let Some(param) = self.get_param(&typed_args[0].resolved_type, 0) {
                                        let inner_type_name = self.type_name(&param);
                                        if let Some(fields) = type_shapes.get(&inner_type_name) {
                                            if let Some(field_ty) = fields.get(&field_name) {
                                                resolved = field_ty.clone();
                                            }
                                        }
                                    }
                                }
                                let mut opt = serde_json::Map::new();
                                opt.insert("name".to_string(), serde_json::Value::String("Option".to_string()));
                                opt.insert("params".to_string(), serde_json::Value::Array(vec![resolved]));
                                resolved_type = serde_json::Value::Object(opt);
                            }
                            "compute_availability" => {
                                is_resolved = true;
                                let mut col = serde_json::Map::new();
                                col.insert("name".to_string(), serde_json::Value::String("Collection".to_string()));
                                let mut inner_ty = serde_json::Map::new();
                                inner_ty.insert("name".to_string(), serde_json::Value::String("TimeSlot".to_string()));
                                inner_ty.insert("params".to_string(), serde_json::Value::Array(Vec::new()));
                                col.insert("params".to_string(), serde_json::Value::Array(vec![serde_json::Value::Object(inner_ty)]));
                                resolved_type = serde_json::Value::Object(col);
                            }
                            "build_snapshot" => {
                                is_resolved = true;
                                resolved_type = self.type_ir(&serde_json::Value::String("AvailabilitySnapshot".to_string()));
                            }
                            "stdlib.IO.read_text" | "stdlib.IO.read_json" | "stdlib.IO.exists" | "stdlib.IO.list_dir" => {
                                is_resolved = true;
                                if typed_args.len() != 2 {
                                    type_errors.push(ClassifierDiagnostic {
                                        rule: "OOF-TM1".to_string(),
                                        message: format!("{} expects exactly 2 arguments, got {}", fn_name, typed_args.len()),
                                        node: node_name.to_string(),
                                        line: None,
                                    });
                                } else {
                                    let arg0_name = self.type_name(&typed_args[0].resolved_type);
                                    if arg0_name != "String" && arg0_name != "Unknown" {
                                        type_errors.push(ClassifierDiagnostic {
                                            rule: "OOF-TY0".to_string(),
                                            message: format!("Type mismatch for argument 0: expected String, got {}", arg0_name),
                                            node: node_name.to_string(),
                                            line: None,
                                        });
                                    }
                                }
                                
                                let mut res = serde_json::Map::new();
                                res.insert("name".to_string(), serde_json::Value::String("Result".to_string()));
                                
                                let t_type = match fn_name.as_str() {
                                    "stdlib.IO.read_text" => self.type_ir(&serde_json::Value::String("String".to_string())),
                                    "stdlib.IO.read_json" => self.type_ir(&serde_json::Value::String("JsonValue".to_string())),
                                    "stdlib.IO.exists" => self.type_ir(&serde_json::Value::String("Bool".to_string())),
                                    "stdlib.IO.list_dir" => {
                                        let mut col = serde_json::Map::new();
                                        col.insert("name".to_string(), serde_json::Value::String("Collection".to_string()));
                                        let inner_ty = self.type_ir(&serde_json::Value::String("PathEntry".to_string()));
                                        col.insert("params".to_string(), serde_json::Value::Array(vec![inner_ty]));
                                        serde_json::Value::Object(col)
                                    }
                                    _ => self.type_ir(&serde_json::Value::String("Unknown".to_string())),
                                };
                                let e_type = self.type_ir(&serde_json::Value::String("IoError".to_string()));
                                res.insert("params".to_string(), serde_json::Value::Array(vec![t_type, e_type]));
                                resolved_type = serde_json::Value::Object(res);
                            }
                            "stdlib.IO.write_text" | "stdlib.IO.write_json" => {
                                is_resolved = true;
                                if typed_args.len() != 3 {
                                    type_errors.push(ClassifierDiagnostic {
                                        rule: "OOF-TM1".to_string(),
                                        message: format!("{} expects exactly 3 arguments, got {}", fn_name, typed_args.len()),
                                        node: node_name.to_string(),
                                        line: None,
                                    });
                                } else {
                                    let arg0_name = self.type_name(&typed_args[0].resolved_type);
                                    if arg0_name != "String" && arg0_name != "Unknown" {
                                        type_errors.push(ClassifierDiagnostic {
                                            rule: "OOF-TY0".to_string(),
                                            message: format!("Type mismatch for argument 0: expected String, got {}", arg0_name),
                                            node: node_name.to_string(),
                                            line: None,
                                        });
                                    }
                                    if fn_name == "stdlib.IO.write_text" {
                                        let arg1_name = self.type_name(&typed_args[1].resolved_type);
                                        if arg1_name != "String" && arg1_name != "Unknown" {
                                            type_errors.push(ClassifierDiagnostic {
                                                rule: "OOF-TY0".to_string(),
                                                message: format!("Type mismatch for argument 1: expected String, got {}", arg1_name),
                                                node: node_name.to_string(),
                                                line: None,
                                            });
                                        }
                                    }
                                }

                                let mut res = serde_json::Map::new();
                                res.insert("name".to_string(), serde_json::Value::String("Result".to_string()));
                                let t_type = self.type_ir(&serde_json::Value::String("WriteReceipt".to_string()));
                                let e_type = self.type_ir(&serde_json::Value::String("IoError".to_string()));
                                res.insert("params".to_string(), serde_json::Value::Array(vec![t_type, e_type]));
                                resolved_type = serde_json::Value::Object(res);
                            }
                            // PROP-039 gate 5: recur() — return Unknown here; full validation
                            // happens via check_recur_in_expr in the "compute" case of
                            // typecheck_contract. We suppress OOF-TY0 "Unknown function" noise.
                            "recur" => {
                                is_resolved = true;
                                // resolved_type stays Unknown — contract output type is not
                                // accessible inside infer_expr; check_recur_in_expr handles it.
                            }
                            // LAB-RACK-P9: explicit named user-contract dispatch.
                            // call_contract("ContractName", arg1, arg2, ...) dispatches to a
                            // named contract in the loaded igapp at VM runtime.
                            // Return type: Unknown (callee output type not verified in v0;
                            // dispatch table lookup happens at VM execute time).
                            // First arg must be String (contract name); remaining args are
                            // positional inputs matched to callee's input declaration order.
                            // Cross-contract type verification deferred to a later card.
                            "call_contract" => {
                                is_resolved = true;
                                if typed_args.is_empty() {
                                    type_errors.push(ClassifierDiagnostic {
                                        rule: "OOF-TY0".to_string(),
                                        message: "call_contract requires at least one argument (contract name as String)".to_string(),
                                        node: node_name.to_string(),
                                        line: None,
                                    });
                                } else {
                                    let name_arg_type = self.type_name(&typed_args[0].resolved_type);
                                    if name_arg_type != "String" && name_arg_type != "Unknown" {
                                        type_errors.push(ClassifierDiagnostic {
                                            rule: "OOF-TY0".to_string(),
                                            message: format!(
                                                "call_contract: first argument must be String (contract name), got {}",
                                                name_arg_type
                                            ),
                                            node: node_name.to_string(),
                                            line: None,
                                        });
                                    }
                                }
                                // resolved_type stays Unknown — callee output type not
                                // verifiable in v0 without a cross-contract type table.
                            }
                            _ => {}
                        }
                    }

                    if is_resolved {
                        TypedExpression {
                            resolved_type,
                            deps,
                        }
                    } else {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-TY0".to_string(),
                            message: format!("Unknown function: {}", fn_name),
                            node: node_name.to_string(),
                            line: None,
                        });
                        TypedExpression {
                            resolved_type: self.type_ir(&serde_json::Value::String("Unknown".to_string())),
                            deps: Vec::new(),
                        }
                    }
                }
            }
            Expr::IndexAccess { object, index } => {
                if let Expr::Ref { name } = object.as_ref() {
                    if let Some(point) = olap_env.get(name) {
                        if let Expr::SliceRecord { fields } = index.as_ref() {
                            // Check dimensions: OOF-O4
                            let expected_dims: HashMap<String, serde_json::Value> = point.get("dimensions").unwrap().as_object().unwrap().iter().map(|(k, v)| (k.clone(), v.clone())).collect();
                            for expected_dim in expected_dims.keys() {
                                if !fields.contains_key(expected_dim) {
                                    type_errors.push(ClassifierDiagnostic {
                                        rule: "OOF-O4".to_string(),
                                        message: format!("OLAPPoint access missing required dimension: {}", expected_dim),
                                        node: node_name.to_string(),
                                        line: None,
                                    });
                                }
                            }

                            // Validate dimensions types: OOF-O5
                            let mut deps = Vec::new();
                            for (dim_name, slice_expr) in fields {
                                let slice_typed = self.infer_expr(slice_expr, symbol_types, olap_env, type_shapes, type_errors, type_warnings, node_name, functions);
                                deps.append(&mut slice_typed.deps.clone());
                                if let Some(expected_type) = expected_dims.get(dim_name) {
                                    let expected_name = self.type_name(expected_type);
                                    let slice_name = self.type_name(&slice_typed.resolved_type);
                                    if expected_name != "Unknown" && slice_name != "Unknown" && expected_name != slice_name {
                                        type_errors.push(ClassifierDiagnostic {
                                            rule: "OOF-O5".to_string(),
                                            message: format!("OLAPPoint dimension '{}' expected {}, got {}", dim_name, expected_name, slice_name),
                                            node: node_name.to_string(),
                                            line: None,
                                        });
                                    }
                                }
                            }

                            let measure_type = point.get("measure_type").unwrap().clone();
                            return TypedExpression {
                                 resolved_type: measure_type,
                                 deps,
                            };
                        } else {
                            type_errors.push(ClassifierDiagnostic {
                                rule: "OOF-O4".to_string(),
                                message: "OLAPPoint access requires a dimension slice record".to_string(),
                                node: node_name.to_string(),
                                line: None,
                            });
                        }
                    }
                }
                type_errors.push(ClassifierDiagnostic {
                    rule: "OOF-TY0".to_string(),
                    message: "Unsupported index access".to_string(),
                    node: node_name.to_string(),
                    line: None,
                });
                TypedExpression {
                    resolved_type: self.type_ir(&serde_json::Value::String("Unknown".to_string())),
                    deps: Vec::new(),
                }
            }
            Expr::Lambda { params, body } => {
                let mut local_symbol_types = symbol_types.clone();
                for param in params {
                    local_symbol_types.insert(param.clone(), self.type_ir(&serde_json::Value::String("Integer".to_string())));
                }
                let mut temp_errors = Vec::new();
                let deps = match body.as_ref() {
                    ExprOrBlock::Expr(e) => {
                        let body_typed = self.infer_expr(e, &local_symbol_types, olap_env, type_shapes, &mut temp_errors, type_warnings, node_name, functions);
                        body_typed.deps
                    }
                    ExprOrBlock::Block(block) => {
                        let mut block_deps = Vec::new();
                        for stmt in &block.stmts {
                            match stmt {
                                Stmt::Let { name, expr } => {
                                    local_symbol_types.insert(name.clone(), self.type_ir(&serde_json::Value::String("Unknown".to_string())));
                                    let stmt_typed = self.infer_expr(expr, &local_symbol_types, olap_env, type_shapes, &mut temp_errors, type_warnings, node_name, functions);
                                    block_deps.extend(stmt_typed.deps);
                                }
                                Stmt::ExprStmt { expr } => {
                                    let stmt_typed = self.infer_expr(expr, &local_symbol_types, olap_env, type_shapes, &mut temp_errors, type_warnings, node_name, functions);
                                    block_deps.extend(stmt_typed.deps);
                                }
                            }
                        }
                        if let Some(re) = &block.return_expr {
                            let re_typed = self.infer_expr(re, &local_symbol_types, olap_env, type_shapes, &mut temp_errors, type_warnings, node_name, functions);
                            block_deps.extend(re_typed.deps);
                        }
                        block_deps
                    }
                };
                TypedExpression {
                    resolved_type: self.type_ir(&serde_json::Value::String("Unknown".to_string())),
                    deps,
                }
            }
            _ => {
                type_errors.push(ClassifierDiagnostic {
                    rule: "OOF-TY0".to_string(),
                    message: format!("Unsupported expression kind: {:?}", self.expr_kind(expr)),
                    node: node_name.to_string(),
                    line: None,
                });
                TypedExpression {
                    resolved_type: self.type_ir(&serde_json::Value::String("Unknown".to_string())),
                    deps: Vec::new(),
                }
            }
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
            Expr::Symbol { .. } => "symbol".to_string(),
            Expr::Error { .. } => "error".to_string(),
        }
    }

    fn operator_type(&self, op: &str, left: &serde_json::Value, right: &serde_json::Value, type_errors: &mut Vec<ClassifierDiagnostic>, node_name: &str) -> (String, serde_json::Value) {
        let left_name = self.type_name(left);
        let right_name = self.type_name(right);

        // Fixed-point Decimal rules:
        let is_left_decimal = left_name == "Decimal";
        let is_right_decimal = right_name == "Decimal";

        if is_left_decimal || is_right_decimal {
            if is_left_decimal && is_right_decimal {
                let left_scale = left.get("params").and_then(|p| p.as_array()).and_then(|p| p.get(0)).and_then(|p| p.get("name")).and_then(|n| n.as_str()).unwrap_or("0");
                let right_scale = right.get("params").and_then(|p| p.as_array()).and_then(|p| p.get(0)).and_then(|p| p.get("name")).and_then(|n| n.as_str()).unwrap_or("0");
                match op {
                    "+" | "-" => {
                        // Decimal scale mismatch in add/sub: OOF-TC5
                        if left_scale != right_scale {
                            type_errors.push(ClassifierDiagnostic {
                                rule: "OOF-TC5".to_string(),
                                message: format!("Decimal scale mismatch in operator '{}': left_scale={}, right_scale={}", op, left_scale, right_scale),
                                node: node_name.to_string(),
                                line: None,
                            });
                        }
                        return ("stdlib.decimal.add".to_string(), left.clone());
                    }
                    "*" => {
                        let l_s = left_scale.parse::<i64>().unwrap_or(0);
                        let r_s = right_scale.parse::<i64>().unwrap_or(0);
                        let sum_scale = l_s + r_s;
                        let mut sum_type = serde_json::Map::new();
                        sum_type.insert("name".to_string(), serde_json::Value::String("Decimal".to_string()));
                        let mut inner = serde_json::Map::new();
                        inner.insert("name".to_string(), serde_json::Value::String(sum_scale.to_string()));
                        inner.insert("params".to_string(), serde_json::Value::Array(Vec::new()));
                        sum_type.insert("params".to_string(), serde_json::Value::Array(vec![serde_json::Value::Object(inner)]));
                        return ("stdlib.decimal.mul".to_string(), serde_json::Value::Object(sum_type));
                    }
                    _ => {}
                }
            }
        }

        match op {
            "+" => {
                if left_name != "Integer" || right_name != "Integer" {
                    if left_name != "Unknown" && right_name != "Unknown" {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-TY0".to_string(),
                            message: format!("Type mismatch: expected Integer, got {}+{}", left_name, right_name),
                            node: node_name.to_string(),
                            line: None,
                        });
                    }
                }
                ("stdlib.integer.add".to_string(), self.type_ir(&serde_json::Value::String("Integer".to_string())))
            }
            "++" => {
                if left_name == "String" && right_name == "String" {
                    ("stdlib.string.concat".to_string(), self.type_ir(&serde_json::Value::String("String".to_string())))
                } else if left_name == "Collection" && right_name == "Collection" {
                    ("stdlib.collection.concat".to_string(), left.clone())
                } else {
                    if left_name != "Unknown" && right_name != "Unknown" {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-TY0".to_string(),
                            message: format!("Type mismatch: expected String/String or Collection/Collection, got {}++{}", left_name, right_name),
                            node: node_name.to_string(),
                            line: None,
                        });
                    }
                    ("stdlib.unsupported.++".to_string(), self.type_ir(&serde_json::Value::String("Unknown".to_string())))
                }
            }
            "-" => {
                if left_name != "Integer" || right_name != "Integer" {
                    if left_name != "Unknown" && right_name != "Unknown" {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-TY0".to_string(),
                            message: format!("Type mismatch: expected Integer, got {}-{}", left_name, right_name),
                            node: node_name.to_string(),
                            line: None,
                        });
                    }
                }
                ("stdlib.integer.sub".to_string(), self.type_ir(&serde_json::Value::String("Integer".to_string())))
            }
            "*" => {
                if left_name != "Integer" || right_name != "Integer" {
                    if left_name != "Unknown" && right_name != "Unknown" {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-TY0".to_string(),
                            message: format!("Type mismatch: expected Integer, got {}*{}", left_name, right_name),
                            node: node_name.to_string(),
                            line: None,
                        });
                    }
                }
                ("stdlib.integer.mul".to_string(), self.type_ir(&serde_json::Value::String("Integer".to_string())))
            }
            "/" => {
                if left_name != "Integer" || right_name != "Integer" {
                    if left_name != "Unknown" && right_name != "Unknown" {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-TY0".to_string(),
                            message: format!("Type mismatch: expected Integer, got {}/{}", left_name, right_name),
                            node: node_name.to_string(),
                            line: None,
                        });
                    }
                }
                ("stdlib.integer.div".to_string(), self.type_ir(&serde_json::Value::String("Integer".to_string())))
            }
            ">" => {
                if left_name != "Integer" || right_name != "Integer" {
                    if left_name != "Unknown" && right_name != "Unknown" {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-TY0".to_string(),
                            message: format!("Type mismatch: expected Integer, got {}+{}", left_name, right_name),
                            node: node_name.to_string(),
                            line: None,
                        });
                    }
                }
                ("stdlib.integer.gt".to_string(), self.type_ir(&serde_json::Value::String("Bool".to_string())))
            }
            "&&" => {
                if left_name != "Bool" || right_name != "Bool" {
                    if left_name != "Unknown" && right_name != "Unknown" {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-TY0".to_string(),
                            message: format!("Type mismatch: expected Bool, got {}+{}", left_name, right_name),
                            node: node_name.to_string(),
                            line: None,
                        });
                    }
                }
                ("stdlib.bool.and".to_string(), self.type_ir(&serde_json::Value::String("Bool".to_string())))
            }
            // LAB-RACK-P6: equality operator for primitive types.
            // Compatible pairs: (String, String), (Text, Text), (Text, String), (String, Text),
            //                   (Integer, Integer), (Bool, Bool).
            // Incompatible non-Unknown pairs emit OOF-TY0.
            // The VM binary_op handler dispatches on op=="==" using Rust Value equality —
            // no VM-side change needed; the TypeChecker gap was the sole blocker.
            "==" => {
                let compatible = matches!(
                    (left_name.as_str(), right_name.as_str()),
                    ("String",  "String")  |
                    ("Text",    "Text")    |
                    ("String",  "Text")    |
                    ("Text",    "String")  |
                    ("Integer", "Integer") |
                    ("Bool",    "Bool")    |
                    ("Unknown", _)         |
                    (_,         "Unknown")
                );
                if !compatible {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-TY0".to_string(),
                        message: format!("Type mismatch for ==: cannot compare {} with {}", left_name, right_name),
                        node: node_name.to_string(),
                        line: None,
                    });
                }
                ("stdlib.primitive.eq".to_string(), self.type_ir(&serde_json::Value::String("Bool".to_string())))
            }
            // LAB-RACK-P6: less-than for Integer only.
            // String/Text/Bool comparisons with < are not supported in v0 (OOF-TY0).
            // The VM binary_op handler already handles op=="<" for Integer — no VM change needed.
            "<" => {
                if (left_name != "Integer" || right_name != "Integer")
                    && left_name != "Unknown"
                    && right_name != "Unknown"
                {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-TY0".to_string(),
                        message: format!("Type mismatch for <: expected Integer on both sides, got {} < {}", left_name, right_name),
                        node: node_name.to_string(),
                        line: None,
                    });
                }
                ("stdlib.integer.lt".to_string(), self.type_ir(&serde_json::Value::String("Bool".to_string())))
            }
            _ => {
                type_errors.push(ClassifierDiagnostic {
                    rule: "OOF-TY0".to_string(),
                    message: format!("Unsupported operator: {}", op),
                    node: node_name.to_string(),
                    line: None,
                });
                (format!("stdlib.unsupported.{}", op), self.type_ir(&serde_json::Value::String("Unknown".to_string())))
            }
        }
    }

    fn dedupe_errors(&self, errors: &[ClassifierDiagnostic]) -> Vec<ClassifierDiagnostic> {
        let mut seen = HashSet::new();
        let mut deduped = Vec::new();
        for e in errors {
            let key = (e.rule.clone(), e.message.clone(), e.node.clone(), e.line);
            if !seen.contains(&key) {
                seen.insert(key);
                deduped.push(e.clone());
            }
        }
        deduped
    }
}

pub struct TypedExpression {
    pub resolved_type: serde_json::Value,
    pub deps: Vec<String>,
}

fn is_recursive(body: &crate::parser::BlockBody, fn_name: &str) -> bool {
    for stmt in &body.stmts {
        match stmt {
            Stmt::Let { expr, .. } => {
                if expr_has_call(expr, fn_name) {
                    return true;
                }
            }
            Stmt::ExprStmt { expr } => {
                if expr_has_call(expr, fn_name) {
                    return true;
                }
            }
        }
    }
    if let Some(re) = &body.return_expr {
        if expr_has_call(re, fn_name) {
            return true;
        }
    }
    false
}

fn expr_has_call(expr: &Expr, fn_name: &str) -> bool {
    match expr {
        Expr::Call { fn_name: callee, args } => {
            if callee == fn_name {
                return true;
            }
            args.iter().any(|arg| expr_has_call(arg, fn_name))
        }
        Expr::BinaryOp { left, right, .. } => {
            expr_has_call(left, fn_name) || expr_has_call(right, fn_name)
        }
        Expr::UnaryOp { operand, .. } => {
            expr_has_call(operand, fn_name)
        }
        Expr::FieldAccess { object, .. } => {
            expr_has_call(object, fn_name)
        }
        Expr::IndexAccess { object, index } => {
            expr_has_call(object, fn_name) || expr_has_call(index, fn_name)
        }
        Expr::SliceRecord { fields } => {
            fields.values().any(|v| expr_has_call(v, fn_name))
        }
        Expr::IfExpr { cond, then, else_block } => {
            expr_has_call(cond, fn_name) || 
            is_recursive(then, fn_name) || 
            else_block.as_ref().map_or(false, |eb| is_recursive(eb, fn_name))
        }
        Expr::Lambda { body, .. } => {
            match body.as_ref() {
                ExprOrBlock::Expr(e) => expr_has_call(e, fn_name),
                ExprOrBlock::Block(b) => is_recursive(b, fn_name),
            }
        }
        Expr::ArrayLiteral { items } => {
            items.iter().any(|item| expr_has_call(item, fn_name))
        }
        Expr::RecordLiteral { fields } => {
            fields.values().any(|v| expr_has_call(v, fn_name))
        }
        _ => false
    }
}

fn block_has_now(body: &crate::parser::BlockBody) -> bool {
    for stmt in &body.stmts {
        match stmt {
            Stmt::Let { expr, .. } => {
                if expr_has_now(expr) {
                    return true;
                }
            }
            Stmt::ExprStmt { expr } => {
                if expr_has_now(expr) {
                    return true;
                }
            }
        }
    }
    if let Some(re) = &body.return_expr {
        if expr_has_now(re) {
            return true;
        }
    }
    false
}

fn expr_has_now(expr: &Expr) -> bool {
    match expr {
        Expr::Ref { name } => name == "now",
        Expr::Call { fn_name, args } => fn_name == "now" || args.iter().any(expr_has_now),
        Expr::BinaryOp { left, right, .. } => expr_has_now(left) || expr_has_now(right),
        Expr::UnaryOp { operand, .. } => expr_has_now(operand),
        Expr::FieldAccess { object, .. } => expr_has_now(object),
        Expr::IndexAccess { object, index } => expr_has_now(object) || expr_has_now(index),
        Expr::SliceRecord { fields } => fields.values().any(expr_has_now),
        Expr::IfExpr { cond, then, else_block } => {
            expr_has_now(cond) || block_has_now(then) || else_block.as_ref().map_or(false, block_has_now)
        }
        Expr::Lambda { body, .. } => {
            match body.as_ref() {
                ExprOrBlock::Expr(e) => expr_has_now(e),
                ExprOrBlock::Block(b) => block_has_now(b),
            }
        }
        Expr::ArrayLiteral { items } => items.iter().any(expr_has_now),
        Expr::RecordLiteral { fields } => fields.values().any(expr_has_now),
        _ => false,
    }
}

/// OOF-R3 syntactic_v0: returns true if `expr` syntactically decreases `variant_name`.
/// Accepted patterns:
///   variant_name - N   (N > 0 integer literal)
///   variant_name.tail
///   variant_name.rest
fn syntactic_decrease(expr: &Expr, variant_name: &str) -> bool {
    match expr {
        Expr::BinaryOp { op, left, right } => {
            if op != "-" {
                return false;
            }
            let left_is_var = matches!(left.as_ref(), Expr::Ref { name } if name == variant_name);
            let right_is_pos_int = match right.as_ref() {
                Expr::Literal { value, type_tag } => {
                    type_tag == "Integer" && value.as_i64().map_or(false, |n| n > 0)
                }
                _ => false,
            };
            left_is_var && right_is_pos_int
        }
        Expr::FieldAccess { object, field } => {
            let obj_is_var = matches!(object.as_ref(), Expr::Ref { name } if name == variant_name);
            obj_is_var && (field == "tail" || field == "rest")
        }
        _ => false,
    }
}

/// OOF-R3: produce a human-readable description of an expression for error messages.
fn syntactic_arg_desc(expr: &Expr) -> String {
    match expr {
        Expr::Ref { name } => name.clone(),
        Expr::Literal { value, .. } => value.to_string(),
        Expr::BinaryOp { op, left, right } => {
            format!("{} {} {}", syntactic_arg_desc(left), op, syntactic_arg_desc(right))
        }
        Expr::FieldAccess { object, field } => {
            format!("{}.{}", syntactic_arg_desc(object), field)
        }
        Expr::Call { fn_name, args } => {
            let arg_strs: Vec<String> = args.iter().map(syntactic_arg_desc).collect();
            format!("{}({})", fn_name, arg_strs.join(", "))
        }
        _ => "expr".to_string(),
    }
}
