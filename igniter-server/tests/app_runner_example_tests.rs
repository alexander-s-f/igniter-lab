//! Verification for the packaging-pattern example (LAB-MACHINE-IGNITER-SERVER-APP-RUNNER-EXAMPLE-P13).
//! Machine-free. Proves `build_app` + a thin `serve_loop` runner + whole-stack reload.

use igniter_server::protocol::{ServerApp, ServerDecision, ServerRequest};
use igniter_server::reload::ReloadableApp;
use igniter_server::serving_loop::{serve_loop, ServingPolicy};
use serde_json::{json, Value};
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::Arc;
use std::thread;

// Compile the example exactly as a consumer would - proving `build_app` is real packaging code.
#[path = "../examples/server_app_runner.rs"]
mod runner_example;
use runner_example::{build_app, AppConfig};

fn req(method: &str, path: &str, headers: &[(&str, &str)], body: Value) -> ServerRequest {
    let mut r = ServerRequest::new(method, path, body);
    for (k, v) in headers {
        r.headers.insert(k.to_string(), v.to_string());
    }
    r.correlation_id = r.headers.get("x-correlation-id").cloned();
    r.idempotency_key = r.headers.get("idempotency-key").cloned();
    r
}
fn respond_status(d: &ServerDecision) -> u16 {
    match d {
        ServerDecision::Respond { response } => response.status,
        other => panic!("expected Respond, got {other:?}"),
    }
}
fn http_get_health(addr: &str, bearer: Option<&str>) -> u16 {
    let mut s = TcpStream::connect(addr).unwrap();
    let auth = bearer
        .map(|t| format!("Authorization: Bearer {t}\r\n"))
        .unwrap_or_default();
    let reqtxt = format!("GET /health HTTP/1.1\r\nHost: x\r\n{auth}Content-Length: 0\r\n\r\n");
    s.write_all(reqtxt.as_bytes()).unwrap();
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
fn build_app_returns_send_sync_and_serves_health() {
    // the type annotation proves Send + Sync.
    let app: Arc<dyn ServerApp + Send + Sync> = build_app(&AppConfig::default());
    assert_eq!(
        respond_status(&app.call(req("GET", "/health", &[], Value::Null))),
        200
    );
}

#[test]
fn config_auth_short_circuits_and_trace_decorates() {
    let app = build_app(&AppConfig {
        version: "v1".into(),
        auth_token: Some("secret".into()),
        body_limit: 1 << 20,
    });
    // missing token -> 401 (Auth short-circuits before the app).
    assert_eq!(
        respond_status(&app.call(req("GET", "/health", &[], Value::Null))),
        401
    );
    // valid token -> 200, and TraceApp decorated the response with a correlation id.
    match app.call(req(
        "GET",
        "/health",
        &[("authorization", "Bearer secret")],
        Value::Null,
    )) {
        ServerDecision::Respond { response } => {
            assert_eq!(response.status, 200);
            assert!(response.headers.contains_key("x-correlation-id"));
        }
        other => panic!("expected Respond, got {other:?}"),
    }
}

#[test]
fn config_body_limit_rejects_oversized_before_app() {
    let app = build_app(&AppConfig {
        version: "v1".into(),
        auth_token: None,
        body_limit: 10,
    });
    let big = json!({ "message": "this body is definitely longer than ten bytes" });
    assert_eq!(
        respond_status(&app.call(req("POST", "/echo", &[("idempotency-key", "k")], big))),
        413
    );
}

#[test]
fn reload_swaps_the_whole_stack_over_loopback() {
    let reloadable = ReloadableApp::new(build_app(&AppConfig {
        version: "v1".into(),
        auth_token: Some("TOKA".into()),
        body_limit: 1 << 20,
    }));
    let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
    let addr = listener.local_addr().unwrap().to_string();
    let reload_srv = reloadable.clone();
    let server = thread::spawn(move || {
        serve_loop(
            &listener,
            &reload_srv,
            &ServingPolicy::new(2).loopback_only(),
        )
        .unwrap()
    });

    // v1 accepts TOKA.
    assert_eq!(http_get_health(&addr, Some("TOKA")), 200);
    // operator reloads the WHOLE composed stack to v2 expecting TOKB.
    reloadable.swap(build_app(&AppConfig {
        version: "v2".into(),
        auth_token: Some("TOKB".into()),
        body_limit: 1 << 20,
    }));
    // TOKA is now rejected - the entire stack (auth config included) was swapped.
    assert_eq!(http_get_health(&addr, Some("TOKA")), 401);

    let report = server.join().unwrap();
    assert_eq!(report.requests_served, 2);
    assert_eq!(
        report.app_versions_seen,
        vec!["v1", "v2"],
        "the loop saw v1 then v2"
    );
    assert!(report.is_loopback);
}

#[test]
fn bounded_loopback_serves_health_then_returns() {
    let reloadable = ReloadableApp::new(build_app(&AppConfig::default()));
    let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
    let addr = listener.local_addr().unwrap().to_string();
    let reload_srv = reloadable.clone();
    let server =
        thread::spawn(move || serve_loop(&listener, &reload_srv, &ServingPolicy::new(1)).unwrap());
    assert_eq!(http_get_health(&addr, None), 200);
    let report = server.join().unwrap();
    assert_eq!(
        report.requests_served, 1,
        "loop returned after the budget - not a daemon"
    );
}

#[test]
fn app_owns_routing_unknown_is_404() {
    let app = build_app(&AppConfig::default());
    assert_eq!(
        respond_status(&app.call(req("DELETE", "/whatever", &[], Value::Null))),
        404
    );
}

#[test]
fn decision_carries_no_privileged_effect_identity() {
    let app = build_app(&AppConfig::default());
    let d = app.call(req(
        "POST",
        "/echo",
        &[("idempotency-key", "k1")],
        json!({ "message": "hi" }),
    ));
    let encoded = serde_json::to_value(&d).unwrap();
    assert_eq!(encoded["kind"], json!("invoke_effect"));
    assert_eq!(encoded["target"], json!("echo-record"));
    assert!(encoded.get("capability_id").is_none());
    assert!(encoded.get("operation").is_none());
    assert!(encoded.get("scope").is_none());
}
