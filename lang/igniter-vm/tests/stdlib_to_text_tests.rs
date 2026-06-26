// LAB-LANG-NUMBER-TO-TEXT-P1 + LAB-LANG-DECIMAL-TO-TEXT-P2
//
// Explicit Integer|Decimal→String boundary (`to_text`), no implicit coercion, no formatting/locale/rounding;
// Float HELD. Tested through the shared single source (`eval_math_call`, OP_CALL + eval_ast/HOF parity) and
// the real compiler→VM: the `DatasetMeta.count` render proof `concat("Count: ", to_text(n))` and the exact
// canonical Decimal table (money/report output) incl. the `i64::MIN` magnitude boundary.

use igniter_vm::compiler::Compiler;
use igniter_vm::value::Value;
use igniter_vm::vm::{eval_math_call, VM};
use serde_json::json;
use std::collections::HashMap;
use std::sync::Arc;

fn to_text(i: i64) -> Result<Value, String> {
    eval_math_call("to_text", &[Value::Integer(i)]).unwrap()
}

fn s(v: &str) -> Value {
    Value::String(Arc::from(v))
}

#[test]
fn to_text_basic_zero_and_negative() {
    assert_eq!(to_text(3), Ok(s("3")));
    assert_eq!(to_text(0), Ok(s("0")));
    assert_eq!(to_text(-7), Ok(s("-7")));
}

/// Full i64 range is exact (base-10, no rounding) — unlike `to_float`, integers never lose precision.
#[test]
fn to_text_is_exact_across_i64_range() {
    assert_eq!(to_text(i64::MAX), Ok(s("9223372036854775807")));
    assert_eq!(to_text(i64::MIN), Ok(s("-9223372036854775808")));
    let big = (1i64 << 53) + 1; // the value `to_float` would round; `to_text` keeps it exact.
    assert_eq!(to_text(big), Ok(s("9007199254740993")));
}

/// The namespaced alias resolves to the same result as the bare name.
#[test]
fn to_text_namespaced_alias() {
    assert_eq!(
        eval_math_call("stdlib.string.to_text", &[Value::Integer(42)]).unwrap(),
        Ok(s("42"))
    );
}

#[test]
fn to_text_arity_and_type_errors() {
    assert!(
        eval_math_call("to_text", &[]).unwrap().is_err(),
        "0-arg errors"
    );
    assert!(
        eval_math_call("to_text", &[Value::Integer(1), Value::Integer(2)])
            .unwrap()
            .is_err(),
        "2-arg errors"
    );
    assert!(
        eval_math_call("to_text", &[Value::Float(1.0)])
            .unwrap()
            .is_err(),
        "non-Integer (Float) errors — Float is HELD"
    );
    assert!(
        eval_math_call("to_text", &[s("already")]).unwrap().is_err(),
        "non-Integer (String) errors"
    );
}

// ── compiler→VM parity + the DatasetMeta.count render proof ────────────────────────────────────────────

async fn run(contract: serde_json::Value) -> Result<Value, String> {
    let mut c = Compiler::new();
    let bc = c.compile(&contract)?;
    VM::new(None)
        .execute(&bc, &HashMap::new(), &HashMap::new())
        .await
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

/// `to_text(42)` through the real compiler→VM = "42" (OP_CALL/eval_ast dispatch parity).
#[tokio::test]
async fn to_text_through_compiler_vm() {
    let c = json!({ "contract_id": "ToT", "inputs": [], "expression": call("to_text", vec![lit_int(42)]) });
    assert_eq!(run(c).await, Ok(s("42")));
}

/// The DatasetMeta.count unblock: `concat("Count: ", to_text(3))` = "Count: 3" — a numeric value lands in an
/// escaped text leaf with no Integer→String gap (the P18 gap this card closes).
#[tokio::test]
async fn concat_to_text_count_renders() {
    let expr = call(
        "concat",
        vec![lit_str("Count: "), call("to_text", vec![lit_int(3)])],
    );
    let c = json!({ "contract_id": "Badge", "inputs": [], "expression": expr });
    assert_eq!(
        run(c).await,
        Ok(s("Count: 3")),
        "concat(\"Count: \", to_text(3))"
    );
}

// ── LAB-LANG-DECIMAL-TO-TEXT-P2: exact Decimal→String (canonical base-10, no rounding/locale/exponent) ──

fn dec(value: i64, scale: u32) -> Result<Value, String> {
    eval_math_call("to_text", &[Value::Decimal { value, scale }]).unwrap()
}

/// The card's canonical table — exact `scale` fractional digits, padded, signed, never trimmed.
#[test]
fn to_text_decimal_canonical_table() {
    assert_eq!(dec(12345, 2), Ok(s("123.45")));
    assert_eq!(dec(1200, 2), Ok(s("12.00")), "trailing zeros kept");
    assert_eq!(
        dec(5, 2),
        Ok(s("0.05")),
        "leading integer zero + zero-pad fraction"
    );
    assert_eq!(dec(0, 2), Ok(s("0.00")));
    assert_eq!(dec(-5, 2), Ok(s("-0.05")), "sign on the whole, -0.xx");
    assert_eq!(dec(-12345, 2), Ok(s("-123.45")));
    assert_eq!(dec(42, 0), Ok(s("42")), "scale 0 → no point");
}

/// Higher scales + an all-fraction value zero-pad correctly.
#[test]
fn to_text_decimal_padding_and_scales() {
    assert_eq!(dec(7, 4), Ok(s("0.0007")));
    assert_eq!(dec(123, 5), Ok(s("0.00123")));
    assert_eq!(dec(100, 2), Ok(s("1.00")));
    assert_eq!(dec(-1, 3), Ok(s("-0.001")));
}

/// `i64::MIN` is exact at scale 0 and scale 2 — the `i128` magnitude path avoids the `abs` overflow.
#[test]
fn to_text_decimal_i64_min_boundary() {
    assert_eq!(dec(i64::MIN, 0), Ok(s("-9223372036854775808")));
    assert_eq!(dec(i64::MIN, 2), Ok(s("-92233720368547758.08")));
    assert_eq!(dec(i64::MAX, 2), Ok(s("92233720368547758.07")));
}

/// `to_text(decimal(12345, 2))` through the real compiler→VM = "123.45".
#[tokio::test]
async fn to_text_decimal_through_compiler_vm() {
    let d = call("decimal", vec![lit_int(12345), lit_int(2)]);
    let c = json!({ "contract_id": "Money", "inputs": [], "expression": call("to_text", vec![d]) });
    assert_eq!(run(c).await, Ok(s("123.45")), "to_text(decimal(12345, 2))");
}
