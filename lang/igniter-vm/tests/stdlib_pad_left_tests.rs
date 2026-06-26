// LAB-LANG-STRING-PAD-LEFT-P3
//
// `pad_left(text : String, width : Integer, pad : String) -> String` — a rune-counted table-column primitive
// (NOT a formatter). Tested directly on the shared helper `stdlib_string_pad_left` and through the real
// compiler→VM on BOTH dispatch paths: bytecode `OP_CALL` (the required `pad_left(to_text(7),3,"0")`
// composition) and `eval_ast`/HOF (inside a `fold` lambda body), proving parity.

use igniter_vm::compiler::Compiler;
use igniter_vm::value::Value;
use igniter_vm::vm::{stdlib_string_pad_left, VM};
use serde_json::json;
use std::collections::HashMap;
use std::sync::Arc;

fn s(v: &str) -> Value {
    Value::String(Arc::from(v))
}

/// Direct helper call: `pad_left(text, width, pad)`.
fn pl(text: &str, width: i64, pad: &str) -> Result<Value, String> {
    stdlib_string_pad_left(&[s(text), Value::Integer(width), s(pad)])
}

// ── direct semantics ────────────────────────────────────────────────────────────────────────────────

#[test]
fn pad_left_card_examples() {
    assert_eq!(pl("7", 3, "0"), Ok(s("007")), "single-char pad");
    assert_eq!(pl("abc", 2, "0"), Ok(s("abc")), "no-op when width <= len");
    assert_eq!(
        pl("x", 5, "ab"),
        Ok(s("ababx")),
        "multi-char pad, final fragment truncated"
    );
    assert_eq!(
        pl("é", 3, " "),
        Ok(s("  é")),
        "width counts Unicode scalars, not bytes"
    );
}

#[test]
fn pad_left_no_op_and_equal_width() {
    assert_eq!(pl("abc", 3, "0"), Ok(s("abc")), "equal width → unchanged");
    assert_eq!(
        pl("abcd", 2, "0"),
        Ok(s("abcd")),
        "wider text never truncated"
    );
}

#[test]
fn pad_left_multichar_exact_and_partial() {
    assert_eq!(
        pl("x", 4, "ab"),
        Ok(s("abax")),
        "3 pad chars: a,b,a (partial final repetition)"
    );
    assert_eq!(
        pl("x", 7, "ab"),
        Ok(s("abababx")),
        "6 pad chars: a,b,a,b,a,b"
    );
}

#[test]
fn pad_left_unicode_scalar_count() {
    // "naïve" is 5 scalar chars (ï precomposed); padding to 7 prepends exactly 2.
    assert_eq!(pl("naïve", 7, "."), Ok(s("..naïve")));
    // A multi-byte pad char counts as ONE scalar of width.
    assert_eq!(pl("x", 3, "→"), Ok(s("→→x")));
}

#[test]
fn pad_left_negative_and_zero_width_are_noops() {
    assert_eq!(pl("abc", 0, "0"), Ok(s("abc")), "zero width → unchanged");
    assert_eq!(
        pl("abc", -5, "0"),
        Ok(s("abc")),
        "negative width → unchanged (total, no error)"
    );
}

#[test]
fn pad_left_empty_pad_rejected_only_when_padding_needed() {
    assert!(
        pl("x", 5, "").is_err(),
        "empty pad with padding needed → domain error"
    );
    assert_eq!(
        pl("abc", 2, ""),
        Ok(s("abc")),
        "empty pad is fine when no padding is needed (pad unused)"
    );
}

#[test]
fn pad_left_arity_errors() {
    assert!(
        stdlib_string_pad_left(&[s("x"), Value::Integer(3)]).is_err(),
        "2-arg errors"
    );
    assert!(
        stdlib_string_pad_left(&[s("x"), Value::Integer(3), s("0"), s("extra")]).is_err(),
        "4-arg errors"
    );
}

// ── compiler→VM: OP_CALL (composition with to_text) + eval_ast (fold lambda) parity ──────────────────

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

/// The card's composition proof, through the real bytecode `OP_CALL` path:
/// `pad_left(to_text(7), 3, "0") == "007"` (numeric formatting composes, no formatter primitive).
#[tokio::test]
async fn pad_left_to_text_through_compiler_vm() {
    let expr = call(
        "pad_left",
        vec![call("to_text", vec![lit_int(7)]), lit_int(3), lit_str("0")],
    );
    let c = json!({ "contract_id": "Pad", "inputs": [], "expression": expr });
    assert_eq!(run(c).await, Ok(s("007")), "pad_left(to_text(7), 3, \"0\")");
}

/// eval_ast parity: `pad_left` inside a `fold` lambda body runs identically (single-source dispatch).
/// `fold(["7"], "", (acc, x) -> pad_left(x, 3, "0"))` → "007".
#[tokio::test]
async fn pad_left_inside_fold_lambda_runs() {
    let contract = json!({
        "contract_id": "PadHof",
        "inputs": [],
        "expression": {
            "kind": "map_reduce_aggregate",
            "source": { "kind": "array_literal", "items": [lit_str("7")] },
            "pipeline": [{
                "kind": "fold",
                "param_acc": "acc",
                "param_val": "x",
                "init": lit_str(""),
                "body": call("pad_left", vec![json!({ "kind": "ref", "name": "x" }), lit_int(3), lit_str("0")])
            }]
        }
    });
    assert_eq!(
        run(contract).await,
        Ok(s("007")),
        "pad_left inside fold lambda"
    );
}
