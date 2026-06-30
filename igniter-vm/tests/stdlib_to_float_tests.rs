// LAB-STDLIB-NUMERIC-TO-FLOAT-P8
//
// Explicit Integer→Float boundary (`to_float`), no implicit coercion. Tested through the shared single
// source (`eval_math_call`, OP_CALL + eval_ast/HOF parity, P10) and the real compiler→VM, including the
// statistics-unblock proof `sum(xs) / to_float(count(xs))`.

use igniter_vm::compiler::Compiler;
use igniter_vm::value::Value;
use igniter_vm::vm::{eval_math_call, VM};
use serde_json::json;
use std::collections::HashMap;

fn to_float(i: i64) -> Result<Value, String> {
    eval_math_call("to_float", &[Value::Integer(i)]).unwrap()
}

#[test]
fn to_float_basic_and_negative() {
    assert_eq!(to_float(3), Ok(Value::Float(3.0)));
    assert_eq!(to_float(0), Ok(Value::Float(0.0)));
    assert_eq!(to_float(-7), Ok(Value::Float(-7.0)));
}

/// Large i64 beyond the 53-bit mantissa rounds per IEEE-754 (`as f64`) — documented, stable expectation.
#[test]
fn to_float_large_integer_rounds_as_f64() {
    // 2^53 + 1 is not representable; `as f64` rounds to 2^53.
    let n = (1i64 << 53) + 1;
    assert_eq!(to_float(n), Ok(Value::Float(n as f64)));
    assert_eq!(to_float(n), Ok(Value::Float(9007199254740992.0))); // == 2^53, the rounded value
}

#[test]
fn to_float_arity_and_type_errors() {
    assert!(
        eval_math_call("to_float", &[]).unwrap().is_err(),
        "0-arg errors"
    );
    assert!(
        eval_math_call("to_float", &[Value::Integer(1), Value::Integer(2)])
            .unwrap()
            .is_err(),
        "2-arg errors"
    );
    assert!(
        eval_math_call("to_float", &[Value::Float(1.0)])
            .unwrap()
            .is_err(),
        "non-Integer (Float) errors"
    );
}

// ── compiler→VM parity + the statistics-unblock proof ────────────────────────────────────────────────

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
fn lit_float(v: f64) -> serde_json::Value {
    json!({ "kind": "literal", "type_tag": "Float", "value": v })
}
fn call(fn_name: &str, args: Vec<serde_json::Value>) -> serde_json::Value {
    json!({ "kind": "call", "fn": fn_name, "args": args })
}
fn binop(op: &str, l: serde_json::Value, r: serde_json::Value) -> serde_json::Value {
    json!({ "kind": "binary_op", "op": op, "left": l, "right": r })
}

/// `to_float(3)` through the real compiler→VM = 3.0 (OP_CALL/eval_ast dispatch parity).
#[tokio::test]
async fn to_float_through_compiler_vm() {
    let c = json!({ "contract_id": "ToF", "inputs": [], "expression": call("to_float", vec![lit_int(3)]) });
    assert_eq!(run(c).await, Ok(Value::Float(3.0)));
}

/// The statistics unblock: a Float mean `9.0 / to_float(3)` = 3.0. `Float / Float` is legal; the Integer
/// count is widened explicitly. (Mirrors `sum(xs) / to_float(count(xs))` with the aggregates inlined.)
#[tokio::test]
async fn float_div_to_float_count_normalizes() {
    let mean = binop("/", lit_float(9.0), call("to_float", vec![lit_int(3)]));
    let c = json!({ "contract_id": "Mean", "inputs": [], "expression": mean });
    assert_eq!(
        run(c).await,
        Ok(Value::Float(3.0)),
        "9.0 / to_float(3) = 3.0"
    );
}
