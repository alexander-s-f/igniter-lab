//! map_body_proof_tests.rs — LAB-MACHINE-MAP-VALUE-AND-STDLIB-GET-P28
//!
//! Reconciliation proof: a JSON OBJECT input crosses `IgniterMachine::dispatch` into a Map-like value
//! (`Value::Record`, the live Map representation — no separate `Value::Map`), and the authored stdlib
//! `map_get` / `map_has_key` (normalized to `stdlib.map.get` / `stdlib.map.has_key`) execute end-to-end
//! through the machine (not just a direct VM helper). This is the runtime gate that
//! `LAB-TODOAPP-API-CREATE-OBJECT-BODY-READINESS-P25` flagged as "blocked on Value::Map / stdlib.map.get
//! VM support" — this test proves it is ALREADY LIVE.
//!
//! Authored surface: `.ig` calls the BARE names `map_get(...)` / `map_has_key(...)` (the dotted
//! `stdlib.map.*` form does not parse as a callee — it is the internal normalized name).
//!
//! Proves: present string title → "Buy milk"; missing title → fallback ""; has_key true/false; a body
//! carrying nested/non-string values (bool, int) does not panic; the result serializes back to clean JSON.
//! Ergonomics finding: `map_get` returns `Option[Unknown]`, so a `String`-typed output needs a typed
//! coercion (an `Unknown` output here) — the typed-string gap the Todo object-body card must address.

use igniter_machine::machine::IgniterMachine;
use serde_json::json;

// Two pure contracts over a `Map[String, Unknown]` input — the exact P28 fixture shape.
const SRC: &str = "\
module MapBodyProof

pure contract TitleFromBody {
  input body : Map[String, Unknown]
  compute maybe_title = map_get(body, \"title\")
  compute title = or_else(maybe_title, \"\")
  output title : Unknown
}

pure contract HasTitle {
  input body : Map[String, Unknown]
  compute present = map_has_key(body, \"title\")
  output present : Bool
}
";

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}

/// Load both contracts once (the registry holds all contracts in the source; `dispatch` resolves any).
fn machine() -> IgniterMachine {
    let m = IgniterMachine::new(None, "in_memory").unwrap();
    m.load_contract_source(SRC, "TitleFromBody")
        .expect("Map[String, Unknown] input + stdlib.map.* must compile (gate live)");
    m
}

#[test]
fn present_string_title_returns_value() {
    rt().block_on(async {
        let m = machine();
        // A body with a string title AND nested/non-string values (bool, int) → must not panic.
        let out = m
            .dispatch(
                "TitleFromBody",
                json!({ "body": { "title": "Buy milk", "done": false, "n": 1 } }),
            )
            .await
            .expect("dispatch TitleFromBody");
        // `dispatch` returns the bare single-output value (a scalar here), not a `{title: …}` wrapper.
        assert_eq!(out, json!("Buy milk"), "present title → value; out={out}");
    });
}

#[test]
fn missing_title_returns_fallback() {
    rt().block_on(async {
        let m = machine();
        let out = m
            .dispatch("TitleFromBody", json!({ "body": { "done": true, "n": 2 } }))
            .await
            .expect("dispatch TitleFromBody (no title)");
        assert_eq!(out, json!(""), "missing title → fallback empty; out={out}");
    });
}

#[test]
fn has_key_true_when_present() {
    rt().block_on(async {
        let m = machine();
        let out = m
            .dispatch("HasTitle", json!({ "body": { "title": "Buy milk" } }))
            .await
            .expect("dispatch HasTitle (present)");
        assert_eq!(out, json!(true), "has_key present → true; out={out}");
    });
}

#[test]
fn has_key_false_when_absent() {
    rt().block_on(async {
        let m = machine();
        let out = m
            .dispatch("HasTitle", json!({ "body": { "other": "x" } }))
            .await
            .expect("dispatch HasTitle (absent)");
        assert_eq!(out, json!(false), "has_key absent → false; out={out}");
    });
}

#[test]
fn empty_map_is_safe() {
    rt().block_on(async {
        let m = machine();
        // Empty object → no key; get → fallback, has_key → false. No panic.
        let title = m
            .dispatch("TitleFromBody", json!({ "body": {} }))
            .await
            .expect("dispatch empty");
        assert_eq!(title, json!(""));
        let present = m
            .dispatch("HasTitle", json!({ "body": {} }))
            .await
            .expect("dispatch empty has_key");
        assert_eq!(present, json!(false));
    });
}
