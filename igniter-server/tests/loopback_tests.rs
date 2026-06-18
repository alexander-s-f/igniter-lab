//! Real loopback HTTP proofs for the Rack-like server (LAB-MACHINE-IGNITER-SERVER-BINARY-P2).
//!
//! Each test binds `127.0.0.1:0`, serves one request on a thread through a `ServerApp`, and drives a
//! raw HTTP/1.1 client over the socket. No public listener, no framework, no machine, no DB.

use igniter_server::fixture::DemoApp;
use igniter_server::host::serve_once;
use igniter_server::protocol::{ServerApp, ServerDecision, ServerRequest, ServerResponse};
use serde_json::{json, Value};
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::thread;

/// Send a raw HTTP/1.1 request to `addr`, return `(status_code, body_json)`.
fn roundtrip(addr: &str, method: &str, path: &str, body: &Value, extra_headers: &[(&str, &str)]) -> (u16, Value) {
    let body_bytes = serde_json::to_vec(body).unwrap();
    let mut req = format!("{method} {path} HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\n");
    for (k, v) in extra_headers {
        req.push_str(&format!("{k}: {v}\r\n"));
    }
    req.push_str(&format!("Content-Length: {}\r\n\r\n", body_bytes.len()));

    let mut stream = TcpStream::connect(addr).unwrap();
    stream.write_all(req.as_bytes()).unwrap();
    stream.write_all(&body_bytes).unwrap();
    stream.flush().unwrap();

    let mut raw = Vec::new();
    stream.read_to_end(&mut raw).unwrap();
    let text = String::from_utf8_lossy(&raw);
    let status: u16 = text
        .split_whitespace()
        .nth(1)
        .and_then(|s| s.parse().ok())
        .unwrap_or(0);
    let body_start = text.find("\r\n\r\n").map(|i| i + 4).unwrap_or(text.len());
    let body_json: Value = serde_json::from_str(text[body_start..].trim()).unwrap_or(Value::Null);
    (status, body_json)
}

/// Serve exactly one request through `app` on a fresh loopback listener; returns the bound addr.
fn serve_one_in_thread(app: impl ServerApp + Send + 'static) -> String {
    let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
    let addr = listener.local_addr().unwrap().to_string();
    thread::spawn(move || {
        serve_once(&listener, &app).unwrap();
    });
    addr
}

#[test]
fn health_returns_200_through_server_app_call() {
    let addr = serve_one_in_thread(DemoApp);
    let (status, body) = roundtrip(&addr, "GET", "/health", &Value::Null, &[]);
    assert_eq!(status, 200);
    assert_eq!(body["ok"], json!(true));
}

#[test]
fn unknown_route_is_404_from_app_not_host() {
    let addr = serve_one_in_thread(DemoApp);
    let (status, body) = roundtrip(&addr, "GET", "/nope", &Value::Null, &[]);
    assert_eq!(status, 404);
    assert_eq!(body["error"], json!("no route"));
}

#[test]
fn effect_route_is_observed_invoke_effect_decision() {
    let addr = serve_one_in_thread(DemoApp);
    let (status, body) = roundtrip(
        &addr,
        "POST",
        "/effect/demo",
        &json!({ "event": "lead" }),
        &[("x-correlation-id", "corr-9"), ("idempotency-key", "evt-9")],
    );
    // P2: the decision is observable; execution is deferred to P3.
    assert_eq!(status, 202);
    assert_eq!(body["decision"], json!("invoke_effect"));
    assert_eq!(body["target"], json!("demo-effect"));
    assert_eq!(body["execution"], json!("deferred_to_p3"));
    assert_eq!(body["correlation_id"], json!("corr-9"));
    assert_eq!(body["idempotency_key"], json!("evt-9"));
    // the app decision carries no effect identity — none can leak through the protocol.
    assert!(body.get("capability_id").is_none());
    assert!(body.get("scope").is_none());
}

#[test]
fn invoke_route_is_observed_invoke_decision() {
    let addr = serve_one_in_thread(DemoApp);
    let (status, body) = roundtrip(&addr, "POST", "/invoke/demo", &json!({ "x": 1 }), &[]);
    assert_eq!(status, 202);
    assert_eq!(body["decision"], json!("invoke"));
    assert_eq!(body["target"], json!("demo-invoke"));
}

/// The host owns NO route meaning: the same `serve_once` host, given a DIFFERENT app, routes
/// differently. `/health` (which `DemoApp` answers 200) is a 404 here, and a path the host has never
/// heard of answers 200 — proving routing lives in the app, not server config.
#[test]
fn routing_lives_in_app_not_server_config() {
    struct OtherApp;
    impl ServerApp for OtherApp {
        fn call(&self, req: ServerRequest) -> ServerDecision {
            match (req.method.as_str(), req.path.as_str()) {
                ("GET", "/totally-custom") => ServerDecision::Respond {
                    response: ServerResponse::json(200, json!({ "from": "other-app" })),
                },
                _ => ServerDecision::Respond {
                    response: ServerResponse::json(404, json!({ "error": "other-app: no route" })),
                },
            }
        }
    }

    // /health is 404 under OtherApp (DemoApp answered it 200) — the host knows nothing about it.
    let addr = serve_one_in_thread(OtherApp);
    let (status, body) = roundtrip(&addr, "GET", "/health", &Value::Null, &[]);
    assert_eq!(status, 404);
    assert_eq!(body["error"], json!("other-app: no route"));

    // and a path only OtherApp knows answers 200 on the same host code.
    let addr2 = serve_one_in_thread(OtherApp);
    let (status2, body2) = roundtrip(&addr2, "GET", "/totally-custom", &Value::Null, &[]);
    assert_eq!(status2, 200);
    assert_eq!(body2["from"], json!("other-app"));
}
