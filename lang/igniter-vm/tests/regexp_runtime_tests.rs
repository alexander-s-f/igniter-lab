// tests/regexp_runtime_tests.rs — LAB-STDLIB-REGEXP-P3
// Runtime semantics for stdlib.regexp.{matches,capture} through the real bytecode VM (OP_CALL).
// Mirrors the P2 proof, now via the compiler-emitted qualified names + VM native dispatch.

use igniter_vm::compiler::Compiler;
use igniter_vm::value::Value;
use igniter_vm::vm::VM;
use serde_json::json;
use std::collections::HashMap;
use std::sync::Arc;

fn call(fn_name: &str, args: Vec<serde_json::Value>) -> serde_json::Value {
    json!({ "kind": "call", "fn": fn_name, "args": args })
}
fn lit_s(s: &str) -> serde_json::Value {
    json!({ "kind": "literal", "value": s })
}
fn lit_i(n: i64) -> serde_json::Value {
    json!({ "kind": "literal", "value": n })
}

async fn run(node: serde_json::Value) -> Result<Value, String> {
    let contract = json!({ "expression": node });
    let bc = Compiler::new().compile(&contract).expect("compile failed");
    VM::new(None).execute(&bc, &HashMap::new(), &HashMap::new()).await
}

fn s(v: &str) -> Value {
    Value::String(Arc::from(v))
}

// ── matches ──────────────────────────────────────────────────────────────────────────────────────
#[tokio::test]
async fn matches_anchored_and_unanchored() {
    assert_eq!(run(call("stdlib.regexp.matches", vec![lit_s("/todos/42"), lit_s("^/todos/([0-9]+)$")])).await, Ok(Value::Bool(true)));
    assert_eq!(run(call("stdlib.regexp.matches", vec![lit_s("/todos/x"), lit_s("^/todos/([0-9]+)$")])).await, Ok(Value::Bool(false)));
    assert_eq!(run(call("stdlib.regexp.matches", vec![lit_s("abc123"), lit_s("[0-9]+")])).await, Ok(Value::Bool(true)));
    assert_eq!(run(call("stdlib.regexp.matches", vec![lit_s("abc"), lit_s("[0-9]+")])).await, Ok(Value::Bool(false)));
}

// ── capture index semantics ────────────────────────────────────────────────────────────────────
#[tokio::test]
async fn capture_index_semantics() {
    let p = "^/todos/([0-9]+)$";
    assert_eq!(run(call("stdlib.regexp.capture", vec![lit_s("/todos/42"), lit_s(p), lit_i(0)])).await, Ok(s("/todos/42")));
    assert_eq!(run(call("stdlib.regexp.capture", vec![lit_s("/todos/42"), lit_s(p), lit_i(1)])).await, Ok(s("42")));
    assert_eq!(run(call("stdlib.regexp.capture", vec![lit_s("/todos/42"), lit_s(p), lit_i(2)])).await, Ok(Value::Nil)); // out-of-range → None
    assert_eq!(run(call("stdlib.regexp.capture", vec![lit_s("/todos/x"), lit_s(p), lit_i(1)])).await, Ok(Value::Nil)); // no match → None
    // optional unmatched group → None.
    assert_eq!(run(call("stdlib.regexp.capture", vec![lit_s("ab"), lit_s("^a(x)?b$"), lit_i(1)])).await, Ok(Value::Nil));
    assert_eq!(run(call("stdlib.regexp.capture", vec![lit_s("axb"), lit_s("^a(x)?b$"), lit_i(1)])).await, Ok(s("x")));
}

// ── IgWeb route pressure ─────────────────────────────────────────────────────────────────────────
#[tokio::test]
async fn route_pressure() {
    assert_eq!(run(call("stdlib.regexp.capture", vec![lit_s("/todos/42"), lit_s("^/todos/([0-9]+)$"), lit_i(1)])).await, Ok(s("42")));
    assert_eq!(run(call("stdlib.regexp.capture", vec![lit_s("/todos/42/done"), lit_s("^/todos/([0-9]+)/done$"), lit_i(1)])).await, Ok(s("42")));
    let nested = "^/accounts/([0-9]+)/todos/([0-9]+)$";
    assert_eq!(run(call("stdlib.regexp.capture", vec![lit_s("/accounts/7/todos/42"), lit_s(nested), lit_i(1)])).await, Ok(s("7")));
    assert_eq!(run(call("stdlib.regexp.capture", vec![lit_s("/accounts/7/todos/42"), lit_s(nested), lit_i(2)])).await, Ok(s("42")));
    assert_eq!(run(call("stdlib.regexp.capture", vec![lit_s("/webhooks/callrail"), lit_s("^/webhooks/([a-z0-9_-]+)$"), lit_i(1)])).await, Ok(s("callrail")));
    // mismatch is clean false / None — no panic.
    assert_eq!(run(call("stdlib.regexp.matches", vec![lit_s("/nope"), lit_s("^/webhooks/([a-z0-9_-]+)$")])).await, Ok(Value::Bool(false)));
}

// ── bare-name dispatch parity (un-rewritten) ─────────────────────────────────────────────────────
#[tokio::test]
async fn bare_names_also_dispatch() {
    assert_eq!(run(call("matches", vec![lit_s("/x/1"), lit_s("^/x/([0-9]+)$")])).await, Ok(Value::Bool(true)));
    assert_eq!(run(call("capture", vec![lit_s("/x/1"), lit_s("^/x/([0-9]+)$"), lit_i(1)])).await, Ok(s("1")));
}

// ── Unicode capture: substring, valid UTF-8 ──────────────────────────────────────────────────────
#[tokio::test]
async fn unicode_capture_substring() {
    assert_eq!(run(call("stdlib.regexp.capture", vec![lit_s("/todos/київ"), lit_s("^/todos/(.+)$"), lit_i(1)])).await, Ok(s("київ")));
}

// ── invalid pattern → operational error (never false/None) ───────────────────────────────────────
#[tokio::test]
async fn invalid_pattern_is_runtime_error() {
    assert!(run(call("stdlib.regexp.matches", vec![lit_s("x"), lit_s("(")])).await.is_err());
    assert!(run(call("stdlib.regexp.capture", vec![lit_s("x"), lit_s("["), lit_i(1)])).await.is_err());
    // lookaround + backref are rejected by the linear-time engine.
    assert!(run(call("stdlib.regexp.matches", vec![lit_s("foobar"), lit_s("foo(?=bar)")])).await.is_err());
    assert!(run(call("stdlib.regexp.matches", vec![lit_s("aa"), lit_s(r"(a)\1")])).await.is_err());
}
