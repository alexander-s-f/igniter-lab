// tests/igweb_adapter_tests.rs — LAB-IGNITER-WEB-ROUTING-ADAPTER-P5 (P8: consumes the igniter-web crate)
// Proves `.igweb` live behind igniter-server. The app is built by the `igniter_web` lab crate's
// builder — no hand-assembly, no `#[path]` support code.
#![cfg(feature = "machine")]

use igniter_server::protocol::{ServerApp, ServerDecision, ServerRequest, ServerResponse};
use igniter_web::testkit::{build_todo_app, roundtrip};
use serde_json::json;

#[test]
fn igweb_app_health_roundtrip() {
    let app = build_todo_app("adapter_health");
    let (status, _body) = roundtrip(&*app, "GET", "/health", &[], "");
    assert_eq!(status, 200, "GET /health → 200 through the server host");
}

#[test]
fn igweb_app_route_param_roundtrip() {
    let app = build_todo_app("adapter_param");
    let (status, body) = roundtrip(&*app, "GET", "/todos/42", &[], "");
    assert_eq!(status, 200);
    assert_eq!(body["body"], json!("42"), "captured id=42 flowed through the generated regexp");
}

#[test]
fn igweb_app_mutation_requires_idempotency_key() {
    let app = build_todo_app("adapter_keyless");
    assert_eq!(roundtrip(&*app, "POST", "/todos/42/done", &[], "").0, 400, "keyless mutating route → 400 before any effect");
}

#[test]
fn igweb_app_mutation_emits_invoke_effect() {
    let app = build_todo_app("adapter_effect");
    let (status, body) = roundtrip(&*app, "POST", "/todos/42/done", &[("idempotency-key", "k-9")], "{}");
    assert_eq!(status, 202, "InvokeEffect observed as 202 deferred (P2 host::execute)");
    assert_eq!(body["decision"], json!("invoke_effect"));
    assert_eq!(body["target"], json!("todo-done"));
    assert_eq!(body["idempotency_key"], json!("k-9"));
    assert!(body.get("capability_id").is_none());
    assert!(body.get("scope").is_none());
}

#[test]
fn igweb_app_unknown_and_method_refusals() {
    let app = build_todo_app("adapter_refusals");
    assert_eq!(roundtrip(&*app, "GET", "/missing", &[], "").0, 404, "unknown path → 404");
    assert_eq!(roundtrip(&*app, "POST", "/health", &[], "").0, 405, "wrong method → 405");
}

/// The host has no route table: a totally different app on the same host routes differently.
#[test]
fn server_host_has_no_route_table() {
    struct OtherApp;
    impl ServerApp for OtherApp {
        fn call(&self, req: ServerRequest) -> ServerDecision {
            let status = if req.path == "/only-here" { 200 } else { 404 };
            ServerDecision::Respond { response: ServerResponse::json(status, json!({})) }
        }
    }
    let other = OtherApp;
    assert_eq!(roundtrip(&other, "GET", "/health", &[], "").0, 404, "/health unknown to OtherApp — host holds no routes");
    assert_eq!(roundtrip(&other, "GET", "/only-here", &[], "").0, 200);
}
