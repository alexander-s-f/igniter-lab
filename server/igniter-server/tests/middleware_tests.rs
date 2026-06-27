//! Generic wrapper-middleware proofs (LAB-MACHINE-IGNITER-SERVER-MIDDLEWARE-P8). Machine-free.
//!
//! Proves: sequential decoration; auth + body-limit short-circuit (inner never called); middleware is
//! route-agnostic; effect identity cannot be injected; `ReloadableApp` wraps the whole stack; the
//! composed stack is `Send + Sync`; no hidden cross-request state.

use igniter_server::host::serve_bounded_reloadable;
use igniter_server::middleware::{AuthTokenApp, BodyLimitApp, ServerAppExt, TraceApp};
use igniter_server::protocol::{
    AppIdentity, ServerApp, ServerDecision, ServerRequest, ServerResponse,
};
use igniter_server::reload::ReloadableApp;
use serde_json::{Value, json};
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;

/// Test app that counts calls and records the requests it saw (so we can assert what middleware
/// injected). The counter/record is TEST instrumentation, not middleware state.
struct RecordingApp {
    calls: Arc<AtomicUsize>,
    seen: Arc<Mutex<Vec<ServerRequest>>>,
    version: String,
}
impl RecordingApp {
    fn new(version: &str) -> (Self, Arc<AtomicUsize>, Arc<Mutex<Vec<ServerRequest>>>) {
        let calls = Arc::new(AtomicUsize::new(0));
        let seen = Arc::new(Mutex::new(Vec::new()));
        (
            Self {
                calls: calls.clone(),
                seen: seen.clone(),
                version: version.to_string(),
            },
            calls,
            seen,
        )
    }
}
impl ServerApp for RecordingApp {
    fn call(&self, req: ServerRequest) -> ServerDecision {
        self.calls.fetch_add(1, Ordering::SeqCst);
        self.seen.lock().unwrap().push(req.clone());
        ServerDecision::Respond {
            response: ServerResponse::json(200, json!({ "app": self.version, "ok": true })),
        }
    }
    fn identity(&self) -> AppIdentity {
        AppIdentity::new("rec", &self.version, "")
    }
}

/// Panics if ever called — proves a short-circuiting wrapper did NOT delegate.
struct PanicApp;
impl ServerApp for PanicApp {
    fn call(&self, _req: ServerRequest) -> ServerDecision {
        panic!("inner app must not be called when middleware short-circuits");
    }
}

/// Routes 200 only for GET <ok_path>; proves routing lives in the inner app, not middleware.
struct RouteApp {
    version: String,
    ok_path: String,
}
impl ServerApp for RouteApp {
    fn call(&self, req: ServerRequest) -> ServerDecision {
        if req.method == "GET" && req.path == self.ok_path {
            ServerDecision::Respond {
                response: ServerResponse::json(200, json!({ "app_version": self.version })),
            }
        } else {
            ServerDecision::Respond {
                response: ServerResponse::json(404, json!({ "error": "no route" })),
            }
        }
    }
    fn identity(&self) -> AppIdentity {
        AppIdentity::new("route", &self.version, "")
    }
}

fn req(method: &str, path: &str, headers: &[(&str, &str)], body: Value) -> ServerRequest {
    let mut r = ServerRequest::new(method, path, body);
    for (k, v) in headers {
        r.headers.insert(k.to_string(), v.to_string());
    }
    r.correlation_id = r.headers.get("x-correlation-id").cloned();
    r
}

// 1 ── sequential decoration: stack composes, inner sees injected headers, response decorated ──────
#[test]
fn sequential_decoration_preserves_inner_and_decorates() {
    let (rec, calls, seen) = RecordingApp::new("v1");
    // BodyLimit -> Auth -> Trace -> rec
    let stack = rec.with_trace().with_auth("TOK").with_body_limit(1_000_000);

    let decision = stack.call(req(
        "POST",
        "/x",
        &[("authorization", "Bearer TOK")],
        json!({}),
    ));

    assert_eq!(calls.load(Ordering::SeqCst), 1, "inner called exactly once");
    let inner_req = &seen.lock().unwrap()[0];
    assert_eq!(
        inner_req.headers.get("x-auth-ok").map(String::as_str),
        Some("true"),
        "auth injected"
    );
    assert!(
        inner_req.correlation_id.is_some(),
        "trace injected a correlation id"
    );
    assert!(
        inner_req
            .headers
            .get("x-correlation-id")
            .unwrap()
            .starts_with("corr-"),
        "deterministic corr"
    );
    match decision {
        ServerDecision::Respond { response } => {
            assert_eq!(response.status, 200);
            assert!(
                response.headers.contains_key("x-correlation-id"),
                "response decorated by trace"
            );
        }
        other => panic!("expected Respond, got {other:?}"),
    }
}

// 2 ── auth short-circuit: invalid token → 401, inner never called ─────────────────────────────────
#[test]
fn short_circuit_auth_does_not_call_inner() {
    let stack = AuthTokenApp::new(PanicApp, "TOK");
    // missing token
    match stack.call(req("POST", "/x", &[], json!({}))) {
        ServerDecision::Respond { response } => assert_eq!(response.status, 401),
        other => panic!("expected 401 Respond, got {other:?}"),
    }
    // wrong token
    match stack.call(req(
        "POST",
        "/x",
        &[("authorization", "Bearer NOPE")],
        json!({}),
    )) {
        ServerDecision::Respond { response } => assert_eq!(response.status, 401),
        other => panic!("expected 401 Respond, got {other:?}"),
    }
}

#[test]
fn auth_empty_expected_token_fails_closed() {
    let stack = AuthTokenApp::new(PanicApp, "");
    match stack.call(req(
        "POST",
        "/x",
        &[("authorization", "Bearer ")],
        json!({}),
    )) {
        ServerDecision::Respond { response } => assert_eq!(response.status, 401),
        other => panic!("expected 401 Respond, got {other:?}"),
    }
}

#[test]
fn auth_strips_inbound_auth_ok_spoof() {
    let stack = AuthTokenApp::new(PanicApp, "TOK");
    match stack.call(req("POST", "/x", &[("x-auth-ok", "true")], json!({}))) {
        ServerDecision::Respond { response } => assert_eq!(response.status, 401),
        other => panic!("expected 401 Respond, got {other:?}"),
    }

    let (rec, calls, seen) = RecordingApp::new("v1");
    let stack = AuthTokenApp::new(rec, "TOK");
    match stack.call(req(
        "POST",
        "/x",
        &[("authorization", "Bearer TOK"), ("x-auth-ok", "spoofed")],
        json!({}),
    )) {
        ServerDecision::Respond { response } => assert_eq!(response.status, 200),
        other => panic!("expected 200 Respond, got {other:?}"),
    }
    assert_eq!(calls.load(Ordering::SeqCst), 1);
    let inner_req = &seen.lock().unwrap()[0];
    assert_eq!(
        inner_req.headers.get("x-auth-ok").map(String::as_str),
        Some("true")
    );
}

// 3 ── body-limit short-circuit: oversized body → 413, inner never called ──────────────────────────
#[test]
fn short_circuit_body_limit_does_not_call_inner() {
    let stack = BodyLimitApp::new(PanicApp, 10);
    let big = json!({ "data": "xxxxxxxxxxxxxxxxxxxx" }); // serializes well past 10 bytes
    match stack.call(req("POST", "/x", &[], big)) {
        ServerDecision::Respond { response } => assert_eq!(response.status, 413),
        other => panic!("expected 413 Respond, got {other:?}"),
    }
}

// 4 ── route-agnostic: same wrapper, different inner app → routing follows the inner ───────────────
#[test]
fn middleware_is_route_agnostic() {
    let stack_a = TraceApp::new(RouteApp {
        version: "a".into(),
        ok_path: "/a".into(),
    });
    let stack_b = TraceApp::new(RouteApp {
        version: "b".into(),
        ok_path: "/b".into(),
    });

    let status = |d: ServerDecision| match d {
        ServerDecision::Respond { response } => response.status,
        _ => 0,
    };
    assert_eq!(
        status(stack_a.call(req("GET", "/a", &[], Value::Null))),
        200
    );
    assert_eq!(
        status(stack_a.call(req("GET", "/b", &[], Value::Null))),
        404,
        "wrapper added no route for /b"
    );
    assert_eq!(
        status(stack_b.call(req("GET", "/b", &[], Value::Null))),
        200,
        "routing follows the inner app"
    );
}

// 5 ── effect identity not injectable: InvokeEffect passes through unchanged, no privileged keys ────
#[test]
fn middleware_cannot_inject_effect_identity() {
    struct EffectApp;
    impl ServerApp for EffectApp {
        fn call(&self, _req: ServerRequest) -> ServerDecision {
            ServerDecision::InvokeEffect {
                target: "demo-target".into(),
                input: json!({ "x": 1 }),
                correlation_id: None,
                idempotency_key: Some("K1".into()),
            }
        }
    }
    let stack = EffectApp.with_trace().with_auth("TOK");
    let decision = stack.call(req(
        "POST",
        "/x",
        &[("authorization", "Bearer TOK")],
        json!({}),
    ));
    let encoded = serde_json::to_value(&decision).unwrap();
    assert_eq!(
        encoded["kind"],
        json!("invoke_effect"),
        "decision kind unchanged by middleware"
    );
    assert_eq!(encoded["target"], json!("demo-target"));
    assert!(encoded.get("capability_id").is_none());
    assert!(encoded.get("operation").is_none());
    assert!(encoded.get("scope").is_none());
}

// 6 ── ReloadableApp wraps the WHOLE composed stack (middleware config + inner swap together) ──────
fn roundtrip(addr: &str, method: &str, path: &str, headers: &[(&str, &str)]) -> u16 {
    let mut h = format!("{method} {path} HTTP/1.1\r\nHost: x\r\n");
    for (k, v) in headers {
        h.push_str(&format!("{k}: {v}\r\n"));
    }
    h.push_str("Content-Length: 0\r\n\r\n");
    let mut s = TcpStream::connect(addr).unwrap();
    s.write_all(h.as_bytes()).unwrap();
    s.flush().unwrap();
    let mut raw = Vec::new();
    s.read_to_end(&mut raw).unwrap();
    String::from_utf8_lossy(&raw)
        .split_whitespace()
        .nth(1)
        .and_then(|x| x.parse().ok())
        .unwrap_or(0)
}

#[test]
fn reloadable_app_wraps_whole_stack() {
    // v1 stack: Auth(TOKA) -> RouteApp v1 (/x). v2 stack: Auth(TOKB) -> RouteApp v2 (/x).
    let stack_v1: Arc<dyn ServerApp + Send + Sync> = Arc::new(AuthTokenApp::new(
        RouteApp {
            version: "v1".into(),
            ok_path: "/x".into(),
        },
        "TOKA",
    ));
    let stack_v2: Arc<dyn ServerApp + Send + Sync> = Arc::new(AuthTokenApp::new(
        RouteApp {
            version: "v2".into(),
            ok_path: "/x".into(),
        },
        "TOKB",
    ));

    let host = ReloadableApp::new(stack_v1);

    // in-flight snapshot stability at the seam: snapshot, swap, snapshot keeps old identity.
    let snapshot = host.current();
    assert_eq!(host.identity().version, "v1");

    let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
    let addr = listener.local_addr().unwrap().to_string();
    let host_srv = host.clone();
    let server = thread::spawn(move || serve_bounded_reloadable(&listener, &host_srv, 2).unwrap());

    // request 1 under v1: TOKA accepted.
    assert_eq!(
        roundtrip(&addr, "GET", "/x", &[("authorization", "Bearer TOKA")]),
        200
    );

    host.swap(stack_v2); // swap the WHOLE stack (middleware token + inner) for the next request
    assert_eq!(
        snapshot.identity().version,
        "v1",
        "in-flight snapshot kept its stack"
    );
    assert_eq!(host.identity().version, "v2", "active stack is now v2");

    // request 2: TOKA now rejected because the AUTH MIDDLEWARE also swapped (expects TOKB).
    assert_eq!(
        roundtrip(&addr, "GET", "/x", &[("authorization", "Bearer TOKA")]),
        401,
        "whole stack swapped, not just inner"
    );

    server.join().unwrap();
}

// 7 ── the composed stack is Send + Sync (storable as a trait object) ──────────────────────────────
#[test]
fn composed_stack_is_send_sync() {
    fn assert_send_sync<T: Send + Sync>(_: &T) {}
    let (rec, _c, _s) = RecordingApp::new("v1");
    let stack = rec.with_trace().with_auth("TOK").with_body_limit(1024);
    assert_send_sync(&stack);
    let _erased: Arc<dyn ServerApp + Send + Sync> = Arc::new(stack);
}

// 8 ── no hidden cross-request mutable state: valid/invalid/valid evaluated independently ──────────
#[test]
fn no_hidden_cross_request_state() {
    let (rec, calls, _seen) = RecordingApp::new("v1");
    let stack = AuthTokenApp::new(rec, "TOK");

    let status = |d: ServerDecision| match d {
        ServerDecision::Respond { response } => response.status,
        _ => 0,
    };
    assert_eq!(
        status(stack.call(req(
            "POST",
            "/x",
            &[("authorization", "Bearer TOK")],
            json!({})
        ))),
        200
    );
    assert_eq!(
        status(stack.call(req(
            "POST",
            "/x",
            &[("authorization", "Bearer NOPE")],
            json!({})
        ))),
        401
    );
    assert_eq!(
        status(stack.call(req(
            "POST",
            "/x",
            &[("authorization", "Bearer TOK")],
            json!({})
        ))),
        200
    );
    assert_eq!(
        calls.load(Ordering::SeqCst),
        2,
        "inner called only for the two authorized requests; no leakage"
    );
}
