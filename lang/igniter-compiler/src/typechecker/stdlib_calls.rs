use super::*;

// LAB-COLLECTION-NESTED-OPS-DIAGNOSTIC-P2
// Some collection ops inside a higher-order collection lambda remain non-executable in v0. These helpers
// detect that shape so the typechecker can reject it early (OOF-COL-NESTED) and name the `call_contract`
// workaround. Single-level HOFs (`map(xs, x -> sin(x))`) and top-level `sum(map(...))` are NOT caught —
// only a still-unsupported collection op *inside* a HOF lambda body.

/// Collection ops STILL unsupported inside a HOF lambda body. NARROWED by
/// LAB-VM-NESTED-HOF-EVAL-AST-RECOVERY-P3: `map`/`filter`/`sum` execute nested (eval_ast arms +
/// qualified-name normalization). LAB-VM-NESTED-FOLD-MAP-REDUCE-AGGREGATE-P4: `fold` now executes nested too
/// — eval_ast gained a `map_reduce_aggregate` arm running the `fold`/`reduce` pipeline stage with `local_env`
/// capture — so it is dropped from this guard. `filter_map`/`reduce` still have no eval_ast arm, so they keep
/// the early guided diagnostic (`OOF-COL-NESTED`) instead of a late VM failure.
const NESTED_COLLECTION_OPS: &[&str] = &["filter_map", "reduce"];

/// Collection HOFs that take a lambda — whose lambda body is scanned for a (still-unsupported) nested op.
const LAMBDA_HOF_NAMES: &[&str] = &["map", "filter", "filter_map", "fold", "reduce"];

fn nested_op_base(name: &str) -> &str {
    name.rsplit('.').next().unwrap_or(name)
}

fn expr_has_nested_collection_op(e: &Expr) -> bool {
    match e {
        Expr::Call { fn_name, args } => {
            NESTED_COLLECTION_OPS.contains(&nested_op_base(fn_name))
                || args.iter().any(expr_has_nested_collection_op)
        }
        Expr::BinaryOp { left, right, .. } => {
            expr_has_nested_collection_op(left) || expr_has_nested_collection_op(right)
        }
        Expr::UnaryOp { operand, .. } => expr_has_nested_collection_op(operand),
        Expr::FieldAccess { object, .. } => expr_has_nested_collection_op(object),
        Expr::IndexAccess { object, index } => {
            expr_has_nested_collection_op(object) || expr_has_nested_collection_op(index)
        }
        Expr::Lambda { body, .. } => expr_or_block_has_nested_collection_op(body),
        Expr::IfExpr {
            cond,
            then,
            else_block,
        } => {
            expr_has_nested_collection_op(cond)
                || block_has_nested_collection_op(then)
                || else_block
                    .as_ref()
                    .is_some_and(block_has_nested_collection_op)
        }
        Expr::MatchExpr { subject, arms } => {
            expr_has_nested_collection_op(subject)
                || arms.iter().any(|a| expr_has_nested_collection_op(&a.body))
        }
        Expr::Block(b) => block_has_nested_collection_op(b),
        Expr::ArrayLiteral { items } => items.iter().any(expr_has_nested_collection_op),
        Expr::RecordLiteral { fields } | Expr::SliceRecord { fields } => {
            fields.values().any(expr_has_nested_collection_op)
        }
        Expr::RecordSpread { spread, fields } => {
            expr_has_nested_collection_op(spread)
                || fields.values().any(expr_has_nested_collection_op)
        }
        Expr::VariantConstruct { fields, .. } => fields.values().any(expr_has_nested_collection_op),
        Expr::Try { expr } => expr_has_nested_collection_op(expr),
        _ => false, // Literal, Ref, Symbol, Error
    }
}

fn block_has_nested_collection_op(b: &crate::parser::BlockBody) -> bool {
    // v0: only the block's return expression is scanned (lambda bodies in the workload are expressions;
    // a nested collection op bound in a block `let` is an accepted v0 limitation).
    b.return_expr
        .as_ref()
        .is_some_and(|e| expr_has_nested_collection_op(e))
}

fn expr_or_block_has_nested_collection_op(b: &ExprOrBlock) -> bool {
    match b {
        ExprOrBlock::Expr(e) => expr_has_nested_collection_op(e),
        ExprOrBlock::Block(b) => block_has_nested_collection_op(b),
    }
}

impl TypeChecker {
    pub(super) fn infer_stdlib_call(
        &self,
        fn_name: &str,
        args: &[Expr],
        typed_args: &[TypedExpression],
        symbol_types: &HashMap<String, serde_json::Value>,
        olap_env: &HashMap<String, HashMap<String, serde_json::Value>>,
        type_shapes: &HashMap<String, HashMap<String, serde_json::Value>>,
        type_errors: &mut Vec<ClassifierDiagnostic>,
        type_warnings: &mut Vec<ClassifierDiagnostic>,
        node_name: &str,
        functions: &[crate::parser::FunctionDecl],
        contract_registry: &HashMap<String, ContractRegistryEntry>,
        current_contract_name: &str,
    ) -> Option<serde_json::Value> {
        let mut is_resolved = false;
        let mut resolved_type = self.type_ir(&serde_json::Value::String("Unknown".to_string()));
        let is_collection_first_arg = typed_args
            .first()
            .map(|t| self.type_name(&t.resolved_type) == "Collection")
            .unwrap_or(false);
        let is_legacy_minmax_aggregate =
            matches!(fn_name, "min" | "max") && is_collection_first_arg;

        // LAB-COLLECTION-NESTED-OPS-DIAGNOSTIC-P2: reject a collection op nested inside a HOF lambda body at
        // typecheck time (it would otherwise typecheck and fail late at VM eval as "Unsupported operator").
        {
            let base = nested_op_base(fn_name);
            if LAMBDA_HOF_NAMES.contains(&base) {
                if let Some(lambda_body) = args.iter().find_map(|a| match a {
                    Expr::Lambda { body, .. } => Some(body.as_ref()),
                    _ => None,
                }) {
                    if expr_or_block_has_nested_collection_op(lambda_body) {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-COL-NESTED".to_string(),
                            message: format!(
                                "nested collection operation inside a `{base}` lambda is not executable (v0): a \
                                 still-unsupported collection op (filter_map/reduce) appears inside a \
                                 higher-order lambda. Extract the inner operation into a named contract and call it via \
                                 call_contract — e.g. `{base}(xs, x -> call_contract(\"Inner\", x, ...))`. See \
                                 LAB-NESTED-COLLECTION-OPS-PRESSURE-KURAMOTO-P1."
                            ),
                            node: node_name.to_string(),
                            line: None,
                        });
                    }
                }
            }
        }

        match fn_name {
            "mul" => {
                is_resolved = true;
                if typed_args.len() >= 2 {
                    let left = &typed_args[0].resolved_type;
                    let right = &typed_args[1].resolved_type;
                    let left_name = self.type_name(left);
                    let right_name = self.type_name(right);
                    if left_name == "Decimal" && right_name == "Decimal" {
                        let left_scale_val = self.decimal_scale(left);
                        let right_scale_val = self.decimal_scale(right);
                        let l_s = left_scale_val.parse::<i64>().unwrap_or(0);
                        let r_s = right_scale_val.parse::<i64>().unwrap_or(0);
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
                        resolved_type = serde_json::Value::Object(sum_type);
                    } else {
                        resolved_type =
                            self.type_ir(&serde_json::Value::String("Decimal".to_string()));
                    }
                } else {
                    resolved_type = self.type_ir(&serde_json::Value::String("Decimal".to_string()));
                }
            }
            "div" | "sub" | "add" => {
                is_resolved = true;
                resolved_type = self.type_ir(&serde_json::Value::String("Decimal".to_string()));
            }
            // LAB-NUMERIC-DECIMAL-CONSTRUCT-P1: explicit Decimal constructor.
            //   decimal(value, scale) -> Decimal[scale]
            //   value : Integer (exact minor units), scale : Integer *literal*.
            // The scale must be a literal so Decimal[scale] is statically known
            // (mirrors the Decimal[N] annotation, whose scale is also a literal).
            // OOF-TY0: arity != 2 or value not Integer.  OOF-DM4: non-literal /
            // negative scale. On any error, falls back to bare Decimal to avoid a
            // cascade. No implicit Float/Integer -> Decimal coercion is introduced.
            "decimal" => {
                is_resolved = true;
                let mut scale_opt: Option<i64> = None;
                if args.len() != 2 {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-TY0".to_string(),
                        message: format!(
                            "stdlib.decimal.decimal: expected 2 arguments (value, scale), got {}",
                            args.len()
                        ),
                        node: node_name.to_string(),
                        line: None,
                    });
                } else {
                    let value_name = self.type_name(&typed_args[0].resolved_type);
                    if value_name != "Integer" && value_name != "Unknown" {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-TY0".to_string(),
                            message: format!(
                                "stdlib.decimal.decimal arg 1: expected Integer, got {}",
                                value_name
                            ),
                            node: node_name.to_string(),
                            line: None,
                        });
                    }
                    match &args[1] {
                        Expr::Literal { value, type_tag } if type_tag == "Integer" => {
                            match value.as_i64() {
                                Some(s) if s >= 0 => {
                                    scale_opt = Some(s);
                                }
                                _ => {
                                    type_errors.push(ClassifierDiagnostic {
                                        rule: "OOF-DM4".to_string(),
                                        message: "stdlib.decimal.decimal: scale must be a non-negative Integer literal".to_string(),
                                        node: node_name.to_string(),
                                        line: None,
                                    });
                                }
                            }
                        }
                        _ => {
                            type_errors.push(ClassifierDiagnostic {
                                rule: "OOF-DM4".to_string(),
                                message: "stdlib.decimal.decimal: scale must be an Integer literal"
                                    .to_string(),
                                node: node_name.to_string(),
                                line: None,
                            });
                        }
                    }
                }
                resolved_type = match scale_opt {
                    Some(s) => {
                        let mut dec = serde_json::Map::new();
                        dec.insert(
                            "name".to_string(),
                            serde_json::Value::String("Decimal".to_string()),
                        );
                        let mut inner = serde_json::Map::new();
                        inner.insert("name".to_string(), serde_json::Value::String(s.to_string()));
                        inner.insert("params".to_string(), serde_json::Value::Array(Vec::new()));
                        dec.insert(
                            "params".to_string(),
                            serde_json::Value::Array(vec![serde_json::Value::Object(inner)]),
                        );
                        serde_json::Value::Object(dec)
                    }
                    None => self.type_ir(&serde_json::Value::String("Decimal".to_string())),
                };
            }
            "stdlib.numeric.add" => {
                is_resolved = true;
                if !typed_args.is_empty() {
                    resolved_type = typed_args[0].resolved_type.clone();
                } else {
                    resolved_type = self.type_ir(&serde_json::Value::String("Integer".to_string()));
                }
            }
            // LAB-STDLIB-MATH-TRANSCENDENTALS-P2: Tier-1 Float transcendentals (fast f64 path).
            // LAB-STDLIB-MATH-DET-TIER1-P5: `det_*` = the DETERMINISTIC surface — identical signature
            // ((Float)->Float, OOF-MATH1/2), distinguished at runtime (VM) by the reproducible algorithm.
            // sin/cos/sqrt : (Float) -> Float ; no implicit Integer/Decimal coercion (P2 bias).
            // OOF-MATH1 = arity; OOF-MATH2 = non-Float argument. Float returned on all paths.
            "stdlib.math.sin"
            | "sin"
            | "stdlib.math.cos"
            | "cos"
            | "stdlib.math.sqrt"
            | "sqrt"
            | "stdlib.math.det_sin"
            | "det_sin"
            | "stdlib.math.det_cos"
            | "det_cos"
            | "stdlib.math.det_sqrt"
            | "det_sqrt"
            | "stdlib.math.det_ln"
            | "det_ln"
            | "stdlib.math.det_exp"
            | "det_exp"
            | "stdlib.math.det_tan"
            | "det_tan" => {
                is_resolved = true;
                resolved_type = self.type_ir(&serde_json::Value::String("Float".to_string()));
                if args.len() != 1 {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-MATH1".to_string(),
                        message: format!("{}: expected 1 argument, got {}", fn_name, args.len()),
                        node: node_name.to_string(),
                        line: None,
                    });
                } else if !typed_args.is_empty() {
                    let arg_name = self.type_name(&typed_args[0].resolved_type);
                    if arg_name != "Float" && arg_name != "Unknown" {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-MATH2".to_string(),
                            message: format!(
                                "{}: argument must be Float, got {}",
                                fn_name, arg_name
                            ),
                            node: node_name.to_string(),
                            line: None,
                        });
                    }
                }
            }
            // pi() -> Float : zero-arg constant surface.
            "stdlib.math.pi" | "pi" => {
                is_resolved = true;
                resolved_type = self.type_ir(&serde_json::Value::String("Float".to_string()));
                if !args.is_empty() {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-MATH1".to_string(),
                        message: format!("pi: expected 0 arguments, got {}", args.len()),
                        node: node_name.to_string(),
                        line: None,
                    });
                }
            }
            // LAB-STDLIB-NUMERIC-TO-FLOAT-P8: the explicit Integer→Float boundary (NO implicit coercion;
            // `+ - * / min/max/clamp` stay same-type). to_float : (Integer)->Float. OOF-MATH1 arity,
            // OOF-MATH2 non-Integer. Unblocks `sum / to_float(count)`-style normalization.
            "stdlib.math.to_float" | "to_float" => {
                is_resolved = true;
                resolved_type = self.type_ir(&serde_json::Value::String("Float".to_string()));
                if args.len() != 1 {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-MATH1".to_string(),
                        message: format!("to_float: expected 1 argument, got {}", args.len()),
                        node: node_name.to_string(),
                        line: None,
                    });
                } else if let Some(first) = typed_args.first() {
                    let arg_name = self.type_name(&first.resolved_type);
                    if arg_name != "Integer" && arg_name != "Unknown" {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-MATH2".to_string(),
                            message: format!(
                                "to_float: argument must be Integer, got {}",
                                arg_name
                            ),
                            node: node_name.to_string(),
                            line: None,
                        });
                    }
                }
            }
            // LAB-LANG-NUMBER-TO-TEXT-P1 + LAB-LANG-DECIMAL-TO-TEXT-P2: the exact number→text surface —
            // to_text : (Integer | Decimal)->String. Mirrors the `char_at`/string builtins (OOF-TY0, String on
            // every path incl. errors). NO implicit coercion, NO formatting/locale/rounding; **Float HELD**
            // (a Float — or any other non-Integer/non-Decimal — arg is OOF-TY0). A bare `Decimal` value names
            // `"Decimal"` (scale lives in params), the same convention the Decimal `+`/`-` arm relies on.
            "stdlib.string.to_text" | "to_text" => {
                is_resolved = true;
                resolved_type = self.type_ir(&serde_json::Value::String("String".to_string()));
                if args.len() != 1 {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-TY0".to_string(),
                        message: format!("to_text: expected 1 argument, got {}", args.len()),
                        node: node_name.to_string(),
                        line: None,
                    });
                } else if let Some(first) = typed_args.first() {
                    let arg_name = self.type_name(&first.resolved_type);
                    if arg_name != "Integer" && arg_name != "Decimal" && arg_name != "Unknown" {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-TY0".to_string(),
                            message: format!(
                                "to_text: argument must be Integer or Decimal, got {}",
                                arg_name
                            ),
                            node: node_name.to_string(),
                            line: None,
                        });
                    }
                }
            }
            // LAB-LANG-FLOAT-TO-TEXT-IMPL-P7: explicit fixed-point Float→String.
            //   float_to_text(Float, Integer, String) -> String  (mode `"half_even"` only in v0).
            // OOF-TY0 on arity / wrong arg types AND on a LITERAL unsupported rounding mode (the §2 message);
            // a dynamic mode is rejected at runtime (VM). NOT implicit `to_text(Float)` — this is explicit.
            "float_to_text" | "stdlib.string.float_to_text" => {
                is_resolved = true;
                resolved_type = self.type_ir(&serde_json::Value::String("String".to_string()));
                if args.len() != 3 {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-TY0".to_string(),
                        message: format!(
                            "float_to_text: expected 3 argument(s), got {}",
                            args.len()
                        ),
                        node: node_name.to_string(),
                        line: None,
                    });
                } else {
                    for (i, want) in [(0usize, "Float"), (1, "Integer"), (2, "String")] {
                        if let Some(a) = typed_args.get(i) {
                            let n = self.type_name(&a.resolved_type);
                            if n != "Unknown" && n != want {
                                type_errors.push(ClassifierDiagnostic {
                                    rule: "OOF-TY0".to_string(),
                                    message: format!(
                                        "float_to_text arg {}: expected {}, got {}",
                                        i + 1,
                                        want,
                                        n
                                    ),
                                    node: node_name.to_string(),
                                    line: None,
                                });
                            }
                        }
                    }
                    // Literal rounding-mode rejection (knowable at compile time → fail early).
                    if let Expr::Literal { value, type_tag } = &args[2] {
                        if type_tag == "String" {
                            if let Some(m) = value.as_str() {
                                if m != "half_even" {
                                    type_errors.push(ClassifierDiagnostic {
                                        rule: "OOF-TY0".to_string(),
                                        message: format!(
                                            "float_to_text: unsupported rounding mode \"{m}\"; v0 supports only \"half_even\""
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
            // LAB-STDLIB-MATH-INTEGER-ROOTS-AND-MOD-P8: N1 integer-only roots/powers/modulo. Integer args,
            // Integer result. OOF-MATH1 arity, OOF-MATH2 non-Integer. Domain errors are runtime (VM), not here.
            "stdlib.math.isqrt" | "isqrt" | "stdlib.math.ipow" | "ipow" | "stdlib.math.mod"
            | "mod" => {
                is_resolved = true;
                let base = fn_name.rsplit('.').next().unwrap_or(fn_name);
                let want = if base == "isqrt" { 1 } else { 2 };
                resolved_type = self.type_ir(&serde_json::Value::String("Integer".to_string()));
                if args.len() != want {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-MATH1".to_string(),
                        message: format!(
                            "{}: expected {} argument(s), got {}",
                            base,
                            want,
                            args.len()
                        ),
                        node: node_name.to_string(),
                        line: None,
                    });
                }
                for t in typed_args.iter() {
                    let n = self.type_name(&t.resolved_type);
                    if n != "Integer" && n != "Unknown" {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-MATH2".to_string(),
                            message: format!("{}: argument must be Integer, got {}", base, n),
                            node: node_name.to_string(),
                            line: None,
                        });
                    }
                }
            }
            // LAB-STDLIB-MATH-NUMERIC-BASICS-P7: N0 basics — polymorphic over {Integer, Float}, same-type-in/out
            // (no implicit coercion; Decimal deferred). `abs/min/max/clamp` return the input type T;
            // `sign` -> Integer. OOF-MATH1 arity, OOF-MATH2 non-numeric (incl. deferred Decimal), OOF-MATH3 mixed.
            "stdlib.math.abs" | "abs" | "stdlib.math.sign" | "sign" | "stdlib.math.min"
            | "stdlib.math.max" | "stdlib.math.clamp" | "clamp" | "min" | "max"
                if !is_legacy_minmax_aggregate =>
            {
                is_resolved = true;
                let base = fn_name.rsplit('.').next().unwrap_or(fn_name);
                let want = match base {
                    "abs" | "sign" => 1,
                    "min" | "max" => 2,
                    _ => 3, // clamp
                };
                // Return type: `sign` is always Integer; the others mirror the first argument's type.
                resolved_type = if base == "sign" {
                    self.type_ir(&serde_json::Value::String("Integer".to_string()))
                } else if let Some(first) = typed_args.first() {
                    first.resolved_type.clone()
                } else {
                    self.type_ir(&serde_json::Value::String("Float".to_string()))
                };
                if args.len() != want {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-MATH1".to_string(),
                        message: format!(
                            "{}: expected {} argument(s), got {}",
                            base,
                            want,
                            args.len()
                        ),
                        node: node_name.to_string(),
                        line: None,
                    });
                }
                let names: Vec<String> = typed_args
                    .iter()
                    .map(|t| self.type_name(&t.resolved_type))
                    .collect();
                let is_num = |n: &str| n == "Integer" || n == "Float" || n == "Unknown";
                if let Some(bad) = names.iter().find(|n| !is_num(n)) {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-MATH2".to_string(),
                        message: format!(
                            "{}: argument must be Integer or Float (Decimal support deferred), got {}",
                            base, bad
                        ),
                        node: node_name.to_string(),
                        line: None,
                    });
                } else {
                    // Same-type required among the known (non-Unknown) arguments — no implicit coercion.
                    let known: Vec<&String> =
                        names.iter().filter(|n| n.as_str() != "Unknown").collect();
                    if known.windows(2).any(|w| w[0] != w[1]) {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-MATH3".to_string(),
                            message: format!(
                                "{}: mixed numeric types {:?} (no implicit coercion)",
                                base, known
                            ),
                            node: node_name.to_string(),
                            line: None,
                        });
                    }
                }
            }
            // LAB-STDLIB-RANDOM-PRNG-WITHOUT-BITOPS-P2: pure deterministic PRNG (native SplitMix64), explicit
            // state threading, scalar surface (no record returns, no language bitops). `Rng` state is a plain
            // Integer (opaque). rng_seed/rng_next/rng_value : (Integer)->Integer ; rng_uniform01 :
            // (Integer)->Float. P3 adds deterministic distribution helpers that sample from an explicit
            // state. OOF-RAND1 = arity, OOF-RAND2 = non-Integer argument. No ambient/crypto/entropy.
            "stdlib.random.rng_seed"
            | "rng_seed"
            | "stdlib.random.rng_next"
            | "rng_next"
            | "stdlib.random.rng_value"
            | "rng_value"
            | "stdlib.random.rng_uniform01"
            | "rng_uniform01"
            | "stdlib.random.rng_uniform_int"
            | "rng_uniform_int"
            | "stdlib.random.rng_bernoulli_per_million"
            | "rng_bernoulli_per_million" => {
                is_resolved = true;
                let base = fn_name.rsplit('.').next().unwrap_or(fn_name);
                let (expected_args, ret) = match base {
                    "rng_uniform01" => (1, "Float"),
                    "rng_uniform_int" => (3, "Integer"),
                    "rng_bernoulli_per_million" => (2, "Bool"),
                    _ => (1, "Integer"),
                };
                resolved_type = self.type_ir(&serde_json::Value::String(ret.to_string()));
                if args.len() != expected_args {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-RAND1".to_string(),
                        message: format!(
                            "{}: expected {} argument(s), got {}",
                            base,
                            expected_args,
                            args.len()
                        ),
                        node: node_name.to_string(),
                        line: None,
                    });
                } else {
                    for typed in typed_args {
                        let arg_name = self.type_name(&typed.resolved_type);
                        if arg_name != "Integer" && arg_name != "Unknown" {
                            type_errors.push(ClassifierDiagnostic {
                                rule: "OOF-RAND2".to_string(),
                                message: format!(
                                    "{}: arguments must be Integer, got {}",
                                    base, arg_name
                                ),
                                node: node_name.to_string(),
                                line: None,
                            });
                            break;
                        }
                    }
                }
            }
            "stdlib.option.wrap" => {
                is_resolved = true;
                let mut opt = serde_json::Map::new();
                opt.insert(
                    "name".to_string(),
                    serde_json::Value::String("Option".to_string()),
                );
                let inner_ty = if !typed_args.is_empty() {
                    typed_args[0].resolved_type.clone()
                } else {
                    self.type_ir(&serde_json::Value::String("Integer".to_string()))
                };
                opt.insert(
                    "params".to_string(),
                    serde_json::Value::Array(vec![inner_ty]),
                );
                resolved_type = serde_json::Value::Object(opt);
            }
            "count" => {
                is_resolved = true;
                resolved_type = self.type_ir(&serde_json::Value::String("Integer".to_string()));
                // LANG-STDLIB-COLLECTION-MAP-FILTER-PROP-P5: OOF-COL1 arity; OOF-COL2 non-Collection.
                if args.len() != 1 {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-COL1".to_string(),
                        message: format!(
                            "stdlib.collection.count: expected 1 argument, got {}",
                            args.len()
                        ),
                        node: node_name.to_string(),
                        line: None,
                    });
                } else if !typed_args.is_empty() {
                    let col_arg_name = self.type_name(&typed_args[0].resolved_type);
                    if col_arg_name != "Collection" && col_arg_name != "Unknown" {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-COL2".to_string(),
                            message: format!(
                                "stdlib.collection.count: first argument must be Collection[T], got {}",
                                col_arg_name
                            ),
                            node: node_name.to_string(),
                            line: None,
                        });
                    }
                }
            }
            // LANG-STDLIB-IS-EMPTY-PROP-P4: Rust parity for is_empty + non_empty.
            // is_empty(Collection[T]) -> Bool  — true iff zero elements
            // non_empty(Collection[T]) -> Bool — true iff one or more elements
            // OOF-COL1: arity != 1; OOF-COL2: non-Collection / non-Unknown first arg.
            // Bool returned on ALL paths including error paths (no Unknown propagation).
            "is_empty" | "non_empty" => {
                is_resolved = true;
                resolved_type = self.type_ir(&serde_json::Value::String("Bool".to_string()));
                if args.len() != 1 {
                    let qualified = if fn_name == "is_empty" {
                        "stdlib.collection.is_empty"
                    } else {
                        "stdlib.collection.non_empty"
                    };
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-COL1".to_string(),
                        message: format!(
                            "{}: expected 1 argument (collection), got {}",
                            qualified,
                            args.len()
                        ),
                        node: node_name.to_string(),
                        line: None,
                    });
                } else if !typed_args.is_empty() {
                    let col_arg_name = self.type_name(&typed_args[0].resolved_type);
                    if col_arg_name != "Collection" && col_arg_name != "Unknown" {
                        let qualified = if fn_name == "is_empty" {
                            "stdlib.collection.is_empty"
                        } else {
                            "stdlib.collection.non_empty"
                        };
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-COL2".to_string(),
                            message: format!(
                                "{}: first argument must be Collection[T], got {}",
                                qualified, col_arg_name
                            ),
                            node: node_name.to_string(),
                            line: None,
                        });
                    }
                }
            }
            // LANG-STDLIB-STRING-SURFACE-P3: char_at(String, Integer) -> String
            // OOF-TY0 for arity != 2, arg1 not String/Unknown, arg2 not Integer/Unknown.
            // String returned on ALL paths including OOF error paths.
            "char_at" => {
                is_resolved = true;
                resolved_type = self.type_ir(&serde_json::Value::String("String".to_string()));
                if args.len() != 2 {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-TY0".to_string(),
                        message: format!(
                            "stdlib.string.char_at: expected 2 argument(s), got {}",
                            args.len()
                        ),
                        node: node_name.to_string(),
                        line: None,
                    });
                } else {
                    if !typed_args.is_empty() {
                        let source_name = self.type_name(&typed_args[0].resolved_type);
                        if source_name != "Unknown" && source_name != "String" {
                            type_errors.push(ClassifierDiagnostic {
                                rule: "OOF-TY0".to_string(),
                                message: format!(
                                    "stdlib.string.char_at arg 1: expected String, got {}",
                                    source_name
                                ),
                                node: node_name.to_string(),
                                line: None,
                            });
                        }
                    }
                    if typed_args.len() >= 2 {
                        let index_name = self.type_name(&typed_args[1].resolved_type);
                        if index_name != "Unknown" && index_name != "Integer" {
                            type_errors.push(ClassifierDiagnostic {
                                rule: "OOF-TY0".to_string(),
                                message: format!(
                                    "stdlib.string.char_at arg 2: expected Integer, got {}",
                                    index_name
                                ),
                                node: node_name.to_string(),
                                line: None,
                            });
                        }
                    }
                }
            }
            // LANG-STDLIB-STRING-SUBSTRING-P2: substring(String, Integer, Integer) -> String
            // (source, start, length) — byte-based, 0-based. OOF-TY0 only.
            "substring" => {
                is_resolved = true;
                resolved_type = self.type_ir(&serde_json::Value::String("String".to_string()));
                if args.len() != 3 {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-TY0".to_string(),
                        message: format!(
                            "stdlib.string.substring: expected 3 argument(s), got {}",
                            args.len()
                        ),
                        node: node_name.to_string(),
                        line: None,
                    });
                } else {
                    if !typed_args.is_empty() {
                        let source_name = self.type_name(&typed_args[0].resolved_type);
                        if source_name != "Unknown" && source_name != "String" {
                            type_errors.push(ClassifierDiagnostic {
                                rule: "OOF-TY0".to_string(),
                                message: format!(
                                    "stdlib.string.substring arg 1: expected String, got {}",
                                    source_name
                                ),
                                node: node_name.to_string(),
                                line: None,
                            });
                        }
                    }
                    if typed_args.len() >= 2 {
                        let start_name = self.type_name(&typed_args[1].resolved_type);
                        if start_name != "Unknown" && start_name != "Integer" {
                            type_errors.push(ClassifierDiagnostic {
                                rule: "OOF-TY0".to_string(),
                                message: format!(
                                    "stdlib.string.substring arg 2: expected Integer, got {}",
                                    start_name
                                ),
                                node: node_name.to_string(),
                                line: None,
                            });
                        }
                    }
                    if typed_args.len() >= 3 {
                        let length_name = self.type_name(&typed_args[2].resolved_type);
                        if length_name != "Unknown" && length_name != "Integer" {
                            type_errors.push(ClassifierDiagnostic {
                                rule: "OOF-TY0".to_string(),
                                message: format!(
                                    "stdlib.string.substring arg 3: expected Integer, got {}",
                                    length_name
                                ),
                                node: node_name.to_string(),
                                line: None,
                            });
                        }
                    }
                }
            }
            // LAB-LANG-STRING-PAD-LEFT-P3: pad_left(String, Integer, String) -> String — a table-column
            // primitive (rune-counted width). OOF-TY0 on arity / wrong arg types, String on every path. NOT a
            // formatter: numeric padding composes as `pad_left(to_text(x), width, "0")`.
            "pad_left" | "stdlib.string.pad_left" => {
                is_resolved = true;
                resolved_type = self.type_ir(&serde_json::Value::String("String".to_string()));
                if args.len() != 3 {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-TY0".to_string(),
                        message: format!(
                            "stdlib.string.pad_left: expected 3 argument(s), got {}",
                            args.len()
                        ),
                        node: node_name.to_string(),
                        line: None,
                    });
                } else {
                    for (i, want) in [(0usize, "String"), (1, "Integer"), (2, "String")] {
                        if let Some(a) = typed_args.get(i) {
                            let n = self.type_name(&a.resolved_type);
                            if n != "Unknown" && n != want {
                                type_errors.push(ClassifierDiagnostic {
                                    rule: "OOF-TY0".to_string(),
                                    message: format!(
                                        "stdlib.string.pad_left arg {}: expected {}, got {}",
                                        i + 1,
                                        want,
                                        n
                                    ),
                                    node: node_name.to_string(),
                                    line: None,
                                });
                            }
                        }
                    }
                }
            }
            "first" | "last" => {
                is_resolved = true;
                let mut inner_ty = serde_json::Value::Null;
                if !typed_args.is_empty() {
                    if let Some(param) = self.get_param(&typed_args[0].resolved_type, 0) {
                        inner_ty = param;
                    }
                }
                if inner_ty.is_null()
                    || (inner_ty.is_object() && inner_ty.as_object().unwrap().is_empty())
                {
                    let mut default_ty = serde_json::Map::new();
                    default_ty.insert(
                        "name".to_string(),
                        serde_json::Value::String("Unknown".to_string()),
                    );
                    default_ty.insert("params".to_string(), serde_json::Value::Array(Vec::new()));
                    inner_ty = serde_json::Value::Object(default_ty);
                }
                let mut opt = serde_json::Map::new();
                opt.insert(
                    "name".to_string(),
                    serde_json::Value::String("Option".to_string()),
                );
                opt.insert(
                    "params".to_string(),
                    serde_json::Value::Array(vec![inner_ty]),
                );
                resolved_type = serde_json::Value::Object(opt);
            }
            "sum" => {
                is_resolved = true;
                if args.len() == 1 {
                    // LANG-STDLIB-COLLECTION-SUM-SCALAR-P2: scalar sum(Collection[T]) -> T
                    // (T must be Numeric). Returns the element type EXACTLY — not bare
                    // `Decimal` — so Decimal scale is preserved. OOF-COL8 on a non-numeric element.
                    let elem = self
                        .get_param(&typed_args[0].resolved_type, 0)
                        .unwrap_or_else(|| {
                            self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                        });
                    let elem_name = self.type_name(&elem);
                    if matches!(
                        elem_name.as_str(),
                        "Integer" | "Float" | "Decimal" | "Unknown"
                    ) {
                        resolved_type = elem;
                    } else {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-COL8".to_string(),
                            message: format!(
                                "stdlib.collection.sum: scalar sum element type must be Numeric (Integer, Float, Decimal[N]), got {}",
                                elem_name
                            ),
                            node: node_name.to_string(),
                            line: None,
                        });
                        resolved_type =
                            self.type_ir(&serde_json::Value::String("Unknown".to_string()));
                    }
                } else {
                    // 2-arg field projection: sum(Collection[T], :field) -> F (existing).
                    let mut resolved =
                        self.type_ir(&serde_json::Value::String("Decimal".to_string()));
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
            }
            "zip" => {
                is_resolved = true;
                let mut inner_a = serde_json::Map::new();
                inner_a.insert(
                    "name".to_string(),
                    serde_json::Value::String("Unknown".to_string()),
                );
                inner_a.insert("params".to_string(), serde_json::Value::Array(Vec::new()));
                let mut inner_b = serde_json::Map::new();
                inner_b.insert(
                    "name".to_string(),
                    serde_json::Value::String("Unknown".to_string()),
                );
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
                pair.insert(
                    "name".to_string(),
                    serde_json::Value::String("Pair".to_string()),
                );
                pair.insert(
                    "params".to_string(),
                    serde_json::Value::Array(vec![
                        serde_json::Value::Object(inner_a),
                        serde_json::Value::Object(inner_b),
                    ]),
                );

                let mut col = serde_json::Map::new();
                col.insert(
                    "name".to_string(),
                    serde_json::Value::String("Collection".to_string()),
                );
                col.insert(
                    "params".to_string(),
                    serde_json::Value::Array(vec![serde_json::Value::Object(pair)]),
                );
                resolved_type = serde_json::Value::Object(col);
            }
            "unwrap_or" | "or_else" => {
                is_resolved = true;
                if typed_args.len() >= 2 {
                    // LAB-MAP-RUST-P1: proper or_else — extract V from Option[V] params[0]
                    // or_else(Option[V], default) → V; fallback to default's type for non-Option
                    let first_name = self.type_name(&typed_args[0].resolved_type);
                    resolved_type = if first_name == "Option" || first_name == "Result" {
                        self.get_param(&typed_args[0].resolved_type, 0)
                            .unwrap_or_else(|| typed_args[1].resolved_type.clone())
                    } else {
                        typed_args[1].resolved_type.clone()
                    };
                } else {
                    resolved_type = self.type_ir(&serde_json::Value::String("Unknown".to_string()));
                }
            }
            "range" => {
                // LANG-STDLIB-COLLECTION-RANGE-P3: range(start, stop) -> Collection[Integer]
                // OOF-COL1 on arity != 2 (parity with Ruby TC P2).
                is_resolved = true;
                let mut col = serde_json::Map::new();
                col.insert(
                    "name".to_string(),
                    serde_json::Value::String("Collection".to_string()),
                );
                let mut inner_ty = serde_json::Map::new();
                inner_ty.insert(
                    "name".to_string(),
                    serde_json::Value::String("Integer".to_string()),
                );
                inner_ty.insert("params".to_string(), serde_json::Value::Array(Vec::new()));
                col.insert(
                    "params".to_string(),
                    serde_json::Value::Array(vec![serde_json::Value::Object(inner_ty)]),
                );
                resolved_type = serde_json::Value::Object(col);
                if args.len() != 2 {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-COL1".to_string(),
                        message: format!(
                            "stdlib.collection.range: expected 2 arguments (start, stop), got {}",
                            args.len()
                        ),
                        node: node_name.to_string(),
                        line: None,
                    });
                }
            }
            "filter" | "take" => {
                is_resolved = true;
                if !typed_args.is_empty() {
                    resolved_type = typed_args[0].resolved_type.clone();
                } else {
                    resolved_type =
                        self.type_ir(&serde_json::Value::String("Collection".to_string()));
                }
                // LANG-STDLIB-COLLECTION-MAP-FILTER-PROP-P4: bind lambda parameter to
                // Collection element type T; validate predicate returns Bool (OOF-COL3).
                // LANG-STDLIB-COLLECTION-MAP-FILTER-PROP-P5: OOF-COL1/COL2 for filter only.
                let col_type_name = self.type_name(&resolved_type);
                if fn_name == "filter" {
                    if args.len() != 2 {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-COL1".to_string(),
                            message: format!(
                                "stdlib.collection.filter: expected 2 arguments, got {}",
                                args.len()
                            ),
                            node: node_name.to_string(),
                            line: None,
                        });
                    } else if !typed_args.is_empty() {
                        let filter_arg0_name = self.type_name(&typed_args[0].resolved_type);
                        if filter_arg0_name != "Collection" && filter_arg0_name != "Unknown" {
                            type_errors.push(ClassifierDiagnostic {
                                rule: "OOF-COL2".to_string(),
                                message: format!(
                                    "stdlib.collection.filter: first argument must be Collection[T], got {}",
                                    filter_arg0_name
                                ),
                                node: node_name.to_string(),
                                line: None,
                            });
                        }
                    }
                }
                if args.len() >= 2 {
                    if let Expr::Lambda { params, body } = &args[1] {
                        let elem_ty = if col_type_name == "Collection" {
                            self.get_param(&resolved_type, 0).unwrap_or_else(|| {
                                self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                            })
                        } else {
                            self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                        };
                        let mut local_symbols = symbol_types.clone();
                        for p in params {
                            local_symbols.insert(p.clone(), elem_ty.clone());
                        }
                        // LAB-HOF-LAMBDA-ERROR-PROPAGATION-P2: propagate filter lambda
                        // body errors to type_errors (parity with Ruby TC line 2547).
                        let body_type = match body.as_ref() {
                            ExprOrBlock::Expr(e) => {
                                self.infer_expr(
                                    e,
                                    &local_symbols,
                                    olap_env,
                                    type_shapes,
                                    type_errors,
                                    type_warnings,
                                    node_name,
                                    functions,
                                    contract_registry,
                                    current_contract_name,
                                )
                                .resolved_type
                            }
                            ExprOrBlock::Block(block) => {
                                let mut last_type =
                                    self.type_ir(&serde_json::Value::String("Unknown".to_string()));
                                let mut local_syms = local_symbols.clone();
                                for stmt in &block.stmts {
                                    match stmt {
                                        Stmt::Let { name, expr } => {
                                            let t = self.infer_expr(
                                                expr,
                                                &local_syms,
                                                olap_env,
                                                type_shapes,
                                                type_errors,
                                                type_warnings,
                                                node_name,
                                                functions,
                                                contract_registry,
                                                current_contract_name,
                                            );
                                            local_syms
                                                .insert(name.clone(), t.resolved_type.clone());
                                            last_type = t.resolved_type;
                                        }
                                        Stmt::ExprStmt { expr } => {
                                            let t = self.infer_expr(
                                                expr,
                                                &local_syms,
                                                olap_env,
                                                type_shapes,
                                                type_errors,
                                                type_warnings,
                                                node_name,
                                                functions,
                                                contract_registry,
                                                current_contract_name,
                                            );
                                            last_type = t.resolved_type;
                                        }
                                    }
                                }
                                if let Some(re) = &block.return_expr {
                                    last_type = self
                                        .infer_expr(
                                            re,
                                            &local_syms,
                                            olap_env,
                                            type_shapes,
                                            type_errors,
                                            type_warnings,
                                            node_name,
                                            functions,
                                            contract_registry,
                                            current_contract_name,
                                        )
                                        .resolved_type;
                                }
                                last_type
                            }
                        };
                        let pred_name = self.type_name(&body_type);
                        if pred_name != "Bool" && pred_name != "Unknown" {
                            type_errors.push(ClassifierDiagnostic {
                                rule: "OOF-COL3".to_string(),
                                message: format!(
                                    "stdlib.collection.filter: predicate must return Bool, got {}",
                                    pred_name
                                ),
                                node: node_name.to_string(),
                                line: None,
                            });
                        }
                    }
                }
            }
            "filter_map" => {
                is_resolved = true;
                // LANG-SUMTYPE-COLLECT-P3: filter_map(Collection[T], (T -> Option[U])) -> Collection[U].
                // Keeps each Some(u) payload, drops every None. Mirrors `map`: OOF-COL1 arity,
                // OOF-COL2 non-Collection first arg, OOF-COL3 callback must return Option. U is
                // preferred from the callback's concrete Option param; when a parametric `match`
                // callback collapses to bare Option (COLLECT-P1 sub-gap), U falls back to the
                // Collection[U] output context (collection_elem_hints, route B2). The expected
                // Option[U] is temp-installed as a sealed hint while inferring the callback body
                // so none()/some() resolve against U.
                if args.len() != 2 {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-COL1".to_string(),
                        message: format!(
                            "stdlib.collection.filter_map: expected 2 arguments, got {}",
                            args.len()
                        ),
                        node: node_name.to_string(),
                        line: None,
                    });
                } else if !typed_args.is_empty() {
                    let arg0_name = self.type_name(&typed_args[0].resolved_type);
                    if arg0_name != "Collection" && arg0_name != "Unknown" {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-COL2".to_string(),
                            message: format!(
                                "stdlib.collection.filter_map: first argument must be Collection[T], got {}",
                                arg0_name
                            ),
                            node: node_name.to_string(),
                            line: None,
                        });
                    }
                }
                let first_arg_type = if !typed_args.is_empty() {
                    typed_args[0].resolved_type.clone()
                } else {
                    self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                };
                let first_arg_name = self.type_name(&first_arg_type);

                // Route B2: element-type hint U from the Collection[U] output context.
                let ctx_u = self.collection_elem_hints.borrow().get(node_name).cloned();

                let mut lambda_return_type =
                    self.type_ir(&serde_json::Value::String("Unknown".to_string()));
                if args.len() >= 2 {
                    if let Expr::Lambda { params, body } = &args[1] {
                        let mut local_symbols = symbol_types.clone();
                        let elem_ty = if first_arg_name == "Collection" {
                            self.get_param(&first_arg_type, 0).unwrap_or_else(|| {
                                self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                            })
                        } else {
                            self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                        };
                        for p in params {
                            local_symbols.insert(p.clone(), elem_ty.clone());
                        }
                        // Temp-install Option[U] sealed hint so none()/some() resolve vs U.
                        let prev_hint = self.sealed_output_hints.borrow().get(node_name).cloned();
                        if let Some(u) = &ctx_u {
                            if self.type_name(u) != "Unknown" {
                                let mut opt = serde_json::Map::new();
                                opt.insert(
                                    "name".to_string(),
                                    serde_json::Value::String("Option".to_string()),
                                );
                                opt.insert(
                                    "params".to_string(),
                                    serde_json::Value::Array(vec![u.clone()]),
                                );
                                self.sealed_output_hints
                                    .borrow_mut()
                                    .insert(node_name.to_string(), serde_json::Value::Object(opt));
                            }
                        }
                        lambda_return_type = match body.as_ref() {
                            ExprOrBlock::Expr(e) => {
                                self.infer_expr(
                                    e,
                                    &local_symbols,
                                    olap_env,
                                    type_shapes,
                                    type_errors,
                                    type_warnings,
                                    node_name,
                                    functions,
                                    contract_registry,
                                    current_contract_name,
                                )
                                .resolved_type
                            }
                            ExprOrBlock::Block(block) => {
                                let mut last_type =
                                    self.type_ir(&serde_json::Value::String("Unknown".to_string()));
                                let mut local_syms = local_symbols.clone();
                                for stmt in &block.stmts {
                                    match stmt {
                                        Stmt::Let { name, expr } => {
                                            let t = self.infer_expr(
                                                expr,
                                                &local_syms,
                                                olap_env,
                                                type_shapes,
                                                type_errors,
                                                type_warnings,
                                                node_name,
                                                functions,
                                                contract_registry,
                                                current_contract_name,
                                            );
                                            local_syms
                                                .insert(name.clone(), t.resolved_type.clone());
                                            last_type = t.resolved_type;
                                        }
                                        Stmt::ExprStmt { expr } => {
                                            last_type = self
                                                .infer_expr(
                                                    expr,
                                                    &local_syms,
                                                    olap_env,
                                                    type_shapes,
                                                    type_errors,
                                                    type_warnings,
                                                    node_name,
                                                    functions,
                                                    contract_registry,
                                                    current_contract_name,
                                                )
                                                .resolved_type;
                                        }
                                    }
                                }
                                if let Some(re) = &block.return_expr {
                                    last_type = self
                                        .infer_expr(
                                            re,
                                            &local_syms,
                                            olap_env,
                                            type_shapes,
                                            type_errors,
                                            type_warnings,
                                            node_name,
                                            functions,
                                            contract_registry,
                                            current_contract_name,
                                        )
                                        .resolved_type;
                                }
                                last_type
                            }
                        };
                        // Restore the prior sealed hint.
                        match prev_hint {
                            Some(p) => {
                                self.sealed_output_hints
                                    .borrow_mut()
                                    .insert(node_name.to_string(), p);
                            }
                            None => {
                                self.sealed_output_hints.borrow_mut().remove(node_name);
                            }
                        }
                    }
                }

                // OOF-COL3: callback must return Option[U].
                let ret_name = self.type_name(&lambda_return_type);
                if ret_name != "Option" && ret_name != "Unknown" {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-COL3".to_string(),
                        message: format!(
                            "stdlib.collection.filter_map: callback must return Option[U], got {}",
                            ret_name
                        ),
                        node: node_name.to_string(),
                        line: None,
                    });
                }

                // U: callback's concrete Option param, else output context, else Unknown.
                let u_type = self
                    .get_param(&lambda_return_type, 0)
                    .filter(|t| self.type_name(t) != "Unknown")
                    .or_else(|| ctx_u.clone().filter(|t| self.type_name(t) != "Unknown"))
                    .unwrap_or_else(|| {
                        self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                    });

                let mut col = serde_json::Map::new();
                col.insert(
                    "name".to_string(),
                    serde_json::Value::String("Collection".to_string()),
                );
                col.insert("params".to_string(), serde_json::Value::Array(vec![u_type]));
                resolved_type = serde_json::Value::Object(col);
            }
            "map" => {
                is_resolved = true;
                // LANG-STDLIB-COLLECTION-MAP-FILTER-PROP-P5: OOF-COL1 arity; OOF-COL2 non-Collection.
                if args.len() != 2 {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-COL1".to_string(),
                        message: format!(
                            "stdlib.collection.map: expected 2 arguments, got {}",
                            args.len()
                        ),
                        node: node_name.to_string(),
                        line: None,
                    });
                } else if !typed_args.is_empty() {
                    let map_arg0_name = self.type_name(&typed_args[0].resolved_type);
                    if map_arg0_name != "Collection" && map_arg0_name != "Unknown" {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-COL2".to_string(),
                            message: format!(
                                "stdlib.collection.map: first argument must be Collection[T], got {}",
                                map_arg0_name
                            ),
                            node: node_name.to_string(),
                            line: None,
                        });
                    }
                }
                let first_arg_type = if !typed_args.is_empty() {
                    typed_args[0].resolved_type.clone()
                } else {
                    self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                };
                let first_arg_name = self.type_name(&first_arg_type);

                let mut lambda_return_type =
                    self.type_ir(&serde_json::Value::String("Unknown".to_string()));
                if args.len() >= 2 {
                    if let Expr::Lambda { params, body } = &args[1] {
                        let mut local_symbols = symbol_types.clone();
                        // LANG-STDLIB-COLLECTION-MAP-FILTER-PROP-P4: bind lambda param
                        // to Collection element type T, not a hardcoded Integer placeholder.
                        let elem_ty = if first_arg_name == "Collection" {
                            self.get_param(&first_arg_type, 0).unwrap_or_else(|| {
                                self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                            })
                        } else {
                            self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                        };
                        for p in params {
                            local_symbols.insert(p.clone(), elem_ty.clone());
                        }
                        // LAB-HOF-LAMBDA-ERROR-PROPAGATION-P2: propagate map lambda
                        // body errors to type_errors (parity with Ruby TC line 2547).
                        lambda_return_type = match body.as_ref() {
                            ExprOrBlock::Expr(e) => {
                                let body_typed = self.infer_expr(
                                    e,
                                    &local_symbols,
                                    olap_env,
                                    type_shapes,
                                    type_errors,
                                    type_warnings,
                                    node_name,
                                    functions,
                                    contract_registry,
                                    current_contract_name,
                                );
                                body_typed.resolved_type
                            }
                            ExprOrBlock::Block(block) => {
                                let mut last_type =
                                    self.type_ir(&serde_json::Value::String("Unknown".to_string()));
                                for stmt in &block.stmts {
                                    match stmt {
                                        Stmt::Let { name, expr } => {
                                            local_symbols.insert(
                                                name.clone(),
                                                self.type_ir(&serde_json::Value::String(
                                                    "Unknown".to_string(),
                                                )),
                                            );
                                            let stmt_typed = self.infer_expr(
                                                expr,
                                                &local_symbols,
                                                olap_env,
                                                type_shapes,
                                                type_errors,
                                                type_warnings,
                                                node_name,
                                                functions,
                                                contract_registry,
                                                current_contract_name,
                                            );
                                            last_type = stmt_typed.resolved_type;
                                        }
                                        Stmt::ExprStmt { expr } => {
                                            let stmt_typed = self.infer_expr(
                                                expr,
                                                &local_symbols,
                                                olap_env,
                                                type_shapes,
                                                type_errors,
                                                type_warnings,
                                                node_name,
                                                functions,
                                                contract_registry,
                                                current_contract_name,
                                            );
                                            last_type = stmt_typed.resolved_type;
                                        }
                                    }
                                }
                                if let Some(re) = &block.return_expr {
                                    let re_typed = self.infer_expr(
                                        re,
                                        &local_symbols,
                                        olap_env,
                                        type_shapes,
                                        type_errors,
                                        type_warnings,
                                        node_name,
                                        functions,
                                        contract_registry,
                                        current_contract_name,
                                    );
                                    last_type = re_typed.resolved_type;
                                }
                                last_type
                            }
                        };
                    }
                }

                if first_arg_name == "Option" {
                    let mut opt = serde_json::Map::new();
                    opt.insert(
                        "name".to_string(),
                        serde_json::Value::String("Option".to_string()),
                    );
                    opt.insert(
                        "params".to_string(),
                        serde_json::Value::Array(vec![lambda_return_type]),
                    );
                    resolved_type = serde_json::Value::Object(opt);
                } else if first_arg_name == "Result" {
                    let err_type = self.get_param(&first_arg_type, 1).unwrap_or_else(|| {
                        self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                    });
                    let mut res = serde_json::Map::new();
                    res.insert(
                        "name".to_string(),
                        serde_json::Value::String("Result".to_string()),
                    );
                    res.insert(
                        "params".to_string(),
                        serde_json::Value::Array(vec![lambda_return_type, err_type]),
                    );
                    resolved_type = serde_json::Value::Object(res);
                } else {
                    let mut col = serde_json::Map::new();
                    col.insert(
                        "name".to_string(),
                        serde_json::Value::String("Collection".to_string()),
                    );
                    col.insert(
                        "params".to_string(),
                        serde_json::Value::Array(vec![lambda_return_type]),
                    );
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

                let mut lambda_return_type =
                    self.type_ir(&serde_json::Value::String("Unknown".to_string()));
                if args.len() >= 2 {
                    if let Expr::Lambda { params, body } = &args[1] {
                        let mut local_symbols = symbol_types.clone();
                        // LANG-SUMTYPE-CONSTRUCT-MATCH-P3: and_then binds the lambda param to
                        // T (the ok/inner type of the first arg), mirroring the Ruby canon.
                        // flat_map keeps its prior Integer placeholder (untouched).
                        for p in params {
                            let param_ty = if fn_name == "and_then" {
                                self.get_param(&first_arg_type, 0).unwrap_or_else(|| {
                                    self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                                })
                            } else {
                                self.type_ir(&serde_json::Value::String("Integer".to_string()))
                            };
                            local_symbols.insert(p.clone(), param_ty);
                        }
                        let mut temp_errors = Vec::new();
                        lambda_return_type = match body.as_ref() {
                            ExprOrBlock::Expr(e) => {
                                let body_typed = self.infer_expr(
                                    e,
                                    &local_symbols,
                                    olap_env,
                                    type_shapes,
                                    &mut temp_errors,
                                    type_warnings,
                                    node_name,
                                    functions,
                                    contract_registry,
                                    current_contract_name,
                                );
                                body_typed.resolved_type
                            }
                            ExprOrBlock::Block(block) => {
                                let mut last_type =
                                    self.type_ir(&serde_json::Value::String("Unknown".to_string()));
                                for stmt in &block.stmts {
                                    match stmt {
                                        Stmt::Let { name, expr } => {
                                            local_symbols.insert(
                                                name.clone(),
                                                self.type_ir(&serde_json::Value::String(
                                                    "Unknown".to_string(),
                                                )),
                                            );
                                            let stmt_typed = self.infer_expr(
                                                expr,
                                                &local_symbols,
                                                olap_env,
                                                type_shapes,
                                                &mut temp_errors,
                                                type_warnings,
                                                node_name,
                                                functions,
                                                contract_registry,
                                                current_contract_name,
                                            );
                                            last_type = stmt_typed.resolved_type;
                                        }
                                        Stmt::ExprStmt { expr } => {
                                            let stmt_typed = self.infer_expr(
                                                expr,
                                                &local_symbols,
                                                olap_env,
                                                type_shapes,
                                                &mut temp_errors,
                                                type_warnings,
                                                node_name,
                                                functions,
                                                contract_registry,
                                                current_contract_name,
                                            );
                                            last_type = stmt_typed.resolved_type;
                                        }
                                    }
                                }
                                if let Some(re) = &block.return_expr {
                                    let re_typed = self.infer_expr(
                                        re,
                                        &local_symbols,
                                        olap_env,
                                        type_shapes,
                                        &mut temp_errors,
                                        type_warnings,
                                        node_name,
                                        functions,
                                        contract_registry,
                                        current_contract_name,
                                    );
                                    last_type = re_typed.resolved_type;
                                }
                                last_type
                            }
                        };
                    }
                }

                let inner_u = self.get_param(&lambda_return_type, 0).unwrap_or_else(|| {
                    self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                });

                if first_arg_name == "Option" {
                    let mut opt = serde_json::Map::new();
                    opt.insert(
                        "name".to_string(),
                        serde_json::Value::String("Option".to_string()),
                    );
                    opt.insert(
                        "params".to_string(),
                        serde_json::Value::Array(vec![inner_u]),
                    );
                    resolved_type = serde_json::Value::Object(opt);
                } else if first_arg_name == "Result" {
                    // LANG-SUMTYPE-CONSTRUCT-MATCH-P3: and_then is fixed-error-family — the
                    // result keeps the input's E. flat_map keeps its prior preference for the
                    // lambda body's E.
                    let err_type = if fn_name == "and_then" {
                        self.get_param(&first_arg_type, 1).unwrap_or_else(|| {
                            self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                        })
                    } else {
                        self.get_param(&lambda_return_type, 1)
                            .or_else(|| self.get_param(&first_arg_type, 1))
                            .unwrap_or_else(|| {
                                self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                            })
                    };
                    let mut res = serde_json::Map::new();
                    res.insert(
                        "name".to_string(),
                        serde_json::Value::String("Result".to_string()),
                    );
                    res.insert(
                        "params".to_string(),
                        serde_json::Value::Array(vec![inner_u, err_type]),
                    );
                    resolved_type = serde_json::Value::Object(res);
                } else {
                    let mut col = serde_json::Map::new();
                    col.insert(
                        "name".to_string(),
                        serde_json::Value::String("Collection".to_string()),
                    );
                    col.insert(
                        "params".to_string(),
                        serde_json::Value::Array(vec![inner_u]),
                    );
                    resolved_type = serde_json::Value::Object(col);
                }
            }
            // LANG-SUMTYPE-CONSTRUCT-MATCH-P3: some/none/ok/err are intercepted before
            // the stdlib path (see infer_sealed_construct) and lowered to sealed
            // variant_construct nodes, so they no longer resolve here.
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
                    "length",
                    &typed_args,
                    &["Text"],
                    type_errors,
                    node_name,
                );
                resolved_type = self.type_ir(&serde_json::Value::String("Integer".to_string()));
            }
            "trim" => {
                is_resolved = true;
                resolved_type = self.check_text_stdlib_call(
                    "trim",
                    &typed_args,
                    &["Text"],
                    type_errors,
                    node_name,
                );
            }
            "concat" => {
                is_resolved = true;
                // Route on first arg type: Collection/Unknown → collection path; else text path.
                let first_name = if !typed_args.is_empty() {
                    self.type_name(&typed_args[0].resolved_type)
                } else {
                    "Unknown".to_string()
                };
                if first_name == "Collection" || first_name == "Unknown" {
                    // Collection concat — OOF-COL1/COL2/COL7 parity with Ruby P3
                    if typed_args.len() != 2 {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-COL1".to_string(),
                            message: format!(
                                "stdlib.collection.concat: expected 2 argument(s), got {}",
                                typed_args.len()
                            ),
                            node: node_name.to_string(),
                            line: None,
                        });
                        resolved_type =
                            self.type_ir(&serde_json::Value::String("Unknown".to_string()));
                    } else {
                        let second_name = self.type_name(&typed_args[1].resolved_type);
                        if second_name != "Collection" && second_name != "Unknown" {
                            type_errors.push(ClassifierDiagnostic {
                                rule: "OOF-COL2".to_string(),
                                message: format!(
                                    "stdlib.collection.concat: second argument must be a Collection, got {}",
                                    second_name
                                ),
                                node: node_name.to_string(),
                                line: None,
                            });
                            resolved_type =
                                self.type_ir(&serde_json::Value::String("Unknown".to_string()));
                        } else {
                            let elem1 = self.get_param(&typed_args[0].resolved_type, 0);
                            let elem2 = self.get_param(&typed_args[1].resolved_type, 0);
                            let elem1_name = elem1
                                .as_ref()
                                .map(|t| self.type_name(t))
                                .unwrap_or_else(|| "Unknown".to_string());
                            let elem2_name = elem2
                                .as_ref()
                                .map(|t| self.type_name(t))
                                .unwrap_or_else(|| "Unknown".to_string());
                            if elem1_name != "Unknown"
                                && elem2_name != "Unknown"
                                && elem1_name != elem2_name
                            {
                                type_errors.push(ClassifierDiagnostic {
                                    rule: "OOF-COL7".to_string(),
                                    message: format!(
                                        "stdlib.collection.concat: element type mismatch ({} vs {})",
                                        elem1_name, elem2_name
                                    ),
                                    node: node_name.to_string(),
                                    line: None,
                                });
                            }
                            // Prefer first arg elem; fall back to second if Unknown
                            let result_elem = if elem1_name != "Unknown" {
                                elem1.unwrap_or_else(|| {
                                    self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                                })
                            } else {
                                elem2.unwrap_or_else(|| {
                                    self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                                })
                            };
                            let mut col = serde_json::Map::new();
                            col.insert(
                                "name".to_string(),
                                serde_json::Value::String("Collection".to_string()),
                            );
                            col.insert(
                                "params".to_string(),
                                serde_json::Value::Array(vec![result_elem]),
                            );
                            resolved_type = serde_json::Value::Object(col);
                        }
                    }
                } else {
                    // Text path: accepts Text or String (v0 compat).
                    // LANG-STRING-TEXT-ALIAS-P2: String+String → stdlib.string.concat → String.
                    let both_string = typed_args.len() == 2
                        && self.type_name(&typed_args[0].resolved_type) == "String"
                        && self.type_name(&typed_args[1].resolved_type) == "String";
                    if both_string {
                        resolved_type =
                            self.type_ir(&serde_json::Value::String("String".to_string()));
                    } else {
                        resolved_type = self.check_text_stdlib_call(
                            "concat",
                            &typed_args,
                            &["Text", "Text"],
                            type_errors,
                            node_name,
                        );
                    }
                }
            }
            "split" => {
                is_resolved = true;
                resolved_type = self.check_text_stdlib_call(
                    "split",
                    &typed_args,
                    &["Text", "Text"],
                    type_errors,
                    node_name,
                );
            }
            "contains" | "starts_with" | "ends_with" => {
                is_resolved = true;
                resolved_type = self.check_text_stdlib_call(
                    fn_name,
                    &typed_args,
                    &["Text", "Text"],
                    type_errors,
                    node_name,
                );
            }
            "replace" | "replace_all" => {
                is_resolved = true;
                resolved_type = self.check_text_stdlib_call(
                    fn_name,
                    &typed_args,
                    &["Text", "Text", "Text"],
                    type_errors,
                    node_name,
                );
            }
            "byte_length" | "rune_length" | "grapheme_length" => {
                is_resolved = true;
                resolved_type = self.check_text_stdlib_call(
                    fn_name,
                    &typed_args,
                    &["Text"],
                    type_errors,
                    node_name,
                );
            }
            "byte_slice" | "rune_slice" | "grapheme_slice" => {
                is_resolved = true;
                resolved_type = self.check_text_stdlib_call(
                    fn_name,
                    &typed_args,
                    &["Text", "Integer", "Integer"],
                    type_errors,
                    node_name,
                );
            }
            // LAB-STDLIB-REGEXP-P3: stdlib.regexp.matches(String,String) -> Bool.
            "matches" => {
                is_resolved = true;
                resolved_type = self.check_text_stdlib_call(
                    "matches",
                    &typed_args,
                    &["Text", "Text"],
                    type_errors,
                    node_name,
                );
                // best-effort literal-pattern diagnostic (OOF-RE1): if the pattern arg is a string
                // literal, it must compile. Dynamic patterns are validated at runtime (operational err).
                self.check_literal_regexp_pattern(args.get(1), type_errors, node_name);
            }
            // stdlib.regexp.capture(String,String,Integer) -> Option[String]. Heterogeneous arity, so
            // checked in-place (check_text_stdlib_call assumes all-Text args).
            "capture" => {
                is_resolved = true;
                if typed_args.len() != 3 {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-TY0".to_string(),
                        message: format!(
                            "stdlib.regexp.capture: expected 3 arguments, got {}",
                            typed_args.len()
                        ),
                        node: node_name.to_string(),
                        line: None,
                    });
                } else {
                    for idx in [0usize, 1usize] {
                        let actual = self.type_name(&typed_args[idx].resolved_type);
                        if actual != "Unknown" && !self.text_arg_compatible(&actual, "Text") {
                            type_errors.push(ClassifierDiagnostic {
                                rule: "OOF-TY0".to_string(),
                                message: format!(
                                    "stdlib.regexp.capture arg {}: expected Text, got {}",
                                    idx + 1,
                                    actual
                                ),
                                node: node_name.to_string(),
                                line: None,
                            });
                        }
                    }
                    let idx_actual = self.type_name(&typed_args[2].resolved_type);
                    if idx_actual != "Integer" && idx_actual != "Unknown" {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-TY0".to_string(),
                            message: format!(
                                "stdlib.regexp.capture arg 3: expected Integer, got {}",
                                idx_actual
                            ),
                            node: node_name.to_string(),
                            line: None,
                        });
                    }
                }
                self.check_literal_regexp_pattern(args.get(1), type_errors, node_name);
                // return type: Option[String]
                let string_ty = self.type_ir(&serde_json::Value::String("String".to_string()));
                let mut opt = serde_json::Map::new();
                opt.insert(
                    "name".to_string(),
                    serde_json::Value::String("Option".to_string()),
                );
                opt.insert(
                    "params".to_string(),
                    serde_json::Value::Array(vec![string_ty]),
                );
                resolved_type = serde_json::Value::Object(opt);
            }
            "find" => {
                is_resolved = true;
                if typed_args.len() != 2 {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-TM1".to_string(),
                        message: format!(
                            "find expects exactly 2 arguments, got {}",
                            typed_args.len()
                        ),
                        node: node_name.to_string(),
                        line: None,
                    });
                }
                let inner_ty = if !typed_args.is_empty() {
                    self.get_param(&typed_args[0].resolved_type, 0)
                        .unwrap_or_else(|| {
                            self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                        })
                } else {
                    self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                };
                let mut opt = serde_json::Map::new();
                opt.insert(
                    "name".to_string(),
                    serde_json::Value::String("Option".to_string()),
                );
                opt.insert(
                    "params".to_string(),
                    serde_json::Value::Array(vec![inner_ty]),
                );
                resolved_type = serde_json::Value::Object(opt);
            }
            "any" | "all" => {
                is_resolved = true;
                if typed_args.len() != 2 {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-TM1".to_string(),
                        message: format!(
                            "{} expects exactly 2 arguments, got {}",
                            fn_name,
                            typed_args.len()
                        ),
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
                        .unwrap_or_else(|| {
                            self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                        })
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
                result_map.insert(
                    "name".to_string(),
                    serde_json::Value::String("Result".to_string()),
                );
                result_map.insert(
                    "params".to_string(),
                    serde_json::Value::Array(vec![t_type, e_type]),
                );
                resolved_type = serde_json::Value::Object(result_map);
            }
            "diff_seconds" => {
                is_resolved = true;
                if typed_args.len() != 2 {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-TM1".to_string(),
                        message: format!(
                            "diff_seconds expects exactly 2 arguments, got {}",
                            typed_args.len()
                        ),
                        node: node_name.to_string(),
                        line: None,
                    });
                } else {
                    for arg_typed in typed_args {
                        let arg_type = &arg_typed.resolved_type;
                        let arg_name = self.type_name(arg_type);
                        if arg_name != "DateTime" && arg_name != "Unknown" {
                            type_errors.push(ClassifierDiagnostic {
                                rule: "OOF-TY0".to_string(),
                                message: format!(
                                    "Type mismatch: expected DateTime, got {}",
                                    arg_name
                                ),
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
                        message: format!(
                            "add_seconds expects exactly 2 arguments, got {}",
                            typed_args.len()
                        ),
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
                        message: format!(
                            "parse_datetime expects exactly 2 arguments, got {}",
                            typed_args.len()
                        ),
                        node: node_name.to_string(),
                        line: None,
                    });
                } else {
                    for arg_typed in typed_args {
                        let arg_type = &arg_typed.resolved_type;
                        let arg_name = self.type_name(arg_type);
                        if arg_name != "String" && arg_name != "Unknown" {
                            type_errors.push(ClassifierDiagnostic {
                                rule: "OOF-TY0".to_string(),
                                message: format!(
                                    "Type mismatch: expected String, got {}",
                                    arg_name
                                ),
                                node: node_name.to_string(),
                                line: None,
                            });
                        }
                    }
                }
                let mut opt = serde_json::Map::new();
                opt.insert(
                    "name".to_string(),
                    serde_json::Value::String("Option".to_string()),
                );
                let dt_type = self.type_ir(&serde_json::Value::String("DateTime".to_string()));
                opt.insert(
                    "params".to_string(),
                    serde_json::Value::Array(vec![dt_type]),
                );
                resolved_type = serde_json::Value::Object(opt);
            }
            "format_datetime" => {
                is_resolved = true;
                if typed_args.len() != 2 {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-TM1".to_string(),
                        message: format!(
                            "format_datetime expects exactly 2 arguments, got {}",
                            typed_args.len()
                        ),
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
                        message: format!(
                            "{} expects exactly 2 arguments, got {}",
                            fn_name,
                            typed_args.len()
                        ),
                        node: node_name.to_string(),
                        line: None,
                    });
                } else {
                    for arg_typed in typed_args {
                        let arg_type = &arg_typed.resolved_type;
                        let arg_name = self.type_name(arg_type);
                        if arg_name != "DateTime" && arg_name != "Unknown" {
                            type_errors.push(ClassifierDiagnostic {
                                rule: "OOF-TY0".to_string(),
                                message: format!(
                                    "Type mismatch: expected DateTime, got {}",
                                    arg_name
                                ),
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
                resolved_type = self.infer_fold_call_type(
                    args,
                    &typed_args,
                    None,
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
            "append" => {
                // LANG-STDLIB-COLLECTION-APPEND-PROP-P4: stdlib.collection.append
                // append(Collection[T], T) -> Collection[T]
                // OOF-COL1: arity != 2
                // OOF-COL2: non-Collection / non-Unknown first arg
                // OOF-COL6: item type concrete mismatch (Unknown permissive)
                is_resolved = true;
                if args.len() != 2 {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-COL1".to_string(),
                        message: format!(
                            "stdlib.collection.append: expected 2 arguments, got {}",
                            args.len()
                        ),
                        node: node_name.to_string(),
                        line: None,
                    });
                    resolved_type = self.type_ir(&serde_json::Value::String("Unknown".to_string()));
                } else {
                    let col_arg_name = if !typed_args.is_empty() {
                        self.type_name(&typed_args[0].resolved_type)
                    } else {
                        "Unknown".to_string()
                    };
                    if col_arg_name != "Collection" && col_arg_name != "Unknown" {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-COL2".to_string(),
                            message: format!(
                                "stdlib.collection.append: first argument must be Collection[T], got {}",
                                col_arg_name
                            ),
                            node: node_name.to_string(),
                            line: None,
                        });
                        resolved_type =
                            self.type_ir(&serde_json::Value::String("Unknown".to_string()));
                    } else {
                        let elem_type = if col_arg_name == "Collection" && !typed_args.is_empty() {
                            self.get_param(&typed_args[0].resolved_type, 0)
                                .unwrap_or_else(|| {
                                    self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                                })
                        } else {
                            self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                        };
                        let elem_name = self.type_name(&elem_type);
                        if typed_args.len() >= 2 {
                            let item_name = self.type_name(&typed_args[1].resolved_type);
                            if elem_name != "Unknown"
                                && item_name != "Unknown"
                                && elem_name != item_name
                            {
                                type_errors.push(ClassifierDiagnostic {
                                    rule: "OOF-COL6".to_string(),
                                    message: format!(
                                        "stdlib.collection.append: item type {} does not match collection element type {}",
                                        item_name, elem_name
                                    ),
                                    node: node_name.to_string(),
                                    line: None,
                                });
                            }
                        }
                        let mut col = serde_json::Map::new();
                        col.insert(
                            "name".to_string(),
                            serde_json::Value::String("Collection".to_string()),
                        );
                        col.insert(
                            "params".to_string(),
                            serde_json::Value::Array(vec![elem_type]),
                        );
                        resolved_type = serde_json::Value::Object(col);
                    }
                }
            }
            "avg" | "min" | "max" if fn_name == "avg" || is_legacy_minmax_aggregate => {
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
                opt.insert(
                    "name".to_string(),
                    serde_json::Value::String("Option".to_string()),
                );
                opt.insert(
                    "params".to_string(),
                    serde_json::Value::Array(vec![resolved]),
                );
                resolved_type = serde_json::Value::Object(opt);
            }
            "compute_availability" => {
                is_resolved = true;
                let mut col = serde_json::Map::new();
                col.insert(
                    "name".to_string(),
                    serde_json::Value::String("Collection".to_string()),
                );
                let mut inner_ty = serde_json::Map::new();
                inner_ty.insert(
                    "name".to_string(),
                    serde_json::Value::String("TimeSlot".to_string()),
                );
                inner_ty.insert("params".to_string(), serde_json::Value::Array(Vec::new()));
                col.insert(
                    "params".to_string(),
                    serde_json::Value::Array(vec![serde_json::Value::Object(inner_ty)]),
                );
                resolved_type = serde_json::Value::Object(col);
            }
            "build_snapshot" => {
                is_resolved = true;
                resolved_type = self.type_ir(&serde_json::Value::String(
                    "AvailabilitySnapshot".to_string(),
                ));
            }
            "stdlib.IO.read_text"
            | "stdlib.IO.read_json"
            | "stdlib.IO.exists"
            | "stdlib.IO.list_dir" => {
                is_resolved = true;
                if typed_args.len() != 2 {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-TM1".to_string(),
                        message: format!(
                            "{} expects exactly 2 arguments, got {}",
                            fn_name,
                            typed_args.len()
                        ),
                        node: node_name.to_string(),
                        line: None,
                    });
                } else {
                    let arg0_name = self.type_name(&typed_args[0].resolved_type);
                    if arg0_name != "String" && arg0_name != "Unknown" {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-TY0".to_string(),
                            message: format!(
                                "Type mismatch for argument 0: expected String, got {}",
                                arg0_name
                            ),
                            node: node_name.to_string(),
                            line: None,
                        });
                    }
                }

                let mut res = serde_json::Map::new();
                res.insert(
                    "name".to_string(),
                    serde_json::Value::String("Result".to_string()),
                );

                let t_type = match fn_name {
                    "stdlib.IO.read_text" => {
                        self.type_ir(&serde_json::Value::String("String".to_string()))
                    }
                    "stdlib.IO.read_json" => {
                        self.type_ir(&serde_json::Value::String("JsonValue".to_string()))
                    }
                    "stdlib.IO.exists" => {
                        self.type_ir(&serde_json::Value::String("Bool".to_string()))
                    }
                    "stdlib.IO.list_dir" => {
                        let mut col = serde_json::Map::new();
                        col.insert(
                            "name".to_string(),
                            serde_json::Value::String("Collection".to_string()),
                        );
                        let inner_ty =
                            self.type_ir(&serde_json::Value::String("PathEntry".to_string()));
                        col.insert(
                            "params".to_string(),
                            serde_json::Value::Array(vec![inner_ty]),
                        );
                        serde_json::Value::Object(col)
                    }
                    _ => self.type_ir(&serde_json::Value::String("Unknown".to_string())),
                };
                let e_type = self.type_ir(&serde_json::Value::String("IoError".to_string()));
                res.insert(
                    "params".to_string(),
                    serde_json::Value::Array(vec![t_type, e_type]),
                );
                resolved_type = serde_json::Value::Object(res);
            }
            "stdlib.IO.write_text" | "stdlib.IO.write_json" => {
                is_resolved = true;
                if typed_args.len() != 3 {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-TM1".to_string(),
                        message: format!(
                            "{} expects exactly 3 arguments, got {}",
                            fn_name,
                            typed_args.len()
                        ),
                        node: node_name.to_string(),
                        line: None,
                    });
                } else {
                    let arg0_name = self.type_name(&typed_args[0].resolved_type);
                    if arg0_name != "String" && arg0_name != "Unknown" {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-TY0".to_string(),
                            message: format!(
                                "Type mismatch for argument 0: expected String, got {}",
                                arg0_name
                            ),
                            node: node_name.to_string(),
                            line: None,
                        });
                    }
                    if fn_name == "stdlib.IO.write_text" {
                        let arg1_name = self.type_name(&typed_args[1].resolved_type);
                        if arg1_name != "String" && arg1_name != "Unknown" {
                            type_errors.push(ClassifierDiagnostic {
                                rule: "OOF-TY0".to_string(),
                                message: format!(
                                    "Type mismatch for argument 1: expected String, got {}",
                                    arg1_name
                                ),
                                node: node_name.to_string(),
                                line: None,
                            });
                        }
                    }
                }

                let mut res = serde_json::Map::new();
                res.insert(
                    "name".to_string(),
                    serde_json::Value::String("Result".to_string()),
                );
                let t_type = self.type_ir(&serde_json::Value::String("WriteReceipt".to_string()));
                let e_type = self.type_ir(&serde_json::Value::String("IoError".to_string()));
                res.insert(
                    "params".to_string(),
                    serde_json::Value::Array(vec![t_type, e_type]),
                );
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
            // LAB-RACK-P11: two-tier callee resolution.
            //   Tier 1 — literal string callee: look up module contract registry;
            //            resolve output type or emit OOF-TY0.
            //   Tier 2 — dynamic callee (ref / computed): Unknown; VM fail-closed.
            "call_contract" => {
                is_resolved = true;
                if typed_args.is_empty() {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-TY0".to_string(),
                        message:
                            "call_contract requires at least one argument (contract name as String)"
                                .to_string(),
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
                    } else {
                        // LAB-RACK-P11 Tier 1: literal string callee → static lookup.
                        // Inspect the raw first arg to detect a literal string.
                        if let Some(first_raw_arg) = args.get(0) {
                            if let Expr::Literal {
                                type_tag,
                                value: callee_name_val,
                            } = first_raw_arg
                            {
                                if type_tag == "String" {
                                    if let Some(callee_name) = callee_name_val.as_str() {
                                        // positional arg count = total args minus the callee name
                                        let positional_count = args.len() - 1;
                                        match contract_registry.get(callee_name) {
                                            None => {
                                                type_errors.push(ClassifierDiagnostic {
                                                rule: "OOF-TY0".to_string(),
                                                message: format!(
                                                    "call_contract: unknown callee '{}' — not found in this module",
                                                    callee_name
                                                ),
                                                node: node_name.to_string(),
                                                line: None,
                                            });
                                            }
                                            Some(entry) if entry.modifier != "pure" => {
                                                type_errors.push(ClassifierDiagnostic {
                                                rule: "OOF-TY0".to_string(),
                                                message: format!(
                                                    "call_contract: callee '{}' is not pure (modifier: {}); only pure contracts may be called via call_contract in v0",
                                                    callee_name, entry.modifier
                                                ),
                                                node: node_name.to_string(),
                                                line: None,
                                            });
                                            }
                                            Some(entry)
                                                if entry.contract_name == current_contract_name =>
                                            {
                                                type_errors.push(ClassifierDiagnostic {
                                                rule: "OOF-TY0".to_string(),
                                                message: format!(
                                                    "call_contract: self-recursion via '{}' is closed in v0; use recur() for recursive contracts",
                                                    callee_name
                                                ),
                                                node: node_name.to_string(),
                                                line: None,
                                            });
                                            }
                                            Some(entry)
                                                if positional_count != entry.input_count =>
                                            {
                                                type_errors.push(ClassifierDiagnostic {
                                                rule: "OOF-TY0".to_string(),
                                                message: format!(
                                                    "call_contract: callee '{}' expects {} input(s), got {}",
                                                    callee_name, entry.input_count, positional_count
                                                ),
                                                node: node_name.to_string(),
                                                line: None,
                                            });
                                            }
                                            Some(entry) => {
                                                // Valid literal callee.
                                                if let Some(ref out_type) = entry.single_output_type
                                                {
                                                    // Single-output pure callee — resolve to its output type.
                                                    resolved_type = self.type_ir(out_type);
                                                }
                                                // Multi-output → resolved_type stays Unknown (deferred).

                                                // P8 (LAB-IGNITER-COMPILER-CALL-CONTRACT-ARG-TYPING):
                                                // structurally validate each supplied argument type against the
                                                // callee's declared input type — the SAME IgType boundary as the
                                                // P6 user-`def` signature check (`check_user_fn_call_signature`).
                                                // Arity already matched above, so `input_types` lines up with the
                                                // positional args (which start at typed_args[1]; [0] is the name).
                                                // Unknown / Unknown-bearing on either side is skipped (deferred,
                                                // never a false reject) exactly as P6 does.
                                                for (i, expected_raw) in
                                                    entry.input_types.iter().enumerate()
                                                {
                                                    let Some(actual_arg) = typed_args.get(i + 1)
                                                    else {
                                                        break;
                                                    };
                                                    let expected = self.type_ir(expected_raw);
                                                    let actual = &actual_arg.resolved_type;
                                                    if self.unknown_or_unknown_bearing(&expected)
                                                        || self.unknown_or_unknown_bearing(actual)
                                                    {
                                                        continue;
                                                    }
                                                    if !self
                                                        .structurally_assignable(actual, &expected)
                                                    {
                                                        let pname = entry
                                                            .input_names
                                                            .get(i)
                                                            .cloned()
                                                            .unwrap_or_else(|| {
                                                                format!("#{}", i + 1)
                                                            });
                                                        type_errors.push(ClassifierDiagnostic {
                                                            rule: "OOF-TY0".to_string(),
                                                            message: format!(
                                                                "call_contract: callee '{}' parameter '{}' expects {}, got {}",
                                                                callee_name,
                                                                pname,
                                                                self.type_display(&expected),
                                                                self.type_display(actual)
                                                            ),
                                                            node: node_name.to_string(),
                                                            line: None,
                                                        });
                                                    }
                                                }
                                            }
                                        }
                                    } // end if let Some(callee_name)
                                }
                                // type_tag != "String" → handled by name_arg_type check above
                            }
                            // Tier 2: non-literal first arg (Ref, BinaryOp, etc.)
                            // → resolved_type stays Unknown; VM fail-closed as in P9.
                        }
                    }
                }
                // resolved_type: either resolved to callee output type (Tier 1 success),
                // Unknown (Tier 2 dynamic or multi-output), or OOF-TY0 emitted.
            }
            // LAB-MAP-RUST-P1: Map[String,V] stdlib type inference
            "map_get" | "stdlib.map.get" => {
                is_resolved = true;
                // map_get(Map[String,V], String) → Option[V]
                let val_type = if !typed_args.is_empty() {
                    self.get_param(&typed_args[0].resolved_type, 1)
                        .unwrap_or_else(|| {
                            self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                        })
                } else {
                    self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                };
                resolved_type = self.make_option_type_ir(val_type);
            }
            "map_has_key" | "stdlib.map.has_key" => {
                is_resolved = true;
                // map_has_key(Map[String,V], String) → Bool
                resolved_type = self.type_ir(&serde_json::Value::String("Bool".to_string()));
            }
            // LAB-MACHINE-MAP-GET-STRING-P34: typed, fail-closed string extractor.
            // map_get_string(Map[String,V], String) → Option[String]: Some ONLY for a present STRING
            // value; None for missing / non-string / null. Stricter than map_get (which is permissive):
            // a clearly-non-Map first arg or non-String key is a typecheck error (Unknown is allowed for
            // dynamic inputs like `req.body_json`).
            "map_get_string" | "stdlib.map.get_string" => {
                is_resolved = true;
                if args.len() != 2 {
                    type_errors.push(ClassifierDiagnostic {
                        rule: "OOF-TY0".to_string(),
                        message: format!(
                            "stdlib.map.get_string: expected 2 arguments (map, key), got {}",
                            args.len()
                        ),
                        node: node_name.to_string(),
                        line: None,
                    });
                } else {
                    let map_name = self.type_name(&typed_args[0].resolved_type);
                    if map_name != "Map" && map_name != "Unknown" {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-TY0".to_string(),
                            message: format!(
                                "stdlib.map.get_string arg 1: expected Map[String, V], got {}",
                                map_name
                            ),
                            node: node_name.to_string(),
                            line: None,
                        });
                    }
                    let key_name = self.type_name(&typed_args[1].resolved_type);
                    if key_name != "String" && key_name != "Unknown" {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-TY0".to_string(),
                            message: format!(
                                "stdlib.map.get_string arg 2: expected String key, got {}",
                                key_name
                            ),
                            node: node_name.to_string(),
                            line: None,
                        });
                    }
                }
                // Always Option[String] (the typed contract), regardless of the map's value type.
                let str_type = self.type_ir(&serde_json::Value::String("String".to_string()));
                resolved_type = self.make_option_type_ir(str_type);
            }
            "map_from_pairs" | "stdlib.map.from_pairs" => {
                is_resolved = true;
                // map_from_pairs(Collection[Pair[String,V]]) → Map[String,V]
                let val_type = if !typed_args.is_empty() {
                    // Collection params[0] = Pair[String,V]; Pair params[1] = V
                    self.get_param(&typed_args[0].resolved_type, 0)
                        .and_then(|pair_ty| self.get_param(&pair_ty, 1))
                        .unwrap_or_else(|| {
                            self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                        })
                } else {
                    self.type_ir(&serde_json::Value::String("Unknown".to_string()))
                };
                let key_type = self.type_ir(&serde_json::Value::String("String".to_string()));
                resolved_type = self.make_map_type_ir(key_type, val_type);
            }
            "map_empty" | "stdlib.map.empty" => {
                is_resolved = true;
                // map_empty() → Map[String,Unknown]
                let key_type = self.type_ir(&serde_json::Value::String("String".to_string()));
                let val_type = self.type_ir(&serde_json::Value::String("Unknown".to_string()));
                resolved_type = self.make_map_type_ir(key_type, val_type);
            }
            _ => {}
        }

        if is_resolved {
            Some(resolved_type)
        } else {
            None
        }
    }

    /// LAB-STDLIB-REGEXP-P3: best-effort compile-time validation of a LITERAL regexp pattern. If the
    /// pattern arg is a string literal that fails to compile (bad syntax, or a rejected feature like
    /// lookaround/backref), emit `OOF-RE1`. Dynamic (non-literal) patterns are NOT checked here — they
    /// surface as runtime operational errors. Uses the same `regex` engine the VM uses, so a literal
    /// that passes here behaves identically at runtime.
    fn check_literal_regexp_pattern(
        &self,
        pattern_arg: Option<&Expr>,
        type_errors: &mut Vec<ClassifierDiagnostic>,
        node_name: &str,
    ) {
        if let Some(Expr::Literal { value, type_tag }) = pattern_arg {
            if type_tag == "String" || type_tag == "Text" {
                if let Some(pat) = value.as_str() {
                    if let Err(e) = regex::Regex::new(pat) {
                        type_errors.push(ClassifierDiagnostic {
                            rule: "OOF-RE1".to_string(),
                            message: format!("stdlib.regexp: invalid literal pattern: {}", e),
                            node: node_name.to_string(),
                            line: None,
                        });
                    }
                }
            }
        }
    }
}
