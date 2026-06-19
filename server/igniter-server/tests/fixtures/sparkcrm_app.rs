//! SparkCRM-shaped `ServerApp` + sanitized payloads — TEST FIXTURE (LAB-MACHINE-IGNITER-SERVER-APP-
//! BOUNDARY-P6). Moved here OUT of `igniter-server/src/` so the core crate exports only generic server
//! substrate; a domain app is a consumer that implements `ServerApp`, never part of the server API.
//! The SHADOW-P2 proof is preserved verbatim — only its location changed.
//!
//! Included by the SparkCRM test binaries via `#[path = "fixtures/sparkcrm_app.rs"] mod ...`. Strictly
//! offline/in-memory/sanitized: no live SparkCRM, no network, no DB, no credentials.
#![allow(dead_code)] // shared across two test binaries; each uses a subset.

use igniter_server::protocol::{
    AppIdentity, ServerApp, ServerDecision, ServerRequest, ServerResponse,
};
use serde_json::{json, Value};
use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};

/// Offline SparkCRM-shaped app. Stateless. Carries vendor normalization (path→target, raw fields→clean
/// input, duplicate-key extraction) so the machine duplicate policy stays GENERIC
/// (`key_header = "idempotency-key"`): the protocol carries ONE canonical `idempotency_key`.
#[derive(Default)]
pub struct SparkCrmApp;

impl SparkCrmApp {
    /// Map an inbound webhook path to a logical INBOUND target (never an outbound capability id).
    fn target_for(method: &str, path: &str) -> Option<&'static str> {
        match (method, path) {
            ("POST", "/webhook/leads") => Some("lead-intake"),
            ("POST", "/webhook/bids") => Some("lead-bid"),
            ("POST", "/webhook/status") => Some("lead-status"),
            _ => None,
        }
    }

    /// Normalize raw vendor fields into a clean local capsule input. Always provides `base` (consumed
    /// by the capsule as `code = base + attempt`); the host injects `attempt`. Extra descriptive
    /// fields are carried for traceability — the capsule reads only what it declares.
    fn normalize_input(target: &str, body: &Value) -> Value {
        let lead_id = body
            .get("lead")
            .and_then(|l| l.get("external_id"))
            .and_then(|v| v.as_str())
            .unwrap_or("unknown");
        let value_cents = body.get("value_cents").and_then(|v| v.as_i64());
        let bid_cents = body.get("bid_amount_cents").and_then(|v| v.as_i64());
        match target {
            "lead-bid" => json!({
                "lead_id": lead_id,
                "bid_amount_cents": bid_cents.unwrap_or(0),
                "base": bid_cents.unwrap_or(0),
            }),
            "lead-status" => json!({
                "lead_id": lead_id,
                "status": body.get("status").and_then(|v| v.as_str()).unwrap_or("unknown"),
                "base": value_cents.unwrap_or(0),
            }),
            _ => json!({
                "lead_id": lead_id,
                "base": value_cents.unwrap_or(1000),
            }),
        }
    }

    /// Canonical duplicate-key extraction precedence (vendor normalization lives HERE):
    /// 1. `x-auction-id` header · 2. body `auction_id` · 3. deterministic composite from non-secret
    /// stable fields · 4. `idempotency-key` header fallback. `None` = no resolvable key (→ 400).
    pub fn extract_key(req: &ServerRequest) -> Option<String> {
        if let Some(v) = req.headers.get("x-auction-id") {
            if !v.is_empty() {
                return Some(v.clone());
            }
        }
        if let Some(v) = req.body.get("auction_id").and_then(|v| v.as_str()) {
            if !v.is_empty() {
                return Some(v.to_string());
            }
        }
        if let Some(c) = Self::composite_key(&req.body) {
            return Some(c);
        }
        if let Some(v) = req.headers.get("idempotency-key") {
            if !v.is_empty() {
                return Some(v.clone());
            }
        }
        None
    }

    /// Deterministic composite key from non-secret stable fields (`phone`, `email`, `campaign`, plus
    /// an optional payload-supplied `event_bucket` — NEVER the host clock, to preserve replay
    /// determinism). `None` if no stable field is present. Opaque (`comp-<hex>`); the digest helper is
    /// the std `DefaultHasher` (a lab choice, no algorithm mandated).
    fn composite_key(body: &Value) -> Option<String> {
        let fields = [
            body.get("phone").and_then(|v| v.as_str()),
            body.get("email").and_then(|v| v.as_str()),
            body.get("campaign").and_then(|v| v.as_str()),
            body.get("event_bucket").and_then(|v| v.as_str()),
        ];
        if fields.iter().all(|f| f.is_none()) {
            return None;
        }
        let mut h = DefaultHasher::new();
        for f in fields {
            match f {
                Some(s) => {
                    1u8.hash(&mut h);
                    s.hash(&mut h);
                }
                None => 0u8.hash(&mut h),
            }
        }
        Some(format!("comp-{:016x}", h.finish()))
    }
}

impl ServerApp for SparkCrmApp {
    fn call(&self, req: ServerRequest) -> ServerDecision {
        let target = match Self::target_for(&req.method, &req.path) {
            Some(t) => t,
            None => {
                return ServerDecision::Respond {
                    response: ServerResponse::json(404, json!({ "error": "no route" })),
                }
            }
        };
        // Keyless webhook → 400, ZERO effects (never silently treated as fresh).
        let key = match Self::extract_key(&req) {
            Some(k) => k,
            None => {
                return ServerDecision::Respond {
                    response: ServerResponse::json(
                        400,
                        json!({ "error": "missing duplicate key" }),
                    ),
                }
            }
        };
        let input = Self::normalize_input(target, &req.body);
        ServerDecision::InvokeEffect {
            target: target.to_string(),
            input,
            correlation_id: req.correlation_id.clone(),
            idempotency_key: Some(key), // canonical key; the host maps it to the generic duplicate gate.
        }
    }

    fn identity(&self) -> AppIdentity {
        AppIdentity::new("sparkcrm-shadow", "p2", "")
    }
}

/// Sanitized, in-memory webhook fixtures (fabricated — no real vendor data).
pub mod payloads {
    use serde_json::{json, Value};

    pub fn lead_intake() -> Value {
        json!({
            "auction_id": "AUC-LEAD-1001",
            "lead": { "external_id": "lead_9982" },
            "phone": "+1-555-0100",
            "email": "ada@example.test",
            "campaign": "spring-auctions",
            "value_cents": 1500
        })
    }

    pub fn lead_bid() -> Value {
        json!({
            "auction_id": "AUC-BID-2002",
            "lead": { "external_id": "lead_9982" },
            "bid_amount_cents": 4200,
            "campaign": "spring-auctions"
        })
    }

    pub fn lead_status() -> Value {
        json!({
            "auction_id": "AUC-STAT-3003",
            "lead": { "external_id": "lead_9982" },
            "status": "converted",
            "value_cents": 9000
        })
    }

    pub fn lead_composite_only() -> Value {
        json!({
            "lead": { "external_id": "lead_7777" },
            "phone": "+1-555-0199",
            "email": "grace@example.test",
            "campaign": "fall-auctions",
            "value_cents": 800
        })
    }

    pub fn lead_keyless() -> Value {
        json!({
            "lead": { "external_id": "lead_0000" },
            "note": "no identifying fields"
        })
    }
}
