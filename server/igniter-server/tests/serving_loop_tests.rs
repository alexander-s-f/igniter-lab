//! Bounded serving-loop proofs (LAB-MACHINE-IGNITER-SERVER-SERVING-LOOP-P5). Machine-free.
//!
//! Each test binds `127.0.0.1:0` (the CALLER binds; the loop never does) and drives real loopback
//! HTTP through `serve_loop`. Proves: exactly-N then return (no daemon); swap between requests in the
//! same loop; in-flight snapshot preserved across a swap; no host route table; opt-in loopback guard.

use igniter_server::protocol::{
    AppIdentity, ServerApp, ServerDecision, ServerRequest, ServerResponse,
};
use igniter_server::reload::ReloadableApp;
use igniter_server::serving_loop::{serve_loop, ServingPolicy, ServingReport};
use serde_json::{json, Value};
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::{Arc, Condvar, Mutex};
use std::thread;

struct RouteApp {
    id: AppIdentity,
    ok_path: String,
}
impl ServerApp for RouteApp {
    fn call(&self, req: ServerRequest) -> ServerDecision {
        if req.method == "GET" && req.path == self.ok_path {
            ServerDecision::Respond {
                response: ServerResponse::json(
                    200,
                    json!({ "ok": true, "app_version": self.id.version }),
                ),
            }
        } else {
            ServerDecision::Respond {
                response: ServerResponse::json(
                    404,
                    json!({ "error": "no route", "app_version": self.id.version }),
                ),
            }
        }
    }
    fn identity(&self) -> AppIdentity {
        self.id.clone()
    }
}
fn route_app(version: &str, ok_path: &str) -> Arc<dyn ServerApp + Send + Sync> {
    Arc::new(RouteApp {
        id: AppIdentity::new("demo", version, ""),
        ok_path: ok_path.to_string(),
    })
}

fn roundtrip(addr: &str, method: &str, path: &str) -> (u16, Value) {
    let req = format!("{method} {path} HTTP/1.1\r\nHost: x\r\nContent-Length: 0\r\n\r\n");
    let mut stream = TcpStream::connect(addr).unwrap();
    stream.write_all(req.as_bytes()).unwrap();
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
    let body: Value = serde_json::from_str(text[body_start..].trim()).unwrap_or(Value::Null);
    (status, body)
}

/// Spawn `serve_loop` on a caller-bound loopback listener; return `(addr, handle→report)`.
fn spawn_loop(
    host: ReloadableApp,
    policy: ServingPolicy,
) -> (String, thread::JoinHandle<ServingReport>) {
    let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
    let addr = listener.local_addr().unwrap().to_string();
    let h = thread::spawn(move || serve_loop(&listener, &host, &policy).unwrap());
    (addr, h)
}

#[test]
fn loop_serves_exactly_n_then_returns() {
    let host = ReloadableApp::new(route_app("v1", "/health"));
    let (addr, handle) = spawn_loop(host, ServingPolicy::new(3));

    for _ in 0..3 {
        assert_eq!(roundtrip(&addr, "GET", "/health").0, 200);
    }
    // join proves the loop RETURNED after exactly 3 — it is not a daemon.
    let report = handle.join().unwrap();
    assert_eq!(report.requests_served, 3);
    assert_eq!(report.app_versions_seen, vec!["v1", "v1", "v1"]);
    assert!(report.is_loopback);
}

#[test]
fn loop_swaps_app_between_requests() {
    let host = ReloadableApp::new(route_app("v1", "/health"));
    let (addr, handle) = spawn_loop(host.clone(), ServingPolicy::new(2));

    let (s1, b1) = roundtrip(&addr, "GET", "/health");
    assert_eq!(s1, 200);
    assert_eq!(b1["app_version"], json!("v1"));

    host.swap(route_app("v2", "/health")); // reload between requests, same loop + listener

    let (s2, b2) = roundtrip(&addr, "GET", "/health");
    assert_eq!(s2, 200);
    assert_eq!(b2["app_version"], json!("v2"));

    let report = handle.join().unwrap();
    assert_eq!(
        report.app_versions_seen,
        vec!["v1", "v2"],
        "the loop saw v1 then v2"
    );
}

struct GatedApp {
    id: AppIdentity,
    started: Arc<(Mutex<bool>, Condvar)>,
    proceed: Arc<(Mutex<bool>, Condvar)>,
}
impl ServerApp for GatedApp {
    fn call(&self, _req: ServerRequest) -> ServerDecision {
        let (m, c) = &*self.started;
        *m.lock().unwrap() = true;
        c.notify_all();
        let (m, c) = &*self.proceed;
        let mut g = m.lock().unwrap();
        while !*g {
            g = c.wait(g).unwrap();
        }
        ServerDecision::Respond {
            response: ServerResponse::json(200, json!({ "app_version": self.id.version })),
        }
    }
    fn identity(&self) -> AppIdentity {
        self.id.clone()
    }
}

#[test]
fn loop_preserves_in_flight_snapshot_during_swap() {
    let started = Arc::new((Mutex::new(false), Condvar::new()));
    let proceed = Arc::new((Mutex::new(false), Condvar::new()));
    let v1: Arc<dyn ServerApp + Send + Sync> = Arc::new(GatedApp {
        id: AppIdentity::new("demo", "v1", ""),
        started: started.clone(),
        proceed: proceed.clone(),
    });
    let host = ReloadableApp::new(v1);
    let (addr, handle) = spawn_loop(host.clone(), ServingPolicy::new(1));

    let client = thread::spawn(move || roundtrip(&addr, "GET", "/health"));

    // wait until the loop snapshotted v1 and entered call.
    {
        let (m, c) = &*started;
        let mut g = m.lock().unwrap();
        while !*g {
            g = c.wait(g).unwrap();
        }
    }
    host.swap(route_app("v2", "/health")); // swap WHILE the request is in flight
    assert_eq!(host.identity().version, "v2");

    {
        let (m, c) = &*proceed;
        *m.lock().unwrap() = true;
        c.notify_all();
    }
    let (status, body) = client.join().unwrap();
    let report = handle.join().unwrap();
    assert_eq!(status, 200);
    assert_eq!(
        body["app_version"],
        json!("v1"),
        "in-flight request kept v1 across the swap"
    );
    assert_eq!(
        report.app_versions_seen,
        vec!["v1"],
        "the loop recorded the snapshotted v1"
    );
}

#[test]
fn loop_has_no_route_table() {
    let host = ReloadableApp::new(route_app("v1", "/a"));
    let (addr, handle) = spawn_loop(host.clone(), ServingPolicy::new(4));

    assert_eq!(roundtrip(&addr, "GET", "/a").0, 200);
    assert_eq!(roundtrip(&addr, "GET", "/b").0, 404);

    host.swap(route_app("v2", "/b"));

    assert_eq!(
        roundtrip(&addr, "GET", "/b").0,
        200,
        "routing changed by swap, not by host config"
    );
    assert_eq!(
        roundtrip(&addr, "GET", "/a").0,
        404,
        "the loop holds no route table"
    );

    let report = handle.join().unwrap();
    assert_eq!(report.requests_served, 4);
}

#[test]
fn loop_loopback_only_opt_in_serves_on_127() {
    // opt-in guard ALLOWS a loopback listener (refusal of non-loopback is proven by the pure
    // unit test in serving_loop.rs, without ever binding a public address).
    let host = ReloadableApp::new(route_app("v1", "/health"));
    let (addr, handle) = spawn_loop(host, ServingPolicy::new(1).loopback_only());
    assert_eq!(roundtrip(&addr, "GET", "/health").0, 200);
    let report = handle.join().unwrap();
    assert_eq!(report.requests_served, 1);
    assert!(report.is_loopback);
}
