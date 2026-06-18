//! Generic wrapper middleware (LAB-MACHINE-IGNITER-SERVER-MIDDLEWARE-P8). Machine-free.
//!
//! A middleware is just a `ServerApp` that wraps an inner `ServerApp` (zero-cost, Approach 1 from the
//! middleware-shape design). It may **observe, reject, or decorate** requests/responses — it is NOT a
//! new authority plane:
//!
//! - it must NOT route by `(method, path)` (routing stays in the innermost `ServerApp::call`);
//! - it must NOT name effects (`ServerDecision` carries no `capability_id`/`operation`/`scope`, so this
//!   is structurally impossible);
//! - it must NOT hold hidden mutable state — every wrapper here is `&self`-pure over
//!   `(request, inner decision)`.
//!
//! Composition (the card pipeline) builds one stack of plain trait objects:
//!
//! ```text
//! request -> BodyLimitApp -> AuthTokenApp -> TraceApp -> ServerApp::call -> response
//! ```
//!
//! `ReloadableApp` wraps the OUTER composed stack, so a swap replaces middleware + core atomically.

use crate::protocol::{AppIdentity, ServerApp, ServerDecision, ServerRequest, ServerResponse};
use serde_json::json;
use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};

// ── TraceApp: ensure/propagate a correlation id; decorate Respond — no decision-kind change ───────

/// Ensures a correlation id exists on the request (deterministically derived if absent — no clock, no
/// RNG, so replay-safe), propagates it to the inner app, and decorates a `Respond` with the
/// `x-correlation-id` header. It never changes the decision kind and never routes.
pub struct TraceApp<A> {
    inner: A,
}

impl<A: ServerApp> TraceApp<A> {
    pub fn new(inner: A) -> Self {
        Self { inner }
    }
}

impl<A: ServerApp> ServerApp for TraceApp<A> {
    fn call(&self, mut request: ServerRequest) -> ServerDecision {
        let correlation_id = request.correlation_id.clone().unwrap_or_else(|| deterministic_correlation(&request));
        request.correlation_id = Some(correlation_id.clone());
        request.headers.insert("x-correlation-id".to_string(), correlation_id.clone());

        match self.inner.call(request) {
            ServerDecision::Respond { mut response } => {
                response.headers.insert("x-correlation-id".to_string(), correlation_id);
                ServerDecision::Respond { response }
            }
            other => other, // Invoke / InvokeEffect pass through unchanged (no effect identity touched).
        }
    }

    fn identity(&self) -> AppIdentity {
        self.inner.identity()
    }
}

/// Deterministic correlation id from stable request fields (method+path+body). Pure — same request
/// yields the same id under replay; never a clock or RNG.
fn deterministic_correlation(req: &ServerRequest) -> String {
    let mut h = DefaultHasher::new();
    req.method.hash(&mut h);
    req.path.hash(&mut h);
    serde_json::to_vec(&req.body).unwrap_or_default().hash(&mut h);
    format!("corr-{:016x}", h.finish())
}

// ── AuthTokenApp: static bearer-token gate; short-circuits before inner on failure ───────────────

/// Checks a configured bearer token in the `authorization` header. On failure returns `401` WITHOUT
/// calling the inner app. On success it injects a generic `x-auth-ok` marker and delegates. Lab-only:
/// a real deployment sources the token from the host's secret provider, never from an app/route table.
pub struct AuthTokenApp<A> {
    inner: A,
    expected_token: String,
}

impl<A: ServerApp> AuthTokenApp<A> {
    pub fn new(inner: A, expected_token: impl Into<String>) -> Self {
        Self { inner, expected_token: expected_token.into() }
    }
}

impl<A: ServerApp> ServerApp for AuthTokenApp<A> {
    fn call(&self, mut request: ServerRequest) -> ServerDecision {
        let ok = request
            .headers
            .get("authorization")
            .map(|h| h.strip_prefix("Bearer ").unwrap_or(h) == self.expected_token)
            .unwrap_or(false);

        if !ok {
            return ServerDecision::Respond { response: ServerResponse::json(401, json!({ "error": "unauthorized" })) };
        }
        request.headers.insert("x-auth-ok".to_string(), "true".to_string());
        self.inner.call(request)
    }

    fn identity(&self) -> AppIdentity {
        self.inner.identity()
    }
}

// ── BodyLimitApp: reject oversized bodies before inner ───────────────────────────────────────────

/// Rejects requests whose serialized JSON body exceeds `max_bytes` with `413`, before calling the
/// inner app. No streaming/body-parser scope — the host already parsed the request.
pub struct BodyLimitApp<A> {
    inner: A,
    max_bytes: usize,
}

impl<A: ServerApp> BodyLimitApp<A> {
    pub fn new(inner: A, max_bytes: usize) -> Self {
        Self { inner, max_bytes }
    }
}

impl<A: ServerApp> ServerApp for BodyLimitApp<A> {
    fn call(&self, request: ServerRequest) -> ServerDecision {
        let body_len = serde_json::to_vec(&request.body).map(|v| v.len()).unwrap_or(0);
        if body_len > self.max_bytes {
            return ServerDecision::Respond { response: ServerResponse::json(413, json!({ "error": "payload too large" })) };
        }
        self.inner.call(request)
    }

    fn identity(&self) -> AppIdentity {
        self.inner.identity()
    }
}

// ── ergonomic stack builders (sugar over the structs; no new runtime) ─────────────────────────────

/// Fluent composition so a deeply nested stack reads top-down. `app.with_trace().with_auth(t)
/// .with_body_limit(n)` builds `BodyLimitApp<AuthTokenApp<TraceApp<App>>>` — i.e. the card pipeline
/// `BodyLimit -> Auth -> Trace -> app`.
pub trait ServerAppExt: ServerApp + Sized {
    fn with_trace(self) -> TraceApp<Self> {
        TraceApp::new(self)
    }
    fn with_auth(self, token: impl Into<String>) -> AuthTokenApp<Self> {
        AuthTokenApp::new(self, token)
    }
    fn with_body_limit(self, max_bytes: usize) -> BodyLimitApp<Self> {
        BodyLimitApp::new(self, max_bytes)
    }
}

impl<A: ServerApp> ServerAppExt for A {}
