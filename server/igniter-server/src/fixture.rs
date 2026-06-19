//! A tiny fixture `ServerApp` (LAB-MACHINE-IGNITER-SERVER-BINARY-P2).
//!
//! This is the PROOF that product routing lives in app code, not server config: routing is a plain
//! Rust `match` on `(method, path)` inside `call`. There is no route table, no config file, no
//! framework, and the host that runs this app knows none of these paths. Swap in a different
//! `ServerApp` and the routing changes entirely while the host is unchanged.
//!
//! Names are intentionally generic — no SparkCRM paths, tables, or business terms.

use crate::protocol::{AppIdentity, ServerApp, ServerDecision, ServerRequest, ServerResponse};
use serde_json::json;

/// Demo app with three routes, each producing a different `ServerDecision` shape:
/// - `GET /health`        -> `Respond(200)`            (app answers directly)
/// - `POST /effect/*`     -> `InvokeEffect`            (host would run the P7 effect path)
/// - `POST /invoke/*`     -> `Invoke`                  (host would run pure activation)
/// - anything else        -> `Respond(404)`
#[derive(Default)]
pub struct DemoApp;

impl ServerApp for DemoApp {
    fn call(&self, req: ServerRequest) -> ServerDecision {
        match (req.method.as_str(), req.path.as_str()) {
            ("GET", "/health") => ServerDecision::Respond {
                response: ServerResponse::json(200, json!({ "ok": true, "service": "igniter-server" })),
            },
            ("POST", p) if p.starts_with("/effect/") => ServerDecision::InvokeEffect {
                target: "demo-effect".into(),
                input: req.body,
                correlation_id: req.correlation_id,
                idempotency_key: req.idempotency_key,
            },
            ("POST", p) if p.starts_with("/invoke/") => ServerDecision::Invoke {
                target: "demo-invoke".into(),
                input: req.body,
                correlation_id: req.correlation_id,
                idempotency_key: req.idempotency_key,
            },
            _ => ServerDecision::Respond {
                response: ServerResponse::json(404, json!({ "error": "no route" })),
            },
        }
    }

    fn identity(&self) -> AppIdentity {
        AppIdentity::new("demo-app", "v0", "")
    }
}
