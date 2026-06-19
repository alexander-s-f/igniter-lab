//! LAB-MACHINE-CAPABILITY-IO-AUTHORITY-P5 — typed capability passport.
//!
//! Replaces presence-only `authority_ref` with a verifiable `CapabilityPassport`, checked at
//! the host boundary before the executor. Wrong-capability / missing-scope / revoked / expired
//! → runtime refusal with NO receipt. Executor denial remains denial-as-data with a receipt.
//! Replay requires the same authority digest. Expiry uses the injected clock. The contract/VM
//! never receive the passport. No OAuth/JWT/ACL/roles.

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{
    run_effect_with_passport, verify_passport, AuthRefusal, CapabilityExecutorRegistry,
    CapabilityPassport, EchoCapabilityExecutor, EffectRequest, KvReadExecutor, OutcomeKind,
    RunMode, RECEIPTS_STORE,
};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::machine::IgniterMachine;
use igniter_machine::service_loop::{run_service_with_passport, HostRequest};
use serde_json::json;
use std::collections::HashMap;
use std::sync::Arc;

const FIXTURE: &str =
    "../../frame-ui/igniter-view-engine/fixtures/storage_capability/storage_capability_exec.ig";
const STORAGE_CAP: &str = "IO.StorageCapability";

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}

fn receipts() -> Arc<dyn TBackend> {
    Arc::new(InMemoryBackend::new())
}

fn clock(t: f64) -> Arc<dyn ClockProvider> {
    Arc::new(FixedClock::new(t))
}

/// A valid passport for `cap` with the given scopes (not revoked, far-future expiry).
fn passport(subject: &str, cap: &str, scopes: &[&str]) -> CapabilityPassport {
    CapabilityPassport {
        subject: subject.to_string(),
        capability_id: cap.to_string(),
        scopes: scopes.iter().map(|s| s.to_string()).collect(),
        issued_at: 0.0,
        expires_at: Some(1_000_000.0),
        revoked: false,
        evidence_digest: "sig:abc".to_string(),
    }
}

/// An effect request with NO presence-only authority — authority comes from the passport.
fn req(cap: &str, key: &str, args: serde_json::Value) -> EffectRequest {
    EffectRequest {
        capability_id: cap.to_string(),
        idempotency_key: key.to_string(),
        authority_ref: None,
        args,
    }
}

// ── valid passport authorizes + records the authority digest ───────────────────

#[test]
fn valid_passport_authorizes_and_records_digest() {
    rt().block_on(async {
        let echo = Arc::new(EchoCapabilityExecutor::new("echo"));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(echo.clone());
        let store = receipts();
        let p = passport("svc:reader", "echo", &["read"]);

        let out = run_effect_with_passport(
            &reg,
            &store,
            &clock(10.0),
            &p,
            "read",
            &req("echo", "k1", json!(1)),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(out.kind, OutcomeKind::Succeeded);
        assert_eq!(echo.call_count(), 1);

        let fact = store
            .read_as_of(RECEIPTS_STORE, "echo:k1", f64::MAX)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(fact.value["authority_digest"], json!(p.authority_digest()));
    });
}

// ── refusals: wrong capability / missing scope / revoked / expired — no receipt ─

#[test]
fn wrong_capability_refused_no_receipt() {
    rt().block_on(async {
        let echo = Arc::new(EchoCapabilityExecutor::new("echo"));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(echo.clone());
        let store = receipts();
        // passport is for a DIFFERENT capability than the request
        let p = passport("svc", "other-cap", &["read"]);

        let out = run_effect_with_passport(
            &reg,
            &store,
            &clock(10.0),
            &p,
            "read",
            &req("echo", "w1", json!(1)),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(out.kind, OutcomeKind::Denied);
        assert_eq!(echo.call_count(), 0);
        assert!(store
            .read_as_of(RECEIPTS_STORE, "echo:w1", f64::MAX)
            .await
            .unwrap()
            .is_none());
    });
}

#[test]
fn missing_scope_refused_no_receipt() {
    rt().block_on(async {
        let echo = Arc::new(EchoCapabilityExecutor::new("echo"));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(echo.clone());
        let store = receipts();
        let p = passport("svc", "echo", &["read"]); // has "read", not "write"

        let out = run_effect_with_passport(
            &reg,
            &store,
            &clock(10.0),
            &p,
            "write",
            &req("echo", "s1", json!(1)),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(out.kind, OutcomeKind::Denied);
        assert_eq!(echo.call_count(), 0);
        assert!(store
            .read_as_of(RECEIPTS_STORE, "echo:s1", f64::MAX)
            .await
            .unwrap()
            .is_none());
    });
}

#[test]
fn revoked_passport_refused_no_receipt() {
    rt().block_on(async {
        let echo = Arc::new(EchoCapabilityExecutor::new("echo"));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(echo.clone());
        let store = receipts();
        let mut p = passport("svc", "echo", &["read"]);
        p.revoked = true;

        let out = run_effect_with_passport(
            &reg,
            &store,
            &clock(10.0),
            &p,
            "read",
            &req("echo", "rv1", json!(1)),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(out.kind, OutcomeKind::Denied);
        assert_eq!(echo.call_count(), 0);
        assert!(store
            .read_as_of(RECEIPTS_STORE, "echo:rv1", f64::MAX)
            .await
            .unwrap()
            .is_none());
    });
}

#[test]
fn expiry_uses_injected_clock() {
    rt().block_on(async {
        let echo = Arc::new(EchoCapabilityExecutor::new("echo"));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(echo.clone());
        let store = receipts();
        let mut p = passport("svc", "echo", &["read"]);
        p.expires_at = Some(100.0);

        // clock past expiry → Expired refusal, no receipt
        let expired = run_effect_with_passport(
            &reg,
            &store,
            &clock(200.0),
            &p,
            "read",
            &req("echo", "e1", json!(1)),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(expired.kind, OutcomeKind::Denied);
        assert_eq!(echo.call_count(), 0);

        // clock before expiry → authorized
        let ok = run_effect_with_passport(
            &reg,
            &store,
            &clock(50.0),
            &p,
            "read",
            &req("echo", "e2", json!(1)),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(ok.kind, OutcomeKind::Succeeded);
        assert_eq!(echo.call_count(), 1);
    });
}

#[test]
fn verify_passport_unit_refusals() {
    let p = passport("svc", "cap", &["read"]);
    assert_eq!(
        verify_passport(&p, "other", "read", &clock(1.0)).unwrap_err(),
        AuthRefusal::WrongCapability
    );
    assert_eq!(
        verify_passport(&p, "cap", "write", &clock(1.0)).unwrap_err(),
        AuthRefusal::MissingScope
    );
    let mut rev = p.clone();
    rev.revoked = true;
    assert_eq!(
        verify_passport(&rev, "cap", "read", &clock(1.0)).unwrap_err(),
        AuthRefusal::Revoked
    );
    let mut exp = p.clone();
    exp.expires_at = Some(10.0);
    assert_eq!(
        verify_passport(&exp, "cap", "read", &clock(20.0)).unwrap_err(),
        AuthRefusal::Expired
    );
    assert!(verify_passport(&p, "cap", "read", &clock(1.0)).is_ok());
}

// ── replay requires the SAME authority digest ──────────────────────────────────

#[test]
fn replay_requires_same_authority_digest() {
    rt().block_on(async {
        let echo = Arc::new(EchoCapabilityExecutor::new("echo"));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(echo.clone());
        let store = receipts();
        let a = passport("svc:A", "echo", &["read"]);
        let b = passport("svc:B", "echo", &["read", "extra"]); // different subject + scopes → different digest

        // live with passport A
        run_effect_with_passport(
            &reg,
            &store,
            &clock(10.0),
            &a,
            "read",
            &req("echo", "k", json!(1)),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(echo.call_count(), 1);

        // same idempotency key but DIFFERENT authority → refused, executor not re-run
        let mismatch = run_effect_with_passport(
            &reg,
            &store,
            &clock(11.0),
            &b,
            "read",
            &req("echo", "k", json!(1)),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(mismatch.kind, OutcomeKind::Denied);
        assert_eq!(echo.call_count(), 1);

        // same authority A → legitimate replay, executor still not re-run
        let replay = run_effect_with_passport(
            &reg,
            &store,
            &clock(12.0),
            &a,
            "read",
            &req("echo", "k", json!(1)),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(replay.kind, OutcomeKind::Succeeded);
        assert_eq!(echo.call_count(), 1);
    });
}

// ── executor denial remains denial-as-data (with receipt) under passport path ──

#[test]
fn executor_denial_remains_denial_as_data() {
    rt().block_on(async {
        let kv = Arc::new(KvReadExecutor::new("echo", HashMap::new()));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(kv.clone());
        let store = receipts();
        let p = passport("svc", "echo", &["read"]);

        // passport authorizes (preflight passes) but the executor itself denies
        let out = run_effect_with_passport(
            &reg,
            &store,
            &clock(10.0),
            &p,
            "read",
            &req("echo", "d1", json!({"key": "__forbidden__"})),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(out.kind, OutcomeKind::Denied);
        assert_eq!(kv.call_count(), 1, "executor was reached (passport passed)");

        let fact = store
            .read_as_of(RECEIPTS_STORE, "echo:d1", f64::MAX)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(fact.value["outcome_kind"], json!("denied"));
        assert_eq!(fact.value["authority_digest"], json!(p.authority_digest()));
    });
}

// ── authority is host-side: the contract/VM never receive a passport ───────────

#[test]
fn authority_is_host_side_not_contract() {
    rt().block_on(async {
        let m = IgniterMachine::new(None, "in_memory").unwrap();
        m.load_program(&[FIXTURE.to_string()], "ExecuteQuery")
            .unwrap();
        let mut kv = HashMap::new();
        kv.insert("x".to_string(), json!(1));
        let exec = Arc::new(KvReadExecutor::new(STORAGE_CAP, kv));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec.clone());

        // dispatch takes no passport at all — the contract runs with zero authority involvement
        let _ = m.dispatch("ExecuteQuery", json!({"plan": {}})).await;
        assert_eq!(exec.call_count(), 0);

        // the host boundary authorizes + performs the effect
        let p = passport("svc", STORAGE_CAP, &["read"]);
        let hr = HostRequest {
            contract: "ExecuteQuery".to_string(),
            effect: "read_file".to_string(),
            idempotency_key: "h1".to_string(),
            authority_ref: None,
            args: json!({"key": "x"}),
        };
        let out = run_service_with_passport(&m, &reg, &clock(10.0), &p, "read", &hr, RunMode::Live)
            .await
            .unwrap();
        assert_eq!(out.kind, OutcomeKind::Succeeded);
        assert_eq!(exec.call_count(), 1);

        let fact = m
            .storage
            .read_as_of(RECEIPTS_STORE, "IO.StorageCapability:h1", f64::MAX)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(fact.value["authority_digest"], json!(p.authority_digest()));
    });
}
