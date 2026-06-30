// LAB-STDLIB-MATH-EVAL-AST-PARITY-P10
//
// Tier-1 stdlib math (fast P2 `sin/cos/sqrt/pi` + deterministic P5 `det_*`) must work INSIDE HOF/lambda
// bodies (`map`/`fold`/`filter`), not only as direct bytecode `OP_CALL`s. P9 found these compile but fail
// at runtime — a 1-arg `sin` in a lambda body was evaluated by `eval_ast` and fell to the binary-operator
// handler ("Operator sin expects exactly 2 operands; got 1"). P10 routes both paths through one shared
// source, `eval_math_call`.
//
// These tests build the exact AST the compiler emits (`array_literal` source + `fold` pipeline + `call`
// node), compile via the VM's `Compiler`, and run via `VM::execute` — exercising the real eval_ast path.

use igniter_vm::compiler::Compiler;
use igniter_vm::value::Value;
use igniter_vm::vm::{eval_math_call, VM};
use serde_json::json;
use std::collections::HashMap;

fn float_arr(vals: &[f64]) -> serde_json::Value {
    let items: Vec<_> = vals
        .iter()
        .map(|v| json!({ "kind": "literal", "type_tag": "Float", "value": v }))
        .collect();
    json!({ "kind": "array_literal", "items": items })
}
fn ref_(name: &str) -> serde_json::Value {
    json!({ "kind": "ref", "name": name })
}
fn call(fn_name: &str, args: Vec<serde_json::Value>) -> serde_json::Value {
    json!({ "kind": "call", "fn": fn_name, "args": args })
}
fn add(l: serde_json::Value, r: serde_json::Value) -> serde_json::Value {
    json!({ "kind": "binary_op", "op": "+", "left": l, "right": r })
}

/// `fold(vals, 0.0, (acc, x) -> body)` as the VM's `map_reduce_aggregate` AST.
fn fold_contract(vals: &[f64], body: serde_json::Value) -> serde_json::Value {
    json!({
        "contract_id": "HofMath",
        "inputs": [],
        "expression": {
            "kind": "map_reduce_aggregate",
            "source": float_arr(vals),
            "pipeline": [{
                "kind": "fold",
                "param_acc": "acc",
                "param_val": "x",
                "init": { "kind": "literal", "type_tag": "Float", "value": 0.0 },
                "body": body
            }]
        }
    })
}

/// `fold(map(vals, x -> map_body), 0.0, (acc, y) -> acc + y)` — the closest in-repo shape to P9's
/// `map(others, other -> sin(...)) |> sum` pressure, using the same eval_ast lambda dispatch for map.
fn map_then_sum_contract(vals: &[f64], map_body: serde_json::Value) -> serde_json::Value {
    json!({
        "contract_id": "HofMathMapThenSum",
        "inputs": [],
        "expression": {
            "kind": "map_reduce_aggregate",
            "source": float_arr(vals),
            "pipeline": [
                {
                    "kind": "map",
                    "param": "x",
                    "body": map_body
                },
                {
                    "kind": "fold",
                    "param_acc": "acc",
                    "param_val": "y",
                    "init": { "kind": "literal", "type_tag": "Float", "value": 0.0 },
                    "body": add(ref_("acc"), ref_("y"))
                }
            ]
        }
    })
}

async fn run(contract: serde_json::Value) -> Result<Value, String> {
    let mut c = Compiler::new();
    let bc = c.compile(&contract)?;
    VM::new(None)
        .execute(&bc, &HashMap::new(), &HashMap::new())
        .await
}

fn as_f64(r: Result<Value, String>) -> f64 {
    match r {
        Ok(Value::Float(x)) => x,
        other => panic!("expected Float, got {other:?}"),
    }
}

// ── eval_ast / HOF path (the P10 fix) ───────────────────────────────────────────────────────────────

/// The exact P9 blocker shape, now passing: `sum_j sin(x_j)` via fold over [0, π/2, π] ≈ 1.0.
#[tokio::test]
async fn sin_inside_fold_lambda_runs() {
    let body = add(ref_("acc"), call("sin", vec![ref_("x")]));
    let r = as_f64(
        run(fold_contract(
            &[0.0, std::f64::consts::FRAC_PI_2, std::f64::consts::PI],
            body,
        ))
        .await,
    );
    assert!(
        (r - 1.0).abs() < 1e-12,
        "sin(0)+sin(π/2)+sin(π) ≈ 1.0, got {r}"
    );
}

/// P9's pressure shape directly: map each item through `sin`, then sum the mapped Floats.
#[tokio::test]
async fn map_then_sum_sin_inside_lambda_runs() {
    let r = as_f64(
        run(map_then_sum_contract(
            &[0.0, std::f64::consts::FRAC_PI_2, std::f64::consts::PI],
            call("sin", vec![ref_("x")]),
        ))
        .await,
    );
    assert!((r - 1.0).abs() < 1e-12, "map(sin) then sum ≈ 1.0, got {r}");
}

/// cos / sqrt / pi also work inside the HOF lambda body, not only direct bytecode calls.
#[tokio::test]
async fn cos_sqrt_pi_inside_fold_lambda() {
    let cos = as_f64(
        run(fold_contract(
            &[0.0],
            add(ref_("acc"), call("cos", vec![ref_("x")])),
        ))
        .await,
    );
    assert!((cos - 1.0).abs() < 1e-12, "cos(0)=1, got {cos}");
    let sqrt = as_f64(
        run(fold_contract(
            &[4.0],
            add(ref_("acc"), call("sqrt", vec![ref_("x")])),
        ))
        .await,
    );
    assert!((sqrt - 2.0).abs() < 1e-12, "sqrt(4)=2, got {sqrt}");
    let pi = as_f64(run(fold_contract(&[0.0], add(ref_("acc"), call("pi", vec![])))).await);
    assert!(
        (pi - std::f64::consts::PI).abs() < 1e-12,
        "pi()=π, got {pi}"
    );
}

/// Deterministic `det_sin` inside a lambda preserves golden-bit semantics.
#[tokio::test]
async fn det_sin_inside_fold_lambda_is_golden() {
    // body ignores acc → returns det_sin(0.5) for the single element.
    let r = as_f64(run(fold_contract(&[0.5], call("det_sin", vec![ref_("x")]))).await);
    assert_eq!(
        r.to_bits(),
        0x3fdeaee8744b05f0,
        "det_sin(0.5) golden bits inside HOF"
    );
}

/// Negative `det_sqrt` inside a lambda is a deterministic ERROR, not a silent NaN/null.
#[tokio::test]
async fn det_sqrt_negative_inside_fold_lambda_errors() {
    let r = run(fold_contract(&[-1.0], call("det_sqrt", vec![ref_("x")]))).await;
    assert!(r.is_err(), "det_sqrt(-1) in a lambda must error, got {r:?}");
    assert!(r.unwrap_err().contains("domain"), "domain error");
}

/// A wrong-arity math call inside a lambda gives the math message, NOT the binary-operator fallback.
#[tokio::test]
async fn arity_error_inside_lambda_is_math_message() {
    let r = run(fold_contract(
        &[1.0],
        call("sin", vec![ref_("x"), ref_("x")]),
    ))
    .await;
    let e = r.unwrap_err();
    assert!(
        e.contains("sin expects exactly 1 argument"),
        "math arity msg, got: {e}"
    );
    assert!(
        !e.contains("expects exactly 2 operands"),
        "must NOT fall to binary-op msg: {e}"
    );
}

// ── single-source unit tests (`eval_math_call`, shared by OP_CALL + eval_ast) ────────────────────────

#[test]
fn shared_source_values_and_errors() {
    let f = |name: &str, args: &[Value]| eval_math_call(name, args).unwrap();
    assert_eq!(f("sin", &[Value::Float(0.0)]), Ok(Value::Float(0.0)));
    assert_eq!(f("sqrt", &[Value::Float(4.0)]), Ok(Value::Float(2.0)));
    assert_eq!(f("pi", &[]), Ok(Value::Float(std::f64::consts::PI)));
    // det_sqrt(2) == the canonical √2 double (golden bits).
    assert_eq!(
        as_f64(f("det_sqrt", &[Value::Float(2.0)])).to_bits(),
        0x3ff6a09e667f3bcd
    );
    // errors: domain, non-finite, arity, non-Float
    assert!(f("det_sqrt", &[Value::Float(-1.0)]).is_err());
    assert!(f("det_sin", &[Value::Float(f64::NAN)]).is_err());
    assert!(f("sin", &[Value::Float(1.0), Value::Float(2.0)]).is_err());
    assert!(f("sin", &[Value::Integer(1)]).is_err());
    // not a math fn → None (caller falls through)
    assert!(eval_math_call("filter", &[]).is_none());
}
