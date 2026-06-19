//! Verification for the external `ServerApp` example (LAB-MACHINE-IGNITER-SERVER-EXAMPLE-APP-P10).
//! Machine-free. The example is the discoverable teaching artifact; this proves its behavior.

use igniter_server::middleware::ServerAppExt;
use igniter_server::protocol::{ServerApp, ServerDecision, ServerRequest};
use serde_json::{json, Value};
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::thread;

// Include the example exactly as a third-party consumer would compile it — proving it is real,
// reusable `ServerApp` code, not a hidden test-only shim.
#[path = "../examples/server_app_basic.rs"]
mod example_app;
use example_app::ExampleApp;

/// Build a `ServerRequest` the way the host parser would (headers lower-cased; correlation_id /
/// idempotency_key promoted from headers to typed fields).
fn req(method: &str, path: &str, headers: &[(&str, &str)], body: Value) -> ServerRequest {
    let mut r = ServerRequest::new(method, path, body);
    for (k, v) in headers {
        r.headers.insert(k.to_string(), v.to_string());
    }
    r.correlation_id = r.headers.get("x-correlation-id").cloned();
    r.idempotency_key = r.headers.get("idempotency-key").cloned();
    r
}

fn invoke_effect(d: &ServerDecision) -> (&str, &Value, &Option<String>, &Option<String>) {
    match d {
        ServerDecision::InvokeEffect {
            target,
            input,
            correlation_id,
            idempotency_key,
        } => (target.as_str(), input, correlation_id, idempotency_key),
        other => panic!("expected InvokeEffect, got {other:?}"),
    }
}

fn respond_status(d: &ServerDecision) -> u16 {
    match d {
        ServerDecision::Respond { response } => response.status,
        other => panic!("expected Respond, got {other:?}"),
    }
}

#[test]
fn health_returns_respond_200() {
    let d = ExampleApp.call(req("GET", "/health", &[], Value::Null));
    assert_eq!(respond_status(&d), 200);
}

#[test]
fn post_tickets_with_key_is_invoke_effect() {
    let d = ExampleApp.call(req(
        "POST",
        "/tickets",
        &[("idempotency-key", "tkt-1001"), ("x-correlation-id", "corr-1")],
        json!({ "title": "printer jam", "priority": "high", "secret": "should-not-leak-but-app-ignores" }),
    ));
    let (target, input, correlation_id, idempotency_key) = invoke_effect(&d);
    assert_eq!(target, "ticket-create");
    assert_eq!(idempotency_key.as_deref(), Some("tkt-1001"));
    assert_eq!(
        correlation_id.as_deref(),
        Some("corr-1"),
        "correlation propagated"
    );
    // sanitized input: only the declared clean fields, app-controlled defaults.
    assert_eq!(input["title"], json!("printer jam"));
    assert_eq!(input["priority"], json!("high"));
}

#[test]
fn keyless_post_tickets_is_400_no_effect() {
    let d = ExampleApp.call(req("POST", "/tickets", &[], json!({ "title": "no key" })));
    assert_eq!(
        respond_status(&d),
        400,
        "keyless → 400, never a silent fresh effect"
    );
}

#[test]
fn unknown_route_is_404() {
    let d = ExampleApp.call(req("DELETE", "/whatever", &[], Value::Null));
    assert_eq!(respond_status(&d), 404);
}

#[test]
fn decision_carries_no_privileged_effect_identity() {
    let d = ExampleApp.call(req(
        "POST",
        "/tickets",
        &[("idempotency-key", "tkt-9")],
        json!({ "title": "x" }),
    ));
    let encoded = serde_json::to_value(&d).unwrap();
    assert_eq!(encoded["kind"], json!("invoke_effect"));
    assert!(encoded.get("capability_id").is_none());
    assert!(encoded.get("operation").is_none());
    assert!(encoded.get("scope").is_none());
}

#[test]
fn identity_names_the_example() {
    assert_eq!(ExampleApp.identity().name, "ticket-intake-example");
    assert_eq!(ExampleApp.identity().version, "v0");
}

#[test]
fn composes_with_p8_middleware() {
    // Auth(outer) -> Trace -> ExampleApp. Middleware never routes; the app still owns routing.
    let stack = ExampleApp.with_trace().with_auth("demo-secret");

    // missing token → Auth short-circuits to 401; the app is never reached.
    let unauth = stack.call(req("GET", "/health", &[], Value::Null));
    assert_eq!(respond_status(&unauth), 401);

    // valid token → flows through Trace + app; /health is 200 and Trace decorated the correlation id.
    let ok = stack.call(req(
        "GET",
        "/health",
        &[("authorization", "Bearer demo-secret")],
        Value::Null,
    ));
    match ok {
        ServerDecision::Respond { response } => {
            assert_eq!(response.status, 200);
            assert!(
                response.headers.contains_key("x-correlation-id"),
                "TraceApp decorated the response"
            );
        }
        other => panic!("expected Respond, got {other:?}"),
    }
}

/// Optional: prove the example serves over a real loopback socket through the P2 host (machine-free).
#[test]
fn health_over_real_loopback_host() {
    let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
    let addr = listener.local_addr().unwrap().to_string();
    let server = thread::spawn(move || {
        igniter_server::host::serve_once(&listener, &ExampleApp).unwrap();
    });

    let mut stream = TcpStream::connect(&addr).unwrap();
    stream
        .write_all(b"GET /health HTTP/1.1\r\nHost: x\r\nContent-Length: 0\r\n\r\n")
        .unwrap();
    stream.flush().unwrap();
    let mut raw = Vec::new();
    stream.read_to_end(&mut raw).unwrap();
    let text = String::from_utf8_lossy(&raw);
    let status: u16 = text
        .split_whitespace()
        .nth(1)
        .and_then(|s| s.parse().ok())
        .unwrap_or(0);

    server.join().unwrap();
    assert_eq!(status, 200);
    assert!(text.contains("ticket-intake-example"));
}
