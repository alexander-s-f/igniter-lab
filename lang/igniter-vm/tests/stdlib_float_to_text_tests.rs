// LAB-LANG-FLOAT-TO-TEXT-IMPL-P7
//
// `float_to_text(x : Float, decimals : Integer, rounding : String) -> String` — EXPLICIT fixed-point Float
// formatting (never implicit `to_text(Float)`). v0: `"half_even"` only, finite only, `decimals ∈ 0..=17`,
// rounded-zero magnitude normalized to unsigned. Exact values are PINNED (P5 §6, rustc-verified) so a future
// std change is caught. Tested on the shared `eval_math_call` source + the real compiler→VM (OP_CALL + fold).

use igniter_vm::compiler::Compiler;
use igniter_vm::value::Value;
use igniter_vm::vm::{eval_math_call, VM};
use serde_json::json;
use std::collections::HashMap;
use std::sync::Arc;

fn s(v: &str) -> Value {
    Value::String(Arc::from(v))
}

/// Direct call through the single source: `float_to_text(x, decimals, mode)`.
fn ftt(x: f64, decimals: i64, mode: &str) -> Result<Value, String> {
    eval_math_call(
        "float_to_text",
        &[Value::Float(x), Value::Integer(decimals), s(mode)],
    )
    .expect("float_to_text is routed through eval_math_call")
}

fn ok(v: &str) -> Result<Value, String> {
    Ok(s(v))
}

// ── exact values (pinned, P5 §6) ─────────────────────────────────────────────────────────────────────

#[test]
fn basic_and_padding() {
    assert_eq!(ftt(1.5, 2, "half_even"), ok("1.50"));
    assert_eq!(ftt(1.0, 3, "half_even"), ok("1.000"));
    assert_eq!(ftt(3.7, 0, "half_even"), ok("4"));
    assert_eq!(ftt(3.14159, 2, "half_even"), ok("3.14"));
}

#[test]
fn half_even_ties() {
    assert_eq!(ftt(0.5, 0, "half_even"), ok("0"), "tie→even (0)");
    assert_eq!(ftt(1.5, 0, "half_even"), ok("2"), "tie→even (2)");
    assert_eq!(ftt(2.5, 0, "half_even"), ok("2"), "tie→even (2, NOT 3)");
    assert_eq!(ftt(3.5, 0, "half_even"), ok("4"), "tie→even (4)");
    assert_eq!(ftt(-2.5, 0, "half_even"), ok("-2"), "negative tie→even keeps sign");
    assert_eq!(ftt(0.125, 2, "half_even"), ok("0.12"), "exact-f64 tie→even");
    assert_eq!(ftt(0.375, 2, "half_even"), ok("0.38"), "exact-f64 tie→even");
}

#[test]
fn negative_zero_normalized() {
    assert_eq!(ftt(-0.0, 2, "half_even"), ok("0.00"), "-0.0 → unsigned");
    assert_eq!(ftt(-0.001, 2, "half_even"), ok("0.00"), "rounds to zero → unsigned");
    assert_eq!(ftt(-0.4, 0, "half_even"), ok("0"), "rounds to zero → unsigned");
    assert_eq!(ftt(-0.04, 1, "half_even"), ok("0.0"), "rounds to zero → unsigned");
    // A real negative keeps its sign.
    assert_eq!(ftt(-1.25, 1, "half_even"), ok("-1.2"), "non-zero negative keeps sign");
}

#[test]
fn f64_reality_not_decimal() {
    // The binary f64 is BELOW the decimal-looking literal — honest "floats aren't decimals".
    assert_eq!(ftt(2.675, 2, "half_even"), ok("2.67"));
    assert_eq!(ftt(1.005, 2, "half_even"), ok("1.00"));
}

#[test]
fn no_exponent_for_large_values() {
    assert_eq!(ftt(1e20, 2, "half_even"), ok("100000000000000000000.00"), "fixed-point, no exponent");
}

#[test]
fn precision_bound_edges() {
    assert!(ftt(0.1, 17, "half_even").is_ok(), "17 decimals allowed");
    assert!(ftt(0.1, 18, "half_even").is_err(), "18 decimals rejected");
    assert!(ftt(0.1, -1, "half_even").is_err(), "negative decimals rejected");
}

// ── deterministic rejections (no output) ─────────────────────────────────────────────────────────────

#[test]
fn non_finite_rejected() {
    assert!(ftt(f64::NAN, 2, "half_even").is_err(), "NaN rejected");
    assert!(ftt(f64::INFINITY, 2, "half_even").is_err(), "+Inf rejected");
    assert!(ftt(f64::NEG_INFINITY, 2, "half_even").is_err(), "-Inf rejected");
}

#[test]
fn dynamic_unsupported_mode_rejected() {
    let err = ftt(1.5, 2, "half_up").unwrap_err();
    assert!(
        err.contains("unsupported rounding mode \"half_up\"") && err.contains("half_even"),
        "stable §2 message: {err}"
    );
}

#[test]
fn arity_and_type_errors() {
    assert!(
        eval_math_call("float_to_text", &[Value::Float(1.5), Value::Integer(2)])
            .unwrap()
            .is_err(),
        "2-arg errors"
    );
    assert!(
        eval_math_call("float_to_text", &[Value::Integer(1), Value::Integer(2), s("half_even")])
            .unwrap()
            .is_err(),
        "non-Float x errors at runtime"
    );
}

// ── compiler→VM: OP_CALL e2e + eval_ast (fold) parity ────────────────────────────────────────────────

async fn run(contract: serde_json::Value) -> Result<Value, String> {
    let mut c = Compiler::new();
    let bc = c.compile(&contract)?;
    VM::new(None).execute(&bc, &HashMap::new(), &HashMap::new()).await
}
fn lit_float(v: f64) -> serde_json::Value {
    json!({ "kind": "literal", "type_tag": "Float", "value": v })
}
fn lit_int(v: i64) -> serde_json::Value {
    json!({ "kind": "literal", "type_tag": "Integer", "value": v })
}
fn lit_str(v: &str) -> serde_json::Value {
    json!({ "kind": "literal", "type_tag": "String", "value": v })
}
fn call(fn_name: &str, args: Vec<serde_json::Value>) -> serde_json::Value {
    json!({ "kind": "call", "fn": fn_name, "args": args })
}

#[tokio::test]
async fn float_to_text_through_compiler_vm() {
    let expr = call("float_to_text", vec![lit_float(3.14159), lit_int(2), lit_str("half_even")]);
    let c = json!({ "contract_id": "Ftt", "inputs": [], "expression": expr });
    assert_eq!(run(c).await, Ok(s("3.14")), "float_to_text(3.14159, 2, \"half_even\")");
}

/// eval_ast parity: `float_to_text` inside a `fold` lambda body runs identically (single-source dispatch).
#[tokio::test]
async fn float_to_text_inside_fold_lambda_runs() {
    let contract = json!({
        "contract_id": "FttHof",
        "inputs": [],
        "expression": {
            "kind": "map_reduce_aggregate",
            "source": { "kind": "array_literal", "items": [lit_float(2.5)] },
            "pipeline": [{
                "kind": "fold",
                "param_acc": "acc",
                "param_val": "x",
                "init": lit_str(""),
                "body": call("float_to_text", vec![json!({ "kind": "ref", "name": "x" }), lit_int(0), lit_str("half_even")])
            }]
        }
    });
    assert_eq!(run(contract).await, Ok(s("2")), "float_to_text(2.5,0,half_even) inside fold → tie-to-even");
}
