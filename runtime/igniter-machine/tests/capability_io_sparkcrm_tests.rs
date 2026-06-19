//! LAB-MACHINE-CAPABILITY-SPARKCRM-EXECUTOR-P15 — SparkCRM-shaped executor vs a LOCAL fake TLS upstream.
//!
//! The capstone: a domain executor (forward create + compensating cancel + correlation lookup)
//! over the real P14 TLS transport, against a LOCAL fake SparkCRM server. No production API, no
//! real credentials, no internet. Behind the `tls` feature.
#![cfg(feature = "tls")]

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{CapabilityExecutorRegistry, CapabilityPassport, RunMode, RECEIPTS_STORE};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::compensation::{run_compensation, CompensationResult};
use igniter_machine::correlation::{reconcile_unknown_by_correlation, CorrelationReconcileResult};
use igniter_machine::http::{HttpTransport, MapSecretProvider, SecretProvider, TlsLoopbackHttpTransport};
use igniter_machine::retry_queue::{enqueue_retry, RETRY_QUEUE_STORE};
use igniter_machine::sparkcrm::SparkCrmExecutor;
use igniter_machine::write::{run_write_effect, WriteRequest, WriteState};
use serde_json::{json, Value};
use std::collections::HashSet;
use std::sync::{Arc, Mutex};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;
use tokio_rustls::rustls::{Certificate, PrivateKey, ServerConfig};
use tokio_rustls::TlsAcceptor;

const CAP: &str = "IO.SparkCrmCapability";
const CERT: &str = include_str!("fixtures/tls/cert.pem");
const KEY: &str = include_str!("fixtures/tls/key.pem");
const CA: &str = include_str!("fixtures/tls/ca.pem");
const SECRET_REF: &str = "{{secret:sparkcrm_token}}";

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
        scopes: vec!["write".into()],
        issued_at: 0.0,
        expires_at: Some(1_000_000.0),
        revoked: false,
        evidence_digest: "sig".into(),
    }
}
fn secrets() -> Arc<dyn SecretProvider> {
    Arc::new(MapSecretProvider::new(&[("sparkcrm_token", "test-token-s3cr3t")]))
}

#[derive(Clone, Copy, PartialEq)]
enum Mode {
    Normal,
    RateLimited,
    BadRequest,
    ServerError,
    DropBeforeRecord,
    DropAfterRecord,
}

#[derive(Default)]
struct State {
    posts: u64,
    landed: HashSet<String>,
}

fn find(hay: &[u8], n: &[u8]) -> Option<usize> {
    hay.windows(n.len()).position(|w| w == n)
}
fn content_length(head: &str) -> usize {
    head.lines()
        .find(|l| l.to_ascii_lowercase().starts_with("content-length:"))
        .and_then(|l| l.split(':').nth(1))
        .and_then(|v| v.trim().parse().ok())
        .unwrap_or(0)
}
fn header(head: &str, name: &str) -> Option<String> {
    head.lines()
        .find(|l| l.to_ascii_lowercase().starts_with(&name.to_ascii_lowercase()))
        .and_then(|l| l.split(':').nth(1))
        .map(|v| v.trim().to_string())
}

fn tls_config() -> Arc<ServerConfig> {
    let certs: Vec<Certificate> = rustls_pemfile::certs(&mut CERT.as_bytes()).unwrap().into_iter().map(Certificate).collect();
    let key = PrivateKey(rustls_pemfile::pkcs8_private_keys(&mut KEY.as_bytes()).unwrap().remove(0));
    Arc::new(ServerConfig::builder().with_safe_defaults().with_no_client_auth().with_single_cert(certs, key).unwrap())
}

/// A fake SparkCRM HTTPS server: POST /leads (create), POST /leads/{id}/cancel, GET /status.
async fn start_sparkcrm(mode: Mode) -> (u16, Arc<Mutex<State>>) {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let acceptor = TlsAcceptor::from(tls_config());
    let state = Arc::new(Mutex::new(State::default()));
    let st = state.clone();
    tokio::spawn(async move {
        while let Ok((tcp, _)) = listener.accept().await {
            let acceptor = acceptor.clone();
            let st = st.clone();
            tokio::spawn(async move {
                let mut tls = match acceptor.accept(tcp).await { Ok(s) => s, Err(_) => return };
                let mut data = Vec::new();
                let mut buf = vec![0u8; 4096];
                let (method, path, head) = loop {
                    let n = match tls.read(&mut buf).await { Ok(0) => return, Ok(n) => n, Err(_) => return };
                    data.extend_from_slice(&buf[..n]);
                    if let Some(hp) = find(&data, b"\r\n\r\n") {
                        let head = String::from_utf8_lossy(&data[..hp]).to_string();
                        if data.len() - (hp + 4) >= content_length(&head) {
                            let mut parts = head.lines().next().unwrap_or("").split_whitespace();
                            break (parts.next().unwrap_or("").to_string(), parts.next().unwrap_or("").to_string(), head);
                        }
                    }
                };
                let corr = header(&head, "x-correlation-id:").unwrap_or_default();

                let (status, body): (u16, String) = if method == "POST" && path == "/leads" {
                    let mut s = st.lock().unwrap();
                    s.posts += 1;
                    if mode == Mode::DropBeforeRecord {
                        return; // drop without landing
                    }
                    s.landed.insert(corr.clone());
                    drop(s);
                    match mode {
                        Mode::DropAfterRecord => return, // landed, but ack lost
                        Mode::RateLimited => (429, "{\"error\":\"rate\"}".into()),
                        Mode::BadRequest => (400, "{\"error\":\"bad\"}".into()),
                        Mode::ServerError => (503, "{\"error\":\"down\"}".into()),
                        _ => (201, "{\"id\":\"lead-1\"}".into()),
                    }
                } else if method == "POST" && path.starts_with("/leads/") && path.ends_with("/cancel") {
                    (200, "{\"cancelled\":true}".into())
                } else if method == "GET" && path.starts_with("/status") {
                    let landed = st.lock().unwrap().landed.contains(&corr);
                    if landed { (200, "{\"found\":true}".into()) } else { (404, "{\"found\":false}".into()) }
                } else {
                    (404, "{}".into())
                };

                let resp = format!("HTTP/1.1 {status} S\r\nConnection: close\r\nContent-Length: {}\r\n\r\n{}", body.len(), body);
                let _ = tls.write_all(resp.as_bytes()).await;
                let _ = tls.shutdown().await;
            });
        }
    });
    (port, state)
}

fn spark(port: u16, allowed_host: &str) -> Arc<SparkCrmExecutor> {
    let transport = Arc::new(TlsLoopbackHttpTransport::trusting_pem(CA.as_bytes())) as Arc<dyn HttpTransport>;
    Arc::new(SparkCrmExecutor::new(CAP, transport, secrets(), &format!("https://localhost:{port}"), allowed_host, SECRET_REF))
}
fn create_req(key: &str, corr: &str) -> WriteRequest {
    WriteRequest {
        capability_id: CAP.into(),
        operation: "create_lead".into(),
        idempotency_key: key.into(),
        payload: json!({ "action": "create_lead", "lead": { "name": "Ada" }, "correlation_id": corr }),
    }
}
async fn receipt(receipts: &Arc<dyn TBackend>, key: &str) -> Value {
    receipts.read_as_of(RECEIPTS_STORE, &format!("{CAP}:{key}"), f64::MAX).await.unwrap().unwrap().value
}

// ── #1/#2: forward create succeeds; receipt redacts auth + stores correlation ──

#[test]
fn forward_create_succeeds_receipt_redacts_and_correlates() {
    rt().block_on(async {
        let (port, st) = start_sparkcrm(Mode::Normal).await;
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let exec = spark(port, "localhost");
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);

        let out = run_write_effect(&reg, &receipts, &clock(), &passport(), "write", &create_req("c1", "corr-1"), RunMode::Live).await.unwrap();
        assert_eq!(out.state, WriteState::Committed);
        assert_eq!(st.lock().unwrap().posts, 1);

        let r = receipt(&receipts, "c1").await;
        assert!(!r.to_string().contains("test-token-s3cr3t"), "auth secret must never be in the receipt");
        assert_eq!(r["correlation_id"], json!("corr-1"));
        assert_eq!(r["result"]["redacted_headers"], json!(["Authorization"]));
    });
}

// ── #3: replay does not re-send ────────────────────────────────────────────────

#[test]
fn replay_does_not_resend() {
    rt().block_on(async {
        let (port, st) = start_sparkcrm(Mode::Normal).await;
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let exec = spark(port, "localhost");
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);

        run_write_effect(&reg, &receipts, &clock(), &passport(), "write", &create_req("c3", "corr-3"), RunMode::Live).await.unwrap();
        run_write_effect(&reg, &receipts, &clock(), &passport(), "write", &create_req("c3", "corr-3"), RunMode::Live).await.unwrap();
        assert_eq!(st.lock().unwrap().posts, 1, "replay must not POST a second lead");
    });
}

// ── #4: lost response → unknown_external_state ─────────────────────────────────

#[test]
fn lost_response_is_unknown() {
    rt().block_on(async {
        let (port, _) = start_sparkcrm(Mode::DropAfterRecord).await;
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let exec = spark(port, "localhost");
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);

        let out = run_write_effect(&reg, &receipts, &clock(), &passport(), "write", &create_req("c4", "corr-4"), RunMode::Live).await.unwrap();
        assert_eq!(out.state, WriteState::UnknownExternalState);
    });
}

// ── #5: reconcile by correlation resolves landed / not-landed ──────────────────

#[test]
fn reconcile_by_correlation_landed_and_not_landed() {
    rt().block_on(async {
        // landed-but-unknown: server records the lead then drops the ack
        let (port, _) = start_sparkcrm(Mode::DropAfterRecord).await;
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let exec = spark(port, "localhost");
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec.clone());
        run_write_effect(&reg, &receipts, &clock(), &passport(), "write", &create_req("c5a", "corr-5a"), RunMode::Live).await.unwrap();
        // the SparkCRM executor IS the correlation resolver (GET /status)
        let r = reconcile_unknown_by_correlation(&receipts, &*exec, &clock(), CAP, "c5a").await.unwrap();
        assert_eq!(r, CorrelationReconcileResult::ResolvedCommitted, "server /status confirms it landed");

        // not-landed: a different unknown whose correlation the server never saw
        let (port2, _) = start_sparkcrm(Mode::DropBeforeRecord).await;
        let exec2 = spark(port2, "localhost");
        let mut reg2 = CapabilityExecutorRegistry::new();
        reg2.register(exec2.clone());
        run_write_effect(&reg2, &receipts, &clock(), &passport(), "write", &create_req("c5b", "corr-5b"), RunMode::Live).await.unwrap();
        let r2 = reconcile_unknown_by_correlation(&receipts, &*exec2, &clock(), CAP, "c5b").await.unwrap();
        assert_eq!(r2, CorrelationReconcileResult::ResolvedPermanentFailure, "server /status 404 → did not land");
    });
}

// ── #6: compensation aborts a committed effect ─────────────────────────────────

#[test]
fn compensation_aborts_committed() {
    rt().block_on(async {
        let (port, _) = start_sparkcrm(Mode::Normal).await;
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let exec = spark(port, "localhost");
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec.clone());
        run_write_effect(&reg, &receipts, &clock(), &passport(), "write", &create_req("c6", "corr-6"), RunMode::Live).await.unwrap();

        // the SparkCRM executor IS the compensator (POST /leads/{id}/cancel)
        let r = run_compensation(&receipts, &clock(), &passport(), &*exec, CAP, "c6", "comp-6").await.unwrap();
        assert_eq!(r, CompensationResult::Aborted);
        assert_eq!(receipt(&receipts, "c6").await["state"], json!("aborted"));
    });
}

// ── #7: 429 → retryable and produces a P9 retry intent ─────────────────────────

#[test]
fn rate_limit_retryable_and_enqueues_intent() {
    rt().block_on(async {
        let (port, _) = start_sparkcrm(Mode::RateLimited).await;
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let exec = spark(port, "localhost");
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);

        let out = run_write_effect(&reg, &receipts, &clock(), &passport(), "write", &create_req("c7", "corr-7"), RunMode::Live).await.unwrap();
        assert_eq!(out.state, WriteState::Retryable, "429 → retryable");

        // a 429 retryable feeds the P9 durable queue
        enqueue_retry(&receipts, &clock(), &create_req("c7", "corr-7"), "write", &passport().authority_digest(), 3, 10.0).await.unwrap();
        // the retry intent is keyed by the base idempotency key (P9)
        let intent = receipts.read_as_of(RETRY_QUEUE_STORE, "c7", f64::MAX).await.unwrap();
        assert!(intent.is_some(), "a retry intent fact was enqueued");
        assert_eq!(intent.unwrap().value["state"], json!("pending"));
    });
}

// ── #8: 4xx permanent, 5xx (POST) unknown per policy ───────────────────────────

#[test]
fn status_taxonomy_4xx_permanent_5xx_unknown() {
    rt().block_on(async {
        let (p400, _) = start_sparkcrm(Mode::BadRequest).await;
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(spark(p400, "localhost"));
        let bad = run_write_effect(&reg, &receipts, &clock(), &passport(), "write", &create_req("c8a", "corr-8a"), RunMode::Live).await.unwrap();
        assert_eq!(bad.state, WriteState::PermanentFailure, "400 → permanent");

        let (p503, _) = start_sparkcrm(Mode::ServerError).await;
        let mut reg2 = CapabilityExecutorRegistry::new();
        reg2.register(spark(p503, "localhost"));
        let down = run_write_effect(&reg2, &receipts, &clock(), &passport(), "write", &create_req("c8b", "corr-8b"), RunMode::Live).await.unwrap();
        assert_eq!(down.state, WriteState::UnknownExternalState, "5xx on a POST → mutation unknown");
    });
}

// ── #9: non-allowlisted host refused before connect ────────────────────────────

#[test]
fn non_allowlisted_host_refused() {
    rt().block_on(async {
        let (port, st) = start_sparkcrm(Mode::Normal).await;
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        // the executor's allowlist does NOT include the upstream host
        let exec = spark(port, "sparkcrm.production.example");
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);

        let out = run_write_effect(&reg, &receipts, &clock(), &passport(), "write", &create_req("c9", "corr-9"), RunMode::Live).await.unwrap();
        assert_eq!(out.state, WriteState::PermanentFailure);
        assert_eq!(st.lock().unwrap().posts, 0, "nothing reached the upstream");
    });
}
