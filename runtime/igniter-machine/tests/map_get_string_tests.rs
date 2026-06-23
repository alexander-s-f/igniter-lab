//! map_get_string_tests.rs — LAB-MACHINE-MAP-GET-STRING-P34
//!
//! Proves the typed, fail-closed string extractor `map_get_string` (normalized name
//! `stdlib.map.get_string`) end-to-end through `IgniterMachine::dispatch` over a `Map[String, Unknown]`
//! input (the live Map runtime proven by P28). Authored surface is the BARE name `map_get_string(...)`.
//!
//! Semantics (all proven below):
//!   present STRING value → Some(value)   (here: returns the raw string)
//!   missing key          → None          (Nil → or_else fallback)
//!   present NON-STRING    → None          (fail closed; e.g. bool/int/object)
//!   null value           → None
//!
//! Plus a negative typecheck: a clearly-non-Map first arg is rejected at compile time (OOF-TY0).

use igniter_machine::machine::IgniterMachine;
use serde_json::json;

// `title_opt = map_get_string(body, "title")` → Some(string)|None; or_else makes a probe-able scalar:
// present string → the string; everything else → the "<<none>>" sentinel (so None is observable).
const SRC: &str = "\
module MapGetStringProof

pure contract TitleString {
  input body : Map[String, Unknown]
  compute title_opt = map_get_string(body, \"title\")
  compute title = or_else(title_opt, \"<<none>>\")
  output title : Unknown
}
";

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}

fn machine() -> IgniterMachine {
    let m = IgniterMachine::new(None, "in_memory").unwrap();
    m.load_contract_source(SRC, "TitleString")
        .expect("map_get_string must compile + typecheck (Option[String])");
    m
}

async fn title_for(body: serde_json::Value) -> serde_json::Value {
    machine()
        .dispatch("TitleString", json!({ "body": body }))
        .await
        .expect("dispatch TitleString")
}

#[test]
fn present_string_returns_some_value() {
    rt().block_on(async {
        // Body carries a string title plus nested/non-string fields — must not panic.
        let out = title_for(json!({ "title": "Buy milk", "done": false, "n": 1 })).await;
        assert_eq!(out, json!("Buy milk"), "present string title → Some(value); out={out}");
    });
}

#[test]
fn missing_key_returns_none() {
    rt().block_on(async {
        let out = title_for(json!({ "other": "x" })).await;
        assert_eq!(out, json!("<<none>>"), "missing key → None; out={out}");
    });
}

#[test]
fn present_non_string_returns_none() {
    rt().block_on(async {
        // title is a number / bool / object → fail closed to None, NOT a stringified value.
        for bad in [json!(5), json!(true), json!({ "nested": "x" }), json!([1, 2])] {
            let out = title_for(json!({ "title": bad })).await;
            assert_eq!(out, json!("<<none>>"), "non-string title → None; bad={bad} out={out}");
        }
    });
}

#[test]
fn null_value_returns_none() {
    rt().block_on(async {
        let out = title_for(json!({ "title": null })).await;
        assert_eq!(out, json!("<<none>>"), "null title → None; out={out}");
    });
}

#[test]
fn empty_map_returns_none() {
    rt().block_on(async {
        let out = title_for(json!({})).await;
        assert_eq!(out, json!("<<none>>"), "empty map → None");
    });
}

// ── negative typecheck: a clearly-non-Map first arg is rejected at compile time ───────────────────

#[test]
fn non_map_first_arg_rejected_at_typecheck() {
    let bad_src = "\
module MapGetStringBad

pure contract Bad {
  input n : Integer
  compute title = map_get_string(n, \"title\")
  output title : Unknown
}
";
    let m = IgniterMachine::new(None, "in_memory").unwrap();
    let err = m
        .load_contract_source(bad_src, "Bad")
        .expect_err("non-Map first arg must be a typecheck error");
    let msg = format!("{err:?}");
    assert!(
        msg.contains("OOF-TY0") && msg.contains("get_string"),
        "expected OOF-TY0 for non-Map first arg; got {msg}"
    );
}
