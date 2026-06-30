// LAB-STDLIB-MATH-NUMERIC-BASICS-P7
//
// N0 numeric basics — `abs/min/max/clamp/sign` over {Integer, Float} (Decimal deferred), same-type, no
// implicit coercion, total over finite values. They live in the single shared `eval_math_call` source, so
// they work identically via bytecode OP_CALL and inside HOF/lambda bodies (P10 parity). `sign` returns
// Integer (-1/0/1). Non-finite Float input and `clamp(lo>hi)` are deterministic runtime errors.

use igniter_vm::compiler::Compiler;
use igniter_vm::value::Value;
use igniter_vm::vm::{eval_math_call, VM};
use serde_json::json;
use std::collections::HashMap;

fn m(name: &str, args: &[Value]) -> Result<Value, String> {
    eval_math_call(name, args).expect("a math function")
}
fn i(n: i64) -> Value {
    Value::Integer(n)
}
fn f(x: f64) -> Value {
    Value::Float(x)
}

// ── direct value/error tests on the single source ──────────────────────────────────────────────────

#[test]
fn abs_integer_and_float() {
    assert_eq!(m("abs", &[i(-5)]), Ok(i(5)));
    assert_eq!(m("abs", &[i(5)]), Ok(i(5)));
    assert_eq!(m("abs", &[f(-2.5)]), Ok(f(2.5)));
    assert!(
        m("abs", &[f(f64::NAN)]).is_err(),
        "non-finite Float → error"
    );
    assert!(m("abs", &[i(1), i(2)]).is_err(), "arity");
    assert!(
        m("abs", &[Value::String("x".into())]).is_err(),
        "non-numeric"
    );
}

#[test]
fn sign_returns_integer() {
    assert_eq!(m("sign", &[i(-3)]), Ok(i(-1)));
    assert_eq!(m("sign", &[i(0)]), Ok(i(0)));
    assert_eq!(m("sign", &[i(7)]), Ok(i(1)));
    assert_eq!(m("sign", &[f(-0.0)]), Ok(i(0)));
    assert_eq!(m("sign", &[f(2.5)]), Ok(i(1)));
    assert_eq!(m("sign", &[f(-2.5)]), Ok(i(-1)));
}

#[test]
fn min_max_same_type_only() {
    assert_eq!(m("min", &[i(3), i(7)]), Ok(i(3)));
    assert_eq!(m("max", &[i(3), i(7)]), Ok(i(7)));
    assert_eq!(m("min", &[f(2.0), f(9.5)]), Ok(f(2.0)));
    assert_eq!(m("max", &[f(2.0), f(9.5)]), Ok(f(9.5)));
    assert!(
        m("min", &[i(1), f(2.0)]).is_err(),
        "mixed numeric types rejected"
    );
    assert!(m("max", &[f(1.0)]).is_err(), "arity");
}

#[tokio::test]
async fn scalar_min_max_short_names_through_compiler_vm() {
    let expr = json!({
        "kind": "call", "fn": "max", "args": [
            { "kind": "call", "fn": "min", "args": [
                { "kind": "literal", "type_tag": "Integer", "value": 9 },
                { "kind": "literal", "type_tag": "Integer", "value": 4 }
            ]},
            { "kind": "literal", "type_tag": "Integer", "value": 7 }
        ]
    });
    let contract = json!({ "contract_id": "ScalarMinMax", "inputs": [], "expression": expr });
    let bc = Compiler::new().compile(&contract).unwrap();
    let r = VM::new(None)
        .execute(&bc, &HashMap::new(), &HashMap::new())
        .await
        .unwrap();
    assert_eq!(r, i(7));
}

#[test]
fn clamp_integer_float_and_bounds() {
    assert_eq!(m("clamp", &[i(5), i(0), i(10)]), Ok(i(5)));
    assert_eq!(m("clamp", &[i(15), i(0), i(10)]), Ok(i(10)));
    assert_eq!(m("clamp", &[i(-3), i(0), i(10)]), Ok(i(0)));
    assert_eq!(m("clamp", &[f(0.5), f(0.0), f(1.0)]), Ok(f(0.5)));
    assert_eq!(m("clamp", &[f(-2.5), f(0.0), f(1.0)]), Ok(f(0.0)));
    // invalid bounds → deterministic error (control-code hygiene), never silent inversion.
    assert!(m("clamp", &[i(5), i(10), i(0)]).is_err(), "lo > hi");
    assert!(
        m("clamp", &[f(1.0), f(0.0), f(f64::INFINITY)]).is_err(),
        "non-finite bound"
    );
    assert!(m("clamp", &[i(1), f(0.0), f(1.0)]).is_err(), "mixed types");
}

// ── HOF parity: N0 basics work inside a fold lambda (eval_ast path), same source ─────────────────────

fn float_arr(vals: &[f64]) -> serde_json::Value {
    let items: Vec<_> = vals
        .iter()
        .map(|v| json!({ "kind": "literal", "type_tag": "Float", "value": v }))
        .collect();
    json!({ "kind": "array_literal", "items": items })
}

#[tokio::test]
async fn clamp_inside_fold_lambda() {
    // fold([-5, 0.5, 9], 0.0, (acc, x) -> acc + clamp(x, 0.0, 1.0))  →  0 + 0.5 + 1 = 1.5
    let body = json!({
        "kind": "binary_op", "op": "+",
        "left": { "kind": "ref", "name": "acc" },
        "right": { "kind": "call", "fn": "clamp", "args": [
            { "kind": "ref", "name": "x" },
            { "kind": "literal", "type_tag": "Float", "value": 0.0 },
            { "kind": "literal", "type_tag": "Float", "value": 1.0 }
        ]}
    });
    let contract = json!({
        "contract_id": "ClampFold", "inputs": [],
        "expression": {
            "kind": "map_reduce_aggregate",
            "source": float_arr(&[-5.0, 0.5, 9.0]),
            "pipeline": [{
                "kind": "fold", "param_acc": "acc", "param_val": "x",
                "init": { "kind": "literal", "type_tag": "Float", "value": 0.0 },
                "body": body
            }]
        }
    });
    let bc = Compiler::new().compile(&contract).unwrap();
    let r = VM::new(None)
        .execute(&bc, &HashMap::new(), &HashMap::new())
        .await
        .unwrap();
    match r {
        Value::Float(v) => assert!((v - 1.5).abs() < 1e-12, "clamp-in-fold sum = 1.5, got {v}"),
        other => panic!("expected Float, got {other:?}"),
    }
}
