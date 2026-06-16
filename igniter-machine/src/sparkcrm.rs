//! SparkCRM-shaped capability executor (LAB-MACHINE-CAPABILITY-SPARKCRM-EXECUTOR-P15).
//!
//! The first DOMAIN executor — it ties the whole stack together for one product boundary:
//! a forward action (create), a compensating action (cancel), and a correlation lookup, all
//! over the P14 HTTP/TLS policy (allowlist + https + redaction). It is transport-agnostic
//! (holds an `Arc<dyn HttpTransport>`), so the proof runs it over the REAL TLS transport
//! against a LOCAL fake SparkCRM server — no production API, no real credentials, no internet.
//!
//! Layering: `SparkCrmExecutor` translates a domain request into an HTTP request and delegates
//! to an inner `HttpCapabilityExecutor` (which applies the status taxonomy, redaction, and
//! host/https policy). The OUTER `run_write_effect` / `reconcile` / `compensation` machinery
//! is unchanged — this executor just plugs into it.

use crate::capability::{CapabilityExecutor, EffectOutcome, EffectRequest, OutcomeKind};
use crate::compensation::CompensatableExecutor;
use crate::correlation::{CorrelationLookup, CorrelationResolver};
use crate::http::{HttpCapabilityExecutor, HttpTransport, SecretProvider};
use async_trait::async_trait;
use serde_json::{json, Value};
use std::sync::Arc;

pub struct SparkCrmExecutor {
    capability_id: String,
    http: HttpCapabilityExecutor,
    base_url: String,
    /// A secret REFERENCE (e.g. `{{secret:sparkcrm_token}}`) — resolved by the host
    /// SecretProvider at send time, never a raw credential.
    secret_ref: String,
}

impl SparkCrmExecutor {
    pub fn new(
        capability_id: &str,
        transport: Arc<dyn HttpTransport>,
        secrets: Arc<dyn SecretProvider>,
        base_url: &str,
        allowed_host: &str,
        secret_ref: &str,
    ) -> Self {
        // SparkCRM is a vetted product integration: allowlisted host + https, mutations ALLOWED
        // (the create is a POST) — protected by the full receipt/idempotency/reconcile/compensate
        // stack, NOT the read-only external profile.
        let http = HttpCapabilityExecutor::new(capability_id, transport, secrets)
            .with_allowed_hosts(&[allowed_host])
            .require_https();
        Self {
            capability_id: capability_id.to_string(),
            http,
            base_url: base_url.to_string(),
            secret_ref: secret_ref.to_string(),
        }
    }

    fn auth_headers(&self, idempotency_key: &str) -> Value {
        json!({
            "Authorization": self.secret_ref,
            "Idempotency-Key": idempotency_key,
        })
    }

    async fn http_call(&self, method: &str, url: String, headers: Value, body: &str, correlation: &str, key: &str) -> EffectOutcome {
        let args = json!({
            "method": method,
            "url": url,
            "headers": headers,
            "body": body,
            "correlation_id": correlation,
        });
        let inner = EffectRequest {
            capability_id: self.capability_id.clone(),
            idempotency_key: key.to_string(),
            authority_ref: None,
            args,
        };
        self.http.execute(&inner).await
    }
}

#[async_trait]
impl CapabilityExecutor for SparkCrmExecutor {
    fn capability_id(&self) -> &str {
        &self.capability_id
    }

    /// Forward action. `req.args = { action, lead, correlation_id }`.
    async fn execute(&self, req: &EffectRequest) -> EffectOutcome {
        let action = req.args.get("action").and_then(|a| a.as_str()).unwrap_or("");
        let correlation = req.args.get("correlation_id").and_then(|c| c.as_str()).unwrap_or("");
        match action {
            "create_lead" => {
                let body = serde_json::to_string(req.args.get("lead").unwrap_or(&Value::Null)).unwrap_or_else(|_| "{}".into());
                self.http_call(
                    "POST",
                    format!("{}/leads", self.base_url),
                    self.auth_headers(&req.idempotency_key),
                    &body,
                    correlation,
                    &req.idempotency_key,
                )
                .await
            }
            other => EffectOutcome::permanent(&format!("unknown SparkCRM action: {other}")),
        }
    }
}

/// Extract the created resource id from a forward receipt's recorded result body.
fn lead_id_from_receipt(original_receipt: &Value) -> Option<String> {
    let body = original_receipt.get("result").and_then(|r| r.get("body")).and_then(|b| b.as_str())?;
    let parsed: Value = serde_json::from_str(body).ok()?;
    parsed.get("id").and_then(|i| i.as_str()).map(|s| s.to_string())
}

#[async_trait]
impl CompensatableExecutor for SparkCrmExecutor {
    fn capability_id(&self) -> &str {
        &self.capability_id
    }
    fn is_compensatable(&self) -> bool {
        true // a created lead can be cancelled
    }

    /// Compensating action: cancel the previously created lead.
    async fn compensate(&self, original_receipt: &Value, compensation_correlation_id: &str) -> EffectOutcome {
        let lead_id = match lead_id_from_receipt(original_receipt) {
            Some(id) => id,
            None => return EffectOutcome::permanent("cannot compensate: no lead id in original receipt"),
        };
        let key = format!("cancel-{compensation_correlation_id}");
        self.http_call(
            "POST",
            format!("{}/leads/{}/cancel", self.base_url, lead_id),
            self.auth_headers(&key),
            "{}",
            compensation_correlation_id,
            &key,
        )
        .await
    }
}

#[async_trait]
impl CorrelationResolver for SparkCrmExecutor {
    /// Look up the fate of a forward action by correlation id (read-only GET /status).
    async fn lookup(&self, correlation_id: &str) -> CorrelationLookup {
        let out = self
            .http_call(
                "GET",
                format!("{}/status?correlation_id={}", self.base_url, correlation_id),
                json!({ "Authorization": self.secret_ref }),
                "",
                correlation_id,
                &format!("status-{correlation_id}"),
            )
            .await;
        match out.kind {
            OutcomeKind::Succeeded => CorrelationLookup::Landed, // 200 → the effect landed
            OutcomeKind::PermanentFailure => {
                // 404 → not found (did not land); any other 4xx is also a definite negative here
                if out.result.get("status").and_then(|s| s.as_u64()) == Some(404) {
                    CorrelationLookup::NotFound
                } else {
                    CorrelationLookup::Unavailable
                }
            }
            _ => CorrelationLookup::Unavailable, // retryable/unknown → cannot determine
        }
    }
}
