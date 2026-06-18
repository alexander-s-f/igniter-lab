//! Hot-reload proofs for the Rack-like server (LAB-MACHINE-IGNITER-SERVER-HOT-RELOAD-P4).
//!
//! Machine-free. Each test binds `127.0.0.1:0` and drives real loopback HTTP through the reloadable
//! host helpers. Proves: a swap affects only later requests; an in-flight request keeps its
//! snapshotted app; the host holds no route table; app identity is observable but not authority.

use igniter_server::host::{serve_bounded_reloadable, serve_once_reloadable};
use igniter_server::protocol::{AppIdentity, ServerApp, ServerDecision, ServerRequest, ServerResponse};
use igniter_server::reload::ReloadableApp;
use serde_json::{json, Value};
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::{Arc, Condvar, Mutex};
use std::thread;

/// An app that answers 200 only for `GET <ok_path>` and 404 otherwise; every response carries its
/// own version so a client can tell which app instance served it. Routing is entirely in `call`.
struct RouteApp {
    id: AppIdentity,
    ok_path: String,
}
impl ServerApp for RouteApp {
    fn call(&self, req: ServerRequest) -> ServerDecision {
        if req.method == "GET" && req.path == self.ok_path {
            ServerDecision::Respond { response: ServerResponse::json(200, json!({ "ok": true, "app_version": self.id.version })) }
        } else {
            ServerDecision::Respond { response: ServerResponse::json(404, json!({ "error": "no route", "app_version": self.id.version })) }
        }
    }
    fn identity(&self) -> AppIdentity {
        self.id.clone()
    }
}
fn route_app(version: &str, ok_path: &str) -> Arc<dyn ServerApp + Send + Sync> {
    Arc::new(RouteApp { id: AppIdentity::new("demo", version, ""), ok_path: ok_path.to_string() })
}

/// Send one raw HTTP/1.1 request, return `(status, body json)`.
fn roundtrip(addr: &str, method: &str, path: &str) -> (u16, Value) {
    let req = format!("{method} {path} HTTP/1.1\r\nHost: x\r\nContent-Length: 0\r\n\r\n");
    let mut stream = TcpStream::connect(addr).unwrap();
    stream.write_all(req.as_bytes()).unwrap();
    stream.flush().unwrap();
    let mut raw = Vec::new();
    stream.read_to_end(&mut raw).unwrap();
    let text = String::from_utf8_lossy(&raw);
    let status: u16 = text.split_whitespace().nth(1).and_then(|s| s.parse().ok()).unwrap_or(0);
    let body_start = text.find("\r\n\r\n").map(|i| i + 4).unwrap_or(text.len());
    let body: Value = serde_json::from_str(text[body_start..].trim()).unwrap_or(Value::Null);
    (status, body)
}

/// Bind a loopback listener and serve `n` reloadable requests on a thread; return `(addr, handle)`.
fn spawn_server(host: ReloadableApp, n: usize) -> (String, thread::JoinHandle<()>) {
    let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
    let addr = listener.local_addr().unwrap().to_string();
    let h = thread::spawn(move || {
        serve_bounded_reloadable(&listener, &host, n).unwrap();
    });
    (addr, h)
}

#[test]
fn reloadable_host_routes_v1_then_v2_on_same_listener() {
    let host = ReloadableApp::new(route_app("v1", "/health"));
    let (addr, server) = spawn_server(host.clone(), 2);

    let (s1, b1) = roundtrip(&addr, "GET", "/health");
    assert_eq!(s1, 200);
    assert_eq!(b1["app_version"], json!("v1"));

    host.swap(route_app("v2", "/health")); // operator reloads between requests

    let (s2, b2) = roundtrip(&addr, "GET", "/health");
    assert_eq!(s2, 200);
    assert_eq!(b2["app_version"], json!("v2"), "request after swap sees v2");

    server.join().unwrap();
}

/// An app that blocks inside `call` until released, so the test can swap the active app WHILE the
/// request is in flight. It signals `started` (after the host already snapshotted it) and then waits.
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
        ServerDecision::Respond { response: ServerResponse::json(200, json!({ "app_version": self.id.version })) }
    }
    fn identity(&self) -> AppIdentity {
        self.id.clone()
    }
}

#[test]
fn in_flight_request_keeps_original_app_after_swap() {
    let started = Arc::new((Mutex::new(false), Condvar::new()));
    let proceed = Arc::new((Mutex::new(false), Condvar::new()));
    let v1: Arc<dyn ServerApp + Send + Sync> = Arc::new(GatedApp {
        id: AppIdentity::new("demo", "v1", ""),
        started: started.clone(),
        proceed: proceed.clone(),
    });
    let host = ReloadableApp::new(v1);

    let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
    let addr = listener.local_addr().unwrap().to_string();
    let host_srv = host.clone();
    let server = thread::spawn(move || {
        serve_once_reloadable(&listener, &host_srv).unwrap();
    });
    // a client that triggers the in-flight (blocking) request.
    let client = thread::spawn(move || roundtrip(&addr, "GET", "/health"));

    // wait until the host has snapshotted v1 and entered v1.call.
    {
        let (m, c) = &*started;
        let mut g = m.lock().unwrap();
        while !*g {
            g = c.wait(g).unwrap();
        }
    }
    // swap the ACTIVE app while the request is still in flight.
    host.swap(route_app("v2", "/health"));
    assert_eq!(host.identity().version, "v2", "active app is now v2");

    // release the in-flight request; it must still answer with v1.
    {
        let (m, c) = &*proceed;
        *m.lock().unwrap() = true;
        c.notify_all();
    }
    let (status, body) = client.join().unwrap();
    server.join().unwrap();
    assert_eq!(status, 200);
    assert_eq!(body["app_version"], json!("v1"), "in-flight request kept its snapshotted app despite the swap");
}

#[test]
fn reload_does_not_create_host_route_table() {
    // v1 routes /a; v2 routes /b. Same host helper, no host route table — routing changes purely by
    // swapping the app. The host never inspects (method, path).
    let host = ReloadableApp::new(route_app("v1", "/a"));
    let (addr, server) = spawn_server(host.clone(), 4);

    assert_eq!(roundtrip(&addr, "GET", "/a").0, 200, "v1 routes /a");
    assert_eq!(roundtrip(&addr, "GET", "/b").0, 404, "v1 does not route /b");

    host.swap(route_app("v2", "/b"));

    assert_eq!(roundtrip(&addr, "GET", "/b").0, 200, "v2 routes /b on the same host");
    assert_eq!(roundtrip(&addr, "GET", "/a").0, 404, "v2 does not route /a — host has no route table");

    server.join().unwrap();
}

#[test]
fn app_identity_is_observable_but_not_authority() {
    let host = ReloadableApp::new(route_app("v1", "/health"));
    assert_eq!(host.identity().version, "v1", "identity is observable");

    // an app claiming a "trusted/admin" identity but routing nothing useful: identity grants NO
    // authority — the request is served purely by call(), so /health is still a 404.
    let sneaky: Arc<dyn ServerApp + Send + Sync> =
        Arc::new(RouteApp { id: AppIdentity::new("totally-trusted", "admin", "deadbeef"), ok_path: "/never".into() });
    host.swap(sneaky);

    assert_eq!(host.identity().name, "totally-trusted", "the claimed identity is observable");
    let (addr, server) = spawn_server(host.clone(), 1);
    let (status, _) = roundtrip(&addr, "GET", "/health");
    assert_eq!(status, 404, "identity confers no routing/authority — behavior comes only from call()");
    server.join().unwrap();
}
