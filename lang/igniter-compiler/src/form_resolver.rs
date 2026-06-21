use crate::form_registry::{FormDiagnostic, FormEntry, FormRegistry};
use crate::parser::Expr;
use crate::typechecker::TypedProgram;
use std::collections::HashMap;

// H2: language primitives that pass through without form registration
// These are correct-behavior misses, not form errors
const LANGUAGE_PRIMITIVES: &[&str] = &[
    "+", "-", "*", "/", "%", "++", "==", "!=", "<", ">", "<=", ">=", "&&", "||", "!", "@", "..",
];

// ── Output types ──────────────────────────────────────────────────────────────

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ResolvedProgram {
    pub resolved_forms: Vec<ResolvedExpr>,
    pub trace: Vec<TraceEvent>,
    pub ambiguities: Vec<AmbiguityEvent>,
    pub diagnostics: Vec<FormDiagnostic>, // P7/P8/P9 fail-closed evidence
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ResolvedExpr {
    pub original_kind: String, // "binary_op", "unary_op", "field_access"
    pub trigger: String,       // "+", ".sum", "!"
    pub resolved_to: String,   // contract name
    pub form_id: String,
    pub priority: i32,
    pub contract_decl: String, // declaring node path (contract::decl)
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub typed_operands: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub typed_result: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub lowering_target: Option<String>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct TraceEvent {
    pub kind: String, // "resolved" | "ambiguity" | "miss"
    pub trigger: String,
    pub expr_kind: String,
    pub candidates: Vec<String>, // contract names
    pub resolved_to: Option<String>,
    pub contract_ctx: String, // which contract body this expr lives in
    pub decl_name: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub typed_operands: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub typed_result: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub refused_candidates: Vec<RefusedCandidate>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub filter_status: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub lowering_target: Option<String>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct AmbiguityEvent {
    pub trigger: String,
    pub candidates: Vec<String>,
    pub contract: String,
    pub decl: String,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct RefusedCandidate {
    pub contract: String,
    pub form_id: String,
    pub reason: String,
    pub expected_operands: Vec<String>,
    pub actual_operands: Vec<String>,
}

#[derive(Debug, Clone)]
struct TypeFacts {
    operands: Vec<String>,
    result: Option<String>,
}

#[derive(Debug, Clone)]
struct ContractSignature {
    input_types: Vec<String>,
}

// ── Resolver ─────────────────────────────────────────────────────────────────

pub struct FormResolver;

impl FormResolver {
    pub fn resolve(typed: &TypedProgram, registry: &FormRegistry) -> ResolvedProgram {
        let mut resolved_forms = Vec::new();
        let mut trace = Vec::new();
        let mut ambiguities = Vec::new();
        let mut diagnostics = Vec::new();
        let signatures = Self::contract_signatures(typed);

        for contract in &typed.contracts {
            let symbol_types: HashMap<String, String> = contract
                .symbols
                .iter()
                .map(|symbol| (symbol.name.clone(), Self::type_name(&symbol.type_info)))
                .collect();
            for decl in &contract.declarations {
                if let Some(expr) = &decl.expr {
                    Self::walk_expr(
                        expr,
                        registry,
                        &signatures,
                        &symbol_types,
                        &contract.name,
                        &decl.name,
                        &mut resolved_forms,
                        &mut trace,
                        &mut ambiguities,
                        &mut diagnostics,
                    );
                }
            }
        }

        ResolvedProgram {
            resolved_forms,
            trace,
            ambiguities,
            diagnostics,
        }
    }

    fn walk_expr(
        expr: &Expr,
        registry: &FormRegistry,
        signatures: &HashMap<String, ContractSignature>,
        symbol_types: &HashMap<String, String>,
        contract_name: &str,
        decl_name: &str,
        resolved: &mut Vec<ResolvedExpr>,
        trace: &mut Vec<TraceEvent>,
        ambiguities: &mut Vec<AmbiguityEvent>,
        diagnostics: &mut Vec<FormDiagnostic>,
    ) {
        // LAB-COMPILER-LIVENESS-P2: non-fatal depth counter (RAII — auto-decrements on all exits)
        let _depth_guard = crate::liveness::FrWalkGuard::enter();
        match expr {
            Expr::BinaryOp { op, left, right } => {
                let left_type = Self::expr_type(left, symbol_types);
                let right_type = Self::expr_type(right, symbol_types);
                let type_facts = TypeFacts {
                    operands: vec![left_type.clone(), right_type.clone()],
                    result: Self::binary_result_type(op, &left_type, &right_type),
                };
                Self::resolve_trigger(
                    op,
                    "binary_op",
                    contract_name,
                    decl_name,
                    registry,
                    signatures,
                    type_facts,
                    resolved,
                    trace,
                    ambiguities,
                    diagnostics,
                );
                Self::walk_expr(
                    left,
                    registry,
                    signatures,
                    symbol_types,
                    contract_name,
                    decl_name,
                    resolved,
                    trace,
                    ambiguities,
                    diagnostics,
                );
                Self::walk_expr(
                    right,
                    registry,
                    signatures,
                    symbol_types,
                    contract_name,
                    decl_name,
                    resolved,
                    trace,
                    ambiguities,
                    diagnostics,
                );
            }
            Expr::UnaryOp { op, operand } => {
                let operand_type = Self::expr_type(operand, symbol_types);
                Self::resolve_trigger(
                    op,
                    "unary_op",
                    contract_name,
                    decl_name,
                    registry,
                    signatures,
                    TypeFacts {
                        operands: vec![operand_type],
                        result: None,
                    },
                    resolved,
                    trace,
                    ambiguities,
                    diagnostics,
                );
                Self::walk_expr(
                    operand,
                    registry,
                    signatures,
                    symbol_types,
                    contract_name,
                    decl_name,
                    resolved,
                    trace,
                    ambiguities,
                    diagnostics,
                );
            }
            Expr::FieldAccess { object, field } => {
                let trigger = format!(".{}", field);
                let object_type = Self::expr_type(object, symbol_types);
                Self::resolve_trigger(
                    &trigger,
                    "field_access",
                    contract_name,
                    decl_name,
                    registry,
                    signatures,
                    TypeFacts {
                        operands: vec![object_type],
                        result: None,
                    },
                    resolved,
                    trace,
                    ambiguities,
                    diagnostics,
                );
                Self::walk_expr(
                    object,
                    registry,
                    signatures,
                    symbol_types,
                    contract_name,
                    decl_name,
                    resolved,
                    trace,
                    ambiguities,
                    diagnostics,
                );
            }
            Expr::Call { fn_name, args } => {
                // P10: explicit contract calls (Call nodes) bypass form resolution entirely
                // We still walk args but do NOT route through trigger resolution
                for arg in args {
                    Self::walk_expr(
                        arg,
                        registry,
                        signatures,
                        symbol_types,
                        contract_name,
                        decl_name,
                        resolved,
                        trace,
                        ambiguities,
                        diagnostics,
                    );
                }
                // Emit trace note that explicit call was encountered (not form-resolved)
                trace.push(TraceEvent {
                    kind: "explicit_call".to_string(),
                    trigger: fn_name.clone(),
                    expr_kind: "call".to_string(),
                    candidates: vec![],
                    resolved_to: None,
                    contract_ctx: contract_name.to_string(),
                    decl_name: decl_name.to_string(),
                    typed_operands: args
                        .iter()
                        .map(|arg| Self::expr_type(arg, symbol_types))
                        .collect(),
                    typed_result: None,
                    refused_candidates: vec![],
                    filter_status: Some("explicit_call_bypass".to_string()),
                    lowering_target: None,
                });
                let _ = fn_name; // suppress unused warning
            }
            Expr::IfExpr {
                cond,
                then,
                else_block,
            } => {
                Self::walk_expr(
                    cond,
                    registry,
                    signatures,
                    symbol_types,
                    contract_name,
                    decl_name,
                    resolved,
                    trace,
                    ambiguities,
                    diagnostics,
                );
                for stmt in &then.stmts {
                    Self::walk_stmt_expr(
                        stmt,
                        registry,
                        signatures,
                        symbol_types,
                        contract_name,
                        decl_name,
                        resolved,
                        trace,
                        ambiguities,
                        diagnostics,
                    );
                }
                if let Some(ret) = &then.return_expr {
                    Self::walk_expr(
                        ret,
                        registry,
                        signatures,
                        symbol_types,
                        contract_name,
                        decl_name,
                        resolved,
                        trace,
                        ambiguities,
                        diagnostics,
                    );
                }
                if let Some(eb) = else_block {
                    for stmt in &eb.stmts {
                        Self::walk_stmt_expr(
                            stmt,
                            registry,
                            signatures,
                            symbol_types,
                            contract_name,
                            decl_name,
                            resolved,
                            trace,
                            ambiguities,
                            diagnostics,
                        );
                    }
                    if let Some(ret) = &eb.return_expr {
                        Self::walk_expr(
                            ret,
                            registry,
                            signatures,
                            symbol_types,
                            contract_name,
                            decl_name,
                            resolved,
                            trace,
                            ambiguities,
                            diagnostics,
                        );
                    }
                }
            }
            Expr::IndexAccess { object, index } => {
                Self::walk_expr(
                    object,
                    registry,
                    signatures,
                    symbol_types,
                    contract_name,
                    decl_name,
                    resolved,
                    trace,
                    ambiguities,
                    diagnostics,
                );
                Self::walk_expr(
                    index,
                    registry,
                    signatures,
                    symbol_types,
                    contract_name,
                    decl_name,
                    resolved,
                    trace,
                    ambiguities,
                    diagnostics,
                );
            }
            Expr::Lambda { body, .. } => match body.as_ref() {
                crate::parser::ExprOrBlock::Expr(e) => Self::walk_expr(
                    e,
                    registry,
                    signatures,
                    symbol_types,
                    contract_name,
                    decl_name,
                    resolved,
                    trace,
                    ambiguities,
                    diagnostics,
                ),
                crate::parser::ExprOrBlock::Block(b) => {
                    for stmt in &b.stmts {
                        Self::walk_stmt_expr(
                            stmt,
                            registry,
                            signatures,
                            symbol_types,
                            contract_name,
                            decl_name,
                            resolved,
                            trace,
                            ambiguities,
                            diagnostics,
                        );
                    }
                    if let Some(ret) = &b.return_expr {
                        Self::walk_expr(
                            ret,
                            registry,
                            signatures,
                            symbol_types,
                            contract_name,
                            decl_name,
                            resolved,
                            trace,
                            ambiguities,
                            diagnostics,
                        );
                    }
                }
            },
            Expr::Ref { .. }
            | Expr::Literal { .. }
            | Expr::Symbol { .. }
            | Expr::ArrayLiteral { .. }
            | Expr::RecordLiteral { .. }
            | Expr::RecordSpread { .. }
            | Expr::SliceRecord { .. }
            | Expr::Error { .. }
            | Expr::VariantConstruct { .. }
            | Expr::MatchExpr { .. }
            | Expr::Block(_)
            | Expr::Try { .. } => {}
        }
    }

    fn walk_stmt_expr(
        stmt: &crate::parser::Stmt,
        registry: &FormRegistry,
        signatures: &HashMap<String, ContractSignature>,
        symbol_types: &HashMap<String, String>,
        contract_name: &str,
        decl_name: &str,
        resolved: &mut Vec<ResolvedExpr>,
        trace: &mut Vec<TraceEvent>,
        ambiguities: &mut Vec<AmbiguityEvent>,
        diagnostics: &mut Vec<FormDiagnostic>,
    ) {
        match stmt {
            crate::parser::Stmt::Let { expr, .. } | crate::parser::Stmt::ExprStmt { expr } => {
                Self::walk_expr(
                    expr,
                    registry,
                    signatures,
                    symbol_types,
                    contract_name,
                    decl_name,
                    resolved,
                    trace,
                    ambiguities,
                    diagnostics,
                )
            }
        }
    }

    fn resolve_trigger(
        trigger: &str,
        expr_kind: &str,
        contract_name: &str,
        decl_name: &str,
        registry: &FormRegistry,
        signatures: &HashMap<String, ContractSignature>,
        type_facts: TypeFacts,
        resolved: &mut Vec<ResolvedExpr>,
        trace: &mut Vec<TraceEvent>,
        ambiguities: &mut Vec<AmbiguityEvent>,
        diagnostics: &mut Vec<FormDiagnostic>,
    ) {
        let all_candidates: Vec<&FormEntry> = registry
            .trigger_index
            .get(trigger)
            .map(|idxs| idxs.iter().map(|&i| &registry.entries[i]).collect())
            .unwrap_or_default();

        // H2: trigger not in registry — classify honestly
        if all_candidates.is_empty() {
            // Is it a known language primitive? → primitive_pass_through (correct, not an error)
            // Otherwise → unresolved_trigger (might be a typo or missing form declaration)
            let kind = if LANGUAGE_PRIMITIVES.contains(&trigger) {
                "primitive_pass_through"
            } else {
                "unresolved_trigger"
            };
            trace.push(TraceEvent {
                kind: kind.to_string(),
                trigger: trigger.to_string(),
                expr_kind: expr_kind.to_string(),
                candidates: vec![],
                resolved_to: None,
                contract_ctx: contract_name.to_string(),
                decl_name: decl_name.to_string(),
                typed_operands: type_facts.operands,
                typed_result: type_facts.result,
                refused_candidates: vec![],
                filter_status: Some(kind.to_string()),
                lowering_target: None,
            });
            return;
        }

        // P7: filter out no_form contracts — fail closed with diagnostic
        let mut blocked_no_form: Vec<String> = Vec::new();
        let candidates: Vec<&FormEntry> = all_candidates
            .into_iter()
            .filter(|e| {
                if registry.no_form_contracts.contains(&e.contract) {
                    blocked_no_form.push(e.contract.clone());
                    false
                } else {
                    true
                }
            })
            .collect();

        for blocked in &blocked_no_form {
            diagnostics.push(FormDiagnostic {
                code: "E-FORM-NOFM-MATCH".to_string(),
                severity: "error".to_string(),
                message: format!(
                    "form '{}' would resolve to no_form contract '{}' in {}::{} — blocked",
                    trigger, blocked, contract_name, decl_name
                ),
                contract: contract_name.to_string(),
            });
            trace.push(TraceEvent {
                kind: "blocked_no_form".to_string(),
                trigger: trigger.to_string(),
                expr_kind: expr_kind.to_string(),
                candidates: blocked_no_form.clone(),
                resolved_to: None,
                contract_ctx: contract_name.to_string(),
                decl_name: decl_name.to_string(),
                typed_operands: type_facts.operands.clone(),
                typed_result: type_facts.result.clone(),
                refused_candidates: vec![],
                filter_status: Some("blocked_no_form".to_string()),
                lowering_target: None,
            });
        }

        // After filtering no_form, check what's left
        if candidates.is_empty() {
            // All candidates were no_form — trigger is fully blocked
            return;
        }

        let mut refused_candidates = Vec::new();
        let candidates: Vec<&FormEntry> = candidates
            .into_iter()
            .filter(|entry| {
                match Self::candidate_refusal(entry, signatures, &type_facts.operands) {
                    Some(refusal) => {
                        refused_candidates.push(refusal);
                        false
                    }
                    None => true,
                }
            })
            .collect();

        let candidate_names: Vec<String> = candidates.iter().map(|c| c.contract.clone()).collect();

        if candidates.is_empty() {
            diagnostics.push(FormDiagnostic {
                code:     "E-FORM-UNRESOLVED".to_string(),
                severity: "error".to_string(),
                message:  format!(
                    "form '{}' has registered candidates in {}::{} but none match typed operands [{}]",
                    trigger, contract_name, decl_name, type_facts.operands.join(", ")
                ),
                contract: contract_name.to_string(),
            });
            trace.push(TraceEvent {
                kind: "unresolved_form_error".to_string(),
                trigger: trigger.to_string(),
                expr_kind: expr_kind.to_string(),
                candidates: refused_candidates
                    .iter()
                    .map(|c| c.contract.clone())
                    .collect(),
                resolved_to: None,
                contract_ctx: contract_name.to_string(),
                decl_name: decl_name.to_string(),
                typed_operands: type_facts.operands,
                typed_result: type_facts.result,
                refused_candidates,
                filter_status: Some("no_surviving_typed_candidate".to_string()),
                lowering_target: None,
            });
            return;
        }

        if candidates.len() == 1 {
            let entry = candidates[0];
            let lowering_target = Some(format!("call:{}", entry.contract));
            resolved.push(ResolvedExpr {
                original_kind: expr_kind.to_string(),
                trigger: trigger.to_string(),
                resolved_to: entry.contract.clone(),
                form_id: entry.id.clone(),
                priority: entry.priority,
                contract_decl: format!("{}::{}", contract_name, decl_name),
                typed_operands: type_facts.operands.clone(),
                typed_result: type_facts.result.clone(),
                lowering_target: lowering_target.clone(),
            });
            trace.push(TraceEvent {
                kind: "resolved".to_string(),
                trigger: trigger.to_string(),
                expr_kind: expr_kind.to_string(),
                candidates: candidate_names,
                resolved_to: Some(entry.contract.clone()),
                contract_ctx: contract_name.to_string(),
                decl_name: decl_name.to_string(),
                typed_operands: type_facts.operands,
                typed_result: type_facts.result,
                refused_candidates,
                filter_status: Some("typed_candidate_selected".to_string()),
                lowering_target,
            });
        } else {
            // H1: ambiguity MUST fail closed — error, NO winner, compilation refused
            diagnostics.push(FormDiagnostic {
                code:     "E-FORM-AMBIG".to_string(),
                severity: "error".to_string(),
                message:  format!(
                    "form '{}' is ambiguous in {}::{}: candidates [{}] — use explicit call to disambiguate (e.g. ContractName(args))",
                    trigger, contract_name, decl_name,
                    candidate_names.join(", ")
                ),
                contract: contract_name.to_string(),
            });
            ambiguities.push(AmbiguityEvent {
                trigger: trigger.to_string(),
                candidates: candidate_names.clone(),
                contract: contract_name.to_string(),
                decl: decl_name.to_string(),
            });
            // H1: NO resolved form entry — ambiguity blocks resolution
            trace.push(TraceEvent {
                kind: "ambiguity_error".to_string(),
                trigger: trigger.to_string(),
                expr_kind: expr_kind.to_string(),
                candidates: candidate_names,
                resolved_to: None, // H1: no winner
                contract_ctx: contract_name.to_string(),
                decl_name: decl_name.to_string(),
                typed_operands: type_facts.operands,
                typed_result: type_facts.result,
                refused_candidates,
                filter_status: Some("ambiguous_after_type_filter".to_string()),
                lowering_target: None,
            });
        }
    }

    fn contract_signatures(typed: &TypedProgram) -> HashMap<String, ContractSignature> {
        let mut signatures = HashMap::new();
        for contract in &typed.contracts {
            let mut input_types = Vec::new();
            for decl in &contract.declarations {
                match decl.kind.as_str() {
                    "input" => input_types.push(Self::type_name(&decl.type_info)),
                    _ => {}
                }
            }
            signatures.insert(contract.name.clone(), ContractSignature { input_types });
        }
        signatures
    }

    fn candidate_refusal(
        entry: &FormEntry,
        signatures: &HashMap<String, ContractSignature>,
        actual_operands: &[String],
    ) -> Option<RefusedCandidate> {
        let signature = signatures.get(&entry.contract)?;
        if actual_operands.is_empty() {
            return None;
        }

        if signature.input_types.len() < actual_operands.len() {
            return Some(Self::refusal(
                entry,
                "arity_mismatch",
                signature.input_types.clone(),
                actual_operands.to_vec(),
            ));
        }

        let expected: Vec<String> = signature
            .input_types
            .iter()
            .take(actual_operands.len())
            .cloned()
            .collect();

        let mismatch = expected
            .iter()
            .zip(actual_operands.iter())
            .any(|(expected, actual)| {
                expected != "Unknown" && actual != "Unknown" && expected != actual
            });

        if mismatch {
            Some(Self::refusal(
                entry,
                "operand_type_mismatch",
                expected,
                actual_operands.to_vec(),
            ))
        } else {
            None
        }
    }

    fn refusal(
        entry: &FormEntry,
        reason: &str,
        expected_operands: Vec<String>,
        actual_operands: Vec<String>,
    ) -> RefusedCandidate {
        RefusedCandidate {
            contract: entry.contract.clone(),
            form_id: entry.id.clone(),
            reason: reason.to_string(),
            expected_operands,
            actual_operands,
        }
    }

    fn expr_type(expr: &Expr, symbol_types: &HashMap<String, String>) -> String {
        match expr {
            Expr::Literal { type_tag, .. } => type_tag.clone(),
            Expr::Ref { name } => symbol_types
                .get(name)
                .cloned()
                .unwrap_or_else(|| "Unknown".to_string()),
            Expr::BinaryOp { op, left, right } => {
                let left_type = Self::expr_type(left, symbol_types);
                let right_type = Self::expr_type(right, symbol_types);
                Self::binary_result_type(op, &left_type, &right_type)
                    .unwrap_or_else(|| "Unknown".to_string())
            }
            Expr::UnaryOp { operand, .. } => Self::expr_type(operand, symbol_types),
            Expr::Call { fn_name, .. } if fn_name == "length" => "Integer".to_string(),
            Expr::Call { fn_name, .. } if fn_name == "trim" => "String".to_string(),
            _ => "Unknown".to_string(),
        }
    }

    fn binary_result_type(op: &str, left_type: &str, right_type: &str) -> Option<String> {
        match op {
            "+" | "-" | "*" | "/" => Some("Integer".to_string()),
            "++" if left_type == "String" && right_type == "String" => Some("String".to_string()),
            "++" if left_type == "Collection" && right_type == "Collection" => {
                Some("Collection".to_string())
            }
            ">" | "<" | ">=" | "<=" | "==" | "!=" | "&&" | "||" => Some("Bool".to_string()),
            _ => None,
        }
    }

    fn type_name(type_info: &serde_json::Value) -> String {
        type_info
            .get("name")
            .and_then(|n| n.as_str())
            .unwrap_or("Unknown")
            .to_string()
    }
}
