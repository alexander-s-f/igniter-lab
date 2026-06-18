//! Machine-backed effect host (LAB-MACHINE-IGNITER-SERVER-EFFECT-P3) — feature `machine` only.
//!
//! This is the **adapter**, not a new effect runner. It connects the Rack-like server protocol to the
//! already-proven `igniter-machine` wire-to-effect contour:
//!
//! ```text
//! ServerRequest -> ServerApp::call -> ServerDecision::InvokeEffect { target, input, ... }
//!   -> MachineEffectHost maps target -> machine ingress route   (INFRA binding, not product route)
//!   -> IngressRouter::handle_effect                              (the EXISTING P7/P10/P11 path)
//!        -> duplicate policy -> ONE replica -> capsule intent
//!        -> run_write_effect_atomic (SingleFlight) -> receipt
//!   -> ServerResponse
//! ```
//!
//! Authority split (P1): the **app** decides a request means `InvokeEffect { target }` (product
//! routing); the **host** holds only the infra binding `target -> machine route/pool` and the effect
//! identity lives in the signed recipe + host `EffectBridgeConfig.effect_passport` — never in the app
//! decision (no `capability_id`/`operation`/`scope` crosses the protocol). The exactly-one guarantees
//! (one selected replica, one atomic effect per `duplicate_key:attempt`) are inherited verbatim
//! because execution IS `handle_effect`; this module adds no effect semantics.

use crate::host;
use crate::protocol::{ServerApp, ServerDecision, ServerRequest, ServerResponse};
use igniter_machine::coordination::CoordinationHub;
use igniter_machine::ingress::{EffectBridgeConfig, IngressRequest, IngressRouter};
use serde_json::{json, Value};
use std::collections::{BTreeMap, HashMap};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};

/// Maps a logical app `target` to an existing `igniter-machine` ingress route and runs the decision
/// through `IngressRouter::handle_effect`. Holds NO `(method, path) -> business action` table — that
/// is the app's job. `target_routes` is pure infra binding (which machine pool serves a target).
pub struct MachineEffectHost<'a> {
    router: &'a IngressRouter,
    hub: &'a CoordinationHub,
    cfg: &'a EffectBridgeConfig<'a>,
    /// infra binding only: `target -> machine ingress route` (e.g. "demo-effect" -> "/w").
    target_routes: BTreeMap<String, String>,
}

impl<'a> MachineEffectHost<'a> {
    pub fn new(router: &'a IngressRouter, hub: &'a CoordinationHub, cfg: &'a EffectBridgeConfig<'a>) -> Self {
        Self { router, hub, cfg, target_routes: BTreeMap::new() }
    }

    /// Bind a logical app target to an existing machine ingress route. INFRA binding (topology), not
    /// product meaning — the app already decided the request maps to this `target`.
    pub fn bind_target(&mut self, target: &str, machine_route: &str) {
        self.target_routes.insert(target.to_string(), machine_route.to_string());
    }

    /// Execute one `InvokeEffect` decision through the machine. Builds the `IngressRequest` the
    /// proven path expects (machine route + the original request's headers, carrying the bearer
    /// passport, duplicate key, correlation + idempotency) with `input` as the body, then forwards to
    /// `handle_effect`. Returns the machine's status/body normalized into a `ServerResponse`.
    pub async fn run_invoke_effect(
        &self,
        req: &ServerRequest,
        target: &str,
        input: &Value,
        correlation_id: Option<String>,
        idempotency_key: Option<String>,
    ) -> ServerResponse {
        let route = match self.target_routes.get(target) {
            Some(r) => r.clone(),
            None => {
                // unbound target = infra misconfiguration, not a product 404. The app routed fine;
                // the host has no machine route for this target.
                return ServerResponse::json(502, json!({ "error": "unbound target", "target": target }));
            }
        };

        // Carry the original request headers (already lower-cased by the parser): Authorization
        // (bearer passport), the duplicate-key header, x-correlation-id, idempotency-key. The app
        // never sees or sets these — they pass through to the machine's auth + duplicate gates.
        let mut headers: HashMap<String, String> = req.headers.iter().map(|(k, v)| (k.clone(), v.clone())).collect();
        if let Some(c) = &correlation_id {
            headers.entry("x-correlation-id".to_string()).or_insert_with(|| c.clone());
        }
        if let Some(i) = &idempotency_key {
            headers.entry("idempotency-key".to_string()).or_insert_with(|| i.clone());
        }

        let ingress = IngressRequest {
            method: req.method.clone(),
            path: route,
            headers,
            body: input.clone(),
        };

        let resp = self.router.handle_effect(self.hub, &ingress, self.cfg).await;

        let mut out_headers = BTreeMap::new();
        out_headers.insert("content-type".to_string(), "application/json".to_string());
        out_headers.insert("x-correlation-id".to_string(), resp.correlation_id.clone());
        ServerResponse { status: resp.status, headers: out_headers, body: resp.body }
    }
}

/// Dispatch a `ServerDecision` against a machine-backed effect host. `Respond` / `Invoke` reuse the
/// protocol-only `host::execute` (Invoke stays observed — the app still names no effect identity);
/// `InvokeEffect` runs through the machine contour.
pub async fn dispatch(req: &ServerRequest, decision: ServerDecision, effect_host: &MachineEffectHost<'_>) -> ServerResponse {
    match decision {
        ServerDecision::InvokeEffect { target, input, correlation_id, idempotency_key } => {
            effect_host.run_invoke_effect(req, &target, &input, correlation_id, idempotency_key).await
        }
        other => host::execute(other),
    }
}

// ── real loopback HTTP/1.1 (one connection), routed through ServerApp then the machine ───────────

async fn read_server_request(stream: &mut TcpStream) -> std::io::Result<ServerRequest> {
    let mut buf = Vec::new();
    let mut tmp = [0u8; 1024];
    loop {
        let n = stream.read(&mut tmp).await?;
        if n == 0 {
            break;
        }
        buf.extend_from_slice(&tmp[..n]);
        if let Some(pos) = host::find_subslice(&buf, b"\r\n\r\n") {
            let need = pos + 4 + host::content_length(&buf[..pos]);
            while buf.len() < need {
                let n = stream.read(&mut tmp).await?;
                if n == 0 {
                    break;
                }
                buf.extend_from_slice(&tmp[..n]);
            }
            break;
        }
    }
    Ok(host::parse_request(&buf))
}

/// Serve exactly ONE inbound loopback connection: parse → `ServerApp::call` (routing in the app) →
/// execute the decision (machine contour for `InvokeEffect`) → write the HTTP/1.1 response. No
/// daemon; returns after one connection. The host never inspects `(method, path)` for routing.
pub async fn serve_once_effect(
    listener: &TcpListener,
    app: &dyn ServerApp,
    effect_host: &MachineEffectHost<'_>,
) -> std::io::Result<()> {
    let (mut stream, _) = listener.accept().await?;
    let req = read_server_request(&mut stream).await?;
    let decision = app.call(req.clone());
    let resp = dispatch(&req, decision, effect_host).await;
    stream.write_all(&host::encode_response(&resp)).await?;
    stream.flush().await
}
