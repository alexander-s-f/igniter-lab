//! LAB-MACHINE-CAPABILITY-HTTP-EXTERNAL-P14 — external allowlist + TLS POLICY (fake transport).
//!
//! Readiness + constrained spike for the first step PAST the loopback glass box. The real
//! rustls transport is a deferred follow-up; here the safety-critical policy is proven against a
//! fake TLS-aware transport: vetted host allowlist (refused before DNS/connect), https-only,
//! no external mutation, cert-failure taxonomy, redirects not followed, redaction, replay,
//! correlation, auditable transport-error outcomes.

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{
    run_effect_with_passport, CapabilityExecutor, CapabilityExecutorRegistry, CapabilityPassport,
    EffectRequest, OutcomeKind, RunMode, RECEIPTS_STORE,
};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::http::{
    FakeHttpTransport, HttpCapabilityExecutor, HttpTransport, HttpTransportError, MapSecretProvider,
    SecretProvider,
};
use serde_json::{json, Value};
use std::sync::Arc;

const CAP: &str = "IO.HttpCapability";
const HOST: &str = "api.example.com";

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap()
}
fn clock() -> Arc<dyn ClockProvider> {
    Arc::new(FixedClock::new(100.0))
}
fn passport() -> CapabilityPassport {
    CapabilityPassport {
        subject: "svc".into(),
        capability_id: CAP.into(),
        scopes: vec!["read".into(), "write".into()],
        issued_at: 0.0,
        expires_at: Some(1_000_000.0),
        revoked: false,
        evidence_digest: "sig".into(),
    }
}
fn no_secrets() -> Arc<dyn SecretProvider> {
    Arc::new(MapSecretProvider::new(&[]))
}
/// The P14 external profile: vetted allowlist + https-only + read-only.
fn ext_exec(transport: Arc<FakeHttpTransport>, secrets: Arc<dyn SecretProvider>) -> HttpCapabilityExecutor {
    HttpCapabilityExecutor::new(CAP, transport as Arc<dyn HttpTransport>, secrets).external_profile(&[HOST])
}
fn ereq(method: &str, url: &str, key: &str, extra: Value) -> EffectRequest {
    let mut args = json!({ "method": method, "url": url, "correlation_id": "c1" });
    if let (Some(o), Some(e)) = (args.as_object_mut(), extra.as_object()) {
        for (k, v) in e {
            o.insert(k.clone(), v.clone());
        }
    }
    EffectRequest { capability_id: CAP.into(), idempotency_key: key.into(), authority_ref: None, args }
}

// ── #1: non-allowlisted host refused before send ───────────────────────────────

#[test]
fn non_allowlisted_host_refused_before_send() {
    rt().block_on(async {
        let t = Arc::new(FakeHttpTransport::ok(200, "x", vec![]));
        let out = ext_exec(t.clone(), no_secrets()).execute(&ereq("GET", "https://evil.com/x", "k", json!({}))).await;
        assert_eq!(out.kind, OutcomeKind::PermanentFailure);
        assert_eq!(t.sends(), 0, "non-allowlisted host must be refused before any send");
    });
}

// ── #2/#8: allowlisted HTTPS GET succeeds, writes receipt with correlation ─────

#[test]
fn allowlisted_https_get_succeeds_with_receipt() {
    rt().block_on(async {
        let t = Arc::new(FakeHttpTransport::ok(200, "ok", vec![("content-type", "application/json")]));
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(Arc::new(ext_exec(t, no_secrets())));

        let out = run_effect_with_passport(&reg, &receipts, &clock(), &passport(), "read", &ereq("GET", &format!("https://{HOST}/ping"), "g1", json!({})), RunMode::Live).await.unwrap();
        assert_eq!(out.kind, OutcomeKind::Succeeded);
        let r = receipts.read_as_of(RECEIPTS_STORE, "IO.HttpCapability:g1", f64::MAX).await.unwrap().unwrap();
        assert_eq!(r.value["outcome_kind"], json!("succeeded"));
        assert_eq!(r.value["correlation_id"], json!("c1"));
    });
}

// ── #3/#9: cert/tls/dns taxonomy, explicit and auditable ───────────────────────

#[test]
fn cert_invalid_permanent_tls_dns_retryable() {
    rt().block_on(async {
        let cert = Arc::new(FakeHttpTransport::err(HttpTransportError::CertInvalid));
        let out = ext_exec(cert, no_secrets()).execute(&ereq("GET", &format!("https://{HOST}/x"), "k", json!({}))).await;
        assert_eq!(out.kind, OutcomeKind::PermanentFailure, "bad cert is a permanent security failure");

        for e in [HttpTransportError::Tls, HttpTransportError::Dns, HttpTransportError::Connect] {
            let t = Arc::new(FakeHttpTransport::err(e));
            let out = ext_exec(t, no_secrets()).execute(&ereq("GET", &format!("https://{HOST}/x"), "k", json!({}))).await;
            assert_eq!(out.kind, OutcomeKind::Retryable, "{e:?} did not reach server → retryable");
        }
    });
}

#[test]
fn transport_error_is_an_auditable_receipt() {
    rt().block_on(async {
        let t = Arc::new(FakeHttpTransport::err(HttpTransportError::Dns));
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(Arc::new(ext_exec(t, no_secrets())));

        run_effect_with_passport(&reg, &receipts, &clock(), &passport(), "read", &ereq("GET", &format!("https://{HOST}/x"), "e1", json!({})), RunMode::Live).await.unwrap();
        let r = receipts.read_as_of(RECEIPTS_STORE, "IO.HttpCapability:e1", f64::MAX).await.unwrap().unwrap();
        assert_eq!(r.value["outcome_kind"], json!("retryable"), "transport errors are auditable outcomes");
    });
}

// ── #4: timeout maps per P10 ───────────────────────────────────────────────────

#[test]
fn timeout_get_is_retryable() {
    rt().block_on(async {
        let t = Arc::new(FakeHttpTransport::err(HttpTransportError::Timeout));
        let out = ext_exec(t, no_secrets()).execute(&ereq("GET", &format!("https://{HOST}/x"), "k", json!({}))).await;
        assert_eq!(out.kind, OutcomeKind::Retryable);
    });
}

// ── #5: redirects are not followed ─────────────────────────────────────────────

#[test]
fn redirect_not_followed_is_permanent() {
    rt().block_on(async {
        let t = Arc::new(FakeHttpTransport::ok(301, "", vec![("location", "https://evil.com/")]));
        let out = ext_exec(t.clone(), no_secrets()).execute(&ereq("GET", &format!("https://{HOST}/x"), "k", json!({}))).await;
        assert_eq!(out.kind, OutcomeKind::PermanentFailure);
        assert!(out.failure_kind.unwrap().contains("redirect not followed"));
    });
}

// ── #6: secrets still redacted ─────────────────────────────────────────────────

#[test]
fn secrets_still_redacted() {
    rt().block_on(async {
        let t = Arc::new(FakeHttpTransport::ok(200, "ok", vec![]));
        let secrets: Arc<dyn SecretProvider> = Arc::new(MapSecretProvider::new(&[("tok", "s3cr3t")]));
        let out = ext_exec(t, secrets).execute(&ereq("GET", &format!("https://{HOST}/x"), "k", json!({ "headers": { "Authorization": "{{secret:tok}}" } }))).await;
        assert_eq!(out.kind, OutcomeKind::Succeeded);
        assert!(!out.result.to_string().contains("s3cr3t"));
        assert_eq!(out.result["redacted_headers"], json!(["Authorization"]));
    });
}

// ── #7: replay does not re-send ────────────────────────────────────────────────

#[test]
fn replay_does_not_resend() {
    rt().block_on(async {
        let t = Arc::new(FakeHttpTransport::ok(200, "ok", vec![]));
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(Arc::new(ext_exec(t.clone(), no_secrets())));
        let req = ereq("GET", &format!("https://{HOST}/x"), "r1", json!({}));

        run_effect_with_passport(&reg, &receipts, &clock(), &passport(), "read", &req, RunMode::Live).await.unwrap();
        run_effect_with_passport(&reg, &receipts, &clock(), &passport(), "read", &req, RunMode::Live).await.unwrap();
        assert_eq!(t.sends(), 1, "replay must not re-send");
    });
}

// ── #10 + https-only: no external POST mutation; plain http refused ────────────

#[test]
fn no_external_post_mutation() {
    rt().block_on(async {
        let t = Arc::new(FakeHttpTransport::ok(200, "ok", vec![]));
        let out = ext_exec(t.clone(), no_secrets()).execute(&ereq("POST", &format!("https://{HOST}/orders"), "k", json!({ "body": "{}" }))).await;
        assert_eq!(out.kind, OutcomeKind::PermanentFailure);
        assert!(out.failure_kind.unwrap().contains("external mutation not permitted"));
        assert_eq!(t.sends(), 0);
    });
}

#[test]
fn plain_http_refused_in_external_profile() {
    rt().block_on(async {
        let t = Arc::new(FakeHttpTransport::ok(200, "ok", vec![]));
        let out = ext_exec(t.clone(), no_secrets()).execute(&ereq("GET", &format!("http://{HOST}/x"), "k", json!({}))).await;
        assert_eq!(out.kind, OutcomeKind::PermanentFailure);
        assert!(out.failure_kind.unwrap().contains("requires https"));
        assert_eq!(t.sends(), 0);
    });
}
