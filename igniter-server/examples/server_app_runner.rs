//! Packaging-pattern example (LAB-MACHINE-IGNITER-SERVER-APP-RUNNER-EXAMPLE-P13).
//!
//! Teaches the P12 v0 packaging model - NOT a framework:
//!
//! ```text
//! AppConfig -> build_app(config) -> Arc<dyn ServerApp + Send + Sync>   (composes P8 middleware)
//!   -> ReloadableApp::new(stack)
//!   -> ServingPolicy::new(n).loopback_only()
//!   -> serve_loop over a caller-bound 127.0.0.1 listener   (the THIN runner)
//! ```
//!
//! The **app** owns routing (`match` in `call`); the **runner** owns the listener + serving policy +
//! reload; **middleware** is composed explicitly at the edge from config. Machine-free: no
//! `igniter-machine`, no effect host, no live IO. Neutral domain (no SparkCRM/vendor vocabulary).
#![allow(dead_code)] // when #[path]-included by the test, `main`/client helpers are unused there.

use igniter_server::middleware::ServerAppExt;
use igniter_server::protocol::{
    AppIdentity, ServerApp, ServerDecision, ServerRequest, ServerResponse,
};
use igniter_server::reload::ReloadableApp;
use igniter_server::serving_loop::{serve_loop, ServingPolicy};
use serde_json::json;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::Arc;
use std::thread;

// -- the neutral inner app (product meaning; routing lives here) -----------------------------------

/// Minimal neutral app: a health probe + an idempotent "echo" intake. Carries only a version so a
/// reload is observable via `identity()`. Stateless / `Send + Sync`.
struct CoreApp {
    version: String,
}

impl ServerApp for CoreApp {
    fn call(&self, req: ServerRequest) -> ServerDecision {
        match (req.method.as_str(), req.path.as_str()) {
            ("GET", "/health") => ServerDecision::Respond {
                response: ServerResponse::json(200, json!({ "ok": true, "version": self.version })),
            },
            ("POST", "/echo") => match req.idempotency_key.clone().filter(|k| !k.is_empty()) {
                Some(key) => ServerDecision::InvokeEffect {
                    target: "echo-record".into(), // a LOGICAL target; host binds it to an effect later.
                    input: json!({ "message": req.body.get("message").and_then(|v| v.as_str()).unwrap_or("") }),
                    correlation_id: req.correlation_id.clone(),
                    idempotency_key: Some(key),
                },
                None => ServerDecision::Respond {
                    response: ServerResponse::json(
                        400,
                        json!({ "error": "missing idempotency-key" }),
                    ),
                },
            },
            _ => ServerDecision::Respond {
                response: ServerResponse::json(404, json!({ "error": "no route" })),
            },
        }
    }

    fn identity(&self) -> AppIdentity {
        AppIdentity::new("runner-example", self.version.clone(), "")
    }
}

// -- the packaging surface: AppConfig + build_app --------------------------------------------------

/// What a packaged app is configured with. Product config (here just a version) + edge policy
/// (auth token, body limit). No listener address, no machine internals - those belong to the runner.
pub struct AppConfig {
    pub version: String,
    pub auth_token: Option<String>,
    pub body_limit: usize,
}

impl Default for AppConfig {
    fn default() -> Self {
        Self {
            version: "v1".into(),
            auth_token: None,
            body_limit: 64 * 1024,
        }
    }
}

/// THE packaging unit: build the composed stack and return it boxed. Middleware is composed
/// EXPLICITLY from config - `BodyLimit -> [Auth] -> Trace -> CoreApp`. Returns a single trait object
/// so any runner can embed it; the effect/machine bindings are supplied separately by the host.
pub fn build_app(config: &AppConfig) -> Arc<dyn ServerApp + Send + Sync> {
    let traced = CoreApp {
        version: config.version.clone(),
    }
    .with_trace();
    match &config.auth_token {
        Some(token) => Arc::new(
            traced
                .with_auth(token.clone())
                .with_body_limit(config.body_limit),
        ),
        None => Arc::new(traced.with_body_limit(config.body_limit)),
    }
}

// -- thin loopback client used by the demo `main` --------------------------------------------------

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

fn main() -> std::io::Result<()> {
    // 1. build the packaged app from config (v1, token TOKA).
    let reloadable = ReloadableApp::new(build_app(&AppConfig {
        version: "v1".into(),
        auth_token: Some("TOKA".into()),
        body_limit: 64 * 1024,
    }));

    // 2. the THIN runner: own a loopback listener + a bounded serving policy.
    let listener = TcpListener::bind(("127.0.0.1", 0))?;
    let addr = listener.local_addr()?.to_string();
    println!("runner on http://{addr} (loopback only, bounded to 2 requests)");

    let reload_srv = reloadable.clone();
    let server = thread::spawn(move || {
        serve_loop(
            &listener,
            &reload_srv,
            &ServingPolicy::new(2).loopback_only(),
        )
        .unwrap()
    });

    // 3. drive it: request 1 under v1/TOKA.
    println!(
        "req1 GET /health (TOKA)               -> {}",
        http_get_health(&addr, Some("TOKA"))
    );

    // 4. operator hot-reloads the WHOLE stack to v2/TOKB between requests.
    reloadable.swap(build_app(&AppConfig {
        version: "v2".into(),
        auth_token: Some("TOKB".into()),
        body_limit: 64 * 1024,
    }));

    // 5. request 2 still presents TOKA -> now rejected by the swapped stack.
    println!(
        "req2 GET /health (TOKA, after swap)   -> {}",
        http_get_health(&addr, Some("TOKA"))
    );

    let report = server.join().unwrap();
    println!(
        "served {} requests; app versions seen: {:?}",
        report.requests_served, report.app_versions_seen
    );
    Ok(())
}
