//! todo_error_contract_tests.rs — LAB-TODOAPP-API-ERROR-CONTRACT-P20
//!
//! Pins the v0 product error contract for the example Todo API — the APP-OWNED errors that are
//! observable on the SYNC path (no machine, no DB): route miss → 404, method mismatch → 405, missing
//! idempotency key → 400, invalid create body → 400. Each asserts the status and that no error body
//! leaks a DSN, bearer token, raw SQL, or a host-config path.
//!
//! Body SHAPE has two app families: framework-generated errors from the `.igweb` lowering (route miss,
//! method mismatch, keyless guard) keep the v0 `{"body": "<message>"}` shape; APP-AUTHORED errors in
//! `todo_handlers.ig` (invalid create body, account/todo not-found) now carry the typed envelope
//! `{"error": {"code", "message"}}` (LAB-TODOAPP-API-ERROR-ENVELOPE-IMPL-P43).
//!
//! Host-owned errors (read-denied 403, conflict 409, unauthorized 401, not-found via ReadThen 404) are
//! pinned on the machine path in `todo_postgres_async_runner_smoke_tests.rs`. The full contract table
//! lives in `examples/todo_postgres_app/API.md`.

use igniter_server::protocol::ServerApp;
use igniter_web::runner::build_app_from_dir;
use igniter_web::testkit::roundtrip;
use serde_json::Value;
use std::path::PathBuf;
use std::sync::Arc;

fn app() -> Arc<dyn ServerApp + Send + Sync> {
    build_app_from_dir(&PathBuf::from(format!(
        "{}/examples/todo_postgres_app",
        env!("CARGO_MANIFEST_DIR")
    )))
    .expect("build todo_postgres_app")
    .0
}

/// No error body may leak host-owned secrets or internals.
fn assert_no_leak(body: &Value) {
    let s = body.to_string().to_lowercase();
    for forbidden in [
        "postgres://",
        "password",
        "dsn",
        "bearer ",
        "select ",
        "insert into",
        "host.toml",
        "/tmp/",
    ] {
        assert!(
            !s.contains(forbidden),
            "error body must not leak `{forbidden}`: {body}"
        );
    }
}

/// App-owned `Respond` errors carry the message under `body` (the stable v0 shape).
fn assert_app_error(body: &Value, status_label: &str) {
    assert!(
        body.get("body").and_then(|v| v.as_str()).is_some(),
        "{status_label}: app error body must be {{\"body\": \"<message>\"}}; got {body}"
    );
    assert_no_leak(body);
}

// ── route miss → 404 ──────────────────────────────────────────────────────────────────────────────

#[test]
fn unknown_path_is_404() {
    let app = app();
    let (s, b) = roundtrip(&*app, "GET", "/nope/not/a/route", &[], "");
    assert_eq!(s, 404, "unknown path → 404; body={b}");
    assert_app_error(&b, "route-miss");
}

// ── method mismatch → 405 ─────────────────────────────────────────────────────────────────────────

#[test]
fn wrong_method_on_known_pattern_is_405() {
    let app = app();
    // DELETE on a known collection pattern → 405 (method not allowed), not 404.
    let (s, b) = roundtrip(&*app, "DELETE", "/accounts/7/todos", &[], "");
    assert_eq!(s, 405, "wrong method → 405; body={b}");
    assert_app_error(&b, "method-mismatch");
}

// ── missing idempotency key → 400 ─────────────────────────────────────────────────────────────────

#[test]
fn keyless_create_is_400() {
    let app = app();
    // Valid string body so the 400 is unambiguously the missing-key guard, not the body contract.
    let (s, b) = roundtrip(&*app, "POST", "/accounts/7/todos", &[], "\"Buy milk\"");
    assert_eq!(s, 400, "keyless create → 400; body={b}");
    assert_app_error(&b, "keyless");
}

// ── invalid create body → 400 (P35 object body contract) ──────────────────────────────────────────

#[test]
fn invalid_create_body_is_400() {
    let app = app();
    let key = &[("idempotency-key", "evt-err")][..];
    for (label, raw) in [
        ("object", "{}"),
        ("number", "5"),
        ("null", "null"),
        ("empty", ""),
    ] {
        let (s, b) = roundtrip(&*app, "POST", "/accounts/7/todos", key, raw);
        assert_eq!(s, 400, "{label} body → 400; body={b}");
        assert_no_leak(&b);
        // P43: this is an APP-AUTHORED error → typed envelope {"error":{"code","message"}}.
        assert_eq!(
            b["error"]["code"],
            Value::from("invalid_body"),
            "{label}: 400 carries the app error code; got {b}"
        );
        // The product 400 names the contract (a non-empty title), never the offending shape's contents.
        assert!(
            b["error"]["message"].as_str().unwrap_or("").contains("title"),
            "{label}: 400 message should explain the contract; got {b}"
        );
    }
}

// ── a valid create is NOT an error (observed 202 on the sync path) ─────────────────────────────────

#[test]
fn valid_create_is_not_an_error_shape() {
    let app = app();
    let key = &[("idempotency-key", "evt-ok")][..];
    let (s, b) = roundtrip(&*app, "POST", "/accounts/7/todos", key, "\"Buy milk\"");
    assert_eq!(s, 202, "valid create → 202 observed; body={b}");
    assert_eq!(b["target"], serde_json::json!("todo-create"));
    assert!(b.get("error").is_none(), "success carries no error field");
}
