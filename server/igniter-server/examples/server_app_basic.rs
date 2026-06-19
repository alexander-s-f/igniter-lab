//! First external `ServerApp` example (LAB-MACHINE-IGNITER-SERVER-EXAMPLE-APP-P10).
//!
//! A teaching artifact, NOT a product app. It lives in `examples/` (never `src/`), depends on the
//! published `igniter_server` crate (`use igniter_server::…` — the dependency direction is app →
//! server), and is fully machine-free: it needs no `--features machine` to build, run, or test.
//!
//! The lesson:
//! - routing lives inside `ServerApp::call` as a plain `match (method, path)` — never server config;
//! - an effect is requested as a LOGICAL `InvokeEffect { target, input, correlation_id,
//!   idempotency_key }` decision; the app names a `target`, never `capability_id`/`operation`/`scope`;
//! - effect authority + machine wiring stay host-side and optional (see P3/P5/P6) — not here.
//!
//! Neutral domain `ticket-intake` (a generic illustrative noun, not a product ontology):
//! - `GET  /health`  -> `Respond(200)`;
//! - `POST /tickets`  with an idempotency key -> `InvokeEffect { target: "ticket-create", … }`;
//! - `POST /tickets`  without a key           -> `Respond(400)` (never a silent fresh effect);
//! - anything else                            -> `Respond(404)`.
#![allow(dead_code)] // when this file is #[path]-included by the test, `main`/helpers are unused there.

use igniter_server::protocol::{
    AppIdentity, ServerApp, ServerDecision, ServerRequest, ServerResponse,
};
use serde_json::{json, Value};

/// The example app. Stateless, zero-field — `Send + Sync`, composes under `ReloadableApp` and the P8
/// wrapper middleware without change.
pub struct ExampleApp;

impl ServerApp for ExampleApp {
    fn call(&self, req: ServerRequest) -> ServerDecision {
        match (req.method.as_str(), req.path.as_str()) {
            ("GET", "/health") => ServerDecision::Respond {
                response: ServerResponse::json(
                    200,
                    json!({ "ok": true, "app": "ticket-intake-example" }),
                ),
            },
            ("POST", "/tickets") => match req.idempotency_key.clone().filter(|k| !k.is_empty()) {
                // canonical key present -> a logical effect decision (NO effect identity).
                Some(key) => ServerDecision::InvokeEffect {
                    target: "ticket-create".into(),
                    input: normalize_ticket(&req.body),
                    correlation_id: req.correlation_id.clone(),
                    idempotency_key: Some(key),
                },
                // keyless -> 400, never a silent fresh effect.
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
        AppIdentity::new("ticket-intake-example", "v0", "example-app-p10")
    }
}

/// Normalize a raw ticket body into a clean, sanitized local input shape. Pure; no secrets.
fn normalize_ticket(body: &Value) -> Value {
    json!({
        "title": body.get("title").and_then(|v| v.as_str()).unwrap_or("(untitled)"),
        "priority": body.get("priority").and_then(|v| v.as_str()).unwrap_or("normal"),
    })
}

/// Build a `ServerRequest` the way the host's parser would (headers lower-cased; `correlation_id` /
/// `idempotency_key` promoted from headers to typed fields). Used by `main`'s demo.
fn demo_request(method: &str, path: &str, headers: &[(&str, &str)], body: Value) -> ServerRequest {
    let mut r = ServerRequest::new(method, path, body);
    for (k, v) in headers {
        r.headers.insert(k.to_string(), v.to_string());
    }
    r.correlation_id = r.headers.get("x-correlation-id").cloned();
    r.idempotency_key = r.headers.get("idempotency-key").cloned();
    r
}

fn main() {
    // Machine-free demonstration: feed sample requests to the app and print the decisions. No socket,
    // no machine, no waiting on a client — `cargo run --example server_app_basic` just prints + exits.
    let app = ExampleApp;
    println!("== {} {} ==", app.identity().name, app.identity().version);

    let samples = [
        demo_request("GET", "/health", &[], Value::Null),
        demo_request(
            "POST",
            "/tickets",
            &[
                ("idempotency-key", "tkt-1001"),
                ("x-correlation-id", "corr-1"),
            ],
            json!({ "title": "printer jam", "priority": "high" }),
        ),
        demo_request("POST", "/tickets", &[], json!({ "title": "no key here" })),
        demo_request("DELETE", "/unknown", &[], Value::Null),
    ];
    for req in samples {
        let decision = app.call(req.clone());
        println!(
            "{} {} -> {}",
            req.method,
            req.path,
            serde_json::to_string(&decision).unwrap()
        );
    }

    // The same app composes under P8 wrapper middleware (host extension mechanism), unchanged.
    use igniter_server::middleware::ServerAppExt;
    let stack = ExampleApp.with_trace().with_auth("demo-secret");
    let no_auth = stack.call(demo_request("GET", "/health", &[], Value::Null));
    let with_auth = stack.call(demo_request(
        "GET",
        "/health",
        &[("authorization", "Bearer demo-secret")],
        Value::Null,
    ));
    println!(
        "middleware (no auth)   -> {}",
        serde_json::to_string(&no_auth).unwrap()
    );
    println!(
        "middleware (with auth) -> {}",
        serde_json::to_string(&with_auth).unwrap()
    );
}
