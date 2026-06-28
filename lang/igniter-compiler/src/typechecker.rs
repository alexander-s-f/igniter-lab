use crate::classifier::{
    ClassifiedContract, ClassifiedDecl, ClassifiedProgram, ClassifiedSymbol, ClassifierDiagnostic,
    DependencyGraph,
};
use crate::parser::{
    Expr, ExprOrBlock, FunctionDecl, OlapPointDecl, Param, Stmt, TypeRef, WindowValue,
};
use sha2::{Digest, Sha256};
use std::collections::{HashMap, HashSet};

#[path = "typechecker/stdlib_calls.rs"]
mod stdlib_calls;

// LAB-IGNITER-COMPILER-TYPE-IR-ENUM-P5: strongly-typed internal type model.
#[path = "typechecker/type_ir.rs"]
mod type_ir;
use type_ir::IgType;

// ── PROP-044 P5: variant shapes type alias ────────────────────────────────────
// variant_name → arm_name → field_name → type_ir (serde_json::Value)
type VariantShapes = HashMap<String, HashMap<String, HashMap<String, serde_json::Value>>>;

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
    pub dv: String,       // dotted-path variant, e.g. "items.tail"
    pub subject: String,  // e.g. "items"
    pub accessor: String, // e.g. "tail"
    pub trust: String,
    pub source: String,
}

#[derive(Debug, Clone, PartialEq)]
pub enum T2Kind {
    T2Pass, // registered relation — SIR structural_size_v1
    T2R8,   // missing relation — OOF-R8
    T2R3,   // numeric accessor — OOF-R3
}

// ── LAB-RACK-P11: module contract registry ────────────────────────────────────

/// Registry entry for a same-module contract — used to resolve literal callee names
/// in `call_contract("Name", ...)` at compile time.
/// Built once in `typecheck()` before the contract loop (mirrors build_size_registry).
#[derive(Debug, Clone)]
pub struct ContractRegistryEntry {
    pub modifier: String,
    pub input_count: usize,
    pub input_names: Vec<String>,
    pub input_types: Vec<serde_json::Value>,
    pub single_output_type: Option<serde_json::Value>, // None if 0 or >1 outputs
    pub single_output_name: Option<String>,
    pub contract_name: String,
}

/// Build STDLIB_SIZE_REGISTRY: hardcoded stdlib_certified entries.
/// Only Collection.tail and Collection.rest are certified in v1.
fn stdlib_size_registry() -> HashMap<(String, String), T2RegistryEntry> {
    let mut m = HashMap::new();
    m.insert(
        ("Collection".to_string(), "tail".to_string()),
        T2RegistryEntry {
            trust: "stdlib_certified".to_string(),
            source: "compiler_builtin".to_string(),
        },
    );
    m.insert(
        ("Collection".to_string(), "rest".to_string()),
        T2RegistryEntry {
            trust: "stdlib_certified".to_string(),
            source: "compiler_builtin".to_string(),
        },
    );
    m
}

/// Numeric accessors are T3 territory — route to OOF-R3, not OOF-R8.
/// Closed list in v1; not user-extensible.
const NUMERIC_ACCESSORS: &[&str] = &[
    "count",
    "length",
    "size",
    "total_count",
    "num_items",
    "num_elements",
];

// ── PROP-042 T3: numeric measure expressions ─────────────────────────────────

/// A single NUMERIC_MEASURE_BUILTINS v0 entry.
/// Only count(Collection[T]) is recognized in v0.
/// size / length / byte_length / rune_length / grapheme_length / user-defined → OOF-R10.
#[derive(Debug, Clone)]
pub struct T3BuiltinEntry {
    pub qualified_name: &'static str, // "stdlib.collection.count"
    pub trust: &'static str,          // "stdlib_numeric_certified"
    pub source: &'static str,         // "compiler_builtin"
}

/// T3 context for a contract currently being typechecked.
#[derive(Debug, Clone)]
pub struct T3Context {
    pub dv: String,       // "count(items)"
    pub fn_name: String,  // "count"
    pub arg_name: String, // "items"
    pub builtin: T3BuiltinEntry,
}

/// NUMERIC_MEASURE_BUILTINS v0.
/// Tuple: (fn_name, qualified_name, trust, source).
const NUMERIC_MEASURE_BUILTINS_V0: &[(&str, &str, &str, &str)] = &[(
    "count",
    "stdlib.collection.count",
    "stdlib_numeric_certified",
    "compiler_builtin",
)];

/// Regex-free T3 function-call form detection.
/// Returns (fn_name, arg_name) when variant matches exactly "fn(arg)".
fn parse_t3_call_form(variant: &str) -> Option<(&str, &str)> {
    let lparen = variant.find('(')?;
    let rparen = variant.rfind(')')?;
    if rparen != variant.len() - 1 {
        return None;
    }
    let fn_name = &variant[..lparen];
    let arg_name = &variant[lparen + 1..rparen];
    // Both parts must be non-empty and word-only (no dots, spaces, parens)
    if fn_name.is_empty() || arg_name.is_empty() {
        return None;
    }
    if !fn_name
        .bytes()
        .all(|b| b.is_ascii_alphanumeric() || b == b'_')
    {
        return None;
    }
    if !arg_name
        .bytes()
        .all(|b| b.is_ascii_alphanumeric() || b == b'_')
    {
        return None;
    }
    Some((fn_name, arg_name))
}

// ── end PROP-042 T3 / end PROP-041 T2 ────────────────────────────────────────

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
    pub entrypoint: Option<TypedEntrypoint>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub type_warnings: Option<Vec<ClassifierDiagnostic>>,
    pub pass_result: String,
    /// PROP-044 P5: SIR-ready variant declarations (emitted at program level).
    /// Built from classified.variant_declarations after variant_shapes pass.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub variant_declarations: Vec<serde_json::Value>,
    /// LAB-FUNCTION-SIR-RUNTIME-P1: app-local `def` functions (parser JSON), carried to the
    /// emitter so their bodies are materialized as executable SIR / VM function registry.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub functions: Vec<serde_json::Value>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct TypedEntrypoint {
    pub kind: String,
    pub target: String,
    pub qualified: bool,
    pub source_span: crate::parser::SourceSpan,
    pub resolved_contract: String,
    pub resolved_contract_id: String,
    pub contract_fragment_class: String,
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
    /// PROP-042 T3: function-call form variant when T3 dispatch passes.
    /// Present only when count(items) recognized and call-site obligation met.
    /// Mutually exclusive with decreases_variant_t2 for the same contract.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub decreases_variant_t3: Option<String>,
    /// PROP-042 T3: numeric measure evidence for numeric_measure_v0 SemanticIR emission.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub numeric_measure_evidence: Option<serde_json::Value>,
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
    /// PROP-044 P5: SIR-ready enriched expression (variant_construct / match_node).
    /// When Some, the emitter uses this in place of json!(decl.expr) for the compute node.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub annotated_expr: Option<serde_json::Value>,
}

pub struct TypeChecker {
    version: String,
    /// PROP-042 T3: current contract's T3 context, if T3 dispatch succeeded.
    /// Set at start of each typecheck_contract call; cleared on exit.
    /// Used by infer_expr to suppress OOF-P1 for field accesses on the T3-measured input.
    t3_context: std::cell::RefCell<Option<T3Context>>,
    /// PROP-044 P5: module-level variant shapes.
    /// Built once in typecheck() from classified.variant_declarations; shared across all contracts.
    /// variant_name → arm_name → field_name → type_ir
    variant_shapes: std::cell::RefCell<VariantShapes>,
    /// LANG-SUMTYPE-CONSTRUCT-MATCH-P3: expected-type hints for sealed constructors.
    /// Reset per-contract; maps output/compute decl name → declared Option/Result
    /// type_ir. Read by infer_sealed_construct (via node_name) to recover the param
    /// none()/ok()/err() cannot infer from their arguments.
    sealed_output_hints: std::cell::RefCell<HashMap<String, serde_json::Value>>,
    /// LANG-SUMTYPE-COLLECT-P3: expected element-type hints for filter_map output
    /// context (fallback B2). Reset per-contract; maps output/compute decl name →
    /// the element type U of a declared Collection[U]. Read by the filter_map arm to
    /// recover U when a parametric `match` callback collapses to bare Option.
    collection_elem_hints: std::cell::RefCell<HashMap<String, serde_json::Value>>,
}

impl TypeChecker {
    pub fn new() -> Self {
        Self {
            version: "typed-pass-executable-proof-v0".to_string(),
            t3_context: std::cell::RefCell::new(None),
            variant_shapes: std::cell::RefCell::new(HashMap::new()),
            sealed_output_hints: std::cell::RefCell::new(HashMap::new()),
            collection_elem_hints: std::cell::RefCell::new(HashMap::new()),
        }
    }

    /// LANG-SUMTYPE-CONSTRUCT-MATCH-P3: sealed built-in sumtype source constructors
    /// (function-form only, v0). Lowered to sealed `variant_construct` SIR nodes.
    fn is_sealed_constructor(name: &str) -> bool {
        matches!(name, "some" | "none" | "ok" | "err")
    }

    /// Admission for sealed built-in sumtypes. User variants take precedence: a user
    /// `variant Option {…}` shadows the built-in. Registration here IS the OOF-KIND4
    /// relax — only Option/Result are admitted; arbitrary named types stay rejected.
    fn sealed_builtin(&self, name: &str) -> bool {
        !self.variant_shapes.borrow().contains_key(name) && matches!(name, "Option" | "Result")
    }

    /// Declared arms (arm→field→type) for a match subject: user shapes if present,
    /// else the sealed built-in registry. Field types are Unknown placeholders for
    /// sealed types; concrete binding types come from sealed_arm_field_types.
    fn declared_arms_for(&self, name: &str) -> HashMap<String, HashMap<String, serde_json::Value>> {
        if let Some(arms) = self.variant_shapes.borrow().get(name) {
            return arms.clone();
        }
        let unknown = self.type_ir(&serde_json::Value::String("Unknown".to_string()));
        let mut arms: HashMap<String, HashMap<String, serde_json::Value>> = HashMap::new();
        match name {
            "Option" => {
                let mut some = HashMap::new();
                some.insert("value".to_string(), unknown.clone());
                arms.insert("Some".to_string(), some);
                arms.insert("None".to_string(), HashMap::new());
            }
            "Result" => {
                let mut ok = HashMap::new();
                ok.insert("value".to_string(), unknown.clone());
                arms.insert("Ok".to_string(), ok);
                let mut err = HashMap::new();
                err.insert("error".to_string(), unknown);
                arms.insert("Err".to_string(), err);
            }
            _ => {}
        }
        arms
    }

    /// Concrete payload types for a sealed match arm, substituted from the subject's
    /// type params: Option[P0] → Some{value:P0}; Result[P0,P1] → Ok{value:P0},
    /// Err{error:P1}. Missing params degrade to Unknown.
    fn sealed_arm_field_types(
        &self,
        subject_rt: &serde_json::Value,
        arm_name: &str,
    ) -> HashMap<String, serde_json::Value> {
        let unknown = self.type_ir(&serde_json::Value::String("Unknown".to_string()));
        let p0 = self
            .get_param(subject_rt, 0)
            .unwrap_or_else(|| unknown.clone());
        let p1 = self
            .get_param(subject_rt, 1)
            .unwrap_or_else(|| unknown.clone());
        let mut m = HashMap::new();
        match (self.type_name(subject_rt).as_str(), arm_name) {
            ("Option", "Some") => {
                m.insert("value".to_string(), p0);
            }
            ("Result", "Ok") => {
                m.insert("value".to_string(), p0);
            }
            ("Result", "Err") => {
                m.insert("error".to_string(), p1);
            }
            _ => {}
        }
        m
    }

    pub fn typecheck(
        &self,
        classified: &ClassifiedProgram,
        functions: &[crate::parser::FunctionDecl],
    ) -> TypedProgram {
        let type_shapes = self.build_type_shapes(classified);
        let mut typed_contracts = Vec::new();
        let mut type_errors = Vec::new();
        let mut type_warnings = Vec::new();

        // Build OLAP points environment
        let olap_env = self.build_olap_env(classified.olap_points.as_ref().unwrap_or(&Vec::new()));

        // PROP-041 T2: build size-relation registry (stdlib + user-declared).
        // Built once before the contracts loop so all contracts share the same registry.
        let size_registry = self.build_size_registry(classified);

        // PROP-044 P5: build variant_shapes from module-level variant declarations.
        // Stored on TypeChecker via RefCell so infer_expr can access it without arg drilling.
        let vshapes = self.build_variant_shapes(classified);
        *self.variant_shapes.borrow_mut() = vshapes;

        // Build SIR-ready variant_declarations for TypedProgram emission.
        let variant_declarations = self.build_variant_declarations_sir(classified);

        // LAB-RACK-P11: build module contract registry for literal callee resolution.
        // Built once before the loop so all contracts see the full module.
        let contract_registry = self.build_contract_registry(classified);

        // PROP-044-P9: OOF-KIND6 — reserved __* field names in module-level declarations.
        // type declarations
        for t in &classified.type_declarations {
            for f in &t.fields {
                if f.name.starts_with("__") {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-KIND6".to_string(),
                        message: format!(
                            "Field '{}' in type '{}' uses reserved compiler prefix '__' (compiler-owned variant runtime field)",
                            f.name, t.name
                        ),
                        node: t.name.clone(),
                        line: None,
                    });
                }
            }
        }
        // variant arm fields
        for vd in &classified.variant_declarations {
            for arm in &vd.arms {
                for field in &arm.fields {
                    if field.name.starts_with("__") {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-KIND6".to_string(),
                            message: format!(
                                "Field '{}' in variant '{}' arm '{}' uses reserved compiler prefix '__'",
                                field.name, vd.name, arm.name
                            ),
                            node: vd.name.clone(),
                            line: None,
                        });
                    }
                }
            }
        }

        for contract in &classified.contracts {
            let mut tc = self.typecheck_contract(
                contract,
                &type_shapes,
                &olap_env,
                classified
                    .assumption_registry
                    .as_ref()
                    .unwrap_or(&Vec::new()),
                functions,
                &size_registry,
                &contract_registry,
            );
            type_errors.append(&mut tc.type_errors.clone());
            if let Some(mut w) = tc.type_warnings.clone() {
                type_warnings.append(&mut w);
            }
            typed_contracts.push(tc);
        }

        let (entrypoint_errors, entrypoint) = self.validate_entrypoint(classified);
        type_errors.extend(entrypoint_errors);

        // Validate recursive functions specify decreases fuel: T1.5
        // SCC-based gate: every member of a nontrivial SCC must declare `decreases fuel`.
        {
            let fn_names: HashSet<String> = functions.iter().map(|f| f.name.clone()).collect();
            let mut fn_names_sorted: Vec<String> = fn_names.iter().cloned().collect();
            fn_names_sorted.sort();
            let fn_calls: HashMap<String, Vec<String>> = functions
                .iter()
                .map(|f| (f.name.clone(), collect_fn_calls(&f.body, &fn_names)))
                .collect();
            let sccs = tarjan_sccs(&fn_names_sorted, &fn_calls);
            let fn_map: HashMap<&str, &FunctionDecl> =
                functions.iter().map(|f| (f.name.as_str(), f)).collect();
            for scc in &sccs {
                let is_nontrivial = scc.len() > 1
                    || fn_calls
                        .get(scc[0].as_str())
                        .map_or(false, |c| c.contains(&scc[0]));
                if !is_nontrivial {
                    continue;
                }
                for fn_name in scc {
                    if let Some(f) = fn_map.get(fn_name.as_str()) {
                        if f.decreases.as_deref() != Some("fuel") {
                            type_errors.push(ClassifierDiagnostic {
                                rule: "OOF-L4".to_string(),
                                message: format!(
                                    "Recursive function '{}' must specify 'decreases fuel'",
                                    fn_name
                                ),
                                node: fn_name.clone(),
                                line: None,
                            });
                        }
                    }
                }
            }
        }

        // NW-T2-4 (compiler §B-U5): interprocedural effect summary.
        // A `pure` contract must not launder ambient `stdlib.IO.*` through an app-local `def`.
        // The classifier only scans contract bodies for inline `stdlib.IO.` prefixes, so a
        // helper `def` that performs I/O presents as a plain call and slips past OOF-M1. Here we
        // compute a transitive per-`def` `ambient_io` summary over the same call graph used for
        // the OOF-L4 recursion gate, then flag any `pure` contract that reaches an effectful def.
        {
            let ambient_io = compute_ambient_io_summary(functions);
            if ambient_io.values().any(|v| *v) {
                let fn_names: HashSet<String> = functions.iter().map(|f| f.name.clone()).collect();
                for contract in &classified.contracts {
                    if contract.modifier != "pure" {
                        continue;
                    }
                    // Collect every app-local def called anywhere in the contract body
                    // (top-level nodes plus loop / service-loop inner nodes).
                    let mut called: HashSet<String> = HashSet::new();
                    for node in &contract.declarations {
                        if let Some(expr) = &node.expr {
                            expr_collect_calls(expr, &fn_names, &mut called);
                        }
                        if let Some(body_nodes) = &node.body_nodes {
                            for inner in body_nodes {
                                if let Some(expr) = &inner.expr {
                                    expr_collect_calls(expr, &fn_names, &mut called);
                                }
                            }
                        }
                    }
                    let mut leaking: Vec<String> = called
                        .into_iter()
                        .filter(|d| *ambient_io.get(d).unwrap_or(&false))
                        .collect();
                    leaking.sort();
                    for def_name in leaking {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-M1".to_string(),
                            message: format!(
                                "pure contract '{}' performs ambient I/O transitively through helper def '{}' (a stdlib.IO.* sink is reachable via the call graph); pure contracts cannot launder effects through a def — use 'observed' for read-only access or move the I/O behind a declared capability",
                                contract.name, def_name
                            ),
                            node: contract.name.clone(),
                            line: None,
                        });
                    }
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

        let source_hash = classified.source_hash.as_deref().unwrap_or("");
        let seed = format!("{}|{}|{}", classified.program_id, source_hash, self.version);
        let program_id = format!("typed_pass/{:x}", Sha256::digest(seed.as_bytes()));

        let pass_result = if type_errors.iter().any(|d| d.rule.starts_with("OOF-")) {
            "oof".to_string()
        } else {
            "ok".to_string()
        };

        TypedProgram {
            kind: "typed_program".to_string(),
            typechecker_version: self.version.clone(),
            program_id: program_id[0..27].to_string(),
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
            olap_points: if olap_env.is_empty() {
                None
            } else {
                Some(
                    olap_env
                        .values()
                        .map(|v| v.get("semantic_node").unwrap().clone())
                        .collect(),
                )
            },
            entrypoint,
            type_warnings: if type_warnings.is_empty() {
                None
            } else {
                Some(self.dedupe_errors(&type_warnings))
            },
            pass_result,
            variant_declarations,
            // LAB-FUNCTION-SIR-RUNTIME-P1: carry app-local def functions (parser JSON) forward.
            functions: functions
                .iter()
                .map(|f| serde_json::to_value(f).unwrap_or(serde_json::Value::Null))
                .collect(),
        }
    }

    fn build_type_shapes(
        &self,
        classified: &ClassifiedProgram,
    ) -> HashMap<String, HashMap<String, serde_json::Value>> {
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

    fn validate_entrypoint(
        &self,
        classified: &ClassifiedProgram,
    ) -> (Vec<ClassifierDiagnostic>, Option<TypedEntrypoint>) {
        let entrypoint = match &classified.entrypoint {
            Some(e) => e,
            None => return (Vec::new(), None),
        };

        let target = entrypoint.target.clone();
        if let Some(contract) = classified
            .contracts
            .iter()
            .find(|c| target == c.name || target == c.contract_id)
        {
            return (
                Vec::new(),
                Some(TypedEntrypoint {
                    kind: "entrypoint_decl".to_string(),
                    target,
                    qualified: entrypoint.qualified,
                    source_span: entrypoint.source_span.clone(),
                    resolved_contract: contract.name.clone(),
                    resolved_contract_id: contract.contract_id.clone(),
                    contract_fragment_class: contract.fragment_class.clone(),
                }),
            );
        }

        if classified
            .type_declarations
            .iter()
            .any(|t| t.name == target)
        {
            return (
                vec![ClassifierDiagnostic {
                    rule: "OOF-EP5".to_string(),
                    message: format!("entrypoint target '{}' is a type, not a contract", target),
                    node: target,
                    line: Some(entrypoint.source_span.line),
                }],
                None,
            );
        }

        (
            vec![ClassifierDiagnostic {
                rule: "OOF-EP2".to_string(),
                message: format!(
                    "entrypoint target '{}' does not resolve to a contract",
                    target
                ),
                node: target,
                line: Some(entrypoint.source_span.line),
            }],
            None,
        )
    }

    fn build_olap_env(
        &self,
        olaps: &[OlapPointDecl],
    ) -> HashMap<String, HashMap<String, serde_json::Value>> {
        let mut env = HashMap::new();
        for point in olaps {
            let mut entry = HashMap::new();
            let name = point.name.clone();

            let dimensions: HashMap<String, serde_json::Value> = point
                .dimensions
                .iter()
                .map(|(k, v)| (k.clone(), self.type_ir(&serde_json::to_value(v).unwrap())))
                .collect();

            let measure_type = self.type_ir(&serde_json::to_value(&point.measure).unwrap());

            // Build structural OLAP type: OLAPPoint[Measure, DimsRecord[Dimensions]]
            let mut olap_type = serde_json::Map::new();
            olap_type.insert(
                "name".to_string(),
                serde_json::Value::String("OLAPPoint".to_string()),
            );
            let mut params = Vec::new();
            params.push(measure_type.clone());

            let mut dims_record = serde_json::Map::new();
            dims_record.insert(
                "name".to_string(),
                serde_json::Value::String("DimsRecord".to_string()),
            );
            dims_record.insert("params".to_string(), serde_json::Value::Array(Vec::new()));
            dims_record.insert(
                "dims".to_string(),
                serde_json::to_value(&dimensions).unwrap(),
            );

            params.push(serde_json::Value::Object(dims_record));
            olap_type.insert("params".to_string(), serde_json::Value::Array(params));

            let mut semantic_node = serde_json::Map::new();
            semantic_node.insert(
                "kind".to_string(),
                serde_json::Value::String("olap_point_decl".to_string()),
            );
            semantic_node.insert("name".to_string(), serde_json::Value::String(name.clone()));
            semantic_node.insert(
                "dimensions".to_string(),
                serde_json::to_value(&point.dimensions).unwrap(),
            );
            semantic_node.insert(
                "measure_type".to_string(),
                serde_json::to_value(&point.measure).unwrap(),
            );
            semantic_node.insert(
                "granularity".to_string(),
                serde_json::to_value(&point.granularity).unwrap(),
            );
            semantic_node.insert(
                "indexed".to_string(),
                serde_json::to_value(&point.indexed).unwrap(),
            );

            entry.insert("name".to_string(), serde_json::Value::String(name.clone()));
            entry.insert("type".to_string(), serde_json::Value::Object(olap_type));
            entry.insert(
                "dimensions".to_string(),
                serde_json::to_value(dimensions).unwrap(),
            );
            entry.insert("measure_type".to_string(), measure_type);
            entry.insert(
                "granularity".to_string(),
                serde_json::to_value(&point.granularity).unwrap(),
            );
            entry.insert(
                "indexed".to_string(),
                serde_json::to_value(&point.indexed).unwrap(),
            );
            entry.insert(
                "semantic_node".to_string(),
                serde_json::Value::Object(semantic_node),
            );

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
        contract_registry: &HashMap<String, ContractRegistryEntry>,
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
            fields.insert(
                "kind".to_string(),
                self.type_ir(&serde_json::Value::String("Symbol".to_string())),
            );
            fields.insert(
                "statement".to_string(),
                self.type_ir(&serde_json::Value::String("String".to_string())),
            );
            fields.insert(
                "strength".to_string(),
                self.type_ir(&serde_json::Value::String("Decimal".to_string())),
            );
            fields.insert(
                "source".to_string(),
                self.type_ir(&serde_json::Value::String("String".to_string())),
            );
            local_type_shapes.insert("Assumption".to_string(), fields);
        }
        let mut clock_tick_fields = HashMap::new();
        clock_tick_fields.insert(
            "time".to_string(),
            self.type_ir(&serde_json::Value::String("Integer".to_string())),
        );
        local_type_shapes.insert("ClockTick".to_string(), clock_tick_fields);

        // Validate assumptions strength at typecheck stage: TASSUMP-1
        for entry in assumptions {
            if let Some(fields) = entry.get("fields") {
                if let Some(strength_val) = fields.get("strength") {
                    if let Some(strength) = strength_val.as_f64() {
                        if strength < 0.0 || strength > 1.0 {
                            type_errors.push(ClassifierDiagnostic {
                                rule: "TASSUMP-1".to_string(),
                                message: "assumption strength must be between 0.0 and 1.0"
                                    .to_string(),
                                node: format!(
                                    "assumption:{}",
                                    entry
                                        .get("name")
                                        .and_then(|n| n.as_str())
                                        .unwrap_or_default()
                                ),
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
        let recur_input_names: Vec<String> = classified
            .declarations
            .iter()
            .filter(|d| d.kind == "input")
            .map(|d| d.name.clone())
            .collect();
        let recur_output_count = classified
            .declarations
            .iter()
            .filter(|d| d.kind == "output")
            .count();
        // The single output type (for recur() return-type inference)
        let recur_output_type: Option<serde_json::Value> = if recur_output_count == 1 {
            classified
                .declarations
                .iter()
                .find(|d| d.kind == "output")
                .and_then(|d| d.type_annotation.as_ref())
                .map(|ta| self.type_ir(ta))
        } else {
            None
        };

        // PROP-039 OOF-R3 / PROP-041 T2 / PROP-042 T3: decreases variant dispatch
        // Priority chain:
        //   T3: function-call form  fn(arg)       → numeric_measure_v0  (OOF-R10 / OOF-R11)
        //   T2: dotted-path         sub.field      → structural_size_v1  (OOF-R3 / OOF-R8)
        //   T1: simple identifier   n              → syntactic_v0
        // Reset per-contract T3 context on the TypeChecker struct (mirrors Ruby @t3_context = nil)
        *self.t3_context.borrow_mut() = None;

        let t2_context: Option<T2Context>;
        let t3_context: Option<T3Context>;
        let clean_decreases_variant: Option<String> = match &classified.decreases_variant {
            Some(v) if parse_t3_call_form(v).is_some() => {
                // PROP-042 T3 dispatch
                let ctx = self.handle_t3_variant(v, classified, &mut type_errors, size_registry);
                // Store in struct so infer_expr can access it for OOF-P1 suppression
                *self.t3_context.borrow_mut() = ctx.clone();
                t3_context = ctx;
                t2_context = None;
                None // function-call form never kept as a raw T1 variant
            }
            Some(v) if v.contains('.') => {
                // PROP-041 T2 dispatch
                let ctx = self.handle_t2_variant(v, classified, &mut type_errors, size_registry);
                t2_context = ctx;
                t3_context = None;
                None // dotted-path never kept as a raw variant in @recur_context
            }
            Some(v) => {
                t2_context = None;
                t3_context = None;
                Some(v.clone())
            }
            None => {
                t2_context = None;
                t3_context = None;
                None
            }
        };
        // Positional index of the decreases variant in the input list
        let decreases_variant_pos: Option<usize> = clean_decreases_variant
            .as_ref()
            .and_then(|v| recur_input_names.iter().position(|n| n == v));

        // LAB-RACK-P13: pre-scan output declarations to build a map of
        // compute-node-name → expected named record type.  Used in the compute
        // phase to validate RecordLiteral field shapes against the declared
        // output type annotation before the output check runs.
        // Only entries whose expected type name appears in local_type_shapes are
        // recorded — primitive / Collection / Unknown expected types are excluded.
        let output_type_hints: HashMap<String, String> = classified
            .declarations
            .iter()
            .filter(|d| d.kind == "output")
            .filter_map(|d| {
                let ann = d.type_annotation.as_ref()?;
                let type_name = self.type_name(&self.type_ir(ann));
                if local_type_shapes.contains_key(&type_name) {
                    Some((d.name.clone(), type_name))
                } else {
                    None
                }
            })
            .collect();

        // LAB-TC-ARRAY-P1: pre-scan output declarations for Collection[T] element
        // type hints. Maps compute-node-name → element type IR (T). Used in the
        // compute phase to contextually type an ArrayLiteral expression that flows
        // into a declared `output x : Collection[T]` position (analogous to the
        // RecordLiteral nominal upgrade above). Only Collection outputs are
        // recorded; non-Collection outputs are excluded. The behavior is
        // contextual: a free-standing array literal with no Collection output
        // hint stays Unknown (see the ArrayLiteral arm in infer_expr).
        let mut collection_output_hints: HashMap<String, serde_json::Value> = classified
            .declarations
            .iter()
            .filter(|d| d.kind == "output")
            .filter_map(|d| {
                let ann = d.type_annotation.as_ref()?;
                let ir = self.type_ir(ann);
                if self.type_name(&ir) != "Collection" {
                    return None;
                }
                let elem = self.get_param(&ir, 0)?;
                Some((d.name.clone(), elem))
            })
            .collect();

        // LANG-SUMTYPE-CONSTRUCT-MATCH-P3: per-contract expected-type hints for sealed
        // constructors. Pre-scan output/compute decls annotated Option[...]/Result[...];
        // keyed by name (an output and its producing compute share a name). Read by
        // infer_sealed_construct (via node_name) to recover the param none()/ok()/err()
        // cannot infer from arguments. Reset per-contract via the RefCell.
        {
            let mut sealed_hints: HashMap<String, serde_json::Value> = HashMap::new();
            for d in &classified.declarations {
                if d.kind != "output" && d.kind != "compute" {
                    continue;
                }
                let Some(ann) = d.type_annotation.as_ref() else {
                    continue;
                };
                let ir = self.type_ir(ann);
                let tn = self.type_name(&ir);
                if tn == "Option" || tn == "Result" {
                    sealed_hints.insert(d.name.clone(), ir);
                }
            }
            *self.sealed_output_hints.borrow_mut() = sealed_hints;
        }

        // LANG-SUMTYPE-COLLECT-P3: per-contract element-type hints for filter_map
        // (route B2). Pre-scan output/compute decls annotated Collection[U]; keyed by
        // name. Read by the filter_map arm (via node_name) to recover U and to
        // temp-install an Option[U] sealed hint while inferring the callback body.
        {
            let mut elem_hints: HashMap<String, serde_json::Value> = HashMap::new();
            for d in &classified.declarations {
                if d.kind != "output" && d.kind != "compute" {
                    continue;
                }
                let Some(ann) = d.type_annotation.as_ref() else {
                    continue;
                };
                let ir = self.type_ir(ann);
                if self.type_name(&ir) != "Collection" {
                    continue;
                }
                if let Some(elem) = self.get_param(&ir, 0) {
                    elem_hints.insert(d.name.clone(), elem);
                }
            }
            *self.collection_elem_hints.borrow_mut() = elem_hints;
        }

        // LAB-TC-ARRAY-P2: pre-scan record-field positions for Collection[T] element
        // hints. When a compute node's expr is a RecordLiteral whose declared output
        // type is a named record (output_type_hints), each field that is a bare Ref
        // to another compute node contributes a hint: if the record type declares
        // that field as `Collection[T]`, the referenced compute node gets element
        // hint T. This lets an intermediate array-literal compute that feeds a
        // typed record field (e.g. `QueryPlan.filters : Collection[FilterPredicate]`)
        // receive contextual typing from the field position — closing the
        // non-blocking gap left open by LAB-TC-ARRAY-P1.
        //
        // The scan is order-independent (it walks all declarations up front), and
        // the referenced compute is processed before the enclosing record literal in
        // dependency order, so the upgrade is in-place when the array literal node is
        // typed — no retroactive symbol mutation is required. Output-context hints
        // (P1) take precedence; field-context hints fill names not already covered.
        for d in &classified.declarations {
            if d.kind != "compute" && d.kind != "snapshot" {
                continue;
            }
            let Some(record_type_name) = output_type_hints.get(&d.name) else {
                continue;
            };
            let Some(Expr::RecordLiteral { fields }) = d.expr.as_ref() else {
                continue;
            };
            let Some(shape) = local_type_shapes.get(record_type_name.as_str()) else {
                continue;
            };
            for (field_name, field_expr) in fields {
                if let Expr::Ref { name: ref_name } = field_expr {
                    if let Some(field_type_ir) = shape.get(field_name) {
                        let field_ir = self.type_ir(field_type_ir);
                        if self.type_name(&field_ir) == "Collection" {
                            if let Some(elem) = self.get_param(&field_ir, 0) {
                                collection_output_hints
                                    .entry(ref_name.clone())
                                    .or_insert(elem);
                            }
                        }
                    }
                }
            }
        }

        // LAB-MAP-RUST-P1: OOF-MAP1/2/3 annotation scan across all declarations
        for decl in &classified.declarations {
            if let Some(ann) = &decl.type_annotation {
                self.check_map_annotation(ann, &decl.name, &decl.kind, &mut type_errors);
            }
        }

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
                    let loop_class_opt = decl
                        .options
                        .as_ref()
                        .and_then(|o| o.get("loop_class"))
                        .and_then(|v| {
                            if let crate::parser::WindowValue::Str(s) = v {
                                Some(s.clone())
                            } else {
                                None
                            }
                        });
                    let is_finite_loop = loop_class_opt.as_deref() == Some("finite");

                    let mut loop_var_types = HashMap::new();
                    if let Some(Expr::Ref { name: ref_name }) = &decl.expr {
                        let item_ty = if let Some(coll_ty) = symbol_types.get(ref_name) {
                            let ty_name = self.type_name(coll_ty);
                            if ty_name == "Array" || ty_name == "Collection" {
                                let param_val = coll_ty
                                    .get("params")
                                    .and_then(|p| p.as_array())
                                    .and_then(|arr| arr.first())
                                    .cloned()
                                    .unwrap_or_else(|| {
                                        serde_json::Value::String("Unknown".to_string())
                                    });
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
                        let item_var = decl
                            .options
                            .as_ref()
                            .and_then(|o| o.get("item"))
                            .and_then(|v| {
                                if let crate::parser::WindowValue::Str(s) = v {
                                    Some(s.clone())
                                } else {
                                    None
                                }
                            })
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
                        let item_var = decl
                            .options
                            .as_ref()
                            .and_then(|o| o.get("item"))
                            .and_then(|v| {
                                if let crate::parser::WindowValue::Str(s) = v {
                                    Some(s.clone())
                                } else {
                                    None
                                }
                            })
                            .unwrap_or_else(|| "item".to_string());
                        body_symbol_types
                            .get(&item_var)
                            .or_else(|| body_symbol_types.get("item"))
                            .and_then(|ty| {
                                ty.get("name")
                                    .and_then(|n| n.as_str())
                                    .map(|s| s.to_string())
                            })
                            .unwrap_or_else(|| "Unknown".to_string())
                    };

                    if let Some(body_nodes) = &decl.body_nodes {
                        // Extract item variable name for OOF-L7 checks
                        let item_var = decl
                            .options
                            .as_ref()
                            .and_then(|o| o.get("item"))
                            .and_then(|v| {
                                if let crate::parser::WindowValue::Str(s) = v {
                                    Some(s.clone())
                                } else {
                                    None
                                }
                            })
                            .unwrap_or_else(|| "item".to_string());

                        for inner_decl in body_nodes {
                            match inner_decl.kind.as_str() {
                                "lead" => {
                                    // PROP-039 gate 8: validate lead initial is a literal
                                    let is_literal = inner_decl
                                        .expr
                                        .as_ref()
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
                                    let lead_type_ir = inner_decl
                                        .type_annotation
                                        .as_ref()
                                        .map(|t| self.type_ir(t))
                                        .unwrap_or_else(|| {
                                            self.type_ir(&serde_json::Value::String(
                                                "Unknown".to_string(),
                                            ))
                                        });
                                    let type_str = lead_type_ir
                                        .get("name")
                                        .and_then(|v| v.as_str())
                                        .unwrap_or("Unknown")
                                        .to_string();
                                    // Add lead to body symbol types for subsequent computes
                                    body_symbol_types.insert(
                                        inner_decl.name.clone(),
                                        self.type_ir(&serde_json::Value::String(type_str)),
                                    );
                                    typed_body_nodes.push(self.typed_decl(
                                        inner_decl,
                                        lead_type_ir,
                                        inner_decl.expr.clone(),
                                        inner_decl.deps.clone(),
                                    ));
                                }
                                "compute" => {
                                    // PROP-039 gate 8: OOF-L7/OOF-L5 target checks.
                                    // Match canon Ruby: every loop body compute must target a
                                    // declared lead binding, regardless of whether the body
                                    // contains any lead declarations.
                                    let target = &inner_decl.name;
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
                                    } else if symbol_types.contains_key(target.as_str())
                                        && !lead_names.contains(target)
                                    {
                                        type_errors.push(crate::classifier::ClassifierDiagnostic {
                                            rule: "OOF-L7".to_string(),
                                            message: format!(
                                                "body compute in loop '{}' targets outer contract symbol '{}' — outer state is read-only",
                                                decl.name, target
                                            ),
                                            node: decl.name.clone(),
                                            line: None,
                                        });
                                    } else if !lead_names.contains(target)
                                        && !symbol_types.contains_key(target.as_str())
                                        && target != &item_var
                                        && target != "item"
                                    {
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

                                    let typed_expr = self.infer_expr(
                                        inner_decl.expr.as_ref().unwrap(),
                                        &body_symbol_types,
                                        olap_env,
                                        &local_type_shapes,
                                        &mut type_errors,
                                        &mut type_warnings,
                                        &inner_decl.name,
                                        functions,
                                        contract_registry,
                                        &classified.name,
                                    );
                                    body_symbol_types.insert(
                                        inner_decl.name.clone(),
                                        typed_expr.resolved_type.clone(),
                                    );
                                    typed_body_nodes.push(self.typed_decl(
                                        inner_decl,
                                        typed_expr.resolved_type,
                                        inner_decl.expr.clone(),
                                        inner_decl.deps.clone(),
                                    ));
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

                    let mut typed_loop_decl =
                        self.typed_decl(decl, ty, decl.expr.clone(), decl.deps.clone());
                    // Store item_type in options for gate 8 emitter
                    if let Some(opts) = &mut typed_loop_decl.options {
                        opts.insert(
                            "item_type".to_string(),
                            crate::parser::WindowValue::Str(item_type_str),
                        );
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
                                let mut typed_expr = self.infer_expr(
                                    inner_decl.expr.as_ref().unwrap(),
                                    &body_symbol_types,
                                    olap_env,
                                    &local_type_shapes,
                                    &mut type_errors,
                                    &mut type_warnings,
                                    &inner_decl.name,
                                    functions,
                                    contract_registry,
                                    &classified.name,
                                );
                                body_symbol_types.insert(
                                    inner_decl.name.clone(),
                                    typed_expr.resolved_type.clone(),
                                );
                                typed_body_nodes.push(self.typed_decl(
                                    inner_decl,
                                    typed_expr.resolved_type,
                                    inner_decl.expr.clone(),
                                    inner_decl.deps.clone(),
                                ));
                            }
                        }
                    }

                    let mut typed_loop_decl = self.typed_decl(decl, ty, None, decl.deps.clone());
                    typed_loop_decl.body_nodes = Some(typed_body_nodes);
                    typed_decls.push(typed_loop_decl);
                }
                "fold_stream" => {
                    // fold_stream result type defaults to init arg type
                    let mut res_type =
                        self.type_ir(&serde_json::Value::String("Unknown".to_string()));
                    if let Some(Expr::Call { args, .. }) = &decl.expr {
                        if args.len() >= 2 {
                            if let Expr::Literal { type_tag, .. } = &args[1] {
                                res_type =
                                    self.type_ir(&serde_json::Value::String(type_tag.clone()));
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
                                let mut lambda_params: HashSet<String> =
                                    params.iter().cloned().collect();
                                let mut escape_refs = Vec::new();
                                self.collect_escape_refs(
                                    body,
                                    &stream_symbols,
                                    &mut lambda_params,
                                    &mut escape_refs,
                                );
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
                    typed_decls.push(self.typed_decl(
                        decl,
                        res_type,
                        decl.expr.clone(),
                        decl.deps.clone(),
                    ));
                }
                "invariant" => {
                    let predicate_ref = decl.predicate_ref.clone().unwrap_or_default();
                    let severity = decl.severity.clone().unwrap_or_else(|| "error".to_string());
                    let pred_type =
                        symbol_types
                            .get(&predicate_ref)
                            .cloned()
                            .unwrap_or_else(|| {
                                self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                            });

                    // TC-INV-1: invariant predicate must be Bool
                    if self.type_name(&pred_type) != "Bool"
                        && self.type_name(&pred_type) != "Unknown"
                    {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-IV3".to_string(),
                            message: format!(
                                "invariant predicate must be Bool, got {}",
                                self.type_name(&pred_type)
                            ),
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
                        output_effect: Some(
                            self.invariant_output_effect(
                                &decl.severity.clone().unwrap_or_default(),
                            ),
                        ),
                        warnings_from: None,
                        uncertain_from: None,
                        metrics_from: None,
                        body_nodes: None,
                        annotated_expr: None,
                    });
                }
                "compute" | "snapshot" => {
                    let mut typed_expr = self.infer_expr(
                        decl.expr.as_ref().unwrap(),
                        &symbol_types,
                        olap_env,
                        &local_type_shapes,
                        &mut type_errors,
                        &mut type_warnings,
                        &decl.name,
                        functions,
                        contract_registry,
                        &classified.name,
                    );
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
                    // LANG-FOLD-STRUCT-ACCUMULATOR-P3: contextual record
                    // accumulator typing for `fold(Collection[T], Acc, lambda)`.
                    // `infer_expr` has no enclosing output context, so an inline
                    // record seed stays Unknown there. When this compute has a
                    // named-record output or compute annotation, re-check the fold
                    // seed and lambda body against that expected `Acc`.
                    if self.type_name(&typed_expr.resolved_type) == "Unknown" {
                        let fold_acc_hint = decl
                            .type_annotation
                            .as_ref()
                            .map(|ann| self.type_ir(ann))
                            .filter(|ir| local_type_shapes.contains_key(&self.type_name(ir)))
                            .or_else(|| {
                                output_type_hints.get(&decl.name).map(|name| {
                                    self.type_ir(&serde_json::Value::String(name.clone()))
                                })
                            });
                        if let (Some(expected_acc), Some(Expr::Call { fn_name, args })) =
                            (fold_acc_hint, decl.expr.as_ref())
                        {
                            if fn_name == "fold" {
                                let mut fold_typed_args = Vec::new();
                                for arg in args {
                                    let arg_typed = self.infer_expr(
                                        arg,
                                        &symbol_types,
                                        olap_env,
                                        &local_type_shapes,
                                        &mut type_errors,
                                        &mut type_warnings,
                                        &decl.name,
                                        functions,
                                        contract_registry,
                                        &classified.name,
                                    );
                                    fold_typed_args.push(arg_typed);
                                }
                                typed_expr.resolved_type = self.infer_fold_call_type(
                                    args,
                                    &fold_typed_args,
                                    Some(&expected_acc),
                                    &symbol_types,
                                    olap_env,
                                    &local_type_shapes,
                                    &mut type_errors,
                                    &mut type_warnings,
                                    &decl.name,
                                    functions,
                                    contract_registry,
                                    &classified.name,
                                );
                            }
                        }
                    }
                    // LAB-RACK-P13: nominal record type checking.
                    // If this compute node is Unknown (e.g. from a RecordLiteral) and there
                    // is an output declaration expecting a named record type, validate the
                    // RecordLiteral field names and types against the declared schema.
                    // On success:  upgrade resolved_type from Unknown → the named record type
                    //              (so the compute node appears as RackResponse in the SIR).
                    // On failure:  emit specific OOF-TY0 errors; leave resolved_type Unknown
                    //              (the output-level Unknown-compat rule still applies, so no
                    //              duplicate "type mismatch" error is emitted).
                    // Uncontextualized RecordLiterals (no output hint) remain Unknown.
                    if self.type_name(&typed_expr.resolved_type) == "Unknown" {
                        if let Some(Expr::RecordLiteral { fields }) = decl.expr.as_ref() {
                            if let Some(expected_type_name) = output_type_hints.get(&decl.name) {
                                if let Some(shape) =
                                    local_type_shapes.get(expected_type_name.as_str()).cloned()
                                {
                                    let errors_before = type_errors.len();
                                    self.check_record_literal_shape(
                                        fields,
                                        &shape,
                                        expected_type_name,
                                        &decl.name,
                                        &symbol_types,
                                        &local_type_shapes,
                                        &mut type_errors,
                                    );
                                    if type_errors.len() == errors_before {
                                        // All checks passed — upgrade compute node type
                                        typed_expr.resolved_type = self.type_ir(
                                            &serde_json::Value::String(expected_type_name.clone()),
                                        );
                                    }
                                }
                            }
                        }
                        // LAB-LANG-RECORD-SPREAD-P2: expand a record spread `{ ...src, f: v }` to an
                        // explicit field-by-field RecordLiteral once the target record type is known. Copied
                        // fields are exactly those the TARGET declares AND the SOURCE has; explicit fields
                        // override. The expanded literal is stashed as `annotated_expr` so the emitter lowers
                        // it via the existing record-literal path (no new SIR node kind).
                        else if let Some(Expr::RecordSpread { spread, fields }) =
                            decl.expr.as_ref()
                        {
                            if let Some(expected_type_name) = output_type_hints.get(&decl.name) {
                                if let Some(target_shape) =
                                    local_type_shapes.get(expected_type_name.as_str()).cloned()
                                {
                                    // Resolve the source's record type (into scratch errors — the source
                                    // was already typed in the main pass, avoid duplicate diagnostics).
                                    let mut scratch = Vec::new();
                                    let src_typed = self.infer_expr(
                                        spread,
                                        &symbol_types,
                                        olap_env,
                                        &local_type_shapes,
                                        &mut scratch,
                                        &mut type_warnings,
                                        &decl.name,
                                        functions,
                                        contract_registry,
                                        &classified.name,
                                    );
                                    let src_type_name = self.type_name(&src_typed.resolved_type);
                                    match local_type_shapes.get(&src_type_name) {
                                        None => {
                                            type_errors.push(ClassifierDiagnostic {
                                                rule: "OOF-TY0".to_string(),
                                                message: format!(
                                                    "record spread source must be a known record type, got `{}`",
                                                    src_type_name
                                                ),
                                                node: decl.name.clone(),
                                                line: None,
                                            });
                                        }
                                        Some(src_shape) => {
                                            // Build the expanded explicit field set.
                                            let mut expanded: HashMap<String, Expr> =
                                                HashMap::new();
                                            for (fname, ftype) in target_shape.iter() {
                                                if let Some(explicit) = fields.get(fname) {
                                                    expanded
                                                        .insert(fname.clone(), explicit.clone());
                                                } else if let Some(stype) = src_shape.get(fname) {
                                                    // copied field — verify source/target field types agree
                                                    if self.type_name(stype)
                                                        != self.type_name(ftype)
                                                    {
                                                        type_errors.push(ClassifierDiagnostic {
                                                            rule: "OOF-TY0".to_string(),
                                                            message: format!(
                                                                "record spread field `{}` type mismatch: source {} vs target {}",
                                                                fname,
                                                                self.type_name(stype),
                                                                self.type_name(ftype)
                                                            ),
                                                            node: decl.name.clone(),
                                                            line: None,
                                                        });
                                                    }
                                                    expanded.insert(
                                                        fname.clone(),
                                                        Expr::FieldAccess {
                                                            object: spread.clone(),
                                                            field: fname.clone(),
                                                        },
                                                    );
                                                }
                                                // else: neither explicit nor in source → left missing,
                                                // reported below by the shape checker.
                                            }
                                            // explicit fields not in the target are rejected by the shape
                                            // checker (extra-field); include them so it can see them.
                                            for (fname, explicit) in fields.iter() {
                                                expanded
                                                    .entry(fname.clone())
                                                    .or_insert_with(|| explicit.clone());
                                            }
                                            let errors_before = type_errors.len();
                                            self.check_record_literal_shape(
                                                &expanded,
                                                &target_shape,
                                                expected_type_name,
                                                &decl.name,
                                                &symbol_types,
                                                &local_type_shapes,
                                                &mut type_errors,
                                            );
                                            if type_errors.len() == errors_before {
                                                // expansion is well-typed — stash it for the emitter and
                                                // upgrade the compute node type.
                                                let lit = Expr::RecordLiteral { fields: expanded };
                                                if let Ok(json) = serde_json::to_value(&lit) {
                                                    typed_expr.annotated_expr = Some(json);
                                                }
                                                typed_expr.resolved_type =
                                                    self.type_ir(&serde_json::Value::String(
                                                        expected_type_name.clone(),
                                                    ));
                                            }
                                        }
                                    }
                                }
                            } else {
                                type_errors.push(ClassifierDiagnostic {
                                    rule: "OOF-TY0".to_string(),
                                    message:
                                        "record spread requires a known target record type (declare the output/compute type)"
                                            .to_string(),
                                    node: decl.name.clone(),
                                    line: None,
                                });
                            }
                        }
                    }
                    // LAB-LANG-RECORD-SPREAD-P2: v0 supports record spread only at the top level of a
                    // typed compute/output (where the target record type drives expansion). A spread nested
                    // inside another expression has no target type here, so reject it with a clear
                    // diagnostic rather than letting an unexpanded `record_spread` reach the emitter.
                    let top_is_spread =
                        matches!(decl.expr.as_ref(), Some(Expr::RecordSpread { .. }));
                    if !top_is_spread {
                        if let Some(e) = decl.expr.as_ref() {
                            if let Ok(j) = serde_json::to_string(e) {
                                if j.contains("\"record_spread\"") {
                                    type_errors.push(ClassifierDiagnostic {
                                        rule: "OOF-TY0".to_string(),
                                        message:
                                            "record spread is only supported at the top level of a typed compute/output (v0)"
                                                .to_string(),
                                        node: decl.name.clone(),
                                        line: None,
                                    });
                                }
                            }
                        }
                    }
                    // LAB-TC-ARRAY-P1: contextual ArrayLiteral typing in a typed
                    // Collection[T] output position. Mirrors the RecordLiteral
                    // nominal upgrade above. infer_expr leaves an ArrayLiteral as
                    // Unknown; here, when there is a `Collection[T]` output hint for
                    // this compute node, each element is checked against the element
                    // type T. On success the compute node is upgraded to
                    // Collection[T] (so it surfaces in the SIR type metadata); on any
                    // element mismatch the OOF-TY0 errors fail the contract closed
                    // and the node stays Unknown. Empty arrays are accepted only with
                    // this contextual type (zero elements → zero checks → upgrade).
                    if self.type_name(&typed_expr.resolved_type) == "Unknown" {
                        if let Some(Expr::ArrayLiteral { items }) = decl.expr.as_ref() {
                            if let Some(elem_type_ir) =
                                collection_output_hints.get(&decl.name).cloned()
                            {
                                let errors_before = type_errors.len();
                                self.check_array_literal_shape(
                                    items,
                                    &elem_type_ir,
                                    &local_type_shapes,
                                    &decl.name,
                                    &symbol_types,
                                    &mut type_errors,
                                );
                                if type_errors.len() == errors_before {
                                    // All elements conform — upgrade to Collection[T].
                                    let mut col = serde_json::Map::new();
                                    col.insert(
                                        "name".to_string(),
                                        serde_json::Value::String("Collection".to_string()),
                                    );
                                    col.insert(
                                        "params".to_string(),
                                        serde_json::Value::Array(vec![elem_type_ir]),
                                    );
                                    typed_expr.resolved_type = serde_json::Value::Object(col);
                                }
                            }
                        }
                    }
                    // LANG-RUST-TYPED-COMPUTE-BINDING-P2: if the compute has a declared
                    // type annotation, apply annotation-based bind-type resolution.
                    // Mirrors Ruby LANG-TYPED-COMPUTE-BINDING-P2 three-way branch:
                    // (a) Unknown-bearing inferred → annotation authoritative, no error.
                    // (b) Concrete match (structurally_assignable) → keep inferred type.
                    // (c) Concrete mismatch → emit OOF-TY0, use annotation to avoid cascade.
                    // Runs after LAB-RACK-P13 and LAB-TC-ARRAY-P1 upgrades so those take
                    // precedence when they fire; annotation override only applies when the
                    // earlier upgrades left the type Unknown-bearing.
                    if let Some(ann) = &decl.type_annotation {
                        let ann_type = self.type_ir(ann);
                        if self.unknown_or_unknown_bearing(&typed_expr.resolved_type) {
                            // (a) inferred is Unknown or Unknown-bearing — annotation authoritative
                            typed_expr.resolved_type = ann_type;
                        } else if !self
                            .structurally_assignable(&typed_expr.resolved_type, &ann_type)
                        {
                            // (c) concrete mismatch — emit OOF-TY0, bind annotation to avoid cascade
                            type_errors.push(ClassifierDiagnostic {
                                rule: "OOF-TY0".to_string(),
                                message: format!(
                                    "Binding type mismatch: declared {}, got {}",
                                    self.type_display(&ann_type),
                                    self.type_display(&typed_expr.resolved_type)
                                ),
                                node: decl.name.clone(),
                                line: None,
                            });
                            typed_expr.resolved_type = ann_type;
                        }
                        // (b) concrete match — structurally_assignable → keep inferred type (no change)
                    }
                    symbol_types.insert(decl.name.clone(), typed_expr.resolved_type.clone());
                    // igniter-string-core: rewrite concat calls before storing expr in TypedDecl.
                    // This resolves the Collection/Text ambiguity so the emitter emits the
                    // correct qualified fn name (stdlib.text.concat / stdlib.collection.concat).
                    let rewritten_expr = decl
                        .expr
                        .as_ref()
                        .map(|e| self.rewrite_concat_calls(e, &symbol_types));
                    // PROP-044 P5: carry annotated_expr (variant_construct / match_node SIR) through to emitter.
                    let annotated = typed_expr.annotated_expr.take();
                    let mut td = self.typed_decl(
                        decl,
                        typed_expr.resolved_type,
                        rewritten_expr,
                        decl.deps.clone(),
                    );
                    td.annotated_expr = annotated;
                    typed_decls.push(td);
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
                                self.check_t2_callsite_in_expr(
                                    expr,
                                    &mut type_errors,
                                    &decl.name,
                                    ctx,
                                    &recur_input_names,
                                );
                            }
                        }
                        // PROP-042 T3: OOF-R11 call-site numeric-measure check
                        if let Some(ctx) = &t3_context {
                            self.check_t3_callsite_in_expr(
                                expr,
                                &mut type_errors,
                                &decl.name,
                                ctx,
                                &recur_input_names,
                                size_registry,
                            );
                        }
                    }
                }
                "output" => {
                    let expected = self.type_ir(decl.type_annotation.as_ref().unwrap());
                    let actual = symbol_types.get(&decl.name).cloned().unwrap_or_else(|| {
                        self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                    });

                    // LANG-OUTPUT-TYPE-ASSIGNABILITY-P4: structural check supersedes the
                    // outer-name-only comparison and the LAB-RACK-P9 guard (D6).
                    // structurally_assignable() implements D2 (actual Unknown → false) and
                    // D3 (expected Unknown → true) at all depths. OOF-TY1 replaces OOF-TY0
                    // at the output boundary.
                    if !self.structurally_assignable(&actual, &expected)
                        && !self.blocking_rule_present(&type_errors)
                    {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-TY1".to_string(),
                            message: format!(
                                "Output type mismatch: expected {}, got {}",
                                self.type_display(&expected),
                                self.type_display(&actual)
                            ),
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
                        warnings_from: if warnings_from.is_empty() {
                            None
                        } else {
                            Some(warnings_from)
                        },
                        uncertain_from: if uncertain_from.is_empty() {
                            None
                        } else {
                            Some(uncertain_from)
                        },
                        metrics_from: if metrics_from.is_empty() {
                            None
                        } else {
                            Some(metrics_from)
                        },
                        body_nodes: None,
                        annotated_expr: None,
                    });
                }
                _ => {}
            }
        }

        let status = if type_errors
            .iter()
            .any(|d| d.rule.starts_with("OOF-") || d.rule.starts_with("E-IO-"))
        {
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
                sorted_keys
                    .into_iter()
                    .map(|name| TypedSymbol {
                        name: name.clone(),
                        type_info: symbol_types.get(name).unwrap().clone(),
                        resolved: self.type_name(symbol_types.get(name).unwrap()) != "Unknown",
                    })
                    .collect()
            },
            declarations: typed_decls,
            type_errors: self.dedupe_errors(&type_errors),
            type_warnings: if type_warnings.is_empty() {
                None
            } else {
                Some(self.dedupe_errors(&type_warnings))
            },
            decreases_variant: clean_decreases_variant,
            // PROP-041 T2: propagate structural-size evidence for SemanticIR structural_size_v1 emission
            decreases_variant_t2: t2_context.as_ref().and_then(|ctx| {
                if ctx.kind == T2Kind::T2Pass {
                    Some(ctx.dv.clone())
                } else {
                    None
                }
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
            // PROP-042 T3: propagate numeric-measure evidence for SemanticIR numeric_measure_v0 emission
            decreases_variant_t3: t3_context.as_ref().map(|ctx| ctx.dv.clone()),
            numeric_measure_evidence: t3_context.as_ref().map(|ctx| {
                serde_json::json!({
                    "fn":     ctx.builtin.qualified_name,
                    "arg":    ctx.arg_name,
                    "trust":  ctx.builtin.trust,
                    "source": ctx.builtin.source
                })
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
    fn build_size_registry(
        &self,
        classified: &ClassifiedProgram,
    ) -> HashMap<(String, String), T2RegistryEntry> {
        let mut registry = stdlib_size_registry();
        let mod_name = classified
            .module
            .clone()
            .unwrap_or_else(|| "unknown".to_string());
        for sr in &classified.size_relations {
            registry.insert(
                (sr.type_name.clone(), sr.accessor.clone()),
                T2RegistryEntry {
                    trust: "user_assumed".to_string(),
                    source: mod_name.clone(),
                },
            );
        }
        registry
    }

    /// LAB-RACK-P11: build the module contract registry for literal callee resolution.
    /// Maps contract_name → ContractRegistryEntry.
    /// Built from ClassifiedProgram.contracts before the contract loop, so all
    /// contracts see the full module (order-independent single pass over declarations).
    fn build_contract_registry(
        &self,
        classified: &ClassifiedProgram,
    ) -> HashMap<String, ContractRegistryEntry> {
        let mut registry = HashMap::new();
        for contract in &classified.contracts {
            let modifier = contract.modifier.clone();
            let input_decls: Vec<&ClassifiedDecl> = contract
                .declarations
                .iter()
                .filter(|d| d.kind == "input")
                .collect();
            let output_decls: Vec<&ClassifiedDecl> = contract
                .declarations
                .iter()
                .filter(|d| d.kind == "output")
                .collect();

            let input_count = input_decls.len();
            let input_names: Vec<String> = input_decls.iter().map(|d| d.name.clone()).collect();
            let input_types: Vec<serde_json::Value> = input_decls
                .iter()
                .filter_map(|d| d.type_annotation.clone())
                .collect();

            let single_output_type = if output_decls.len() == 1 {
                output_decls[0].type_annotation.clone()
            } else {
                None
            };
            let single_output_name = if output_decls.len() == 1 {
                Some(output_decls[0].name.clone())
            } else {
                None
            };

            registry.insert(
                contract.name.clone(),
                ContractRegistryEntry {
                    modifier,
                    input_count,
                    input_names,
                    input_types,
                    single_output_type,
                    single_output_name,
                    contract_name: contract.name.clone(),
                },
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
        let subject = &dv[..dot_pos];
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
        let type_name_str: String = classified
            .declarations
            .iter()
            .find(|d| d.kind == "input" && d.name == subject)
            .and_then(|d| d.type_annotation.as_ref())
            .map(|ta| {
                if let Some(obj) = ta.as_object() {
                    obj.get("name")
                        .and_then(|n| n.as_str())
                        .unwrap_or("Unknown")
                        .to_string()
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
                                    node_name,
                                    ctx.subject,
                                    ctx.accessor,
                                    subject_pos + 1,
                                    arg_desc
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
            Expr::IfExpr {
                cond,
                then,
                else_block,
            } => {
                self.check_t2_callsite_in_expr(cond, type_errors, node_name, ctx, input_names);
                // then block
                for stmt in &then.stmts {
                    if let Stmt::Let { expr, .. } = stmt {
                        self.check_t2_callsite_in_expr(
                            expr,
                            type_errors,
                            node_name,
                            ctx,
                            input_names,
                        );
                    }
                }
                if let Some(re) = &then.return_expr {
                    self.check_t2_callsite_in_expr(re, type_errors, node_name, ctx, input_names);
                }
                // else block
                if let Some(eb) = else_block {
                    for stmt in &eb.stmts {
                        if let Stmt::Let { expr, .. } = stmt {
                            self.check_t2_callsite_in_expr(
                                expr,
                                type_errors,
                                node_name,
                                ctx,
                                input_names,
                            );
                        }
                    }
                    if let Some(re) = &eb.return_expr {
                        self.check_t2_callsite_in_expr(
                            re,
                            type_errors,
                            node_name,
                            ctx,
                            input_names,
                        );
                    }
                }
            }
            _ => {}
        }
    }

    /// True when `expr` is exactly `subject.accessor` (field access on a ref).
    fn t2_structural_arg(&self, expr: &Expr, subject: &str, accessor: &str) -> bool {
        if let Expr::FieldAccess { object, field } = expr {
            if field != accessor {
                return false;
            }
            if let Expr::Ref { name } = object.as_ref() {
                return name == subject;
            }
        }
        false
    }

    // ── end PROP-041 T2 private helpers ─────────────────────────────────────────

    // ── PROP-042 T3: private helpers ─────────────────────────────────────────────

    /// T3 function-call form dispatch.
    /// Fires OOF-R10 for unrecognized/deferred measure functions.
    /// Returns a T3Context when the function is recognized (count).
    fn handle_t3_variant(
        &self,
        variant: &str,
        classified: &ClassifiedContract,
        type_errors: &mut Vec<ClassifierDiagnostic>,
        _size_registry: &HashMap<(String, String), T2RegistryEntry>,
    ) -> Option<T3Context> {
        let (fn_name, arg_name) = parse_t3_call_form(variant)?;

        // Look up the function in NUMERIC_MEASURE_BUILTINS v0
        if let Some(&(_, qualified_name, trust, source)) = NUMERIC_MEASURE_BUILTINS_V0
            .iter()
            .find(|&&(f, _, _, _)| f == fn_name)
        {
            // Recognized builtin — return T3 context; call-site check done separately
            Some(T3Context {
                dv: variant.to_string(),
                fn_name: fn_name.to_string(),
                arg_name: arg_name.to_string(),
                builtin: T3BuiltinEntry {
                    qualified_name,
                    trust,
                    source,
                },
            })
        } else {
            // OOF-R10: unrecognized / deferred measure function
            type_errors.push(ClassifierDiagnostic {
                rule: "OOF-R10".to_string(),
                message: format!(
                    "decreases variant '{}' in '{}' — function '{}' is not a recognized numeric measure; \
                     only count(Collection[T]) is accepted in NUMERIC_MEASURE_BUILTINS v0; \
                     size/length/byte_length and user-defined measures are deferred",
                    variant, classified.name, fn_name
                ),
                node: classified.name.clone(),
                line: None,
            });
            None
        }
    }

    /// T3 call-site check: walks an expression tree looking for recur() calls.
    /// When found, checks that the variant-position arg is a T2-registered structural subvalue
    /// of the T3-measured input (i.e. `arg_name.some_accessor` where accessor is in registry).
    /// Also accepts `arg_name.rest` and `arg_name.tail` (stdlib_certified).
    /// Fires OOF-R11 on mismatch.
    fn check_t3_callsite_in_expr(
        &self,
        expr: &Expr,
        type_errors: &mut Vec<ClassifierDiagnostic>,
        node_name: &str,
        ctx: &T3Context,
        input_names: &[String],
        size_registry: &HashMap<(String, String), T2RegistryEntry>,
    ) {
        match expr {
            Expr::Call { fn_name, args } if fn_name == "recur" => {
                if let Some(subject_pos) = input_names.iter().position(|n| n == &ctx.arg_name) {
                    if subject_pos < args.len() {
                        let variant_arg = &args[subject_pos];
                        if !self.t3_structurally_covered(variant_arg, &ctx.arg_name, size_registry)
                        {
                            let arg_desc = syntactic_arg_desc(variant_arg);
                            type_errors.push(ClassifierDiagnostic {
                                rule: "OOF-R11".to_string(),
                                message: format!(
                                    "recur() in '{}' — numeric measure call-site obligation not met: \
                                     count({}) requires the argument at position {} to be a \
                                     T2-registered structural subvalue of '{}', got: {}; \
                                     declare a size_relation or use a stdlib accessor (tail/rest)",
                                    node_name, ctx.arg_name, subject_pos + 1, ctx.arg_name, arg_desc
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
                    self.check_t3_callsite_in_expr(
                        arg,
                        type_errors,
                        node_name,
                        ctx,
                        input_names,
                        size_registry,
                    );
                }
            }
            Expr::BinaryOp { left, right, .. } => {
                self.check_t3_callsite_in_expr(
                    left,
                    type_errors,
                    node_name,
                    ctx,
                    input_names,
                    size_registry,
                );
                self.check_t3_callsite_in_expr(
                    right,
                    type_errors,
                    node_name,
                    ctx,
                    input_names,
                    size_registry,
                );
            }
            Expr::UnaryOp { operand, .. } => {
                self.check_t3_callsite_in_expr(
                    operand,
                    type_errors,
                    node_name,
                    ctx,
                    input_names,
                    size_registry,
                );
            }
            Expr::FieldAccess { object, .. } => {
                self.check_t3_callsite_in_expr(
                    object,
                    type_errors,
                    node_name,
                    ctx,
                    input_names,
                    size_registry,
                );
            }
            Expr::IndexAccess { object, index } => {
                self.check_t3_callsite_in_expr(
                    object,
                    type_errors,
                    node_name,
                    ctx,
                    input_names,
                    size_registry,
                );
                self.check_t3_callsite_in_expr(
                    index,
                    type_errors,
                    node_name,
                    ctx,
                    input_names,
                    size_registry,
                );
            }
            Expr::IfExpr {
                cond,
                then,
                else_block,
            } => {
                self.check_t3_callsite_in_expr(
                    cond,
                    type_errors,
                    node_name,
                    ctx,
                    input_names,
                    size_registry,
                );
                for stmt in &then.stmts {
                    if let crate::parser::Stmt::Let { expr, .. } = stmt {
                        self.check_t3_callsite_in_expr(
                            expr,
                            type_errors,
                            node_name,
                            ctx,
                            input_names,
                            size_registry,
                        );
                    }
                }
                if let Some(re) = &then.return_expr {
                    self.check_t3_callsite_in_expr(
                        re,
                        type_errors,
                        node_name,
                        ctx,
                        input_names,
                        size_registry,
                    );
                }
                if let Some(eb) = else_block {
                    for stmt in &eb.stmts {
                        if let crate::parser::Stmt::Let { expr, .. } = stmt {
                            self.check_t3_callsite_in_expr(
                                expr,
                                type_errors,
                                node_name,
                                ctx,
                                input_names,
                                size_registry,
                            );
                        }
                    }
                    if let Some(re) = &eb.return_expr {
                        self.check_t3_callsite_in_expr(
                            re,
                            type_errors,
                            node_name,
                            ctx,
                            input_names,
                            size_registry,
                        );
                    }
                }
            }
            _ => {}
        }
    }

    /// True when `expr` is `subject.some_accessor` where `some_accessor` is registered in the
    /// T2 size_registry for the subject's type, OR is a stdlib_certified entry (tail/rest).
    /// Mirrors Ruby `t3_structurally_covered?`.
    fn t3_structurally_covered(
        &self,
        expr: &Expr,
        subject: &str,
        size_registry: &HashMap<(String, String), T2RegistryEntry>,
    ) -> bool {
        if let Expr::FieldAccess { object, field } = expr {
            if let Expr::Ref { name } = object.as_ref() {
                if name != subject {
                    return false;
                }
                // Check all (type, field) pairs in registry for this subject+field
                // We don't have the type here, so match on field alone against any registered entry
                // where the subject matches (mirrors Ruby which uses @size_registry.key?([subject_type, fld]))
                return size_registry.keys().any(|(_, acc)| acc == field);
            }
        }
        false
    }

    // ── end PROP-042 T3 private helpers ──────────────────────────────────────────

    fn collect_escape_refs(
        &self,
        body: &ExprOrBlock,
        stream_symbols: &HashSet<String>,
        lambda_params: &mut HashSet<String>,
        escape_refs: &mut Vec<String>,
    ) {
        match body {
            ExprOrBlock::Expr(e) => {
                self.collect_expr_escape_refs(e, stream_symbols, lambda_params, escape_refs)
            }
            ExprOrBlock::Block(b) => {
                for s in &b.stmts {
                    match s {
                        Stmt::Let { expr, .. } => self.collect_expr_escape_refs(
                            expr,
                            stream_symbols,
                            lambda_params,
                            escape_refs,
                        ),
                        Stmt::ExprStmt { expr } => self.collect_expr_escape_refs(
                            expr,
                            stream_symbols,
                            lambda_params,
                            escape_refs,
                        ),
                    }
                }
                if let Some(re) = &b.return_expr {
                    self.collect_expr_escape_refs(re, stream_symbols, lambda_params, escape_refs);
                }
            }
        }
    }

    fn collect_expr_escape_refs(
        &self,
        expr: &Expr,
        stream_symbols: &HashSet<String>,
        lambda_params: &mut HashSet<String>,
        escape_refs: &mut Vec<String>,
    ) {
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
            Expr::IfExpr {
                cond,
                then,
                else_block,
            } => {
                self.collect_expr_escape_refs(cond, stream_symbols, lambda_params, escape_refs);
                for s in &then.stmts {
                    match s {
                        Stmt::Let { expr, .. } => self.collect_expr_escape_refs(
                            expr,
                            stream_symbols,
                            lambda_params,
                            escape_refs,
                        ),
                        Stmt::ExprStmt { expr } => self.collect_expr_escape_refs(
                            expr,
                            stream_symbols,
                            lambda_params,
                            escape_refs,
                        ),
                    }
                }
                if let Some(re) = &then.return_expr {
                    self.collect_expr_escape_refs(re, stream_symbols, lambda_params, escape_refs);
                }
                if let Some(eb) = else_block {
                    for s in &eb.stmts {
                        match s {
                            Stmt::Let { expr, .. } => self.collect_expr_escape_refs(
                                expr,
                                stream_symbols,
                                lambda_params,
                                escape_refs,
                            ),
                            Stmt::ExprStmt { expr } => self.collect_expr_escape_refs(
                                expr,
                                stream_symbols,
                                lambda_params,
                                escape_refs,
                            ),
                        }
                    }
                    if let Some(re) = &eb.return_expr {
                        self.collect_expr_escape_refs(
                            re,
                            stream_symbols,
                            lambda_params,
                            escape_refs,
                        );
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
            Expr::RecordSpread { spread, fields } => {
                self.collect_expr_escape_refs(spread, stream_symbols, lambda_params, escape_refs);
                for v in fields.values() {
                    self.collect_expr_escape_refs(v, stream_symbols, lambda_params, escape_refs);
                }
            }
            _ => {}
        }
    }

    fn typed_decl(
        &self,
        decl: &ClassifiedDecl,
        type_info: serde_json::Value,
        expr: Option<Expr>,
        deps: Vec<String>,
    ) -> TypedDecl {
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
            annotated_expr: None,
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
                    for (idx, (arg, input_name)) in
                        args.iter().zip(recur_input_names.iter()).enumerate()
                    {
                        let expected_type = symbol_types.get(input_name).cloned().unwrap_or_else(
                            || serde_json::json!({"name": "Unknown", "params": []}),
                        );
                        let mut dummy_errors = Vec::new();
                        let mut dummy_warnings = Vec::new();
                        let empty_registry: HashMap<String, ContractRegistryEntry> = HashMap::new();
                        let arg_typed = self.infer_expr(
                            arg,
                            symbol_types,
                            olap_env,
                            type_shapes,
                            &mut dummy_errors,
                            &mut dummy_warnings,
                            node_name,
                            functions,
                            &empty_registry,
                            node_name,
                        );
                        let actual = self.type_name(&arg_typed.resolved_type);
                        let expected = self.type_name(&expected_type);
                        if actual != "Unknown" && expected != "Unknown" && actual != expected {
                            type_errors.push(ClassifierDiagnostic {
                                rule: "OOF-R6".to_string(),
                                message: format!(
                                    "recur() arg {} type mismatch in '{}' — expected {}, got {}",
                                    idx + 1,
                                    node_name,
                                    expected,
                                    actual
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
                    self.check_recur_in_expr(
                        arg,
                        recur_authorized,
                        recur_input_names,
                        recur_output_count,
                        symbol_types,
                        olap_env,
                        type_shapes,
                        type_errors,
                        type_warnings,
                        node_name,
                        functions,
                        decreases_variant,
                        decreases_variant_pos,
                    );
                }
            }
            Expr::BinaryOp { left, right, .. } => {
                self.check_recur_in_expr(
                    left,
                    recur_authorized,
                    recur_input_names,
                    recur_output_count,
                    symbol_types,
                    olap_env,
                    type_shapes,
                    type_errors,
                    type_warnings,
                    node_name,
                    functions,
                    decreases_variant,
                    decreases_variant_pos,
                );
                self.check_recur_in_expr(
                    right,
                    recur_authorized,
                    recur_input_names,
                    recur_output_count,
                    symbol_types,
                    olap_env,
                    type_shapes,
                    type_errors,
                    type_warnings,
                    node_name,
                    functions,
                    decreases_variant,
                    decreases_variant_pos,
                );
            }
            Expr::UnaryOp { operand, .. } => {
                self.check_recur_in_expr(
                    operand,
                    recur_authorized,
                    recur_input_names,
                    recur_output_count,
                    symbol_types,
                    olap_env,
                    type_shapes,
                    type_errors,
                    type_warnings,
                    node_name,
                    functions,
                    decreases_variant,
                    decreases_variant_pos,
                );
            }
            Expr::FieldAccess { object, .. } => {
                self.check_recur_in_expr(
                    object,
                    recur_authorized,
                    recur_input_names,
                    recur_output_count,
                    symbol_types,
                    olap_env,
                    type_shapes,
                    type_errors,
                    type_warnings,
                    node_name,
                    functions,
                    decreases_variant,
                    decreases_variant_pos,
                );
            }
            Expr::IndexAccess { object, index } => {
                self.check_recur_in_expr(
                    object,
                    recur_authorized,
                    recur_input_names,
                    recur_output_count,
                    symbol_types,
                    olap_env,
                    type_shapes,
                    type_errors,
                    type_warnings,
                    node_name,
                    functions,
                    decreases_variant,
                    decreases_variant_pos,
                );
                self.check_recur_in_expr(
                    index,
                    recur_authorized,
                    recur_input_names,
                    recur_output_count,
                    symbol_types,
                    olap_env,
                    type_shapes,
                    type_errors,
                    type_warnings,
                    node_name,
                    functions,
                    decreases_variant,
                    decreases_variant_pos,
                );
            }
            Expr::IfExpr {
                cond,
                then,
                else_block,
            } => {
                self.check_recur_in_expr(
                    cond,
                    recur_authorized,
                    recur_input_names,
                    recur_output_count,
                    symbol_types,
                    olap_env,
                    type_shapes,
                    type_errors,
                    type_warnings,
                    node_name,
                    functions,
                    decreases_variant,
                    decreases_variant_pos,
                );
                // then/else_block are BlockBody — walk stmts and return_expr
                for stmt in &then.stmts {
                    if let Stmt::Let { expr, .. } = stmt {
                        self.check_recur_in_expr(
                            expr,
                            recur_authorized,
                            recur_input_names,
                            recur_output_count,
                            symbol_types,
                            olap_env,
                            type_shapes,
                            type_errors,
                            type_warnings,
                            node_name,
                            functions,
                            decreases_variant,
                            decreases_variant_pos,
                        );
                    }
                }
                if let Some(re) = &then.return_expr {
                    self.check_recur_in_expr(
                        re,
                        recur_authorized,
                        recur_input_names,
                        recur_output_count,
                        symbol_types,
                        olap_env,
                        type_shapes,
                        type_errors,
                        type_warnings,
                        node_name,
                        functions,
                        decreases_variant,
                        decreases_variant_pos,
                    );
                }
                if let Some(eb) = else_block {
                    for stmt in &eb.stmts {
                        if let Stmt::Let { expr, .. } = stmt {
                            self.check_recur_in_expr(
                                expr,
                                recur_authorized,
                                recur_input_names,
                                recur_output_count,
                                symbol_types,
                                olap_env,
                                type_shapes,
                                type_errors,
                                type_warnings,
                                node_name,
                                functions,
                                decreases_variant,
                                decreases_variant_pos,
                            );
                        }
                    }
                    if let Some(re) = &eb.return_expr {
                        self.check_recur_in_expr(
                            re,
                            recur_authorized,
                            recur_input_names,
                            recur_output_count,
                            symbol_types,
                            olap_env,
                            type_shapes,
                            type_errors,
                            type_warnings,
                            node_name,
                            functions,
                            decreases_variant,
                            decreases_variant_pos,
                        );
                    }
                }
            }
            _ => {}
        }
    }

    // LAB-IGNITER-COMPILER-TYPE-IR-ENUM-P5: the type helper boundary now routes
    // through the typed `IgType` model. The public `{name, params}` JSON shape is
    // preserved via `IgType::from_json_lossy` / `IgType::to_json`, so SIR output,
    // the emitter, and the VM are unaffected. The enum makes a non-string `name`,
    // a non-array `params`, or a bare object-with-no-name unrepresentable: those
    // fail closed to `Unknown` / no-params instead of slipping through.
    fn type_ir(&self, annotation: &serde_json::Value) -> serde_json::Value {
        IgType::from_json_lossy(annotation).to_json()
    }

    fn get_param(&self, type_info: &serde_json::Value, index: usize) -> Option<serde_json::Value> {
        IgType::from_json_lossy(type_info)
            .params()
            .get(index)
            .map(|param| param.to_json())
    }

    fn decimal_scale(&self, type_info: &serde_json::Value) -> String {
        IgType::from_json_lossy(type_info).decimal_scale()
    }

    fn type_name(&self, type_info: &serde_json::Value) -> String {
        IgType::from_json_lossy(type_info).name().to_string()
    }

    fn structurally_assignable(
        &self,
        actual: &serde_json::Value,
        expected: &serde_json::Value,
    ) -> bool {
        IgType::structurally_assignable(
            &IgType::from_json_lossy(actual),
            &IgType::from_json_lossy(expected),
        )
    }

    /// LANG-RUST-TYPED-COMPUTE-BINDING-P2: true when a type IR is Unknown or
    /// recursively contains any Unknown at any param depth.
    /// Mirrors Ruby `unknown_or_unknown_bearing?` in typechecker.rb.
    fn unknown_or_unknown_bearing(&self, t: &serde_json::Value) -> bool {
        IgType::from_json_lossy(t).is_unknown_bearing()
    }

    fn type_display(&self, type_info: &serde_json::Value) -> String {
        IgType::from_json_lossy(type_info).display()
    }

    fn check_record_literal_shape_col4(
        &self,
        fields: &HashMap<String, Expr>,
        expected_shape: &HashMap<String, serde_json::Value>,
        expected_type_name: &str,
        node_name: &str,
        symbol_types: &HashMap<String, serde_json::Value>,
        type_shapes: &HashMap<String, HashMap<String, serde_json::Value>>,
        type_errors: &mut Vec<ClassifierDiagnostic>,
    ) {
        let mut shape_errors = Vec::new();
        self.check_record_literal_shape(
            fields,
            expected_shape,
            expected_type_name,
            node_name,
            symbol_types,
            type_shapes,
            &mut shape_errors,
        );
        for err in shape_errors {
            type_errors.push(ClassifierDiagnostic {
                rule: "OOF-COL4".to_string(),
                message: format!(
                    "stdlib.collection.fold: accumulator record literal does not match {}: {}",
                    expected_type_name, err.message
                ),
                node: node_name.to_string(),
                line: err.line,
            });
        }
    }

    fn infer_fold_body_type(
        &self,
        body: &ExprOrBlock,
        local_symbols: &HashMap<String, serde_json::Value>,
        olap_env: &HashMap<String, HashMap<String, serde_json::Value>>,
        type_shapes: &HashMap<String, HashMap<String, serde_json::Value>>,
        expected_acc: &serde_json::Value,
        type_errors: &mut Vec<ClassifierDiagnostic>,
        type_warnings: &mut Vec<ClassifierDiagnostic>,
        node_name: &str,
        functions: &[crate::parser::FunctionDecl],
        contract_registry: &HashMap<String, ContractRegistryEntry>,
        current_contract_name: &str,
    ) -> serde_json::Value {
        match body {
            ExprOrBlock::Expr(expr) => self.infer_fold_expr_type(
                expr,
                local_symbols,
                olap_env,
                type_shapes,
                expected_acc,
                type_errors,
                type_warnings,
                node_name,
                functions,
                contract_registry,
                current_contract_name,
            ),
            ExprOrBlock::Block(block) => {
                let mut local = local_symbols.clone();
                let mut last_type = self.type_ir(&serde_json::Value::String("Unknown".to_string()));
                for stmt in &block.stmts {
                    match stmt {
                        Stmt::Let { name, expr } => {
                            let typed = self.infer_expr(
                                expr,
                                &local,
                                olap_env,
                                type_shapes,
                                type_errors,
                                type_warnings,
                                node_name,
                                functions,
                                contract_registry,
                                current_contract_name,
                            );
                            local.insert(name.clone(), typed.resolved_type.clone());
                            last_type = typed.resolved_type;
                        }
                        Stmt::ExprStmt { expr } => {
                            let typed = self.infer_expr(
                                expr,
                                &local,
                                olap_env,
                                type_shapes,
                                type_errors,
                                type_warnings,
                                node_name,
                                functions,
                                contract_registry,
                                current_contract_name,
                            );
                            last_type = typed.resolved_type;
                        }
                    }
                }
                if let Some(return_expr) = &block.return_expr {
                    last_type = self.infer_fold_expr_type(
                        return_expr,
                        &local,
                        olap_env,
                        type_shapes,
                        expected_acc,
                        type_errors,
                        type_warnings,
                        node_name,
                        functions,
                        contract_registry,
                        current_contract_name,
                    );
                }
                last_type
            }
        }
    }

    fn infer_fold_expr_type(
        &self,
        expr: &Expr,
        symbol_types: &HashMap<String, serde_json::Value>,
        olap_env: &HashMap<String, HashMap<String, serde_json::Value>>,
        type_shapes: &HashMap<String, HashMap<String, serde_json::Value>>,
        expected_acc: &serde_json::Value,
        type_errors: &mut Vec<ClassifierDiagnostic>,
        type_warnings: &mut Vec<ClassifierDiagnostic>,
        node_name: &str,
        functions: &[crate::parser::FunctionDecl],
        contract_registry: &HashMap<String, ContractRegistryEntry>,
        current_contract_name: &str,
    ) -> serde_json::Value {
        let typed = self.infer_expr(
            expr,
            symbol_types,
            olap_env,
            type_shapes,
            type_errors,
            type_warnings,
            node_name,
            functions,
            contract_registry,
            current_contract_name,
        );
        if let Expr::RecordLiteral { fields } = expr {
            let expected_name = self.type_name(expected_acc);
            if let Some(shape) = type_shapes.get(expected_name.as_str()) {
                let errors_before = type_errors.len();
                self.check_record_literal_shape_col4(
                    fields,
                    shape,
                    &expected_name,
                    node_name,
                    symbol_types,
                    type_shapes,
                    type_errors,
                );
                if type_errors.len() == errors_before {
                    return expected_acc.clone();
                }
            }
        }
        typed.resolved_type
    }

    fn infer_fold_call_type(
        &self,
        args: &[Expr],
        typed_args: &[TypedExpression],
        expected_acc: Option<&serde_json::Value>,
        symbol_types: &HashMap<String, serde_json::Value>,
        olap_env: &HashMap<String, HashMap<String, serde_json::Value>>,
        type_shapes: &HashMap<String, HashMap<String, serde_json::Value>>,
        type_errors: &mut Vec<ClassifierDiagnostic>,
        type_warnings: &mut Vec<ClassifierDiagnostic>,
        node_name: &str,
        functions: &[crate::parser::FunctionDecl],
        contract_registry: &HashMap<String, ContractRegistryEntry>,
        current_contract_name: &str,
    ) -> serde_json::Value {
        let unknown = self.type_ir(&serde_json::Value::String("Unknown".to_string()));
        if args.len() != 3 {
            type_errors.push(ClassifierDiagnostic {
                rule: "OOF-COL4".to_string(),
                message: format!(
                    "stdlib.collection.fold: expected 3 arguments (collection, seed, lambda), got {}",
                    args.len()
                ),
                node: node_name.to_string(),
                line: None,
            });
            return unknown;
        }

        let collection_type = typed_args
            .get(0)
            .map(|t| t.resolved_type.clone())
            .unwrap_or_else(|| unknown.clone());
        let collection_name = self.type_name(&collection_type);
        if collection_name != "Collection" && collection_name != "Unknown" {
            type_errors.push(ClassifierDiagnostic {
                rule: "OOF-COL4".to_string(),
                message: format!(
                    "stdlib.collection.fold: first argument must be Collection[T], got {}",
                    collection_name
                ),
                node: node_name.to_string(),
                line: None,
            });
        }
        let elem_type = if collection_name == "Collection" {
            self.get_param(&collection_type, 0)
                .unwrap_or_else(|| unknown.clone())
        } else {
            unknown.clone()
        };

        let mut acc_type = typed_args
            .get(1)
            .map(|t| t.resolved_type.clone())
            .unwrap_or_else(|| unknown.clone());
        if self.type_name(&acc_type) == "Unknown" {
            if let (Some(expected), Expr::RecordLiteral { fields }) = (expected_acc, &args[1]) {
                let expected_name = self.type_name(expected);
                if let Some(shape) = type_shapes.get(expected_name.as_str()) {
                    let errors_before = type_errors.len();
                    self.check_record_literal_shape_col4(
                        fields,
                        shape,
                        &expected_name,
                        node_name,
                        symbol_types,
                        type_shapes,
                        type_errors,
                    );
                    if type_errors.len() == errors_before {
                        acc_type = expected.clone();
                    }
                }
            }
        }

        if let Expr::Lambda { params, body } = &args[2] {
            if params.len() != 2 {
                type_errors.push(ClassifierDiagnostic {
                    rule: "OOF-COL4".to_string(),
                    message: format!(
                        "stdlib.collection.fold: lambda must accept exactly 2 params (acc, elem), got {}",
                        params.len()
                    ),
                    node: node_name.to_string(),
                    line: None,
                });
            } else if self.type_name(&acc_type) != "Unknown" {
                let mut local_symbols = symbol_types.clone();
                local_symbols.insert(params[0].clone(), acc_type.clone());
                local_symbols.insert(params[1].clone(), elem_type.clone());
                let body_errors_before = type_errors.len();
                let body_type = self.infer_fold_body_type(
                    body,
                    &local_symbols,
                    olap_env,
                    type_shapes,
                    &acc_type,
                    type_errors,
                    type_warnings,
                    node_name,
                    functions,
                    contract_registry,
                    current_contract_name,
                );
                if type_errors.len() == body_errors_before
                    && !self.structurally_assignable(&body_type, &acc_type)
                {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-COL4".to_string(),
                        message: format!(
                            "stdlib.collection.fold: lambda return type {} does not match accumulator type {}",
                            self.type_display(&body_type),
                            self.type_display(&acc_type)
                        ),
                        node: node_name.to_string(),
                        line: None,
                    });
                }
            }
        } else {
            type_errors.push(ClassifierDiagnostic {
                rule: "OOF-COL4".to_string(),
                message: "stdlib.collection.fold: third argument must be a lambda".to_string(),
                node: node_name.to_string(),
                line: None,
            });
        }

        acc_type
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
        col.insert(
            "name".to_string(),
            serde_json::Value::String("Collection".to_string()),
        );
        col.insert(
            "params".to_string(),
            serde_json::Value::Array(vec![text_inner]),
        );
        serde_json::Value::Object(col)
    }

    /// Canonical return type for a stdlib.text.* op name.
    fn text_stdlib_return_type(&self, fn_name: &str) -> serde_json::Value {
        match fn_name {
            "concat" | "trim" | "replace" | "replace_all" | "byte_slice" | "rune_slice"
            | "grapheme_slice" => self.type_ir(&serde_json::Value::String("Text".to_string())),
            "contains" | "starts_with" | "ends_with" | "matches" => {
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
                    fn_name,
                    expected_count,
                    typed_args.len()
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
                        fn_name,
                        idx + 1,
                        expected,
                        actual
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
    fn quick_arg_type(
        &self,
        expr: &Expr,
        symbol_types: &HashMap<String, serde_json::Value>,
    ) -> String {
        match expr {
            Expr::Ref { name } => symbol_types
                .get(name)
                .map(|t| self.type_name(t))
                .unwrap_or_else(|| "Unknown".to_string()),
            Expr::Literal { type_tag, .. } => type_tag.clone(),
            Expr::Call { fn_name, .. } => {
                // Collection-producing fns
                if matches!(
                    fn_name.as_str(),
                    "split"
                        | "range"
                        | "filter"
                        | "map"
                        | "flat_map"
                        | "zip"
                        | "take"
                        | "stdlib.collection.concat"
                ) {
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
                let rewritten_args: Vec<Expr> = args
                    .iter()
                    .map(|a| self.rewrite_concat_calls(a, symbol_types))
                    .collect();
                let new_fn = if fn_name == "concat" {
                    let first_type = args
                        .first()
                        .map(|a| self.quick_arg_type(a, symbol_types))
                        .unwrap_or_else(|| "Unknown".to_string());
                    if first_type == "Collection" || first_type == "Unknown" {
                        "stdlib.collection.concat".to_string()
                    } else if first_type == "String" {
                        // LANG-STRING-TEXT-ALIAS-P2: String+String → stdlib.string.concat
                        let second_type = args
                            .get(1)
                            .map(|a| self.quick_arg_type(a, symbol_types))
                            .unwrap_or_else(|| "Unknown".to_string());
                        if second_type == "String" {
                            "stdlib.string.concat".to_string()
                        } else {
                            "stdlib.text.concat".to_string()
                        }
                    } else {
                        "stdlib.text.concat".to_string()
                    }
                } else {
                    fn_name.clone()
                };
                Expr::Call {
                    fn_name: new_fn,
                    args: rewritten_args,
                }
            }
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
            Expr::IfExpr {
                cond,
                then,
                else_block,
            } => {
                use crate::parser::{BlockBody, Stmt};
                fn rewrite_block(
                    tc: &TypeChecker,
                    block: &BlockBody,
                    sym: &HashMap<String, serde_json::Value>,
                ) -> BlockBody {
                    let stmts = block
                        .stmts
                        .iter()
                        .map(|s| match s {
                            Stmt::Let { name, expr } => Stmt::Let {
                                name: name.clone(),
                                expr: tc.rewrite_concat_calls(expr, sym),
                            },
                            Stmt::ExprStmt { expr } => Stmt::ExprStmt {
                                expr: tc.rewrite_concat_calls(expr, sym),
                            },
                        })
                        .collect();
                    let return_expr = block
                        .return_expr
                        .as_ref()
                        .map(|e| Box::new(tc.rewrite_concat_calls(e, sym)));
                    BlockBody { stmts, return_expr }
                }
                Expr::IfExpr {
                    cond: Box::new(self.rewrite_concat_calls(cond, symbol_types)),
                    then: rewrite_block(self, then, symbol_types),
                    else_block: else_block
                        .as_ref()
                        .map(|b| rewrite_block(self, b, symbol_types)),
                }
            }
            Expr::Lambda { params, body } => {
                use crate::parser::{BlockBody, ExprOrBlock, Stmt};

                let body = match body.as_ref() {
                    ExprOrBlock::Expr(e) => {
                        ExprOrBlock::Expr(self.rewrite_concat_calls(e, symbol_types))
                    }
                    ExprOrBlock::Block(block) => {
                        let stmts = block
                            .stmts
                            .iter()
                            .map(|s| match s {
                                Stmt::Let { name, expr } => Stmt::Let {
                                    name: name.clone(),
                                    expr: self.rewrite_concat_calls(expr, symbol_types),
                                },
                                Stmt::ExprStmt { expr } => Stmt::ExprStmt {
                                    expr: self.rewrite_concat_calls(expr, symbol_types),
                                },
                            })
                            .collect();
                        let return_expr = block
                            .return_expr
                            .as_ref()
                            .map(|e| Box::new(self.rewrite_concat_calls(e, symbol_types)));
                        ExprOrBlock::Block(BlockBody { stmts, return_expr })
                    }
                };

                Expr::Lambda {
                    params: params.clone(),
                    body: Box::new(body),
                }
            }
            Expr::ArrayLiteral { items } => Expr::ArrayLiteral {
                items: items
                    .iter()
                    .map(|i| self.rewrite_concat_calls(i, symbol_types))
                    .collect(),
            },
            Expr::RecordLiteral { fields } => Expr::RecordLiteral {
                fields: fields
                    .iter()
                    .map(|(k, v)| (k.clone(), self.rewrite_concat_calls(v, symbol_types)))
                    .collect(),
            },
            Expr::RecordSpread { spread, fields } => Expr::RecordSpread {
                spread: Box::new(self.rewrite_concat_calls(spread, symbol_types)),
                fields: fields
                    .iter()
                    .map(|(k, v)| (k.clone(), self.rewrite_concat_calls(v, symbol_types)))
                    .collect(),
            },
            // Leaf nodes: clone as-is
            _ => expr.clone(),
        }
    }

    // ---- end igniter-string-core helpers ------------------------------------

    fn blocking_rule_present(&self, errors: &[ClassifierDiagnostic]) -> bool {
        let blocking = [
            "OOF-P1", "OOF-CE4", "OOF-OS2", "OOF-H1", "OOF-BT1", "OOF-BT2", "OOF-BT3", "OOF-BT4",
            "OOF-TM1", "OOF-TM3", "OOF-TM4", "OOF-TM5", "OOF-TM6", "OOF-S3", "OOF-O3", "OOF-O4",
            "OOF-O5", "OOF-IV3",
        ];
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

    /// LAB-LANG-MATCH-ARM-BINDINGS-P2: type a block body's `let` statements left-to-right, returning a
    /// child symbol scope that includes the block-local bindings. `let`-bound names are block-local and do
    /// not leak past the block; expr-statements are typed for diagnostics. The block's final expression is
    /// typed by the caller in the returned scope.
    #[allow(clippy::too_many_arguments)]
    fn infer_block_scope(
        &self,
        block: &crate::parser::BlockBody,
        symbol_types: &HashMap<String, serde_json::Value>,
        olap_env: &HashMap<String, HashMap<String, serde_json::Value>>,
        type_shapes: &HashMap<String, HashMap<String, serde_json::Value>>,
        type_errors: &mut Vec<ClassifierDiagnostic>,
        type_warnings: &mut Vec<ClassifierDiagnostic>,
        node_name: &str,
        functions: &[crate::parser::FunctionDecl],
        contract_registry: &HashMap<String, ContractRegistryEntry>,
        current_contract_name: &str,
    ) -> HashMap<String, serde_json::Value> {
        let mut scope = symbol_types.clone();
        for stmt in &block.stmts {
            match stmt {
                crate::parser::Stmt::Let { name, expr } => {
                    let t = self.infer_expr(
                        expr,
                        &scope,
                        olap_env,
                        type_shapes,
                        type_errors,
                        type_warnings,
                        node_name,
                        functions,
                        contract_registry,
                        current_contract_name,
                    );
                    scope.insert(name.clone(), t.resolved_type);
                }
                crate::parser::Stmt::ExprStmt { expr } => {
                    let _ = self.infer_expr(
                        expr,
                        &scope,
                        olap_env,
                        type_shapes,
                        type_errors,
                        type_warnings,
                        node_name,
                        functions,
                        contract_registry,
                        current_contract_name,
                    );
                }
            }
        }
        scope
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
        contract_registry: &HashMap<String, ContractRegistryEntry>,
        current_contract_name: &str,
    ) -> TypedExpression {
        // LAB-COMPILER-LIVENESS-P2: non-fatal depth counter (RAII — auto-decrements on all exits)
        let _depth_guard = crate::liveness::TcInferGuard::enter();
        match expr {
            Expr::Literal { value, type_tag } => {
                let ty = self.type_ir(&serde_json::Value::String(type_tag.clone()));
                TypedExpression {
                    resolved_type: ty,
                    deps: Vec::new(),
                    annotated_expr: None,
                }
            }
            Expr::Symbol { value } => {
                let ty = self.type_ir(&serde_json::Value::String("Symbol".to_string()));
                TypedExpression {
                    resolved_type: ty,
                    deps: Vec::new(),
                    annotated_expr: None,
                }
            }
            Expr::Ref { name } => {
                let in_symbols = symbol_types.contains_key(name);
                let in_olap = olap_env.contains_key(name);
                let ty = symbol_types
                    .get(name)
                    .cloned()
                    .or_else(|| olap_env.get(name).and_then(|o| o.get("type")).cloned())
                    .unwrap_or_else(|| {
                        self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                    });
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
                    annotated_expr: None,
                }
            }
            Expr::FieldAccess { object, field } => {
                let obj_typed = self.infer_expr(
                    object,
                    symbol_types,
                    olap_env,
                    type_shapes,
                    type_errors,
                    type_warnings,
                    node_name,
                    functions,
                    contract_registry,
                    current_contract_name,
                );
                let obj_type = self.type_name(&obj_typed.resolved_type);

                // OOF-R3 v0 whitelist: Collection.tail / Collection.rest return Collection[T]
                // This is the structural decrease pattern; no type error for whitelisted accessors.
                if obj_type == "Collection" && (field == "tail" || field == "rest") {
                    return TypedExpression {
                        resolved_type: obj_typed.resolved_type.clone(),
                        deps: obj_typed.deps,
                        annotated_expr: None,
                    };
                }

                // LAB-STDLIB-COLLECTION-ZIP-PROOF-P2: `Pair[A, B]` is the synthetic element type produced
                // by `zip` (it has no `type_shapes` entry — it is only ever built as a return type). Resolve
                // its two structural accessors from the type params so paired iteration typechecks:
                // `.first` → param 0 (A), `.second` → param 1 (B). Mirrors the Collection.tail/rest whitelist
                // above; an Unknown param resolves to Unknown (acceptable, never a false OOF-P1).
                if obj_type == "Pair" && (field == "first" || field == "second") {
                    let idx = if field == "first" { 0 } else { 1 };
                    let elem = self
                        .get_param(&obj_typed.resolved_type, idx)
                        .unwrap_or_else(|| {
                            self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                        });
                    return TypedExpression {
                        resolved_type: elem,
                        deps: obj_typed.deps,
                        annotated_expr: None,
                    };
                }

                // PROP-042 T3: suppress OOF-P1 for ALL field accesses on the T3-measured input.
                // T3 allows any T2-registered accessor; OOF-R11 is the authoritative diagnostic
                // for structural coverage failures. Without this suppression, user-declared
                // accessors (e.g. items.sub from size_relation Collection sub) fire OOF-P1
                // because they're not real fields in type_shapes.
                {
                    let t3_ctx = self.t3_context.borrow();
                    if let Some(ctx) = t3_ctx.as_ref() {
                        if let Expr::Ref { name } = object.as_ref() {
                            if name == &ctx.arg_name {
                                // Suppress OOF-P1 — return the object type (Collection propagates through)
                                return TypedExpression {
                                    resolved_type: obj_typed.resolved_type.clone(),
                                    deps: obj_typed.deps,
                                    annotated_expr: None,
                                };
                            }
                        }
                    }
                }

                let field_type = type_shapes
                    .get(&obj_type)
                    .and_then(|fields| fields.get(field))
                    .cloned()
                    .unwrap_or_else(|| {
                        self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                    });

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
                    annotated_expr: None,
                }
            }
            Expr::BinaryOp { op, left, right } => {
                let left_typed = self.infer_expr(
                    left,
                    symbol_types,
                    olap_env,
                    type_shapes,
                    type_errors,
                    type_warnings,
                    node_name,
                    functions,
                    contract_registry,
                    current_contract_name,
                );
                let right_typed = self.infer_expr(
                    right,
                    symbol_types,
                    olap_env,
                    type_shapes,
                    type_errors,
                    type_warnings,
                    node_name,
                    functions,
                    contract_registry,
                    current_contract_name,
                );
                let (resolved_op, res_type) = self.operator_type(
                    op,
                    &left_typed.resolved_type,
                    &right_typed.resolved_type,
                    type_errors,
                    node_name,
                );

                let mut deps = left_typed.deps;
                deps.append(&mut right_typed.deps.clone());

                TypedExpression {
                    resolved_type: res_type,
                    deps,
                    annotated_expr: None,
                }
            }
            Expr::IfExpr {
                cond,
                then,
                else_block,
            } => {
                // cond must be Bool (OOF-IF1)
                let cond_typed = self.infer_expr(
                    cond,
                    symbol_types,
                    olap_env,
                    type_shapes,
                    type_errors,
                    type_warnings,
                    node_name,
                    functions,
                    contract_registry,
                    current_contract_name,
                );
                if self.type_name(&cond_typed.resolved_type) != "Bool"
                    && self.type_name(&cond_typed.resolved_type) != "Unknown"
                {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-IF1".to_string(),
                        message: format!(
                            "if_expr condition must be Bool, got {}",
                            self.type_name(&cond_typed.resolved_type)
                        ),
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
                        resolved_type: self
                            .type_ir(&serde_json::Value::String("Unknown".to_string())),
                        deps: cond_typed.deps,
                        annotated_expr: None,
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
                        resolved_type: self
                            .type_ir(&serde_json::Value::String("Unknown".to_string())),
                        deps: cond_typed.deps,
                        annotated_expr: None,
                    };
                }

                // LAB-LANG-MATCH-ARM-BINDINGS-P2: each branch's `let` bindings are block-local — type the
                // final expression in a child scope that includes them (the branch body is a DAG, not a
                // sequence; `let` is just a named subexpression).
                let then_scope = self.infer_block_scope(
                    then,
                    symbol_types,
                    olap_env,
                    type_shapes,
                    type_errors,
                    type_warnings,
                    node_name,
                    functions,
                    contract_registry,
                    current_contract_name,
                );
                let else_scope = self.infer_block_scope(
                    else_block.as_ref().unwrap(),
                    symbol_types,
                    olap_env,
                    type_shapes,
                    type_errors,
                    type_warnings,
                    node_name,
                    functions,
                    contract_registry,
                    current_contract_name,
                );
                let then_typed = self.infer_expr(
                    then_final.unwrap(),
                    &then_scope,
                    olap_env,
                    type_shapes,
                    type_errors,
                    type_warnings,
                    node_name,
                    functions,
                    contract_registry,
                    current_contract_name,
                );
                let else_typed = self.infer_expr(
                    else_final.unwrap(),
                    &else_scope,
                    olap_env,
                    type_shapes,
                    type_errors,
                    type_warnings,
                    node_name,
                    functions,
                    contract_registry,
                    current_contract_name,
                );

                let then_name = self.type_name(&then_typed.resolved_type);
                let else_name = self.type_name(&else_typed.resolved_type);

                // OOF-IF3 check: then/else branch types must exact-match
                let resolved_type =
                    if then_name != "Unknown" && else_name != "Unknown" && then_name != else_name {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-IF3".to_string(),
                            message: format!(
                                "if_expr branch types must match: then={}, else={}",
                                then_name, else_name
                            ),
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
                    annotated_expr: None,
                }
            }
            // LAB-LANG-MATCH-ARM-BINDINGS-P2: a block expr (match-arm block) — type its `let` bindings
            // into a child scope, then the final expression IS the block's value.
            Expr::Block(block) => {
                let scope = self.infer_block_scope(
                    block,
                    symbol_types,
                    olap_env,
                    type_shapes,
                    type_errors,
                    type_warnings,
                    node_name,
                    functions,
                    contract_registry,
                    current_contract_name,
                );
                match block.return_expr.as_ref() {
                    Some(re) => self.infer_expr(
                        re,
                        &scope,
                        olap_env,
                        type_shapes,
                        type_errors,
                        type_warnings,
                        node_name,
                        functions,
                        contract_registry,
                        current_contract_name,
                    ),
                    None => TypedExpression {
                        resolved_type: self
                            .type_ir(&serde_json::Value::String("Unknown".to_string())),
                        deps: Vec::new(),
                        annotated_expr: None,
                    },
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
                        return TypedExpression {
                            resolved_type: self
                                .type_ir(&serde_json::Value::String("Unknown".to_string())),
                            deps: Vec::new(),
                            annotated_expr: None,
                        };
                    }
                    let history_typed = self.infer_expr(
                        &args[0],
                        symbol_types,
                        olap_env,
                        type_shapes,
                        type_errors,
                        type_warnings,
                        node_name,
                        functions,
                        contract_registry,
                        current_contract_name,
                    );
                    let as_of_typed = self.infer_expr(
                        &args[1],
                        symbol_types,
                        olap_env,
                        type_shapes,
                        type_errors,
                        type_warnings,
                        node_name,
                        functions,
                        contract_registry,
                        current_contract_name,
                    );

                    if self.type_name(&as_of_typed.resolved_type) != "DateTime"
                        && self.type_name(&as_of_typed.resolved_type) != "Unknown"
                    {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-TM3".to_string(),
                            message: format!(
                                "history_at: as_of must be DateTime, got {}",
                                self.type_name(&as_of_typed.resolved_type)
                            ),
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
                    opt.insert(
                        "name".to_string(),
                        serde_json::Value::String("Option".to_string()),
                    );
                    let mut inner_ty = serde_json::Map::new();
                    inner_ty.insert("name".to_string(), serde_json::Value::String(inner));
                    inner_ty.insert("params".to_string(), serde_json::Value::Array(Vec::new()));
                    opt.insert(
                        "params".to_string(),
                        serde_json::Value::Array(vec![serde_json::Value::Object(inner_ty)]),
                    );

                    let mut deps = history_typed.deps;
                    deps.append(&mut as_of_typed.deps.clone());

                    TypedExpression {
                        resolved_type: serde_json::Value::Object(opt),
                        deps,
                        annotated_expr: None,
                    }
                } else if fn_name == "bihistory_at" {
                    if args.len() < 2 {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-TM4".to_string(),
                            message: "bihistory_at requires valid_time (vt) argument".to_string(),
                            node: node_name.to_string(),
                            line: None,
                        });
                        return TypedExpression {
                            resolved_type: self
                                .type_ir(&serde_json::Value::String("Unknown".to_string())),
                            deps: Vec::new(),
                            annotated_expr: None,
                        };
                    }
                    if args.len() < 3 {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-TM5".to_string(),
                            message: "bihistory_at requires transaction_time (tt) argument"
                                .to_string(),
                            node: node_name.to_string(),
                            line: None,
                        });
                        return TypedExpression {
                            resolved_type: self
                                .type_ir(&serde_json::Value::String("Unknown".to_string())),
                            deps: Vec::new(),
                            annotated_expr: None,
                        };
                    }
                    let history_typed = self.infer_expr(
                        &args[0],
                        symbol_types,
                        olap_env,
                        type_shapes,
                        type_errors,
                        type_warnings,
                        node_name,
                        functions,
                        contract_registry,
                        current_contract_name,
                    );
                    let vt_typed = self.infer_expr(
                        &args[1],
                        symbol_types,
                        olap_env,
                        type_shapes,
                        type_errors,
                        type_warnings,
                        node_name,
                        functions,
                        contract_registry,
                        current_contract_name,
                    );
                    let tt_typed = self.infer_expr(
                        &args[2],
                        symbol_types,
                        olap_env,
                        type_shapes,
                        type_errors,
                        type_warnings,
                        node_name,
                        functions,
                        contract_registry,
                        current_contract_name,
                    );

                    for (idx, axis_ref) in [&vt_typed, &tt_typed].iter().enumerate() {
                        let axis_name = if idx == 0 {
                            "valid_time"
                        } else {
                            "transaction_time"
                        };
                        if self.type_name(&axis_ref.resolved_type) != "DateTime"
                            && self.type_name(&axis_ref.resolved_type) != "Unknown"
                        {
                            type_errors.push(ClassifierDiagnostic {
                                rule: "OOF-TM6".to_string(),
                                message: format!(
                                    "bihistory_at: {} must be DateTime, got {}",
                                    axis_name,
                                    self.type_name(&axis_ref.resolved_type)
                                ),
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
                    opt.insert(
                        "name".to_string(),
                        serde_json::Value::String("Option".to_string()),
                    );
                    let mut inner_ty = serde_json::Map::new();
                    inner_ty.insert("name".to_string(), serde_json::Value::String(inner));
                    inner_ty.insert("params".to_string(), serde_json::Value::Array(Vec::new()));
                    opt.insert(
                        "params".to_string(),
                        serde_json::Value::Array(vec![serde_json::Value::Object(inner_ty)]),
                    );

                    let mut deps = history_typed.deps;
                    deps.append(&mut vt_typed.deps.clone());
                    deps.append(&mut tt_typed.deps.clone());

                    TypedExpression {
                        resolved_type: serde_json::Value::Object(opt),
                        deps,
                        annotated_expr: None,
                    }
                } else {
                    let mut is_resolved = false;
                    let mut resolved_type =
                        self.type_ir(&serde_json::Value::String("Unknown".to_string()));
                    let mut deps = Vec::new();

                    let mut typed_args = Vec::new();
                    for arg in args {
                        let arg_typed = self.infer_expr(
                            arg,
                            symbol_types,
                            olap_env,
                            type_shapes,
                            type_errors,
                            type_warnings,
                            node_name,
                            functions,
                            contract_registry,
                            current_contract_name,
                        );
                        deps.extend(arg_typed.deps.clone());
                        typed_args.push(arg_typed);
                    }
                    deps.sort();
                    deps.dedup();

                    // LANG-SUMTYPE-CONSTRUCT-MATCH-P3: sealed constructors some/none/ok/err
                    // lower to sealed variant_construct nodes (precede user-fn/stdlib paths,
                    // mirroring the Ruby canon dispatch).
                    if Self::is_sealed_constructor(fn_name) {
                        return self.infer_sealed_construct(
                            fn_name,
                            args,
                            &typed_args,
                            deps,
                            type_errors,
                            node_name,
                        );
                    }

                    // Check user-defined functions
                    for f in functions {
                        if f.name == *fn_name {
                            is_resolved = true;
                            resolved_type =
                                self.type_ir(&serde_json::to_value(&f.return_type).unwrap());
                            // LAB-IGNITER-COMPILER-USER-FN-SIGNATURE-CHECK-P6: validate the call
                            // signature before trusting `return_type`. Previously an app-local
                            // `def` call was accepted by name alone, so a wrong arity or a wrong
                            // argument type was laundered into the (trusted) return type. The
                            // argument expressions were already inferred into `typed_args` above.
                            self.check_user_fn_call_signature(
                                f,
                                args,
                                &typed_args,
                                node_name,
                                type_errors,
                            );
                            break;
                        }
                    }

                    if !is_resolved {
                        if let Some(stdlib_type) = self.infer_stdlib_call(
                            fn_name,
                            args,
                            &typed_args,
                            symbol_types,
                            olap_env,
                            type_shapes,
                            type_errors,
                            type_warnings,
                            node_name,
                            functions,
                            contract_registry,
                            current_contract_name,
                        ) {
                            is_resolved = true;
                            resolved_type = stdlib_type;
                        }
                    }

                    if is_resolved {
                        TypedExpression {
                            resolved_type,
                            deps,
                            annotated_expr: None,
                        }
                    } else {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-TY0".to_string(),
                            message: format!("Unknown function: {}", fn_name),
                            node: node_name.to_string(),
                            line: None,
                        });
                        TypedExpression {
                            resolved_type: self
                                .type_ir(&serde_json::Value::String("Unknown".to_string())),
                            deps: Vec::new(),
                            annotated_expr: None,
                        }
                    }
                }
            }
            Expr::IndexAccess { object, index } => {
                if let Expr::Ref { name } = object.as_ref() {
                    if let Some(point) = olap_env.get(name) {
                        if let Expr::SliceRecord { fields } = index.as_ref() {
                            // Check dimensions: OOF-O4
                            let expected_dims: HashMap<String, serde_json::Value> = point
                                .get("dimensions")
                                .unwrap()
                                .as_object()
                                .unwrap()
                                .iter()
                                .map(|(k, v)| (k.clone(), v.clone()))
                                .collect();
                            for expected_dim in expected_dims.keys() {
                                if !fields.contains_key(expected_dim) {
                                    type_errors.push(ClassifierDiagnostic {
                                        rule: "OOF-O4".to_string(),
                                        message: format!(
                                            "OLAPPoint access missing required dimension: {}",
                                            expected_dim
                                        ),
                                        node: node_name.to_string(),
                                        line: None,
                                    });
                                }
                            }

                            // Validate dimensions types: OOF-O5
                            let mut deps = Vec::new();
                            for (dim_name, slice_expr) in fields {
                                let slice_typed = self.infer_expr(
                                    slice_expr,
                                    symbol_types,
                                    olap_env,
                                    type_shapes,
                                    type_errors,
                                    type_warnings,
                                    node_name,
                                    functions,
                                    contract_registry,
                                    current_contract_name,
                                );
                                deps.append(&mut slice_typed.deps.clone());
                                if let Some(expected_type) = expected_dims.get(dim_name) {
                                    let expected_name = self.type_name(expected_type);
                                    let slice_name = self.type_name(&slice_typed.resolved_type);
                                    if expected_name != "Unknown"
                                        && slice_name != "Unknown"
                                        && expected_name != slice_name
                                    {
                                        type_errors.push(ClassifierDiagnostic {
                                            rule: "OOF-O5".to_string(),
                                            message: format!(
                                                "OLAPPoint dimension '{}' expected {}, got {}",
                                                dim_name, expected_name, slice_name
                                            ),
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
                                annotated_expr: None,
                            };
                        } else {
                            type_errors.push(ClassifierDiagnostic {
                                rule: "OOF-O4".to_string(),
                                message: "OLAPPoint access requires a dimension slice record"
                                    .to_string(),
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
                    annotated_expr: None,
                }
            }
            Expr::Lambda { params, body } => {
                let mut local_symbol_types = symbol_types.clone();
                for param in params {
                    local_symbol_types.insert(
                        param.clone(),
                        self.type_ir(&serde_json::Value::String("Integer".to_string())),
                    );
                }
                let mut temp_errors = Vec::new();
                let deps = match body.as_ref() {
                    ExprOrBlock::Expr(e) => {
                        let body_typed = self.infer_expr(
                            e,
                            &local_symbol_types,
                            olap_env,
                            type_shapes,
                            &mut temp_errors,
                            type_warnings,
                            node_name,
                            functions,
                            contract_registry,
                            current_contract_name,
                        );
                        body_typed.deps
                    }
                    ExprOrBlock::Block(block) => {
                        let mut block_deps = Vec::new();
                        for stmt in &block.stmts {
                            match stmt {
                                Stmt::Let { name, expr } => {
                                    local_symbol_types.insert(
                                        name.clone(),
                                        self.type_ir(&serde_json::Value::String(
                                            "Unknown".to_string(),
                                        )),
                                    );
                                    let stmt_typed = self.infer_expr(
                                        expr,
                                        &local_symbol_types,
                                        olap_env,
                                        type_shapes,
                                        &mut temp_errors,
                                        type_warnings,
                                        node_name,
                                        functions,
                                        contract_registry,
                                        current_contract_name,
                                    );
                                    block_deps.extend(stmt_typed.deps);
                                }
                                Stmt::ExprStmt { expr } => {
                                    let stmt_typed = self.infer_expr(
                                        expr,
                                        &local_symbol_types,
                                        olap_env,
                                        type_shapes,
                                        &mut temp_errors,
                                        type_warnings,
                                        node_name,
                                        functions,
                                        contract_registry,
                                        current_contract_name,
                                    );
                                    block_deps.extend(stmt_typed.deps);
                                }
                            }
                        }
                        if let Some(re) = &block.return_expr {
                            let re_typed = self.infer_expr(
                                re,
                                &local_symbol_types,
                                olap_env,
                                type_shapes,
                                &mut temp_errors,
                                type_warnings,
                                node_name,
                                functions,
                                contract_registry,
                                current_contract_name,
                            );
                            block_deps.extend(re_typed.deps);
                        }
                        block_deps
                    }
                };
                TypedExpression {
                    resolved_type: self.type_ir(&serde_json::Value::String("Unknown".to_string())),
                    deps,
                    annotated_expr: None,
                }
            }
            Expr::RecordLiteral { fields } => {
                // LAB-RACK-P12: RecordLiteral type inference.
                // All field expressions are typed for dependency collection and error
                // propagation. The literal itself resolves to Unknown — nominal record
                // type matching (structural → named) requires explicit type annotation
                // context not available in infer_expr; deferred to a future card.
                //
                // The Unknown resolved type is compatible with any declared output type
                // via the P9/P11 Unknown output compatibility rule. The declared
                // output type annotation (e.g. `output response : RackResponse`) drives
                // the module contract registry, so P11 callers can still resolve
                // call_contract("Handler", ...) → RackResponse from the registry.

                // PROP-044-P9: OOF-KIND6 — reserved __* field names in record literals.
                for key in fields.keys() {
                    if key.starts_with("__") {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-KIND6".to_string(),
                            message: format!(
                                "Record literal field '{}' uses reserved compiler prefix '__' (compiler-owned variant runtime field)",
                                key
                            ),
                            node: node_name.to_string(),
                            line: None,
                        });
                    }
                }

                let mut deps = Vec::new();
                for expr in fields.values() {
                    let typed = self.infer_expr(
                        expr,
                        symbol_types,
                        olap_env,
                        type_shapes,
                        type_errors,
                        type_warnings,
                        node_name,
                        functions,
                        contract_registry,
                        current_contract_name,
                    );
                    deps.extend(typed.deps);
                }
                TypedExpression {
                    resolved_type: self.type_ir(&serde_json::Value::String("Unknown".to_string())),
                    deps,
                    annotated_expr: None,
                }
            }
            // LAB-LANG-RECORD-SPREAD-P2: type the spread source + explicit fields for deps/diagnostics; the
            // literal stays Unknown here. The actual expansion to an explicit `record_literal` (and the
            // shape-check against the declared target record type) happens at the compute-decl level, where
            // the target type hint is available (mirrors the RecordLiteral nominal upgrade).
            Expr::RecordSpread { spread, fields } => {
                for key in fields.keys() {
                    if key.starts_with("__") {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-KIND6".to_string(),
                            message: format!(
                                "Record literal field '{}' uses reserved compiler prefix '__' (compiler-owned variant runtime field)",
                                key
                            ),
                            node: node_name.to_string(),
                            line: None,
                        });
                    }
                }
                let mut deps = Vec::new();
                let src_typed = self.infer_expr(
                    spread,
                    symbol_types,
                    olap_env,
                    type_shapes,
                    type_errors,
                    type_warnings,
                    node_name,
                    functions,
                    contract_registry,
                    current_contract_name,
                );
                deps.extend(src_typed.deps);
                for expr in fields.values() {
                    let typed = self.infer_expr(
                        expr,
                        symbol_types,
                        olap_env,
                        type_shapes,
                        type_errors,
                        type_warnings,
                        node_name,
                        functions,
                        contract_registry,
                        current_contract_name,
                    );
                    deps.extend(typed.deps);
                }
                TypedExpression {
                    resolved_type: self.type_ir(&serde_json::Value::String("Unknown".to_string())),
                    deps,
                    annotated_expr: None,
                }
            }
            Expr::ArrayLiteral { items } => {
                // LAB-TC-ARRAY-P1: ArrayLiteral element typing.
                // Each element expression is typed for dependency collection and
                // error propagation. The literal itself resolves to Unknown here;
                // nominal Collection[T] typing requires the declared output type
                // context (not available in infer_expr) and is performed in the
                // compute phase via check_array_literal_shape (see
                // collection_output_hints). This mirrors the RecordLiteral arm.
                //
                // The Unknown resolved type is compatible with any declared output
                // type via the P9/P11 Unknown output compatibility rule, so a
                // free-standing array literal (no Collection output hint) does not
                // fabricate a type and does not emit OOF-TY0.
                let mut deps = Vec::new();
                for item in items {
                    let typed = self.infer_expr(
                        item,
                        symbol_types,
                        olap_env,
                        type_shapes,
                        type_errors,
                        type_warnings,
                        node_name,
                        functions,
                        contract_registry,
                        current_contract_name,
                    );
                    deps.extend(typed.deps);
                }
                TypedExpression {
                    resolved_type: self.type_ir(&serde_json::Value::String("Unknown".to_string())),
                    deps,
                    annotated_expr: None,
                }
            }
            // PROP-044 P5: variant construct — `ArmName { field: expr, ... }`
            Expr::VariantConstruct { arm, fields } => self.infer_variant_construct(
                arm,
                fields,
                symbol_types,
                olap_env,
                type_shapes,
                type_errors,
                type_warnings,
                node_name,
                functions,
                contract_registry,
                current_contract_name,
            ),
            // PROP-044 P5: match expression — `match subject { Arm { bindings } => body, ... }`
            Expr::MatchExpr { subject, arms } => self.infer_match_expr(
                subject,
                arms,
                symbol_types,
                olap_env,
                type_shapes,
                type_errors,
                type_warnings,
                node_name,
                functions,
                contract_registry,
                current_contract_name,
            ),
            // LANG-UNARY-OPERATORS-P4: ! : Bool -> Bool, - : Integer -> Integer
            Expr::UnaryOp { op, operand } => {
                let operand_typed = self.infer_expr(
                    operand,
                    symbol_types,
                    olap_env,
                    type_shapes,
                    type_errors,
                    type_warnings,
                    node_name,
                    functions,
                    contract_registry,
                    current_contract_name,
                );
                let operand_type_name = self.type_name(&operand_typed.resolved_type);
                let (_fn_name, result_type_name) = match op.as_str() {
                    "!" => {
                        if operand_type_name != "Bool" && operand_type_name != "Unknown" {
                            type_errors.push(ClassifierDiagnostic {
                                rule: "OOF-TY0".to_string(),
                                message: format!(
                                    "Unary `!` requires Bool operand, got {}",
                                    operand_type_name
                                ),
                                node: node_name.to_string(),
                                line: None,
                            });
                        }
                        ("stdlib.primitive.not", "Bool")
                    }
                    "-" => {
                        if operand_type_name != "Integer" && operand_type_name != "Unknown" {
                            type_errors.push(ClassifierDiagnostic {
                                rule: "OOF-TY0".to_string(),
                                message: format!(
                                    "Unary `-` requires Integer operand, got {}",
                                    operand_type_name
                                ),
                                node: node_name.to_string(),
                                line: None,
                            });
                        }
                        ("stdlib.integer.neg", "Integer")
                    }
                    _ => {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-TY0".to_string(),
                            message: format!("Unknown unary operator: {}", op),
                            node: node_name.to_string(),
                            line: None,
                        });
                        ("stdlib.unsupported", "Unknown")
                    }
                };
                TypedExpression {
                    resolved_type: self
                        .type_ir(&serde_json::Value::String(result_type_name.to_string())),
                    deps: operand_typed.deps,
                    annotated_expr: None,
                }
            }
            // LAB-LANG-FALLIBLE-BINDING-P2: a `Try` only reaches the typechecker if `?` was used outside a
            // `let` RHS inside an output-producing block (valid uses are desugared away in the parser).
            Expr::Try { expr: inner } => {
                let _ = self.infer_expr(
                    inner,
                    symbol_types,
                    olap_env,
                    type_shapes,
                    type_errors,
                    type_warnings,
                    node_name,
                    functions,
                    contract_registry,
                    current_contract_name,
                );
                type_errors.push(ClassifierDiagnostic {
                    rule: "OOF-Q3".to_string(),
                    message: "? is only allowed as a `let` binding right-hand side inside an output-producing block"
                        .to_string(),
                    node: node_name.to_string(),
                    line: None,
                });
                TypedExpression {
                    resolved_type: self.type_ir(&serde_json::Value::String("Unknown".to_string())),
                    deps: Vec::new(),
                    annotated_expr: None,
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
                    annotated_expr: None,
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
            Expr::VariantConstruct { .. } => "variant_construct".to_string(),
            Expr::MatchExpr { .. } => "match_expr".to_string(),
            Expr::Block(_) => "block".to_string(),
            Expr::RecordSpread { .. } => "record_spread".to_string(),
            Expr::Try { .. } => "try".to_string(),
            Expr::Error { .. } => "error".to_string(),
        }
    }

    fn operator_type(
        &self,
        op: &str,
        left: &serde_json::Value,
        right: &serde_json::Value,
        type_errors: &mut Vec<ClassifierDiagnostic>,
        node_name: &str,
    ) -> (String, serde_json::Value) {
        let left_name = self.type_name(left);
        let right_name = self.type_name(right);

        // Fixed-point Decimal rules:
        let is_left_decimal = left_name == "Decimal";
        let is_right_decimal = right_name == "Decimal";

        if is_left_decimal || is_right_decimal {
            if is_left_decimal && is_right_decimal {
                let left_scale = self.decimal_scale(left);
                let right_scale = self.decimal_scale(right);
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
                        sum_type.insert(
                            "name".to_string(),
                            serde_json::Value::String("Decimal".to_string()),
                        );
                        let mut inner = serde_json::Map::new();
                        inner.insert(
                            "name".to_string(),
                            serde_json::Value::String(sum_scale.to_string()),
                        );
                        inner.insert("params".to_string(), serde_json::Value::Array(Vec::new()));
                        sum_type.insert(
                            "params".to_string(),
                            serde_json::Value::Array(vec![serde_json::Value::Object(inner)]),
                        );
                        return (
                            "stdlib.decimal.mul".to_string(),
                            serde_json::Value::Object(sum_type),
                        );
                    }
                    _ => {}
                }
            }
        }

        // v0 homogeneous numeric relaxation: allow Float / Decimal (like Integer) when
        // BOTH sides are the SAME numeric type. The VM binary opcodes (OP_ADD, OP_LT, …)
        // already dispatch on value type, so no runtime change is needed. Heterogeneous
        // numeric (e.g. Integer op Float) is deliberately deferred — separate research.
        // Decimal +/-/* are handled above with scale rules; this covers Float (all ops),
        // Decimal (/ and comparisons), Integer, and equality.
        let is_numeric = |n: &str| matches!(n, "Integer" | "Float" | "Decimal");
        if left_name == right_name && is_numeric(left_name.as_str()) {
            let bool_ir = self.type_ir(&serde_json::Value::String("Bool".to_string()));
            match op {
                "+" => return ("stdlib.integer.add".to_string(), left.clone()),
                "-" => return ("stdlib.integer.sub".to_string(), left.clone()),
                "*" => return ("stdlib.integer.mul".to_string(), left.clone()),
                "/" => return ("stdlib.integer.div".to_string(), left.clone()),
                "<" => return ("stdlib.integer.lt".to_string(), bool_ir),
                "<=" => return ("stdlib.integer.lte".to_string(), bool_ir),
                ">" => return ("stdlib.integer.gt".to_string(), bool_ir),
                ">=" => return ("stdlib.integer.gte".to_string(), bool_ir),
                "==" => return ("stdlib.primitive.eq".to_string(), bool_ir),
                _ => {}
            }
        }

        match op {
            "+" => {
                if left_name != "Integer" || right_name != "Integer" {
                    if left_name != "Unknown" && right_name != "Unknown" {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-TY0".to_string(),
                            message: format!(
                                "Type mismatch: expected Integer, got {}+{}",
                                left_name, right_name
                            ),
                            node: node_name.to_string(),
                            line: None,
                        });
                    }
                }
                (
                    "stdlib.integer.add".to_string(),
                    self.type_ir(&serde_json::Value::String("Integer".to_string())),
                )
            }
            "++" => {
                if left_name == "String" && right_name == "String" {
                    (
                        "stdlib.string.concat".to_string(),
                        self.type_ir(&serde_json::Value::String("String".to_string())),
                    )
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
                    (
                        "stdlib.unsupported.++".to_string(),
                        self.type_ir(&serde_json::Value::String("Unknown".to_string())),
                    )
                }
            }
            "-" => {
                if left_name != "Integer" || right_name != "Integer" {
                    if left_name != "Unknown" && right_name != "Unknown" {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-TY0".to_string(),
                            message: format!(
                                "Type mismatch: expected Integer, got {}-{}",
                                left_name, right_name
                            ),
                            node: node_name.to_string(),
                            line: None,
                        });
                    }
                }
                (
                    "stdlib.integer.sub".to_string(),
                    self.type_ir(&serde_json::Value::String("Integer".to_string())),
                )
            }
            "*" => {
                if left_name != "Integer" || right_name != "Integer" {
                    if left_name != "Unknown" && right_name != "Unknown" {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-TY0".to_string(),
                            message: format!(
                                "Type mismatch: expected Integer, got {}*{}",
                                left_name, right_name
                            ),
                            node: node_name.to_string(),
                            line: None,
                        });
                    }
                }
                (
                    "stdlib.integer.mul".to_string(),
                    self.type_ir(&serde_json::Value::String("Integer".to_string())),
                )
            }
            "/" => {
                if left_name != "Integer" || right_name != "Integer" {
                    if left_name != "Unknown" && right_name != "Unknown" {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-TY0".to_string(),
                            message: format!(
                                "Type mismatch: expected Integer, got {}/{}",
                                left_name, right_name
                            ),
                            node: node_name.to_string(),
                            line: None,
                        });
                    }
                }
                (
                    "stdlib.integer.div".to_string(),
                    self.type_ir(&serde_json::Value::String("Integer".to_string())),
                )
            }
            ">" => {
                if left_name != "Integer" || right_name != "Integer" {
                    if left_name != "Unknown" && right_name != "Unknown" {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-TY0".to_string(),
                            message: format!(
                                "Type mismatch: expected Integer, got {}+{}",
                                left_name, right_name
                            ),
                            node: node_name.to_string(),
                            line: None,
                        });
                    }
                }
                (
                    "stdlib.integer.gt".to_string(),
                    self.type_ir(&serde_json::Value::String("Bool".to_string())),
                )
            }
            "&&" => {
                if left_name != "Bool" || right_name != "Bool" {
                    if left_name != "Unknown" && right_name != "Unknown" {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-TY0".to_string(),
                            message: format!(
                                "Type mismatch: expected Bool, got {}+{}",
                                left_name, right_name
                            ),
                            node: node_name.to_string(),
                            line: None,
                        });
                    }
                }
                (
                    "stdlib.bool.and".to_string(),
                    self.type_ir(&serde_json::Value::String("Bool".to_string())),
                )
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
                    ("String", "String")
                        | ("Text", "Text")
                        | ("String", "Text")
                        | ("Text", "String")
                        | ("Integer", "Integer")
                        | ("Bool", "Bool")
                        | ("Unknown", _)
                        | (_, "Unknown")
                );
                if !compatible {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-TY0".to_string(),
                        message: format!(
                            "Type mismatch for ==: cannot compare {} with {}",
                            left_name, right_name
                        ),
                        node: node_name.to_string(),
                        line: None,
                    });
                }
                (
                    "stdlib.primitive.eq".to_string(),
                    self.type_ir(&serde_json::Value::String("Bool".to_string())),
                )
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
                        message: format!(
                            "Type mismatch for <: expected Integer on both sides, got {} < {}",
                            left_name, right_name
                        ),
                        node: node_name.to_string(),
                        line: None,
                    });
                }
                (
                    "stdlib.integer.lt".to_string(),
                    self.type_ir(&serde_json::Value::String("Bool".to_string())),
                )
            }
            "<=" => {
                if (left_name != "Integer" || right_name != "Integer")
                    && left_name != "Unknown"
                    && right_name != "Unknown"
                {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-TY0".to_string(),
                        message: format!(
                            "Type mismatch for <=: expected Integer on both sides, got {} <= {}",
                            left_name, right_name
                        ),
                        node: node_name.to_string(),
                        line: None,
                    });
                }
                (
                    "stdlib.integer.lte".to_string(),
                    self.type_ir(&serde_json::Value::String("Bool".to_string())),
                )
            }
            ">=" => {
                if (left_name != "Integer" || right_name != "Integer")
                    && left_name != "Unknown"
                    && right_name != "Unknown"
                {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-TY0".to_string(),
                        message: format!(
                            "Type mismatch for >=: expected Integer on both sides, got {} >= {}",
                            left_name, right_name
                        ),
                        node: node_name.to_string(),
                        line: None,
                    });
                }
                (
                    "stdlib.integer.gte".to_string(),
                    self.type_ir(&serde_json::Value::String("Bool".to_string())),
                )
            }
            _ => {
                type_errors.push(ClassifierDiagnostic {
                    rule: "OOF-TY0".to_string(),
                    message: format!("Unsupported operator: {}", op),
                    node: node_name.to_string(),
                    line: None,
                });
                (
                    format!("stdlib.unsupported.{}", op),
                    self.type_ir(&serde_json::Value::String("Unknown".to_string())),
                )
            }
        }
    }

    // ── PROP-044 P5: variant / match inference ───────────────────────────────────

    /// Build variant_shapes (3-level map) from classifier's variant_declarations.
    fn build_variant_shapes(&self, classified: &ClassifiedProgram) -> VariantShapes {
        let mut shapes: VariantShapes = HashMap::new();
        for vd in &classified.variant_declarations {
            let mut arm_map: HashMap<String, HashMap<String, serde_json::Value>> = HashMap::new();
            for arm in &vd.arms {
                let mut field_map: HashMap<String, serde_json::Value> = HashMap::new();
                for field in &arm.fields {
                    field_map.insert(
                        field.name.clone(),
                        self.type_ir(&serde_json::to_value(&field.type_annotation).unwrap()),
                    );
                }
                arm_map.insert(arm.name.clone(), field_map);
            }
            shapes.insert(vd.name.clone(), arm_map);
        }
        shapes
    }

    /// Build SIR-ready variant_declarations for TypedProgram.
    fn build_variant_declarations_sir(
        &self,
        classified: &ClassifiedProgram,
    ) -> Vec<serde_json::Value> {
        classified
            .variant_declarations
            .iter()
            .map(|vd| {
                let arms: Vec<serde_json::Value> = vd
                    .arms
                    .iter()
                    .map(|arm| {
                        let fields: Vec<serde_json::Value> = arm.fields.iter().map(|f| {
                    serde_json::json!({
                        "name": f.name,
                        "type": self.type_ir(&serde_json::to_value(&f.type_annotation).unwrap())
                    })
                }).collect();
                        serde_json::json!({ "name": arm.name, "fields": fields })
                    })
                    .collect();
                serde_json::json!({ "kind": "variant_decl", "name": vd.name, "arms": arms })
            })
            .collect()
    }

    fn variant_type_exists(&self, name: &str) -> bool {
        self.variant_shapes.borrow().contains_key(name) || self.sealed_builtin(name)
    }

    fn find_variant_for_arm(&self, arm_name: &str) -> Option<String> {
        for (vname, arms) in self.variant_shapes.borrow().iter() {
            if arms.contains_key(arm_name) {
                return Some(vname.clone());
            }
        }
        None
    }

    /// Serialize an Expr to JSON and attach resolved_type for SIR annotation.
    fn annotate_expr_with_type(
        &self,
        expr: &Expr,
        resolved_type: &serde_json::Value,
    ) -> serde_json::Value {
        let mut v = serde_json::to_value(expr).unwrap_or(serde_json::Value::Null);
        if let serde_json::Value::Object(ref mut m) = v {
            m.insert("resolved_type".to_string(), resolved_type.clone());
        }
        v
    }

    /// LANG-SUMTYPE-CONSTRUCT-MATCH-P3: type-IR builders for sealed sumtypes.
    fn make_option_ir(&self, inner: serde_json::Value) -> serde_json::Value {
        let mut m = serde_json::Map::new();
        m.insert(
            "name".to_string(),
            serde_json::Value::String("Option".to_string()),
        );
        m.insert("params".to_string(), serde_json::Value::Array(vec![inner]));
        serde_json::Value::Object(m)
    }

    fn make_result_ir(
        &self,
        ok_ty: serde_json::Value,
        err_ty: serde_json::Value,
    ) -> serde_json::Value {
        let mut m = serde_json::Map::new();
        m.insert(
            "name".to_string(),
            serde_json::Value::String("Result".to_string()),
        );
        m.insert(
            "params".to_string(),
            serde_json::Value::Array(vec![ok_ty, err_ty]),
        );
        serde_json::Value::Object(m)
    }

    /// Recover param[idx] from the expected-type hint for `node_name` if it is of the
    /// given family (Option/Result); else Unknown.
    fn sealed_hint_param(&self, node_name: &str, family: &str, idx: usize) -> serde_json::Value {
        let unknown = self.type_ir(&serde_json::Value::String("Unknown".to_string()));
        if let Some(hint) = self.sealed_output_hints.borrow().get(node_name) {
            if self.type_name(hint) == family {
                return self.get_param(hint, idx).unwrap_or(unknown);
            }
        }
        unknown
    }

    /// LAB-IGNITER-COMPILER-USER-FN-SIGNATURE-CHECK-P6: validate an `Expr::Call` to an
    /// app-local user `def` against its declared signature.
    ///
    /// Two faults are caught, both emitted as `OOF-TY0` (the established type-soundness
    /// code, consistent with the binding/output boundaries):
    /// - **arity**: `args.len()` ≠ `params.len()`. Positional param-type checks are then
    ///   skipped because they would be meaningless.
    /// - **parameter type**: each argument's inferred type must be `structurally_assignable`
    ///   to the parameter's declared type. This runs through the P5 `IgType` boundary, so
    ///   generic parameters are compared structurally (`Collection[Integer]` ≠
    ///   `Collection[Text]`) for free.
    ///
    /// A parameter is checked only when *both* the declared and inferred types are concrete
    /// (not Unknown-bearing). This mirrors the P5 variant-field path and the typed-binding
    /// path: the checker never faults on an inference gap, only on a real concrete mismatch.
    fn check_user_fn_call_signature(
        &self,
        f: &crate::parser::FunctionDecl,
        args: &[Expr],
        typed_args: &[TypedExpression],
        node_name: &str,
        type_errors: &mut Vec<ClassifierDiagnostic>,
    ) {
        if args.len() != f.params.len() {
            type_errors.push(ClassifierDiagnostic {
                rule: "OOF-TY0".to_string(),
                message: format!(
                    "Call to '{}': expected {} argument{}, got {}",
                    f.name,
                    f.params.len(),
                    if f.params.len() == 1 { "" } else { "s" },
                    args.len()
                ),
                node: node_name.to_string(),
                line: None,
            });
            return;
        }

        for (i, param) in f.params.iter().enumerate() {
            let expected = self.type_ir(&serde_json::to_value(&param.type_annotation).unwrap());
            let actual = &typed_args[i].resolved_type;
            if self.unknown_or_unknown_bearing(&expected) || self.unknown_or_unknown_bearing(actual)
            {
                continue;
            }
            if !self.structurally_assignable(actual, &expected) {
                type_errors.push(ClassifierDiagnostic {
                    rule: "OOF-TY0".to_string(),
                    message: format!(
                        "Call to '{}': parameter '{}' expects {}, got {}",
                        f.name,
                        param.name,
                        self.type_display(&expected),
                        self.type_display(actual)
                    ),
                    node: node_name.to_string(),
                    line: None,
                });
            }
        }
    }

    /// LANG-SUMTYPE-CONSTRUCT-MATCH-P3: lower some/none/ok/err to a sealed
    /// `variant_construct` node (SIR marker `sealed: true`), mirroring the Ruby canon.
    /// Payload labels locked to value/error; missing params recovered from the
    /// expected-type hint keyed on node_name.
    #[allow(clippy::too_many_arguments)]
    fn infer_sealed_construct(
        &self,
        fn_name: &str,
        args: &[Expr],
        typed_args: &[TypedExpression],
        deps: Vec<String>,
        type_errors: &mut Vec<ClassifierDiagnostic>,
        node_name: &str,
    ) -> TypedExpression {
        let unknown = self.type_ir(&serde_json::Value::String("Unknown".to_string()));
        let expected_arity = if fn_name == "none" { 0 } else { 1 };
        if args.len() != expected_arity {
            type_errors.push(ClassifierDiagnostic {
                rule: "OOF-TY0".to_string(),
                message: format!(
                    "{} requires {} argument{}",
                    fn_name,
                    expected_arity,
                    if expected_arity == 1 { "" } else { "s" }
                ),
                node: node_name.to_string(),
                line: None,
            });
            return TypedExpression {
                resolved_type: unknown,
                deps: Vec::new(),
                annotated_expr: None,
            };
        }

        let (arm, variant, resolved_type, fields): (
            &str,
            &str,
            serde_json::Value,
            serde_json::Map<String, serde_json::Value>,
        ) = match fn_name {
            "some" => {
                let inner = typed_args[0].resolved_type.clone();
                let mut f = serde_json::Map::new();
                f.insert(
                    "value".to_string(),
                    self.annotate_expr_with_type(&args[0], &typed_args[0].resolved_type),
                );
                ("Some", "Option", self.make_option_ir(inner), f)
            }
            "none" => {
                let inner = self.sealed_hint_param(node_name, "Option", 0);
                (
                    "None",
                    "Option",
                    self.make_option_ir(inner),
                    serde_json::Map::new(),
                )
            }
            "ok" => {
                let t = typed_args[0].resolved_type.clone();
                let e = self.sealed_hint_param(node_name, "Result", 1);
                let mut f = serde_json::Map::new();
                f.insert(
                    "value".to_string(),
                    self.annotate_expr_with_type(&args[0], &typed_args[0].resolved_type),
                );
                ("Ok", "Result", self.make_result_ir(t, e), f)
            }
            "err" => {
                let e = typed_args[0].resolved_type.clone();
                let t = self.sealed_hint_param(node_name, "Result", 0);
                let mut f = serde_json::Map::new();
                f.insert(
                    "error".to_string(),
                    self.annotate_expr_with_type(&args[0], &typed_args[0].resolved_type),
                );
                ("Err", "Result", self.make_result_ir(t, e), f)
            }
            _ => unreachable!(),
        };

        let annotated = serde_json::json!({
            "kind": "variant_construct",
            "arm": arm,
            "variant": variant,
            "fields": serde_json::Value::Object(fields),
            "resolved_type": resolved_type,
            "sealed": true
        });

        TypedExpression {
            resolved_type,
            deps,
            annotated_expr: Some(annotated),
        }
    }

    /// PROP-044 P5: Infer a variant_construct expression.
    /// Returns type_ir(variant_name) on success; Unknown with OOF-KIND2 on failure.
    #[allow(clippy::too_many_arguments)]
    fn infer_variant_construct(
        &self,
        arm: &str,
        fields: &HashMap<String, Expr>,
        symbol_types: &HashMap<String, serde_json::Value>,
        olap_env: &HashMap<String, HashMap<String, serde_json::Value>>,
        type_shapes: &HashMap<String, HashMap<String, serde_json::Value>>,
        type_errors: &mut Vec<ClassifierDiagnostic>,
        type_warnings: &mut Vec<ClassifierDiagnostic>,
        node_name: &str,
        functions: &[crate::parser::FunctionDecl],
        contract_registry: &HashMap<String, ContractRegistryEntry>,
        current_contract_name: &str,
    ) -> TypedExpression {
        let variant_name = self.find_variant_for_arm(arm);
        if variant_name.is_none() {
            type_errors.push(ClassifierDiagnostic {
                rule: "OOF-KIND2".to_string(),
                message: format!(
                    "variant_construct arm '{}' is not declared in any variant",
                    arm
                ),
                node: node_name.to_string(),
                line: None,
            });
            return TypedExpression {
                resolved_type: self.type_ir(&serde_json::Value::String("Unknown".to_string())),
                deps: Vec::new(),
                annotated_expr: None,
            };
        }
        let variant_name = variant_name.unwrap();

        let arm_field_shapes: HashMap<String, serde_json::Value> = {
            let vs = self.variant_shapes.borrow();
            vs[&variant_name][arm].clone()
        };

        let mut typed_fields: HashMap<String, serde_json::Value> = HashMap::new();
        let mut all_deps: Vec<String> = Vec::new();
        let errors_before = type_errors.len();

        for (fname, fexpr) in fields {
            let typed_f = self.infer_expr(
                fexpr,
                symbol_types,
                olap_env,
                type_shapes,
                type_errors,
                type_warnings,
                node_name,
                functions,
                contract_registry,
                current_contract_name,
            );
            let field_type = &typed_f.resolved_type;
            if let Some(expected) = arm_field_shapes.get(fname) {
                let actual_name = self.type_name(field_type);
                let expected_name = self.type_name(expected);
                // LAB-IGNITER-WEB-STRUCTURED-EFFECT-INPUT-P7: a variant field declared `Unknown` is an OPEN
                // structured-payload position (e.g. `Decision::InvokeEffect.input`) — it accepts any
                // record/value, validated downstream at the host, never here. Mirrors the D3 rule in
                // `structurally_assignable` ("expected Unknown accepts any").
                if actual_name != expected_name
                    && actual_name != "Unknown"
                    && expected_name != "Unknown"
                {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-KIND2".to_string(),
                        message: format!(
                            "{}::{} field '{}': expected {}, got {}",
                            variant_name, arm, fname, expected_name, actual_name
                        ),
                        node: node_name.to_string(),
                        line: None,
                    });
                } else if actual_name == expected_name
                    && actual_name != "Unknown"
                    && !self.unknown_or_unknown_bearing(field_type)
                    && !self.unknown_or_unknown_bearing(expected)
                    && !self.structurally_assignable(field_type, expected)
                {
                    // LAB-IGNITER-COMPILER-TYPE-IR-ENUM-P5: same outer name but
                    // mismatched type parameters (e.g. `Collection[Integer]` vs
                    // `Collection[Text]`) previously passed by name-only
                    // comparison. The typed `IgType` model checks parameters
                    // structurally and fails closed. Guarded to concrete,
                    // fully-known types so Unknown-bearing payload positions stay
                    // open exactly as before (D3). Display form (with params)
                    // distinguishes this diagnostic from the outer-name case.
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-KIND2".to_string(),
                        message: format!(
                            "{}::{} field '{}': expected {}, got {}",
                            variant_name,
                            arm,
                            fname,
                            self.type_display(expected),
                            self.type_display(field_type)
                        ),
                        node: node_name.to_string(),
                        line: None,
                    });
                }
            } else {
                type_errors.push(ClassifierDiagnostic {
                    rule: "OOF-KIND2".to_string(),
                    message: format!(
                        "field '{}' is not declared in {}::{}",
                        fname, variant_name, arm
                    ),
                    node: node_name.to_string(),
                    line: None,
                });
            }
            all_deps.extend(typed_f.deps);
            typed_fields.insert(
                fname.clone(),
                self.annotate_expr_with_type(fexpr, &typed_f.resolved_type),
            );
        }

        for required in arm_field_shapes.keys() {
            if !fields.contains_key(required.as_str()) {
                type_errors.push(ClassifierDiagnostic {
                    rule: "OOF-KIND2".to_string(),
                    message: format!(
                        "{}::{} is missing required field '{}'",
                        variant_name, arm, required
                    ),
                    node: node_name.to_string(),
                    line: None,
                });
            }
        }

        let resolved_type = self.type_ir(&serde_json::Value::String(variant_name.clone()));
        all_deps.sort();
        all_deps.dedup();

        // Build SIR-ready annotated_expr only when no errors from this construct
        let annotated = if type_errors.len() == errors_before {
            let fields_map: serde_json::Map<String, serde_json::Value> =
                typed_fields.into_iter().collect();
            Some(serde_json::json!({
                "kind": "variant_construct",
                "arm": arm,
                "variant": variant_name,
                "fields": serde_json::Value::Object(fields_map),
                "resolved_type": resolved_type
            }))
        } else {
            None
        };

        TypedExpression {
            resolved_type,
            deps: all_deps,
            annotated_expr: annotated,
        }
    }

    /// PROP-044 P5: Infer a match_expr.
    #[allow(clippy::too_many_arguments)]
    fn infer_match_expr(
        &self,
        subject: &Expr,
        arms: &[crate::parser::MatchArm],
        symbol_types: &HashMap<String, serde_json::Value>,
        olap_env: &HashMap<String, HashMap<String, serde_json::Value>>,
        type_shapes: &HashMap<String, HashMap<String, serde_json::Value>>,
        type_errors: &mut Vec<ClassifierDiagnostic>,
        type_warnings: &mut Vec<ClassifierDiagnostic>,
        node_name: &str,
        functions: &[crate::parser::FunctionDecl],
        contract_registry: &HashMap<String, ContractRegistryEntry>,
        current_contract_name: &str,
    ) -> TypedExpression {
        let subject_typed = self.infer_expr(
            subject,
            symbol_types,
            olap_env,
            type_shapes,
            type_errors,
            type_warnings,
            node_name,
            functions,
            contract_registry,
            current_contract_name,
        );
        let subject_type_name = self.type_name(&subject_typed.resolved_type);

        // LAB-LANG-FALLIBLE-BINDING-P2: a match with exactly `Ok`/`Err` arms over a non-Result subject can
        // only come from the `?` desugar (a hand-written match over Option would use Some/None). Brand the
        // error as a `?` misuse (OOF-Q1) so the user sees "use `?` on Result", not a raw match diagnostic.
        let try_shape = arms.len() == 2
            && arms.iter().any(|a| a.pattern.arm == "Ok")
            && arms
                .iter()
                .all(|a| a.pattern.arm == "Ok" || a.pattern.arm == "Err");

        // OOF-KIND4: non-variant subject (suppress if Unknown — prior error already explains it)
        if subject_type_name != "Unknown" && !self.variant_type_exists(&subject_type_name) {
            type_errors.push(ClassifierDiagnostic {
                rule: if try_shape { "OOF-Q1" } else { "OOF-KIND4" }.to_string(),
                message: if try_shape {
                    format!(
                        "? applies only to Result[T, E], got '{}'",
                        subject_type_name
                    )
                } else {
                    format!(
                        "match subject has type '{}' which is not a variant type",
                        subject_type_name
                    )
                },
                node: node_name.to_string(),
                line: None,
            });
            return TypedExpression {
                resolved_type: self.type_ir(&serde_json::Value::String("Unknown".to_string())),
                deps: subject_typed.deps,
                annotated_expr: None,
            };
        }

        // LAB-LANG-FALLIBLE-BINDING-P2: `?` on an Option (Result-only in v0).
        if try_shape && subject_type_name == "Option" {
            type_errors.push(ClassifierDiagnostic {
                rule: "OOF-Q1".to_string(),
                message: "? is not supported on Option in v0 (Result only)".to_string(),
                node: node_name.to_string(),
                line: None,
            });
            return TypedExpression {
                resolved_type: self.type_ir(&serde_json::Value::String("Unknown".to_string())),
                deps: subject_typed.deps,
                annotated_expr: None,
            };
        }

        // Degraded mode when subject is Unknown (prior error)
        if !self.variant_type_exists(&subject_type_name) {
            for arm in arms {
                self.infer_expr(
                    &arm.body,
                    symbol_types,
                    olap_env,
                    type_shapes,
                    type_errors,
                    type_warnings,
                    node_name,
                    functions,
                    contract_registry,
                    current_contract_name,
                );
            }
            return TypedExpression {
                resolved_type: self.type_ir(&serde_json::Value::String("Unknown".to_string())),
                deps: subject_typed.deps,
                annotated_expr: None,
            };
        }

        // LANG-SUMTYPE-CONSTRUCT-MATCH-P3: user shapes, else sealed built-in registry.
        let declared_arms = self.declared_arms_for(&subject_type_name);
        let sealed = self.sealed_builtin(&subject_type_name);
        let subject_rt = subject_typed.resolved_type.clone();

        let mut covered_arms: HashMap<String, usize> = HashMap::new();
        let mut has_wildcard = false;
        let mut arm_types: Vec<serde_json::Value> = Vec::new();
        let mut typed_arms: Vec<serde_json::Value> = Vec::new();
        let mut all_deps = subject_typed.deps.clone();
        let errors_before = type_errors.len();

        for (idx, arm) in arms.iter().enumerate() {
            let pattern = &arm.pattern;

            if pattern.wildcard {
                has_wildcard = true;
                let body_typed = self.infer_expr(
                    &arm.body,
                    symbol_types,
                    olap_env,
                    type_shapes,
                    type_errors,
                    type_warnings,
                    node_name,
                    functions,
                    contract_registry,
                    current_contract_name,
                );
                let annotated_body =
                    self.annotate_expr_with_type(&arm.body, &body_typed.resolved_type);
                arm_types.push(body_typed.resolved_type.clone());
                all_deps.extend(body_typed.deps);
                typed_arms.push(serde_json::json!({
                    "pattern": serde_json::json!({ "wildcard": true, "arm": "_", "bindings": [] }),
                    "body": annotated_body,
                    "resolved_type": body_typed.resolved_type
                }));
                continue;
            }

            let arm_name = &pattern.arm;

            // OOF-KIND3: duplicate arm
            if covered_arms.contains_key(arm_name.as_str()) {
                type_errors.push(ClassifierDiagnostic {
                    rule: "OOF-KIND3".to_string(),
                    message: format!(
                        "arm '{}' is unreachable — already covered at position {}",
                        arm_name,
                        covered_arms[arm_name.as_str()]
                    ),
                    node: node_name.to_string(),
                    line: None,
                });
                continue;
            }
            covered_arms.insert(arm_name.clone(), idx);

            // OOF-KIND2: arm not in variant
            if !declared_arms.contains_key(arm_name.as_str()) {
                type_errors.push(ClassifierDiagnostic {
                    rule: "OOF-KIND2".to_string(),
                    message: format!(
                        "arm '{}' is not declared in variant '{}'",
                        arm_name, subject_type_name
                    ),
                    node: node_name.to_string(),
                    line: None,
                });
                let body_typed = self.infer_expr(
                    &arm.body,
                    symbol_types,
                    olap_env,
                    type_shapes,
                    type_errors,
                    type_warnings,
                    node_name,
                    functions,
                    contract_registry,
                    current_contract_name,
                );
                arm_types.push(body_typed.resolved_type.clone());
                all_deps.extend(body_typed.deps);
                continue;
            }

            let arm_field_shapes = &declared_arms[arm_name.as_str()];
            // Sealed built-ins substitute the concrete payload type from the subject's
            // params; user variants use their declared field types directly.
            let bind_types = if sealed {
                self.sealed_arm_field_types(&subject_rt, arm_name.as_str())
            } else {
                arm_field_shapes.clone()
            };
            let mut arm_scope = symbol_types.clone();
            for binding in &pattern.bindings {
                if arm_field_shapes.contains_key(binding.as_str()) {
                    let field_type =
                        bind_types
                            .get(binding.as_str())
                            .cloned()
                            .unwrap_or_else(|| {
                                self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                            });
                    arm_scope.insert(binding.clone(), field_type);
                } else {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-KIND2".to_string(),
                        message: format!(
                            "binding '{}' is not a field of {}::{}",
                            binding, subject_type_name, arm_name
                        ),
                        node: node_name.to_string(),
                        line: None,
                    });
                    arm_scope.insert(
                        binding.clone(),
                        self.type_ir(&serde_json::Value::String("Unknown".to_string())),
                    );
                }
            }

            let body_typed = self.infer_expr(
                &arm.body,
                &arm_scope,
                olap_env,
                type_shapes,
                type_errors,
                type_warnings,
                node_name,
                functions,
                contract_registry,
                current_contract_name,
            );
            let annotated_body = self.annotate_expr_with_type(&arm.body, &body_typed.resolved_type);
            arm_types.push(body_typed.resolved_type.clone());
            all_deps.extend(body_typed.deps);
            let bindings_json: Vec<serde_json::Value> = pattern
                .bindings
                .iter()
                .map(|b| serde_json::Value::String(b.clone()))
                .collect();
            typed_arms.push(serde_json::json!({
                "pattern": serde_json::json!({ "wildcard": false, "arm": arm_name, "bindings": bindings_json }),
                "body": annotated_body,
                "resolved_type": body_typed.resolved_type
            }));
        }

        // OOF-KIND1: non-exhaustive
        let uncovered: Vec<&String> = declared_arms
            .keys()
            .filter(|k| !covered_arms.contains_key(k.as_str()))
            .collect();
        if !uncovered.is_empty() && !has_wildcard {
            let mut missing: Vec<String> = uncovered.iter().map(|s| s.to_string()).collect();
            missing.sort();
            type_errors.push(ClassifierDiagnostic {
                rule: "OOF-KIND1".to_string(),
                message: format!(
                    "match on '{}' is non-exhaustive — missing arms: {}",
                    subject_type_name,
                    missing.join(", ")
                ),
                node: node_name.to_string(),
                line: None,
            });
        }

        let result_type =
            self.unify_match_arm_types(&arm_types, &subject_type_name, node_name, type_errors);
        all_deps.sort();
        all_deps.dedup();

        let exhaustive = uncovered.is_empty() || has_wildcard;
        let annotated_subject = self.annotate_expr_with_type(subject, &subject_typed.resolved_type);

        let annotated = if type_errors.len() == errors_before {
            let mut node = serde_json::json!({
                "kind": "match_expr",
                "subject": annotated_subject,
                "subject_type": subject_type_name,
                "arms": typed_arms,
                "exhaustive": exhaustive,
                "has_wildcard": has_wildcard,
                "resolved_type": result_type
            });
            // LANG-SUMTYPE-CONSTRUCT-MATCH-P3: sealed-only marker (Option/Result subjects).
            if sealed {
                node.as_object_mut()
                    .unwrap()
                    .insert("sealed".to_string(), serde_json::Value::Bool(true));
            }
            Some(node)
        } else {
            None
        };

        TypedExpression {
            resolved_type: result_type,
            deps: all_deps,
            annotated_expr: annotated,
        }
    }

    /// Unify match arm result types. Returns Unknown if empty or divergent (OOF-KIND5).
    fn unify_match_arm_types(
        &self,
        arm_types: &[serde_json::Value],
        subject_type: &str,
        node_name: &str,
        type_errors: &mut Vec<ClassifierDiagnostic>,
    ) -> serde_json::Value {
        if arm_types.is_empty() {
            return self.type_ir(&serde_json::Value::String("Unknown".to_string()));
        }
        // Top-level Unknown arms contribute nothing to the join (legacy behavior).
        let present: Vec<&serde_json::Value> = arm_types
            .iter()
            .filter(|t| self.type_name(t) != "Unknown")
            .collect();
        if present.is_empty() {
            return self.type_ir(&serde_json::Value::String("Unknown".to_string()));
        }
        let mut names: Vec<String> = present.iter().map(|t| self.type_name(t)).collect();
        names.sort();
        names.dedup();
        if names.len() > 1 {
            type_errors.push(ClassifierDiagnostic {
                rule: "OOF-KIND5".to_string(),
                message: format!(
                    "match on '{}' has divergent arm result types: {}",
                    subject_type,
                    names.join(", ")
                ),
                node: node_name.to_string(),
                line: None,
            });
            return self.type_ir(&serde_json::Value::String("Unknown".to_string()));
        }
        // LANG-MATCH-ARM-PARAM-UNIFICATION-P2 (route A): preserve type params when all
        // arms share the parametric family, via a position-wise structural join.
        // PURE precision widening — every case that previously dropped params still
        // returns the byte-identical legacy `type_ir(name)`; params are preserved only
        // when the join yields a non-empty, fully-resolved (not Unknown-bearing) result.
        let name = names[0].clone();
        let mut joined: Option<serde_json::Value> = Some(present[0].clone());
        for t in present.iter().skip(1) {
            joined = match joined {
                Some(acc) => self.join_match_param_types(&acc, t),
                None => None,
            };
        }
        if let Some(j) = &joined {
            let has_params = j
                .get("params")
                .and_then(|p| p.as_array())
                .map(|a| !a.is_empty())
                .unwrap_or(false);
            if has_params && !self.unknown_or_unknown_bearing(j) {
                return j.clone();
            }
        }
        self.type_ir(&serde_json::Value::String(name))
    }

    /// Position-wise structural join of two arm result types. `Unknown` is the join
    /// bottom: join(Unknown, X) = X. Identical structures are preserved as-is (keeps
    /// any extra keys). Arity or concrete-name conflict at any depth returns None ⇒
    /// the caller degrades to the legacy bare family result. No diagnostic is emitted
    /// here (P2 reserves OOF-KIND7 for a future strictness card; OOF-KIND6 is already
    /// taken by PROP-044-P9 reserved-field-name checks).
    fn join_match_param_types(
        &self,
        a: &serde_json::Value,
        b: &serde_json::Value,
    ) -> Option<serde_json::Value> {
        let na = self.type_name(a);
        let nb = self.type_name(b);
        if na == "Unknown" {
            return Some(b.clone());
        }
        if nb == "Unknown" {
            return Some(a.clone());
        }
        if na != nb {
            return None;
        }
        if a == b {
            return Some(a.clone());
        } // identical — preserve all keys, zero change

        let pa = a
            .get("params")
            .and_then(|p| p.as_array())
            .cloned()
            .unwrap_or_default();
        let pb = b
            .get("params")
            .and_then(|p| p.as_array())
            .cloned()
            .unwrap_or_default();
        if pa.len() != pb.len() {
            return None;
        }

        let mut joined_params = Vec::with_capacity(pa.len());
        for (x, y) in pa.iter().zip(pb.iter()) {
            match self.join_match_param_types(&self.type_ir(x), &self.type_ir(y)) {
                Some(jp) => joined_params.push(jp),
                None => return None,
            }
        }
        let mut obj = serde_json::Map::new();
        obj.insert("name".to_string(), serde_json::Value::String(na));
        obj.insert(
            "params".to_string(),
            serde_json::Value::Array(joined_params),
        );
        Some(serde_json::Value::Object(obj))
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

    // ── LAB-RACK-P13: nominal record type checking ────────────────────────────

    /// Validate a RecordLiteral expression against a named record type schema.
    /// Emits OOF-TY0 for:
    ///   - missing required fields (present in schema but absent from literal)
    ///   - unexpected fields (present in literal but absent from schema)
    ///   - field value type mismatches (where the field value type is resolvable)
    ///
    /// Called from the compute phase after `infer_expr` returns Unknown.
    /// The caller upgrades the compute node type to the named type IFF no errors
    /// are emitted by this method.
    ///
    /// Field types are checked via `infer_field_expr_type` — only Ref and Literal
    /// expressions are resolved; complex expressions return None (Unknown-compat:
    /// field type check is skipped, which is intentionally permissive in v0).
    /// LAB-TC-NESTED-RECORD-CONTEXT-P1: added `type_shapes` parameter to enable
    /// recursive validation of inline nested record literals against their expected
    /// field type. When a field value is a RecordLiteral and the expected field type
    /// is a named record in type_shapes, we recurse one level. This is contextual
    /// typing only — no global inference, no unification, no retroactive mutation.
    fn check_record_literal_shape(
        &self,
        fields: &HashMap<String, Expr>,
        expected_shape: &HashMap<String, serde_json::Value>,
        expected_type_name: &str,
        node_name: &str,
        symbol_types: &HashMap<String, serde_json::Value>,
        type_shapes: &HashMap<String, HashMap<String, serde_json::Value>>,
        type_errors: &mut Vec<ClassifierDiagnostic>,
    ) {
        // 1. Missing required fields
        for expected_field_name in expected_shape.keys() {
            if !fields.contains_key(expected_field_name) {
                type_errors.push(ClassifierDiagnostic {
                    rule: "OOF-TY0".to_string(),
                    message: format!(
                        "Record type '{}': required field '{}' is missing from literal at node '{}'",
                        expected_type_name, expected_field_name, node_name
                    ),
                    node: node_name.to_string(),
                    line: None,
                });
            }
        }

        // 2. Unexpected / extra fields
        for field_name in fields.keys() {
            if !expected_shape.contains_key(field_name) {
                type_errors.push(ClassifierDiagnostic {
                    rule: "OOF-TY0".to_string(),
                    message: format!(
                        "Record type '{}': unexpected field '{}' in literal at node '{}' (not declared in type)",
                        expected_type_name, field_name, node_name
                    ),
                    node: node_name.to_string(),
                    line: None,
                });
            }
        }

        // 3. Field value type checks
        for (field_name, field_expr) in fields {
            if let Some(expected_field_type_ir) = expected_shape.get(field_name) {
                let expected_field_type = self.type_name(expected_field_type_ir);
                match field_expr {
                    // LAB-TC-NESTED-RECORD-CONTEXT-P1: inline nested record literal —
                    // when the expected field type is a named record in type_shapes,
                    // recurse to validate its shape. Bounded: one call per nesting
                    // level, no global inference or retroactive symbol mutation.
                    // If the expected type is not a named record (Map[...],
                    // Collection[...], scalar) → skip (Unknown-compatible).
                    Expr::RecordLiteral {
                        fields: inner_fields,
                    } => {
                        if let Some(inner_shape) = type_shapes.get(expected_field_type.as_str()) {
                            self.check_record_literal_shape(
                                inner_fields,
                                inner_shape,
                                &expected_field_type,
                                node_name,
                                symbol_types,
                                type_shapes,
                                type_errors,
                            );
                        }
                        // Non-named-record expected type (Map, Collection, scalar):
                        // skip — Unknown-compatible, no false positive.
                    }
                    _ => {
                        if let Some(actual_field_type) =
                            self.infer_field_expr_type(field_expr, symbol_types)
                        {
                            if actual_field_type != expected_field_type
                                && actual_field_type != "Unknown"
                            {
                                type_errors.push(ClassifierDiagnostic {
                                    rule: "OOF-TY0".to_string(),
                                    message: format!(
                                        "Record type '{}': field '{}' expects {}, got {} at node '{}'",
                                        expected_type_name, field_name,
                                        expected_field_type, actual_field_type, node_name
                                    ),
                                    node: node_name.to_string(),
                                    line: None,
                                });
                            }
                        }
                    }
                }
            }
        }
    }

    /// LAB-TC-ARRAY-P1: Validate an ArrayLiteral against a declared Collection[T]
    /// element type. Each element must conform to the element type T:
    ///   - RecordLiteral element → `check_record_literal_shape` against T's shape
    ///     (missing/extra/wrong-typed fields fail closed via that method).
    ///   - Ref / Literal element → element type name must equal T (fail closed on
    ///     mismatch; Unknown is permissive and skipped, as in record fields).
    ///   - record literal where T is not a known record shape (e.g. T = String) →
    ///     fail closed (record literal cannot satisfy a scalar element type).
    ///   - other element expressions → skipped (Unknown-compat, permissive v0).
    ///
    /// Mixed element shapes therefore fail closed: every element is checked against
    /// the SAME element type T, so any element that does not conform emits OOF-TY0.
    ///
    /// Empty arrays emit no errors here — the caller upgrades an empty literal to
    /// Collection[T] using the contextual type. There is no free-standing empty
    /// array type: without a Collection output hint the literal stays Unknown.
    ///
    /// Called from the compute phase after `infer_expr` returns Unknown. The caller
    /// upgrades the compute node type to Collection[T] IFF this method emits no
    /// errors.
    fn check_array_literal_shape(
        &self,
        items: &[Expr],
        elem_type_ir: &serde_json::Value,
        type_shapes: &HashMap<String, HashMap<String, serde_json::Value>>,
        node_name: &str,
        symbol_types: &HashMap<String, serde_json::Value>,
        type_errors: &mut Vec<ClassifierDiagnostic>,
    ) {
        let elem_type_name = self.type_name(elem_type_ir);
        for (idx, item) in items.iter().enumerate() {
            match item {
                Expr::RecordLiteral { fields } => {
                    if let Some(shape) = type_shapes.get(elem_type_name.as_str()) {
                        self.check_record_literal_shape(
                            fields,
                            shape,
                            &elem_type_name,
                            node_name,
                            symbol_types,
                            type_shapes,
                            type_errors,
                        );
                    } else {
                        // Element type is not a known record shape (e.g. a scalar
                        // like String) but the element is a record literal → fail closed.
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-TY0".to_string(),
                            message: format!(
                                "Collection element {} at node '{}': record literal does not match element type '{}'",
                                idx, node_name, elem_type_name
                            ),
                            node: node_name.to_string(),
                            line: None,
                        });
                    }
                }
                _ => {
                    if let Some(actual_type) = self.infer_field_expr_type(item, symbol_types) {
                        if actual_type != elem_type_name && actual_type != "Unknown" {
                            type_errors.push(ClassifierDiagnostic {
                                rule: "OOF-TY0".to_string(),
                                message: format!(
                                    "Collection element {} at node '{}': expected {}, got {}",
                                    idx, node_name, elem_type_name, actual_type
                                ),
                                node: node_name.to_string(),
                                line: None,
                            });
                        }
                    }
                }
            }
        }
    }

    /// Infer the type name of a simple field expression (Ref or Literal).
    /// Returns None for complex expressions — the caller treats None as Unknown-compat
    /// and skips the field type check rather than emitting a spurious error.
    ///
    /// This is intentionally limited to the two common cases in v0 record literals:
    ///   - `field: some_var`   → look up `some_var` in symbol_types
    ///   - `field: 200`        → derive from Literal type_tag (Integer / String / Bool)
    ///
    /// More complex field expressions (arithmetic, function calls, etc.) return None.
    // LAB-MAP-RUST-P1: Map[String,V] type IR builder helpers ----------------------

    fn make_map_type_ir(
        &self,
        key_type: serde_json::Value,
        val_type: serde_json::Value,
    ) -> serde_json::Value {
        let mut m = serde_json::Map::new();
        m.insert(
            "name".to_string(),
            serde_json::Value::String("Map".to_string()),
        );
        m.insert(
            "params".to_string(),
            serde_json::Value::Array(vec![key_type, val_type]),
        );
        serde_json::Value::Object(m)
    }

    fn make_option_type_ir(&self, inner: serde_json::Value) -> serde_json::Value {
        let mut m = serde_json::Map::new();
        m.insert(
            "name".to_string(),
            serde_json::Value::String("Option".to_string()),
        );
        m.insert("params".to_string(), serde_json::Value::Array(vec![inner]));
        serde_json::Value::Object(m)
    }

    /// LAB-MAP-RUST-P1: OOF-MAP1/2/3 annotation check for a single declaration annotation.
    /// OOF-MAP1: non-String key (exempts Unknown — compiler-resolved positions).
    /// OOF-MAP2: Any value (permanently closed).
    /// OOF-MAP3: Unknown value in output annotation.
    fn check_map_annotation(
        &self,
        ann: &serde_json::Value,
        node_name: &str,
        decl_kind: &str,
        errors: &mut Vec<ClassifierDiagnostic>,
    ) {
        let type_ir = self.type_ir(ann);
        let name = self.type_name(&type_ir);
        if name != "Map" {
            return;
        }
        let key_type = self
            .get_param(&type_ir, 0)
            .unwrap_or_else(|| self.type_ir(&serde_json::Value::String("Unknown".to_string())));
        let val_type = self
            .get_param(&type_ir, 1)
            .unwrap_or_else(|| self.type_ir(&serde_json::Value::String("Unknown".to_string())));
        let key_name = self.type_name(&key_type);
        let val_name = self.type_name(&val_type);

        // OOF-MAP1: non-String key (exempts Unknown — compiler-inferred positions)
        if key_name != "String" && key_name != "Unknown" {
            errors.push(ClassifierDiagnostic {
                rule: "OOF-MAP1".to_string(),
                message: format!(
                    "Map key type in v0 must be String; Map[K,V] where K = '{}' requires v1 authorization; use Map[String,V] or a named Record for known key schemas",
                    key_name
                ),
                node: node_name.to_string(),
                line: None,
            });
        }

        // OOF-MAP2: Any value (permanently closed)
        if val_name == "Any" {
            errors.push(ClassifierDiagnostic {
                rule: "OOF-MAP2".to_string(),
                message: "Map value type 'Any' is permanently closed at contract boundaries; use a homogeneous type V or a named Record".to_string(),
                node: node_name.to_string(),
                line: None,
            });
        }

        // OOF-MAP3: Unknown value in output annotation only
        if val_name == "Unknown" && decl_kind == "output" {
            errors.push(ClassifierDiagnostic {
                rule: "OOF-MAP3".to_string(),
                message: "Map value type 'Unknown' is a compiler uncertainty marker and must not appear in user-declared output type annotations".to_string(),
                node: node_name.to_string(),
                line: None,
            });
        }
    }

    fn infer_field_expr_type(
        &self,
        expr: &Expr,
        symbol_types: &HashMap<String, serde_json::Value>,
    ) -> Option<String> {
        match expr {
            Expr::Ref { name } => symbol_types.get(name).map(|t| self.type_name(t)),
            Expr::Literal { type_tag, .. } => Some(type_tag.clone()),
            _ => None,
        }
    }
}

pub struct TypedExpression {
    pub resolved_type: serde_json::Value,
    pub deps: Vec<String>,
    /// PROP-044 P5: SIR-ready enriched expression for variant_construct / match_expr.
    /// Present only for these two kinds; None for all other expressions.
    /// When Some, the TypedDecl annotated_expr carries it through to the emitter.
    pub annotated_expr: Option<serde_json::Value>,
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
        Expr::Call {
            fn_name: callee,
            args,
        } => {
            if callee == fn_name {
                return true;
            }
            args.iter().any(|arg| expr_has_call(arg, fn_name))
        }
        Expr::BinaryOp { left, right, .. } => {
            expr_has_call(left, fn_name) || expr_has_call(right, fn_name)
        }
        Expr::UnaryOp { operand, .. } => expr_has_call(operand, fn_name),
        Expr::FieldAccess { object, .. } => expr_has_call(object, fn_name),
        Expr::IndexAccess { object, index } => {
            expr_has_call(object, fn_name) || expr_has_call(index, fn_name)
        }
        Expr::SliceRecord { fields } => fields.values().any(|v| expr_has_call(v, fn_name)),
        Expr::IfExpr {
            cond,
            then,
            else_block,
        } => {
            expr_has_call(cond, fn_name)
                || is_recursive(then, fn_name)
                || else_block
                    .as_ref()
                    .map_or(false, |eb| is_recursive(eb, fn_name))
        }
        Expr::Lambda { body, .. } => match body.as_ref() {
            ExprOrBlock::Expr(e) => expr_has_call(e, fn_name),
            ExprOrBlock::Block(b) => is_recursive(b, fn_name),
        },
        Expr::ArrayLiteral { items } => items.iter().any(|item| expr_has_call(item, fn_name)),
        Expr::RecordLiteral { fields } => fields.values().any(|v| expr_has_call(v, fn_name)),
        Expr::RecordSpread { spread, fields } => {
            expr_has_call(spread, fn_name) || fields.values().any(|v| expr_has_call(v, fn_name))
        }
        _ => false,
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
        Expr::IfExpr {
            cond,
            then,
            else_block,
        } => {
            expr_has_now(cond)
                || block_has_now(then)
                || else_block.as_ref().map_or(false, block_has_now)
        }
        Expr::Lambda { body, .. } => match body.as_ref() {
            ExprOrBlock::Expr(e) => expr_has_now(e),
            ExprOrBlock::Block(b) => block_has_now(b),
        },
        Expr::ArrayLiteral { items } => items.iter().any(expr_has_now),
        Expr::RecordLiteral { fields } => fields.values().any(expr_has_now),
        Expr::RecordSpread { spread, fields } => {
            expr_has_now(spread) || fields.values().any(expr_has_now)
        }
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

// ── SCC-based OOF-L4 gate (LAB-FUNCTION-RECURSION-P4) ────────────────────────

fn block_collect_calls(
    body: &crate::parser::BlockBody,
    fn_names: &HashSet<String>,
    out: &mut HashSet<String>,
) {
    for stmt in &body.stmts {
        let expr = match stmt {
            Stmt::Let { expr, .. } | Stmt::ExprStmt { expr } => expr,
        };
        expr_collect_calls(expr, fn_names, out);
    }
    if let Some(re) = &body.return_expr {
        expr_collect_calls(re, fn_names, out);
    }
}

fn collect_fn_calls(body: &crate::parser::BlockBody, fn_names: &HashSet<String>) -> Vec<String> {
    let mut out: HashSet<String> = HashSet::new();
    block_collect_calls(body, fn_names, &mut out);
    let mut v: Vec<String> = out.into_iter().collect();
    v.sort();
    v
}

fn expr_collect_calls(expr: &Expr, fn_names: &HashSet<String>, out: &mut HashSet<String>) {
    match expr {
        Expr::Call { fn_name, args } => {
            if fn_names.contains(fn_name) {
                out.insert(fn_name.clone());
            }
            for arg in args {
                expr_collect_calls(arg, fn_names, out);
            }
        }
        Expr::BinaryOp { left, right, .. } => {
            expr_collect_calls(left, fn_names, out);
            expr_collect_calls(right, fn_names, out);
        }
        Expr::UnaryOp { operand, .. } => expr_collect_calls(operand, fn_names, out),
        Expr::FieldAccess { object, .. } => expr_collect_calls(object, fn_names, out),
        Expr::IndexAccess { object, index } => {
            expr_collect_calls(object, fn_names, out);
            expr_collect_calls(index, fn_names, out);
        }
        Expr::SliceRecord { fields } => {
            for v in fields.values() {
                expr_collect_calls(v, fn_names, out);
            }
        }
        Expr::IfExpr {
            cond,
            then,
            else_block,
        } => {
            expr_collect_calls(cond, fn_names, out);
            block_collect_calls(then, fn_names, out);
            if let Some(eb) = else_block {
                block_collect_calls(eb, fn_names, out);
            }
        }
        Expr::Lambda { body, .. } => match body.as_ref() {
            ExprOrBlock::Expr(e) => expr_collect_calls(e, fn_names, out),
            ExprOrBlock::Block(b) => block_collect_calls(b, fn_names, out),
        },
        Expr::ArrayLiteral { items } => {
            for item in items {
                expr_collect_calls(item, fn_names, out);
            }
        }
        Expr::RecordSpread { spread, fields } => {
            expr_collect_calls(spread, fn_names, out);
            for v in fields.values() {
                expr_collect_calls(v, fn_names, out);
            }
        }
        Expr::RecordLiteral { fields } => {
            for v in fields.values() {
                expr_collect_calls(v, fn_names, out);
            }
        }
        Expr::VariantConstruct { fields, .. } => {
            for v in fields.values() {
                expr_collect_calls(v, fn_names, out);
            }
        }
        Expr::MatchExpr { subject, arms } => {
            expr_collect_calls(subject, fn_names, out);
            for arm in arms {
                expr_collect_calls(&arm.body, fn_names, out);
            }
        }
        // NW-T2-4: `?`-wrapped calls (`helper(x)?`) are real call edges. Without this arm both
        // the OOF-L4 recursion graph and the effect summary would miss callees reached through
        // fallible binding.
        Expr::Try { expr } => expr_collect_calls(expr, fn_names, out),
        _ => {}
    }
}

// ── NW-T2-4: interprocedural effect summary (compiler §B-U5) ─────────────────
// First slice models a single `ambient_io` effect: a `def` body that directly calls a
// `stdlib.IO.*` sink, or transitively reaches one through the app-local call graph. Mirrors
// the classifier's inline `stdlib.IO.` prefix scan (classifier::expr_has_io_call) but lifts
// it interprocedurally so a `pure` contract cannot launder I/O through a helper `def`.

fn block_has_io_call(body: &crate::parser::BlockBody) -> bool {
    for stmt in &body.stmts {
        let expr = match stmt {
            Stmt::Let { expr, .. } | Stmt::ExprStmt { expr } => expr,
        };
        if expr_has_io_call(expr) {
            return true;
        }
    }
    if let Some(re) = &body.return_expr {
        if expr_has_io_call(re) {
            return true;
        }
    }
    false
}

fn expr_has_io_call(expr: &Expr) -> bool {
    match expr {
        Expr::Call { fn_name, args } => {
            fn_name.starts_with("stdlib.IO.") || args.iter().any(expr_has_io_call)
        }
        Expr::BinaryOp { left, right, .. } => expr_has_io_call(left) || expr_has_io_call(right),
        Expr::UnaryOp { operand, .. } => expr_has_io_call(operand),
        Expr::FieldAccess { object, .. } => expr_has_io_call(object),
        Expr::IndexAccess { object, index } => expr_has_io_call(object) || expr_has_io_call(index),
        Expr::SliceRecord { fields } => fields.values().any(expr_has_io_call),
        Expr::IfExpr {
            cond,
            then,
            else_block,
        } => {
            expr_has_io_call(cond)
                || block_has_io_call(then)
                || else_block.as_ref().map_or(false, block_has_io_call)
        }
        Expr::Lambda { body, .. } => match body.as_ref() {
            ExprOrBlock::Expr(e) => expr_has_io_call(e),
            ExprOrBlock::Block(b) => block_has_io_call(b),
        },
        Expr::ArrayLiteral { items } => items.iter().any(expr_has_io_call),
        Expr::RecordLiteral { fields } => fields.values().any(expr_has_io_call),
        Expr::RecordSpread { spread, fields } => {
            expr_has_io_call(spread) || fields.values().any(expr_has_io_call)
        }
        Expr::VariantConstruct { fields, .. } => fields.values().any(expr_has_io_call),
        Expr::MatchExpr { subject, arms } => {
            expr_has_io_call(subject) || arms.iter().any(|a| expr_has_io_call(&a.body))
        }
        Expr::Try { expr } => expr_has_io_call(expr),
        _ => false,
    }
}

/// Compute the transitive `ambient_io` summary for every app-local `def`.
///
/// Seed: a def whose body directly calls a `stdlib.IO.*` sink.
/// Propagation: reuse the same call graph + Tarjan SCC machinery as the OOF-L4 gate.
/// Tarjan emits SCCs in reverse-topological order (callees before callers), so a single
/// forward pass over the condensation is sufficient — a callee's summary is final before
/// any caller is visited. Cyclic helper graphs are handled deterministically: every member
/// of an SCC shares one summary value (the SCC is `ambient_io` iff any member touches I/O
/// directly, or any member calls out to an already-`ambient_io` def).
fn compute_ambient_io_summary(functions: &[crate::parser::FunctionDecl]) -> HashMap<String, bool> {
    let fn_names: HashSet<String> = functions.iter().map(|f| f.name.clone()).collect();
    let mut fn_names_sorted: Vec<String> = fn_names.iter().cloned().collect();
    fn_names_sorted.sort();

    let fn_calls: HashMap<String, Vec<String>> = functions
        .iter()
        .map(|f| (f.name.clone(), collect_fn_calls(&f.body, &fn_names)))
        .collect();

    // Seed direct I/O.
    let mut ambient_io: HashMap<String, bool> = functions
        .iter()
        .map(|f| (f.name.clone(), block_has_io_call(&f.body)))
        .collect();

    // Propagate over the SCC condensation (callees finalized before callers).
    let sccs = tarjan_sccs(&fn_names_sorted, &fn_calls);
    for scc in &sccs {
        let mut scc_io = scc.iter().any(|m| *ambient_io.get(m).unwrap_or(&false));
        if !scc_io {
            'outer: for m in scc {
                if let Some(callees) = fn_calls.get(m) {
                    for callee in callees {
                        if *ambient_io.get(callee).unwrap_or(&false) {
                            scc_io = true;
                            break 'outer;
                        }
                    }
                }
            }
        }
        if scc_io {
            for m in scc {
                ambient_io.insert(m.clone(), true);
            }
        }
    }

    ambient_io
}

struct TarjanScc {
    index_map: HashMap<String, usize>,
    lowlink: HashMap<String, usize>,
    on_stack: HashSet<String>,
    stack: Vec<String>,
    counter: usize,
    sccs: Vec<Vec<String>>,
}

impl TarjanScc {
    fn new() -> Self {
        TarjanScc {
            index_map: HashMap::new(),
            lowlink: HashMap::new(),
            on_stack: HashSet::new(),
            stack: Vec::new(),
            counter: 0,
            sccs: Vec::new(),
        }
    }

    fn visit(&mut self, v: &str, adj: &HashMap<String, Vec<String>>) {
        self.index_map.insert(v.to_string(), self.counter);
        self.lowlink.insert(v.to_string(), self.counter);
        self.counter += 1;
        self.stack.push(v.to_string());
        self.on_stack.insert(v.to_string());

        let neighbors: Vec<String> = adj.get(v).cloned().unwrap_or_default();
        for w in &neighbors {
            if !self.index_map.contains_key(w.as_str()) {
                self.visit(w, adj);
                let ll_w = *self.lowlink.get(w.as_str()).unwrap();
                let ll_v = *self.lowlink.get(v).unwrap();
                if ll_w < ll_v {
                    self.lowlink.insert(v.to_string(), ll_w);
                }
            } else if self.on_stack.contains(w.as_str()) {
                let idx_w = *self.index_map.get(w.as_str()).unwrap();
                let ll_v = *self.lowlink.get(v).unwrap();
                if idx_w < ll_v {
                    self.lowlink.insert(v.to_string(), idx_w);
                }
            }
        }

        if *self.lowlink.get(v).unwrap() == *self.index_map.get(v).unwrap() {
            let mut scc = Vec::new();
            loop {
                let w = self.stack.pop().unwrap();
                self.on_stack.remove(&w);
                let is_root = w == v;
                scc.push(w);
                if is_root {
                    break;
                }
            }
            scc.sort();
            self.sccs.push(scc);
        }
    }
}

fn tarjan_sccs(nodes: &[String], adj: &HashMap<String, Vec<String>>) -> Vec<Vec<String>> {
    let mut state = TarjanScc::new();
    for node in nodes {
        if !state.index_map.contains_key(node.as_str()) {
            state.visit(node, adj);
        }
    }
    state.sccs
}

/// OOF-R3: produce a human-readable description of an expression for error messages.
fn syntactic_arg_desc(expr: &Expr) -> String {
    match expr {
        Expr::Ref { name } => name.clone(),
        Expr::Literal { value, .. } => value.to_string(),
        Expr::BinaryOp { op, left, right } => {
            format!(
                "{} {} {}",
                syntactic_arg_desc(left),
                op,
                syntactic_arg_desc(right)
            )
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
