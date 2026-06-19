//! LAB-MACHINE-CAPABILITY-HTTP-P10 — HTTP executor policy, proven on a FAKE transport.
//!
//! Fixes the HTTP policy before any real network: status taxonomy, idempotency, redaction,
//! injected credentials, rate limits, body limits, transport-error classification, replay.
//! No real network / TLS / DNS.

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{
    CapabilityExecutor, CapabilityExecutorRegistry, CapabilityPassport, EffectRequest, OutcomeKind,
    RunMode, RECEIPTS_STORE,
};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::http::{
    FakeHttpTransport, HttpCapabilityExecutor, HttpTransport, HttpTransportError, MapSecretProvider,
    SecretProvider,
};
use igniter_machine::write::{run_write_effect, WriteRequest, WriteState};
use serde_json::{json, Value};
use std::sync::Arc;

const CAP: &str = "IO.HttpCapability";

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap()
}

fn exec_with(
    transport: Arc<FakeHttpTransport>,
    secrets: Arc<dyn SecretProvider>,
) -> HttpCapabilityExecutor {
    HttpCapabilityExecutor::new(CAP, transport as Arc<dyn HttpTransport>, secrets)
}

fn no_secrets() -> Arc<dyn SecretProvider> {
    Arc::new(MapSecretProvider::new(&[]))
}

fn ereq(method: &str, url: &str, key: &str, extra: Value) -> EffectRequest {
    let mut args = json!({ "method": method, "url": url, "correlation_id": "corr-1" });
    if let (Some(o), Some(e)) = (args.as_object_mut(), extra.as_object()) {
        for (k, v) in e {
            o.insert(k.clone(), v.clone());
        }
    }
    EffectRequest { capability_id: CAP.into(), idempotency_key: key.into(), authority_ref: None, args }
}

// ── status taxonomy ────────────────────────────────────────────────────────────

#[test]
fn success_2xx_is_succeeded() {
    rt().block_on(async {
        let t = Arc::new(FakeHttpTransport::ok(200, "hello", vec![("content-type", "text/plain")]));
        let out = exec_with(t.clone(), no_secrets()).execute(&ereq("GET", "https://api/x", "k", json!({}))).await;
        assert_eq!(out.kind, OutcomeKind::Succeeded);
        assert_eq!(out.result["status"], json!(200));
        assert_eq!(out.result["body"], json!("hello"));
        assert_eq!(out.result["correlation_id"], json!("corr-1"));
    });
}

#[test]
fn client_4xx_is_permanent() {
    rt().block_on(async {
        let t = Arc::new(FakeHttpTransport::ok(404, "no", vec![]));
        let out = exec_with(t, no_secrets()).execute(&ereq("GET", "https://api/x", "k", json!({}))).await;
        assert_eq!(out.kind, OutcomeKind::PermanentFailure);
    });
}

#[test]
fn rate_limit_429_is_retryable_with_retry_after() {
    rt().block_on(async {
        let t = Arc::new(FakeHttpTransport::ok(429, "slow down", vec![("retry-after", "30")]));
        let out = exec_with(t, no_secrets()).execute(&ereq("GET", "https://api/x", "k", json!({}))).await;
        assert_eq!(out.kind, OutcomeKind::Retryable);
        assert_eq!(out.result["retry_after"], json!("30"));
    });
}

#[test]
fn server_5xx_idempotent_retryable_but_post_unknown() {
    rt().block_on(async {
        let t = Arc::new(FakeHttpTransport::ok(503, "down", vec![]));
        let get = exec_with(t.clone(), no_secrets()).execute(&ereq("GET", "https://api/x", "k", json!({}))).await;
        assert_eq!(get.kind, OutcomeKind::Retryable, "5xx on idempotent GET → retryable");

        let t2 = Arc::new(FakeHttpTransport::ok(503, "down", vec![]));
        let post = exec_with(t2, no_secrets()).execute(&ereq("POST", "https://api/x", "k", json!({"body": "{}"}))).await;
        assert_eq!(post.kind, OutcomeKind::UnknownExternalState, "5xx on POST → mutation unknown");
    });
}

#[test]
fn timeout_idempotent_retryable_but_post_unknown() {
    rt().block_on(async {
        let tg = Arc::new(FakeHttpTransport::err(HttpTransportError::Timeout));
        let get = exec_with(tg, no_secrets()).execute(&ereq("GET", "https://api/x", "k", json!({}))).await;
        assert_eq!(get.kind, OutcomeKind::Retryable);

        let tp = Arc::new(FakeHttpTransport::err(HttpTransportError::Timeout));
        let post = exec_with(tp, no_secrets()).execute(&ereq("POST", "https://api/x", "k", json!({"body": "{}"}))).await;
        assert_eq!(post.kind, OutcomeKind::UnknownExternalState);
    });
}

#[test]
fn connect_dns_tls_errors_are_retryable_no_mutation() {
    rt().block_on(async {
        for e in [HttpTransportError::Connect, HttpTransportError::Dns, HttpTransportError::Tls] {
            let t = Arc::new(FakeHttpTransport::err(e));
            // even a POST is retryable here — the request never reached the server
            let out = exec_with(t, no_secrets()).execute(&ereq("POST", "https://api/x", "k", json!({"body": "{}"}))).await;
            assert_eq!(out.kind, OutcomeKind::Retryable, "{e:?} → no mutation → retryable");
        }
    });
}

// ── idempotency policy ─────────────────────────────────────────────────────────

#[test]
fn non_idempotent_without_key_refused() {
    rt().block_on(async {
        let t = Arc::new(FakeHttpTransport::ok(200, "ok", vec![]));
        let out = exec_with(t.clone(), no_secrets()).execute(&ereq("POST", "https://api/x", "", json!({"body": "{}"}))).await;
        assert_eq!(out.kind, OutcomeKind::PermanentFailure);
        assert_eq!(t.sends(), 0, "must not send a keyless non-idempotent request");
    });
}

// ── credentials + redaction ────────────────────────────────────────────────────

#[test]
fn missing_secret_is_not_sent() {
    rt().block_on(async {
        let t = Arc::new(FakeHttpTransport::ok(200, "ok", vec![]));
        let out = exec_with(t.clone(), no_secrets())
            .execute(&ereq("GET", "https://api/x", "k", json!({ "headers": { "Authorization": "{{secret:tok}}" } })))
            .await;
        assert_eq!(out.kind, OutcomeKind::PermanentFailure);
        assert_eq!(t.sends(), 0, "must not send when a credential is unresolved");
    });
}

#[test]
fn secret_is_resolved_and_sent_but_redacted_from_result() {
    rt().block_on(async {
        let t = Arc::new(FakeHttpTransport::ok(200, "ok", vec![]));
        let secrets: Arc<dyn SecretProvider> = Arc::new(MapSecretProvider::new(&[("tok", "s3cr3t")]));
        let out = exec_with(t.clone(), secrets)
            .execute(&ereq("GET", "https://api/x", "k", json!({ "headers": { "Authorization": "{{secret:tok}}" } })))
            .await;
        assert_eq!(out.kind, OutcomeKind::Succeeded);

        // the resolved secret WAS sent to the transport
        let sent = t.last_request().unwrap();
        assert!(sent.headers.iter().any(|(k, v)| k == "Authorization" && v == "s3cr3t"));

        // but it is NOT recorded in the result; the header name is listed as redacted
        let s = out.result.to_string();
        assert!(!s.contains("s3cr3t"), "secret must never appear in the recorded result");
        assert_eq!(out.result["redacted_headers"], json!(["Authorization"]));
    });
}

// ── forced request identity digest ─────────────────────────────────────────────

#[test]
fn request_digest_includes_identity() {
    rt().block_on(async {
        async fn digest(url: &str) -> Value {
            let t = Arc::new(FakeHttpTransport::ok(200, "ok", vec![]));
            exec_with(t, no_secrets())
                .execute(&ereq("GET", url, "k", json!({})))
                .await
                .result["request_digest"]
                .clone()
        }
        let a = digest("https://api/a").await;
        let b = digest("https://api/b").await;
        let a2 = digest("https://api/a").await;
        assert_ne!(a, b, "different URL → different digest");
        assert_eq!(a, a2, "same request → same digest");
    });
}

// ── response body limit ────────────────────────────────────────────────────────

#[test]
fn oversized_body_is_permanent() {
    rt().block_on(async {
        let big = "x".repeat(50);
        let t = Arc::new(FakeHttpTransport::ok(200, &big, vec![]));
        let exec = exec_with(t, no_secrets()).with_max_body(10);
        let out = exec.execute(&ereq("GET", "https://api/x", "k", json!({}))).await;
        assert_eq!(out.kind, OutcomeKind::PermanentFailure);
    });
}

// ── replay never re-sends HTTP (through the write protocol) ────────────────────

#[test]
fn replay_never_resends_http() {
    rt().block_on(async {
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let clock: Arc<dyn ClockProvider> = Arc::new(FixedClock::new(100.0));
        let t = Arc::new(FakeHttpTransport::ok(200, "created", vec![("content-type", "application/json")]));
        let secrets: Arc<dyn SecretProvider> = Arc::new(MapSecretProvider::new(&[("tok", "s3cr3t")]));
        let exec = Arc::new(HttpCapabilityExecutor::new(CAP, t.clone(), secrets));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);

        let passport = CapabilityPassport {
            subject: "svc".into(),
            capability_id: CAP.into(),
            scopes: vec!["write".into()],
            issued_at: 0.0,
            expires_at: Some(1_000_000.0),
            revoked: false,
            evidence_digest: "sig".into(),
        };
        let req = WriteRequest {
            capability_id: CAP.into(),
            operation: "http_post".into(),
            idempotency_key: "order-42".into(),
            payload: json!({ "method": "POST", "url": "https://api/orders", "body": "{}", "correlation_id": "corr-42", "headers": { "Authorization": "{{secret:tok}}" } }),
        };

        let first = run_write_effect(&reg, &receipts, &clock, &passport, "write", &req, RunMode::Live).await.unwrap();
        assert_eq!(first.state, WriteState::Committed);
        assert_eq!(t.sends(), 1);

        // replay the SAME write → must NOT re-send the HTTP POST
        let second = run_write_effect(&reg, &receipts, &clock, &passport, "write", &req, RunMode::Live).await.unwrap();
        assert_eq!(second.state, WriteState::Committed);
        assert_eq!(t.sends(), 1, "replay must never re-send HTTP");

        // and the receipt never stored the secret
        let receipt = receipts.read_as_of(RECEIPTS_STORE, "IO.HttpCapability:order-42", f64::MAX).await.unwrap().unwrap();
        assert!(!receipt.value.to_string().contains("s3cr3t"));
    });
}
