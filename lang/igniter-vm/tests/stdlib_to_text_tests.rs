// LAB-LANG-NUMBER-TO-TEXT-P1
//
// Explicit Integer→String boundary (`to_text`), no implicit coercion, no formatting/locale. Tested through
// the shared single source (`eval_math_call`, OP_CALL + eval_ast/HOF parity) and the real compiler→VM,
// including the `DatasetMeta.count`-style render proof `concat("Count: ", to_text(n))`.

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
