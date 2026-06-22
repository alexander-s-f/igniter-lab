// LAB-STDLIB-MATH-INTEGER-ROOTS-AND-MOD-P8
//
// N1 integer-only math: `isqrt` (floor integer sqrt), `ipow` (checked exponentiation by squaring), `mod`
// (Euclidean, non-negative for a positive modulus). Integer-only, deterministic by construction (pure i64,
// no f64), domain errors are deterministic runtime errors. Tested through the shared `eval_math_call`
// (so OP_CALL and the eval_ast/HOF path are in parity) AND through the real compiler+VM.

use igniter_vm::compiler::Compiler;
use igniter_vm::value::Value;
use igniter_vm::vm::{eval_math_call, VM};
use serde_json::json;
use std::collections::HashMap;

// ── shared source unit tests: values, domain errors, overflow, arity, non-Integer ───────────────────

fn ok(name: &str, args: &[Value]) -> Value {
    eval_math_call(name, args).unwrap().unwrap()
}
fn err(name: &str, args: &[Value]) -> String {
    eval_math_call(name, args).unwrap().unwrap_err()
}

#[test]
fn isqrt_values_and_domain() {
    assert_eq!(ok("isqrt", &[Value::Integer(0)]), Value::Integer(0));
    assert_eq!(ok("isqrt", &[Value::Integer(1)]), Value::Integer(1));
    assert_eq!(ok("isqrt", &[Value::Integer(15)]), Value::Integer(3));
    assert_eq!(ok("isqrt", &[Value::Integer(16)]), Value::Integer(4));
    assert_eq!(ok("isqrt", &[Value::Integer(17)]), Value::Integer(4));
    // large: 1_000_000_000_000 = 10^12, isqrt = 10^6
    assert_eq!(
        ok("isqrt", &[Value::Integer(1_000_000_000_000)]),
        Value::Integer(1_000_000)
    );
    // a non-perfect large square: 10^18 isqrt = 1_000_000_000
    assert_eq!(
        ok("isqrt", &[Value::Integer(1_000_000_000_000_000_000)]),
        Value::Integer(1_000_000_000)
    );
    assert!(err("isqrt", &[Value::Integer(-1)]).contains("domain"));
    assert!(err("isqrt", &[Value::Float(4.0)]).contains("Integer"));
    assert!(err("isqrt", &[Value::Integer(1), Value::Integer(2)]).contains("exactly 1"));
}

#[test]
fn ipow_values_domain_overflow() {
    assert_eq!(
        ok("ipow", &[Value::Integer(2), Value::Integer(0)]),
        Value::Integer(1)
    );
    assert_eq!(
        ok("ipow", &[Value::Integer(2), Value::Integer(10)]),
        Value::Integer(1024)
    );
    assert_eq!(
        ok("ipow", &[Value::Integer(3), Value::Integer(4)]),
        Value::Integer(81)
    );
    assert_eq!(
        ok("ipow", &[Value::Integer(-2), Value::Integer(3)]),
        Value::Integer(-8)
    ); // negative base
    assert_eq!(
        ok("ipow", &[Value::Integer(5), Value::Integer(1)]),
        Value::Integer(5)
    );
    assert!(err("ipow", &[Value::Integer(2), Value::Integer(-1)]).contains("domain")); // neg exponent
    assert!(err("ipow", &[Value::Integer(10), Value::Integer(19)]).contains("overflow")); // 10^19 > i64::MAX
    assert!(err("ipow", &[Value::Float(2.0), Value::Integer(3)]).contains("Integer"));
    assert!(err("ipow", &[Value::Integer(2)]).contains("exactly 2"));
}

#[test]
fn mod_values_euclidean_and_zero() {
    assert_eq!(
        ok("mod", &[Value::Integer(7), Value::Integer(3)]),
        Value::Integer(1)
    );
    assert_eq!(
        ok("mod", &[Value::Integer(6), Value::Integer(3)]),
        Value::Integer(0)
    );
    // Euclidean: negative dividend → NON-NEGATIVE result for positive modulus (NOT Rust `%`, which gives -1).
    assert_eq!(
        ok("mod", &[Value::Integer(-1), Value::Integer(3)]),
        Value::Integer(2)
    );
    assert_eq!(
        ok("mod", &[Value::Integer(-7), Value::Integer(3)]),
        Value::Integer(2)
    );
    assert!(err("mod", &[Value::Integer(1), Value::Integer(0)]).contains("division by zero"));
    assert!(err("mod", &[Value::Integer(1), Value::Float(2.0)]).contains("Integer"));
}

/// `eval_math_call` returns `None` for non-math names (caller falls through) — shared-source contract intact.
#[test]
fn non_math_falls_through() {
    assert!(eval_math_call("filter", &[]).is_none());
    assert!(eval_math_call("ipow", &[Value::Integer(2), Value::Integer(3)]).is_some());
}

// ── compiler → VM (real bytecode), and the eval_ast/HOF path (parity) ────────────────────────────────

fn lit_int(v: i64) -> serde_json::Value {
    json!({ "kind": "literal", "type_tag": "Integer", "value": v })
}
fn call(fn_name: &str, args: Vec<serde_json::Value>) -> serde_json::Value {
    json!({ "kind": "call", "fn": fn_name, "args": args })
}
async fn run_expr(expr: serde_json::Value) -> Result<Value, String> {
    let contract = json!({ "contract_id": "IntMod", "inputs": [], "expression": expr });
    let mut c = Compiler::new();
    let bc = c.compile(&contract)?;
    VM::new(None)
        .execute(&bc, &HashMap::new(), &HashMap::new())
        .await
}

/// A nested integer expression compiles and runs: `mod(ipow(2,10), 7)` = 1024 mod 7 = 2.
#[tokio::test]
async fn compiler_vm_nested_integer_expression() {
    let expr = call(
        "mod",
        vec![call("ipow", vec![lit_int(2), lit_int(10)]), lit_int(7)],
    );
    assert_eq!(run_expr(expr).await.unwrap(), Value::Integer(2));
}

/// `bloom_filter`-style hash uses `mod`: `mod((a*key + b), size)` with a=31,b=17,key=42,size=64
/// = (31*42+17) mod 64 = 1319 mod 64 = 39.
#[tokio::test]
async fn bloom_filter_style_hash_uses_mod() {
    let a_key =
        json!({ "kind": "binary_op", "op": "*", "left": lit_int(31), "right": lit_int(42) });
    let a_key_b = json!({ "kind": "binary_op", "op": "+", "left": a_key, "right": lit_int(17) });
    let expr = call("mod", vec![a_key_b, lit_int(64)]);
    assert_eq!(run_expr(expr).await.unwrap(), Value::Integer(39));
}

/// HOF/eval_ast parity: `isqrt` inside a `fold` lambda body. fold([16,9,4], 0, (acc,x) -> acc + isqrt(x))
/// = 4 + 3 + 2 = 9. Proves the integer math composes inside lambdas through the shared `eval_math_call`.
#[tokio::test]
async fn isqrt_inside_fold_lambda() {
    let contract = json!({
        "contract_id": "IntModHof", "inputs": [],
        "expression": {
            "kind": "map_reduce_aggregate",
            "source": { "kind": "array_literal", "items": [lit_int(16), lit_int(9), lit_int(4)] },
            "pipeline": [{
                "kind": "fold", "param_acc": "acc", "param_val": "x",
                "init": lit_int(0),
                "body": { "kind": "binary_op", "op": "+",
                          "left": { "kind": "ref", "name": "acc" },
                          "right": call("isqrt", vec![json!({ "kind": "ref", "name": "x" })]) }
            }]
        }
    });
    let mut c = Compiler::new();
    let bc = c.compile(&contract).unwrap();
    let r = VM::new(None)
        .execute(&bc, &HashMap::new(), &HashMap::new())
        .await
        .unwrap();
    assert_eq!(
        r,
        Value::Integer(9),
        "Σ isqrt(16,9,4) = 4+3+2 = 9 inside a fold lambda"
    );
}
