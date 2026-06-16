//! LAB-MACHINE-CAPABILITY-HTTP-P11 — real LOCAL loopback HTTP executor.
//!
//! Proves the P10 policy against a REAL transport boundary: a `LoopbackHttpTransport` (raw
//! HTTP/1.1 over tokio TCP) talking to a real test server on `127.0.0.1`. No external network,
//! no TLS, no SparkCRM. The executor is loopback-only (non-loopback URLs refused before send).

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{
    run_effect_with_passport, CapabilityExecutor, CapabilityExecutorRegistry, CapabilityPassport,
    EffectRequest, OutcomeKind, RunMode, RECEIPTS_STORE,
};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::http::{HttpCapabilityExecutor, HttpTransport, LoopbackHttpTransport, MapSecretProvider, SecretProvider};
use igniter_machine::write::{run_write_effect, WriteRequest, WriteState};
use serde_json::json;
use std::sync::{Arc, Mutex};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;

const CAP: &str = "IO.HttpCapability";

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

// ── a minimal real HTTP/1.1 test server on 127.0.0.1 ───────────────────────────

#[derive(Clone)]
struct ServerCfg {
    status: u16,
    body: String,
    headers: Vec<(String, String)>,
    drop_no_response: bool,
}

#[derive(Clone, Default, Debug)]
struct Recorded {
    method: String,
    path: String,
    correlation_id: Option<String>,
}

fn find_sub(hay: &[u8], needle: &[u8]) -> Option<usize> {
    hay.windows(needle.len()).position(|w| w == needle)
}
fn content_length(head: &str) -> usize {
    head.lines()
        .find(|l| l.to_ascii_lowercase().starts_with("content-length:"))
        .and_then(|l| l.split(':').nth(1))
        .and_then(|v| v.trim().parse().ok())
        .unwrap_or(0)
}

async fn start_server(cfg: ServerCfg) -> (String, Arc<Mutex<Vec<Recorded>>>) {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let recorded = Arc::new(Mutex::new(Vec::new()));
    let rec = recorded.clone();
    tokio::spawn(async move {
        while let Ok((mut sock, _)) = listener.accept().await {
            let cfg = cfg.clone();
            let rec = rec.clone();
            tokio::spawn(async move {
                let mut data = Vec::new();
                let mut buf = vec![0u8; 4096];
                loop {
                    let n = match sock.read(&mut buf).await {
                        Ok(0) => break,
                        Ok(n) => n,
                        Err(_) => return,
                    };
                    data.extend_from_slice(&buf[..n]);
                    if let Some(hp) = find_sub(&data, b"\r\n\r\n") {
                        let head = String::from_utf8_lossy(&data[..hp]).to_string();
                        if data.len() - (hp + 4) >= content_length(&head) {
                            let mut lines = head.lines();
                            let req_line = lines.next().unwrap_or("");
                            let mut parts = req_line.split_whitespace();
                            let method = parts.next().unwrap_or("").to_string();
                            let path = parts.next().unwrap_or("").to_string();
                            let correlation_id = head
                                .lines()
                                .find(|l| l.to_ascii_lowercase().starts_with("x-correlation-id:"))
                                .and_then(|l| l.split(':').nth(1))
                                .map(|v| v.trim().to_string());
                            rec.lock().unwrap().push(Recorded { method, path, correlation_id });
                            break;
                        }
                    }
                }
                if cfg.drop_no_response {
                    return; // close without responding → client sees a lost response
                }
                let mut resp = format!("HTTP/1.1 {} STATUS\r\nConnection: close\r\n", cfg.status);
                for (k, v) in &cfg.headers {
                    resp.push_str(&format!("{k}: {v}\r\n"));
                }
                resp.push_str(&format!("Content-Length: {}\r\n\r\n{}", cfg.body.len(), cfg.body));
                let _ = sock.write_all(resp.as_bytes()).await;
            });
        }
    });
    (format!("http://127.0.0.1:{port}"), recorded)
}

fn http_exec(secrets: Arc<dyn SecretProvider>) -> Arc<HttpCapabilityExecutor> {
    Arc::new(
        HttpCapabilityExecutor::new(CAP, Arc::new(LoopbackHttpTransport::new()) as Arc<dyn HttpTransport>, secrets)
            .loopback_only(),
    )
}
fn no_secrets() -> Arc<dyn SecretProvider> {
    Arc::new(MapSecretProvider::new(&[]))
}
fn registry(exec: Arc<HttpCapabilityExecutor>) -> CapabilityExecutorRegistry {
    let mut reg = CapabilityExecutorRegistry::new();
    reg.register(exec);
    reg
}
fn get_req(url: &str, key: &str, corr: &str) -> EffectRequest {
    EffectRequest {
        capability_id: CAP.into(),
        idempotency_key: key.into(),
        authority_ref: None,
        args: json!({ "method": "GET", "url": url, "correlation_id": corr }),
    }
}
fn post_req(url: &str, key: &str, corr: &str, headers: serde_json::Value) -> WriteRequest {
    WriteRequest {
        capability_id: CAP.into(),
        operation: "http_post".into(),
        idempotency_key: key.into(),
        payload: json!({ "method": "POST", "url": url, "body": "{}", "correlation_id": corr, "headers": headers }),
    }
}

// ── #1: GET 200 → succeeded + receipt, body bounded ────────────────────────────

#[test]
fn get_200_succeeds_with_receipt() {
    rt().block_on(async {
        let (base, _rec) = start_server(ServerCfg { status: 200, body: "pong".into(), headers: vec![("content-type".into(), "text/plain".into())], drop_no_response: false }).await;
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let reg = registry(http_exec(no_secrets()));

        let out = run_effect_with_passport(&reg, &receipts, &clock(), &passport(), "read", &get_req(&format!("{base}/ping"), "g1", "c1"), RunMode::Live).await.unwrap();
        assert_eq!(out.kind, OutcomeKind::Succeeded);
        assert_eq!(out.result["body"], json!("pong"));
        let r = receipts.read_as_of(RECEIPTS_STORE, "IO.HttpCapability:g1", f64::MAX).await.unwrap().unwrap();
        assert_eq!(r.value["outcome_kind"], json!("succeeded"));
    });
}

// ── #2/#3: status taxonomy on a real server ────────────────────────────────────

#[test]
fn get_404_is_permanent_and_429_is_retryable() {
    rt().block_on(async {
        let (b404, _) = start_server(ServerCfg { status: 404, body: "no".into(), headers: vec![], drop_no_response: false }).await;
        let out = http_exec(no_secrets()).execute(&get_req(&format!("{b404}/x"), "k", "c")).await;
        assert_eq!(out.kind, OutcomeKind::PermanentFailure);

        let (b429, _) = start_server(ServerCfg { status: 429, body: "slow".into(), headers: vec![("retry-after".into(), "12".into())], drop_no_response: false }).await;
        let out = http_exec(no_secrets()).execute(&get_req(&format!("{b429}/x"), "k", "c")).await;
        assert_eq!(out.kind, OutcomeKind::Retryable);
        assert_eq!(out.result["retry_after"], json!("12"));
    });
}

// ── #4: POST with a lost response → unknown_external_state ──────────────────────

#[test]
fn post_lost_response_is_unknown() {
    rt().block_on(async {
        let (base, _) = start_server(ServerCfg { status: 0, body: "".into(), headers: vec![], drop_no_response: true }).await;
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let reg = registry(http_exec(no_secrets()));

        let out = run_write_effect(&reg, &receipts, &clock(), &passport(), "write", &post_req(&format!("{base}/orders"), "p1", "c1", json!({})), RunMode::Live).await.unwrap();
        assert_eq!(out.state, WriteState::UnknownExternalState);
    });
}

// ── #5: missing secret → refused before send, nothing sent ─────────────────────

#[test]
fn missing_secret_refused_before_send() {
    rt().block_on(async {
        let (base, rec) = start_server(ServerCfg { status: 200, body: "ok".into(), headers: vec![], drop_no_response: false }).await;
        let out = http_exec(no_secrets())
            .execute(&EffectRequest {
                capability_id: CAP.into(),
                idempotency_key: "k".into(),
                authority_ref: None,
                args: json!({ "method": "GET", "url": format!("{base}/x"), "correlation_id": "c", "headers": { "Authorization": "{{secret:tok}}" } }),
            })
            .await;
        assert_eq!(out.kind, OutcomeKind::PermanentFailure);
        assert!(rec.lock().unwrap().is_empty(), "no HTTP request must reach the server");
    });
}

// ── #6: Authorization redacted from the receipt ────────────────────────────────

#[test]
fn authorization_is_redacted_from_receipt() {
    rt().block_on(async {
        let (base, _) = start_server(ServerCfg { status: 200, body: "ok".into(), headers: vec![], drop_no_response: false }).await;
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let secrets: Arc<dyn SecretProvider> = Arc::new(MapSecretProvider::new(&[("tok", "s3cr3t")]));
        let reg = registry(http_exec(secrets));

        run_write_effect(&reg, &receipts, &clock(), &passport(), "write", &post_req(&format!("{base}/orders"), "p6", "c6", json!({ "Authorization": "{{secret:tok}}" })), RunMode::Live).await.unwrap();

        let r = receipts.read_as_of(RECEIPTS_STORE, "IO.HttpCapability:p6", f64::MAX).await.unwrap().unwrap();
        assert!(!r.value.to_string().contains("s3cr3t"), "secret must not be in the receipt");
        assert_eq!(r.value["result"]["redacted_headers"], json!(["Authorization"]));
    });
}

// ── #7: replay never sends a second HTTP request ───────────────────────────────

#[test]
fn replay_never_sends_second_request() {
    rt().block_on(async {
        let (base, rec) = start_server(ServerCfg { status: 200, body: "created".into(), headers: vec![], drop_no_response: false }).await;
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let reg = registry(http_exec(no_secrets()));
        let req = post_req(&format!("{base}/orders"), "p7", "c7", json!({}));

        let a = run_write_effect(&reg, &receipts, &clock(), &passport(), "write", &req, RunMode::Live).await.unwrap();
        let b = run_write_effect(&reg, &receipts, &clock(), &passport(), "write", &req, RunMode::Live).await.unwrap();
        assert_eq!(a.state, WriteState::Committed);
        assert_eq!(b.state, WriteState::Committed);
        assert_eq!(rec.lock().unwrap().len(), 1, "the server must receive exactly one request");
    });
}

// ── #8: non-idempotent POST without a key → refused before send ────────────────

#[test]
fn post_without_key_refused_before_send() {
    rt().block_on(async {
        let (base, rec) = start_server(ServerCfg { status: 200, body: "ok".into(), headers: vec![], drop_no_response: false }).await;
        let out = http_exec(no_secrets())
            .execute(&EffectRequest {
                capability_id: CAP.into(),
                idempotency_key: "".into(),
                authority_ref: None,
                args: json!({ "method": "POST", "url": format!("{base}/x"), "body": "{}", "correlation_id": "c" }),
            })
            .await;
        assert_eq!(out.kind, OutcomeKind::PermanentFailure);
        assert!(rec.lock().unwrap().is_empty());
    });
}

// ── #9: correlation id is sent to the server and recorded in the receipt ───────

#[test]
fn correlation_id_sent_and_recorded() {
    rt().block_on(async {
        let (base, rec) = start_server(ServerCfg { status: 200, body: "ok".into(), headers: vec![], drop_no_response: false }).await;
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let reg = registry(http_exec(no_secrets()));

        run_write_effect(&reg, &receipts, &clock(), &passport(), "write", &post_req(&format!("{base}/orders"), "p9", "corr-xyz", json!({})), RunMode::Live).await.unwrap();

        // the server saw the correlation header
        assert_eq!(rec.lock().unwrap()[0].correlation_id.as_deref(), Some("corr-xyz"));
        // and it is a first-class receipt field
        let r = receipts.read_as_of(RECEIPTS_STORE, "IO.HttpCapability:p9", f64::MAX).await.unwrap().unwrap();
        assert_eq!(r.value["correlation_id"], json!("corr-xyz"));
    });
}

// ── #10: a non-loopback URL is refused before any send ─────────────────────────

#[test]
fn non_loopback_url_refused() {
    rt().block_on(async {
        let out = http_exec(no_secrets()).execute(&get_req("http://example.com/x", "k", "c")).await;
        assert_eq!(out.kind, OutcomeKind::PermanentFailure);
        assert!(out.failure_kind.unwrap().contains("host not allowed"));
    });
}
