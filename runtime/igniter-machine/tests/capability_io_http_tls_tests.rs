//! LAB-MACHINE-CAPABILITY-HTTP-TLS-P14-IMPL — real TLS transport vs a LOCAL self-signed server.
//!
//! Proves the P14 policy on a REAL rustls handshake (no external internet): a local TLS server
//! with a self-signed cert (test fixture), and `TlsLoopbackHttpTransport`. Cert-validation
//! failure → permanent; transient handshake error → retryable; allowlist/https/redirect/replay/
//! redaction/correlation all preserved. Behind the `tls` feature.
#![cfg(feature = "tls")]

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{
    run_effect_with_passport, CapabilityExecutor, CapabilityExecutorRegistry, CapabilityPassport,
    EffectRequest, OutcomeKind, RunMode, RECEIPTS_STORE,
};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::http::{
    HttpCapabilityExecutor, HttpTransport, MapSecretProvider, SecretProvider,
    TlsLoopbackHttpTransport,
};
use serde_json::{json, Value};
use std::sync::{Arc, Mutex};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;
use tokio_rustls::rustls::{Certificate, PrivateKey, ServerConfig};
use tokio_rustls::TlsAcceptor;

const CAP: &str = "IO.HttpCapability";
const CERT: &str = include_str!("fixtures/tls/cert.pem"); // leaf server cert (presented by server)
const KEY: &str = include_str!("fixtures/tls/key.pem"); // leaf server key
const CA: &str = include_str!("fixtures/tls/ca.pem"); // trust anchor (trusted by the client)

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}
fn clock() -> Arc<dyn ClockProvider> {
    Arc::new(FixedClock::new(100.0))
}
fn passport() -> CapabilityPassport {
    CapabilityPassport {
        subject: "svc".into(),
        capability_id: CAP.into(),
        scopes: vec!["read".into()],
        issued_at: 0.0,
        expires_at: Some(1_000_000.0),
        revoked: false,
        evidence_digest: "sig".into(),
    }
}
fn no_secrets() -> Arc<dyn SecretProvider> {
    Arc::new(MapSecretProvider::new(&[]))
}
/// Executor over a transport that TRUSTS the local test CA, external-profile + allow localhost.
fn trusting_exec(secrets: Arc<dyn SecretProvider>) -> HttpCapabilityExecutor {
    let t =
        Arc::new(TlsLoopbackHttpTransport::trusting_pem(CA.as_bytes())) as Arc<dyn HttpTransport>;
    HttpCapabilityExecutor::new(CAP, t, secrets).external_profile(&["localhost"])
}
fn ereq(method: &str, url: &str, key: &str, extra: Value) -> EffectRequest {
    let mut args = json!({ "method": method, "url": url, "correlation_id": "corr-tls" });
    if let (Some(o), Some(e)) = (args.as_object_mut(), extra.as_object()) {
        for (k, v) in e {
            o.insert(k.clone(), v.clone());
        }
    }
    EffectRequest {
        capability_id: CAP.into(),
        idempotency_key: key.into(),
        authority_ref: None,
        args,
    }
}

fn find(hay: &[u8], needle: &[u8]) -> Option<usize> {
    hay.windows(needle.len()).position(|w| w == needle)
}
fn content_length(head: &str) -> usize {
    head.lines()
        .find(|l| l.to_ascii_lowercase().starts_with("content-length:"))
        .and_then(|l| l.split(':').nth(1))
        .and_then(|v| v.trim().parse().ok())
        .unwrap_or(0)
}

fn tls_config() -> Arc<ServerConfig> {
    let certs: Vec<Certificate> = rustls_pemfile::certs(&mut CERT.as_bytes())
        .unwrap()
        .into_iter()
        .map(Certificate)
        .collect();
    let key = PrivateKey(
        rustls_pemfile::pkcs8_private_keys(&mut KEY.as_bytes())
            .unwrap()
            .remove(0),
    );
    Arc::new(
        ServerConfig::builder()
            .with_safe_defaults()
            .with_no_client_auth()
            .with_single_cert(certs, key)
            .unwrap(),
    )
}

/// A real local TLS HTTP/1.1 server. Records correlation ids; serves a fixed status/body.
async fn start_tls_server(status: u16, body: &str) -> (u16, Arc<Mutex<Vec<String>>>) {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let acceptor = TlsAcceptor::from(tls_config());
    let recorded = Arc::new(Mutex::new(Vec::new()));
    let rec = recorded.clone();
    let body = body.to_string();
    tokio::spawn(async move {
        while let Ok((tcp, _)) = listener.accept().await {
            let acceptor = acceptor.clone();
            let rec = rec.clone();
            let body = body.clone();
            tokio::spawn(async move {
                let mut tls = match acceptor.accept(tcp).await {
                    Ok(s) => s,
                    Err(_) => return,
                };
                let mut data = Vec::new();
                let mut buf = vec![0u8; 4096];
                loop {
                    let n = match tls.read(&mut buf).await {
                        Ok(0) => break,
                        Ok(n) => n,
                        Err(_) => return,
                    };
                    data.extend_from_slice(&buf[..n]);
                    if let Some(hp) = find(&data, b"\r\n\r\n") {
                        let head = String::from_utf8_lossy(&data[..hp]).to_string();
                        if data.len() - (hp + 4) >= content_length(&head) {
                            let corr = head
                                .lines()
                                .find(|l| l.to_ascii_lowercase().starts_with("x-correlation-id:"))
                                .and_then(|l| l.split(':').nth(1))
                                .map(|v| v.trim().to_string())
                                .unwrap_or_default();
                            rec.lock().unwrap().push(corr);
                            break;
                        }
                    }
                }
                let resp = format!(
                    "HTTP/1.1 {status} S\r\nConnection: close\r\nContent-Length: {}\r\n\r\n{}",
                    body.len(),
                    body
                );
                let _ = tls.write_all(resp.as_bytes()).await;
                // clean TLS close (send close_notify) so the client's read_to_end completes
                // without a truncation error.
                let _ = tls.shutdown().await;
            });
        }
    });
    (port, recorded)
}

/// A plain (non-TLS) TCP server that accepts then drops — a transient handshake failure source.
async fn start_bad_tcp_server() -> u16 {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    tokio::spawn(async move {
        while let Ok((tcp, _)) = listener.accept().await {
            drop(tcp); // immediately close — no TLS handshake
        }
    });
    port
}

// ── #1/#9: real TLS handshake succeeds; correlation sent + recorded ────────────

#[test]
fn tls_handshake_succeeds_with_receipt_and_correlation() {
    rt().block_on(async {
        let (port, rec) = start_tls_server(200, "pong").await;
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(Arc::new(trusting_exec(no_secrets())));

        let out = run_effect_with_passport(
            &reg,
            &receipts,
            &clock(),
            &passport(),
            "read",
            &ereq(
                "GET",
                &format!("https://localhost:{port}/ping"),
                "t1",
                json!({}),
            ),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(out.kind, OutcomeKind::Succeeded, "{:?}", out.failure_kind);
        assert_eq!(out.result["body"], json!("pong"));

        assert_eq!(
            rec.lock().unwrap()[0],
            "corr-tls",
            "server received the correlation header"
        );
        let r = receipts
            .read_as_of(RECEIPTS_STORE, "IO.HttpCapability:t1", f64::MAX)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(r.value["correlation_id"], json!("corr-tls"));
    });
}

// ── #2: invalid (untrusted self-signed) cert → permanent ───────────────────────

#[test]
fn invalid_cert_is_permanent() {
    rt().block_on(async {
        let (port, _) = start_tls_server(200, "x").await;
        // a transport that trusts NOTHING extra → the self-signed cert is UnknownIssuer
        let t = Arc::new(TlsLoopbackHttpTransport::untrusting()) as Arc<dyn HttpTransport>;
        let exec =
            HttpCapabilityExecutor::new(CAP, t, no_secrets()).external_profile(&["localhost"]);
        let out = exec
            .execute(&ereq(
                "GET",
                &format!("https://localhost:{port}/x"),
                "k",
                json!({}),
            ))
            .await;
        assert_eq!(out.kind, OutcomeKind::PermanentFailure);
        assert!(
            out.failure_kind.unwrap().contains("certificate"),
            "bad cert → permanent security failure"
        );
    });
}

// ── #3: transient TLS handshake error → retryable ──────────────────────────────

#[test]
fn transient_tls_error_is_retryable() {
    rt().block_on(async {
        let port = start_bad_tcp_server().await; // accepts then closes — not a TLS endpoint
        let out = trusting_exec(no_secrets())
            .execute(&ereq(
                "GET",
                &format!("https://localhost:{port}/x"),
                "k",
                json!({}),
            ))
            .await;
        // a non-certificate handshake failure is transient → safe to retry
        assert_eq!(out.kind, OutcomeKind::Retryable);
    });
}

// ── #4/#5: non-allowlisted refused before connect; plain http refused ──────────

#[test]
fn non_allowlisted_and_plain_http_refused_before_connect() {
    rt().block_on(async {
        let exec = trusting_exec(no_secrets());
        let nonallow = exec
            .execute(&ereq("GET", "https://evil.com/x", "k", json!({})))
            .await;
        assert_eq!(nonallow.kind, OutcomeKind::PermanentFailure);

        let plain = trusting_exec(no_secrets())
            .execute(&ereq("GET", "http://localhost:9/x", "k", json!({})))
            .await;
        assert_eq!(plain.kind, OutcomeKind::PermanentFailure);
        assert!(plain.failure_kind.unwrap().contains("https"));
    });
}

// ── #6: redirect not followed ──────────────────────────────────────────────────

#[test]
fn redirect_not_followed() {
    rt().block_on(async {
        let (port, _) = start_tls_server(301, "").await;
        let out = trusting_exec(no_secrets())
            .execute(&ereq(
                "GET",
                &format!("https://localhost:{port}/x"),
                "k",
                json!({}),
            ))
            .await;
        assert_eq!(out.kind, OutcomeKind::PermanentFailure);
        assert!(out.failure_kind.unwrap().contains("redirect not followed"));
    });
}

// ── #7: replay does not re-send over TLS ───────────────────────────────────────

#[test]
fn replay_does_not_resend_over_tls() {
    rt().block_on(async {
        let (port, rec) = start_tls_server(200, "ok").await;
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(Arc::new(trusting_exec(no_secrets())));
        let req = ereq(
            "GET",
            &format!("https://localhost:{port}/x"),
            "r1",
            json!({}),
        );

        run_effect_with_passport(
            &reg,
            &receipts,
            &clock(),
            &passport(),
            "read",
            &req,
            RunMode::Live,
        )
        .await
        .unwrap();
        run_effect_with_passport(
            &reg,
            &receipts,
            &clock(),
            &passport(),
            "read",
            &req,
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(
            rec.lock().unwrap().len(),
            1,
            "replay must not open a second TLS connection"
        );
    });
}

// ── #8: secrets redacted over a real TLS request ───────────────────────────────

#[test]
fn secrets_redacted_over_tls() {
    rt().block_on(async {
        let (port, _) = start_tls_server(200, "ok").await;
        let secrets: Arc<dyn SecretProvider> =
            Arc::new(MapSecretProvider::new(&[("tok", "s3cr3t")]));
        let out = trusting_exec(secrets)
            .execute(&ereq(
                "GET",
                &format!("https://localhost:{port}/x"),
                "k",
                json!({ "headers": { "Authorization": "{{secret:tok}}" } }),
            ))
            .await;
        assert_eq!(out.kind, OutcomeKind::Succeeded);
        assert!(!out.result.to_string().contains("s3cr3t"));
        assert_eq!(out.result["redacted_headers"], json!(["Authorization"]));
    });
}
