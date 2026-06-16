//! LAB-MACHINE-CAPABILITY-IO-SECRET-PROVIDER-P22 — env/file/layered secret providers.
//!
//! Hardens the SOURCE of injected credentials: allowlisted env, traversal-safe file, layered
//! override. Secrets stay host-side references (`{{secret:name}}`) — the value never enters
//! contract inputs, receipts, audit, or error bodies; redaction is preserved.

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{CapabilityExecutorRegistry, CapabilityPassport, RunMode, RECEIPTS_STORE};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::http::{FakeHttpTransport, HttpCapabilityExecutor, HttpTransport, MapSecretProvider, SecretProvider};
use igniter_machine::secrets::{EnvSecretProvider, FileSecretProvider, LayeredSecretProvider};
use igniter_machine::write::{run_write_effect, WriteRequest, WriteState};
use serde_json::json;
use std::path::PathBuf;
use std::sync::Arc;

const CAP: &str = "IO.HttpCapability";
const SECRET: &str = "s3cr3t-p22";

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap()
}
fn tmp() -> PathBuf {
    std::env::temp_dir().join(format!("igniter_p22_{}", uuid::Uuid::new_v4()))
}

// ── EnvSecretProvider: allowlist only ──────────────────────────────────────────

#[test]
fn env_provider_resolves_only_allowlisted() {
    let var = "IGNITER_P22_ENV_TOK";
    std::env::set_var(var, SECRET);
    let p = EnvSecretProvider::new().allow("tok", var);
    assert_eq!(p.resolve("tok").as_deref(), Some(SECRET));
    assert_eq!(p.resolve("other"), None, "a non-allowlisted name resolves to nothing");

    // an allowlisted name whose env var is unset → None
    let p2 = EnvSecretProvider::new().allow("missing", "IGNITER_P22_ENV_UNSET");
    assert_eq!(p2.resolve("missing"), None);
    std::env::remove_var(var);
}

// ── FileSecretProvider: reads root, rejects traversal ──────────────────────────

#[test]
fn file_provider_reads_and_rejects_traversal() {
    let root = tmp();
    std::fs::create_dir_all(&root).unwrap();
    std::fs::write(root.join("api_token"), format!("{SECRET}\n")).unwrap();
    let p = FileSecretProvider::new(&root);

    assert_eq!(p.resolve("api_token").as_deref(), Some(SECRET), "trimmed file contents");
    assert_eq!(p.resolve("missing"), None);
    // path-traversal / unsafe names are rejected (never touch the filesystem outside root)
    for bad in ["../api_token", "../../etc/passwd", "a/b", ".hidden", "tok/", ""] {
        assert_eq!(p.resolve(bad), None, "unsafe name '{bad}' must be rejected");
    }
    let _ = std::fs::remove_dir_all(&root);
}

// ── LayeredSecretProvider: override / fall-through ─────────────────────────────

#[test]
fn layered_provider_overrides_then_falls_through() {
    let root = tmp();
    std::fs::create_dir_all(&root).unwrap();
    std::fs::write(root.join("a"), "from_file_a").unwrap();
    std::fs::write(root.join("b"), "from_file_b").unwrap();

    let layered = LayeredSecretProvider::new()
        .layer(Box::new(MapSecretProvider::new(&[("a", "from_map_a")]))) // override "a"
        .layer(Box::new(FileSecretProvider::new(&root)));

    assert_eq!(layered.resolve("a").as_deref(), Some("from_map_a"), "first layer wins");
    assert_eq!(layered.resolve("b").as_deref(), Some("from_file_b"), "falls through to file");
    assert_eq!(layered.resolve("c"), None);
    let _ = std::fs::remove_dir_all(&root);
}

// ── secret resolved from a FILE never lands in the receipt; reference-only inputs ─

#[test]
fn file_secret_never_in_receipt_only_reference_in_inputs() {
    rt().block_on(async {
        let root = tmp();
        std::fs::create_dir_all(&root).unwrap();
        std::fs::write(root.join("tok"), SECRET).unwrap();
        let secrets: Arc<dyn SecretProvider> = Arc::new(FileSecretProvider::new(&root));
        let transport = Arc::new(FakeHttpTransport::ok(200, "ok", vec![]));
        let exec = Arc::new(HttpCapabilityExecutor::new(CAP, transport.clone() as Arc<dyn HttpTransport>, secrets));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let clock: Arc<dyn ClockProvider> = Arc::new(FixedClock::new(100.0));
        let p = CapabilityPassport { subject: "host".into(), capability_id: CAP.into(), scopes: vec!["write".into()], issued_at: 0.0, expires_at: Some(1e9), revoked: false, evidence_digest: "s".into() };

        // the request (contract input) carries only the REFERENCE, not the value
        let req = WriteRequest {
            capability_id: CAP.into(), operation: "http_post".into(), idempotency_key: "s1".into(),
            payload: json!({ "method": "POST", "url": "https://api/x", "body": "{}", "correlation_id": "c", "headers": { "Authorization": "{{secret:tok}}" } }),
        };
        assert!(!serde_json::to_string(&req.payload).unwrap().contains(SECRET), "inputs carry only the reference");

        let out = run_write_effect(&reg, &receipts, &clock, &p, "write", &req, RunMode::Live).await.unwrap();
        assert_eq!(out.state, WriteState::Committed);

        // the RESOLVED secret was sent to the transport ...
        assert!(transport.last_request().unwrap().headers.iter().any(|(k, v)| k == "Authorization" && v == SECRET));
        // ... but never recorded in the receipt (redacted)
        let receipt = receipts.read_as_of(RECEIPTS_STORE, "IO.HttpCapability:s1", f64::MAX).await.unwrap().unwrap();
        assert!(!receipt.value.to_string().contains(SECRET), "secret must never appear in the receipt");
        assert_eq!(receipt.value["result"]["redacted_headers"], json!(["Authorization"]));
        let _ = std::fs::remove_dir_all(&root);
    });
}

// ── a missing secret refuses before send (no transport call) ───────────────────

#[test]
fn missing_secret_refuses_before_send() {
    rt().block_on(async {
        let root = tmp();
        std::fs::create_dir_all(&root).unwrap(); // empty root — "tok" does not exist
        let secrets: Arc<dyn SecretProvider> = Arc::new(FileSecretProvider::new(&root));
        let transport = Arc::new(FakeHttpTransport::ok(200, "ok", vec![]));
        let exec = Arc::new(HttpCapabilityExecutor::new(CAP, transport.clone() as Arc<dyn HttpTransport>, secrets));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let clock: Arc<dyn ClockProvider> = Arc::new(FixedClock::new(100.0));
        let p = CapabilityPassport { subject: "host".into(), capability_id: CAP.into(), scopes: vec!["write".into()], issued_at: 0.0, expires_at: Some(1e9), revoked: false, evidence_digest: "s".into() };

        let req = WriteRequest {
            capability_id: CAP.into(), operation: "http_post".into(), idempotency_key: "m1".into(),
            payload: json!({ "method": "POST", "url": "https://api/x", "body": "{}", "correlation_id": "c", "headers": { "Authorization": "{{secret:tok}}" } }),
        };
        let out = run_write_effect(&reg, &receipts, &clock, &p, "write", &req, RunMode::Live).await.unwrap();
        assert_eq!(out.state, WriteState::PermanentFailure, "unresolved credential → refuse");
        assert_eq!(transport.sends(), 0, "nothing is sent when a secret is missing");
        let _ = std::fs::remove_dir_all(&root);
    });
}
