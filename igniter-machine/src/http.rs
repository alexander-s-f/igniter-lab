//! HTTP capability executor — readiness/design + fake-transport proof
//! (LAB-MACHINE-CAPABILITY-HTTP-P10).
//!
//! HTTP is a new RISK surface, not just another executor. This module fixes the policy (status
//! taxonomy, idempotency, redaction, credentials, rate limits, body limits, transport-error
//! classification, replay) and proves it against a FAKE transport — no real network, TLS, or
//! DNS. A real loopback transport is P11.
//!
//! The executor maps HTTP outcomes onto the existing `EffectOutcome` taxonomy, so the whole
//! P1–P9 machinery (receipts, idempotency, reconciliation, retry, durable queue) applies
//! unchanged. Credentials come from an injected host `SecretProvider` (never contract input);
//! secret headers are redacted from anything recorded.

use crate::capability::{CapabilityExecutor, EffectOutcome, EffectRequest};
use async_trait::async_trait;
use serde_json::{json, Value};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum HttpMethod {
    Get,
    Head,
    Put,
    Delete,
    Post,
    Patch,
}

impl HttpMethod {
    pub fn as_str(&self) -> &'static str {
        match self {
            HttpMethod::Get => "GET",
            HttpMethod::Head => "HEAD",
            HttpMethod::Put => "PUT",
            HttpMethod::Delete => "DELETE",
            HttpMethod::Post => "POST",
            HttpMethod::Patch => "PATCH",
        }
    }
    pub fn from_str(s: &str) -> Option<Self> {
        match s.to_ascii_uppercase().as_str() {
            "GET" => Some(HttpMethod::Get),
            "HEAD" => Some(HttpMethod::Head),
            "PUT" => Some(HttpMethod::Put),
            "DELETE" => Some(HttpMethod::Delete),
            "POST" => Some(HttpMethod::Post),
            "PATCH" => Some(HttpMethod::Patch),
            _ => None,
        }
    }
    /// Idempotent methods may be safely retried after a timeout (no mutation guarantee).
    pub fn idempotent(&self) -> bool {
        matches!(self, HttpMethod::Get | HttpMethod::Head | HttpMethod::Put | HttpMethod::Delete)
    }
}

#[derive(Clone, Debug)]
pub struct HttpRequest {
    pub method: HttpMethod,
    pub url: String,
    pub headers: Vec<(String, String)>,
    pub body: String,
    pub correlation_id: String,
}

#[derive(Clone, Debug)]
pub struct HttpResponse {
    pub status: u16,
    pub headers: Vec<(String, String)>,
    pub body: String,
}

/// Where a transport failure happened — determines whether a mutation could have occurred.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum HttpTransportError {
    /// Failed to resolve the host — request never sent.
    Dns,
    /// TCP connect failed — request never sent.
    Connect,
    /// TLS handshake failed — request never sent.
    Tls,
    /// Sent, but no response within the deadline — mutation status unknown.
    Timeout,
}

#[async_trait]
pub trait HttpTransport: Send + Sync {
    async fn send(&self, req: &HttpRequest) -> Result<HttpResponse, HttpTransportError>;
}

/// Resolves host-held secrets by name. Credentials are injected here, never via contract input.
pub trait SecretProvider: Send + Sync {
    fn resolve(&self, name: &str) -> Option<String>;
}

fn header_get<'a>(headers: &'a [(String, String)], name: &str) -> Option<&'a str> {
    headers
        .iter()
        .find(|(k, _)| k.eq_ignore_ascii_case(name))
        .map(|(_, v)| v.as_str())
}

/// Default redaction set — header names whose VALUES must never be recorded.
pub fn default_redaction() -> Vec<String> {
    ["authorization", "cookie", "set-cookie", "x-api-key", "proxy-authorization"]
        .iter()
        .map(|s| s.to_string())
        .collect()
}

fn is_redacted(redact: &[String], name: &str) -> bool {
    redact.iter().any(|r| r.eq_ignore_ascii_case(name))
}

/// Request identity digest (the HTTP analog of P6b's forced-identity digest): method + URL +
/// body digest + the canonical NON-redacted headers. Secret headers are excluded (they are
/// credentials, not identity).
pub fn http_request_digest(req: &HttpRequest, redact: &[String]) -> String {
    let mut pairs: Vec<String> = req
        .headers
        .iter()
        .filter(|(k, _)| !is_redacted(redact, k))
        .map(|(k, v)| format!("{}:{}", k.to_ascii_lowercase(), v))
        .collect();
    pairs.sort();
    let body_digest = blake3::hash(req.body.as_bytes()).to_hex().to_string();
    let material = format!("{}\n{}\n{}\n{}", req.method.as_str(), req.url, body_digest, pairs.join("\n"));
    blake3::hash(material.as_bytes()).to_hex().to_string()
}

const SECRET_PREFIX: &str = "{{secret:";

/// Resolve `{{secret:NAME}}` references in header values via the provider. Returns an error
/// naming the first unresolved secret. Raw secrets only ever live in the resolved headers that
/// go to the transport — never in the digest or the recorded result.
fn resolve_secrets(
    headers: &[(String, String)],
    secrets: &dyn SecretProvider,
) -> Result<Vec<(String, String)>, String> {
    let mut out = Vec::with_capacity(headers.len());
    for (k, v) in headers {
        if let Some(rest) = v.strip_prefix(SECRET_PREFIX) {
            let name = rest.strip_suffix("}}").unwrap_or(rest);
            match secrets.resolve(name) {
                Some(secret) => out.push((k.clone(), secret)),
                None => return Err(format!("missing credential: {name}")),
            }
        } else {
            out.push((k.clone(), v.clone()));
        }
    }
    Ok(out)
}

/// An HTTP capability executor over an injected transport + secret provider.
pub struct HttpCapabilityExecutor {
    capability_id: String,
    transport: std::sync::Arc<dyn HttpTransport>,
    secrets: std::sync::Arc<dyn SecretProvider>,
    redact: Vec<String>,
    max_body_bytes: usize,
    sends: AtomicU64,
}

impl HttpCapabilityExecutor {
    pub fn new(
        capability_id: &str,
        transport: std::sync::Arc<dyn HttpTransport>,
        secrets: std::sync::Arc<dyn SecretProvider>,
    ) -> Self {
        Self {
            capability_id: capability_id.to_string(),
            transport,
            secrets,
            redact: default_redaction(),
            max_body_bytes: 1 << 20, // 1 MiB
            sends: AtomicU64::new(0),
        }
    }
    pub fn with_max_body(mut self, n: usize) -> Self {
        self.max_body_bytes = n;
        self
    }
    /// How many times the transport was actually invoked (a replay must not increment this).
    pub fn sends(&self) -> u64 {
        self.sends.load(Ordering::SeqCst)
    }

    fn base_result(&self, req: &HttpRequest, status: Option<u16>, content_type: Option<&str>) -> Value {
        // Records identity + correlation + status only — NEVER request secrets/header values.
        let redacted: Vec<&String> = req
            .headers
            .iter()
            .map(|(k, _)| k)
            .filter(|k| is_redacted(&self.redact, k))
            .collect();
        json!({
            "request_digest": http_request_digest(req, &self.redact),
            "correlation_id": req.correlation_id,
            "status": status,
            "content_type": content_type,
            "redacted_headers": redacted,
        })
    }

    fn map_response(&self, req: &HttpRequest, resp: &HttpResponse) -> EffectOutcome {
        if resp.body.len() > self.max_body_bytes {
            return EffectOutcome::permanent("response body exceeds limit");
        }
        let content_type = header_get(&resp.headers, "content-type");
        let base = self.base_result(req, Some(resp.status), content_type);
        let mut with = |extra: Value| {
            let mut b = base.clone();
            if let (Some(o), Some(e)) = (b.as_object_mut(), extra.as_object()) {
                for (k, v) in e {
                    o.insert(k.clone(), v.clone());
                }
            }
            b
        };
        match resp.status {
            200..=299 => EffectOutcome::succeeded(with(json!({ "body": resp.body }))),
            429 => {
                let retry_after = header_get(&resp.headers, "retry-after").map(|s| s.to_string());
                let mut o = EffectOutcome::retryable("rate limited (429)");
                o.result = with(json!({ "retry_after": retry_after }));
                o
            }
            400..=499 => {
                let mut o = EffectOutcome::permanent(&format!("client error {}", resp.status));
                o.result = base;
                o
            }
            500..=599 => {
                let mut o = if req.method.idempotent() {
                    EffectOutcome::retryable(&format!("server error {} (idempotent)", resp.status))
                } else {
                    EffectOutcome::unknown(&format!(
                        "server error {} (non-idempotent) — mutation unknown",
                        resp.status
                    ))
                };
                o.result = base;
                o
            }
            other => {
                let mut o = EffectOutcome::unknown(&format!("unexpected status {other}"));
                o.result = base;
                o
            }
        }
    }

    fn map_error(&self, req: &HttpRequest, err: HttpTransportError) -> EffectOutcome {
        let mut o = match err {
            // never reached the server → no mutation → safe to retry for any method
            HttpTransportError::Dns | HttpTransportError::Connect | HttpTransportError::Tls => {
                EffectOutcome::retryable(&format!("{err:?}: request did not reach the server"))
            }
            // sent but no response → idempotent can retry, otherwise the mutation is unknown
            HttpTransportError::Timeout => {
                if req.method.idempotent() {
                    EffectOutcome::retryable("timeout on idempotent method")
                } else {
                    EffectOutcome::unknown("timeout after sending non-idempotent request — mutation unknown")
                }
            }
        };
        o.result = self.base_result(req, None, None);
        o
    }
}

#[async_trait]
impl CapabilityExecutor for HttpCapabilityExecutor {
    fn capability_id(&self) -> &str {
        &self.capability_id
    }

    async fn execute(&self, req: &EffectRequest) -> EffectOutcome {
        // parse the HTTP request out of the effect args
        let method = match req.args.get("method").and_then(|m| m.as_str()).and_then(HttpMethod::from_str) {
            Some(m) => m,
            None => return EffectOutcome::permanent("malformed HTTP request: missing/invalid method"),
        };
        let url = match req.args.get("url").and_then(|u| u.as_str()) {
            Some(u) if !u.is_empty() => u.to_string(),
            _ => return EffectOutcome::permanent("malformed HTTP request: missing url"),
        };
        let headers: Vec<(String, String)> = req
            .args
            .get("headers")
            .and_then(|h| h.as_object())
            .map(|o| o.iter().map(|(k, v)| (k.clone(), v.as_str().unwrap_or("").to_string())).collect())
            .unwrap_or_default();
        let body = req
            .args
            .get("body")
            .map(|b| if let Some(s) = b.as_str() { s.to_string() } else { b.to_string() })
            .unwrap_or_default();
        let correlation_id = req
            .args
            .get("correlation_id")
            .and_then(|c| c.as_str())
            .unwrap_or("")
            .to_string();

        // POLICY: non-idempotent methods require an idempotency key.
        if !method.idempotent() && req.idempotency_key.is_empty() {
            return EffectOutcome::permanent("non-idempotent method requires an idempotency key");
        }

        // resolve injected credentials; refuse (do NOT send) if a secret is missing.
        let resolved = match resolve_secrets(&headers, self.secrets.as_ref()) {
            Ok(h) => h,
            Err(e) => return EffectOutcome::permanent(&e),
        };

        let http_req = HttpRequest { method, url, headers: resolved, body, correlation_id };

        self.sends.fetch_add(1, Ordering::SeqCst);
        match self.transport.send(&http_req).await {
            Ok(resp) => self.map_response(&http_req, &resp),
            Err(err) => self.map_error(&http_req, err),
        }
    }
}

// ── Fake transport + secret provider (proof only — no real network) ────────────

/// A fake transport: returns a programmed result and captures the last request actually sent
/// (so tests can assert correlation headers / resolved secrets / no re-send on replay).
pub struct FakeHttpTransport {
    programmed: Mutex<Result<HttpResponse, HttpTransportError>>,
    last: Mutex<Option<HttpRequest>>,
    sends: AtomicU64,
}

impl FakeHttpTransport {
    pub fn new(programmed: Result<HttpResponse, HttpTransportError>) -> Self {
        Self { programmed: Mutex::new(programmed), last: Mutex::new(None), sends: AtomicU64::new(0) }
    }
    pub fn ok(status: u16, body: &str, headers: Vec<(&str, &str)>) -> Self {
        Self::new(Ok(HttpResponse {
            status,
            headers: headers.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect(),
            body: body.to_string(),
        }))
    }
    pub fn err(e: HttpTransportError) -> Self {
        Self::new(Err(e))
    }
    pub fn sends(&self) -> u64 {
        self.sends.load(Ordering::SeqCst)
    }
    pub fn last_request(&self) -> Option<HttpRequest> {
        self.last.lock().unwrap().clone()
    }
}

#[async_trait]
impl HttpTransport for FakeHttpTransport {
    async fn send(&self, req: &HttpRequest) -> Result<HttpResponse, HttpTransportError> {
        self.sends.fetch_add(1, Ordering::SeqCst);
        *self.last.lock().unwrap() = Some(req.clone());
        self.programmed.lock().unwrap().clone()
    }
}

/// A fake in-memory secret provider.
pub struct MapSecretProvider {
    map: std::collections::HashMap<String, String>,
}

impl MapSecretProvider {
    pub fn new(pairs: &[(&str, &str)]) -> Self {
        Self { map: pairs.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect() }
    }
}

impl SecretProvider for MapSecretProvider {
    fn resolve(&self, name: &str) -> Option<String> {
        self.map.get(name).cloned()
    }
}
