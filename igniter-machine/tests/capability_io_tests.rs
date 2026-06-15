//! LAB-MACHINE-CAPABILITY-IO-P1 — fake-executor proof of the production IO boundary.
//!
//! Proves the whole model without real DB/network: a CapabilityExecutor performs the
//! effect, a ServiceLoop-like runner validates authority + idempotency, an EffectReceipt
//! is written as a bitemporal fact, and replay reads receipts without touching the
//! executor. `unknown_external_state` stays epistemic, not collapsed into failure.
//!
//! Guardrail under test: external world is contract-shaped but never carries pure-contract
//! authority — it always carries receipt, failure, authority, and idempotency.

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{
    run_effect, CapabilityExecutorRegistry, EchoCapabilityExecutor, EffectRequest,
    KvReadExecutor, OutcomeKind, RunMode, RECEIPTS_STORE,
};
use serde_json::json;
use std::collections::HashMap;
use std::sync::Arc;

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}

fn receipts() -> Arc<dyn TBackend> {
    Arc::new(InMemoryBackend::new())
}

fn req(cap: &str, key: &str, args: serde_json::Value) -> EffectRequest {
    EffectRequest {
        capability_id: cap.to_string(),
        idempotency_key: key.to_string(),
        authority_ref: Some("passport:test".to_string()),
        args,
    }
}

// ── B: fake executor model + C: receipt fact schema ───────────────────────────

#[test]
fn live_effect_runs_executor_writes_receipt_fact() {
    rt().block_on(async {
        let echo = Arc::new(EchoCapabilityExecutor::new("echo"));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(echo.clone());
        let store = receipts();

        let out = run_effect(&reg, &store, &req("echo", "k1", json!({"hi": 1})), RunMode::Live)
            .await
            .unwrap();

        // typed success, executor called exactly once
        assert_eq!(out.kind, OutcomeKind::Succeeded);
        assert_eq!(out.result, json!({"hi": 1}));
        assert_eq!(echo.call_count(), 1);

        // receipt persisted as a bitemporal fact with the full schema
        let fact = store
            .read_as_of(RECEIPTS_STORE, "echo:k1", f64::MAX)
            .await
            .unwrap()
            .expect("receipt fact must exist");
        assert_eq!(fact.store, RECEIPTS_STORE);
        assert_eq!(fact.key, "echo:k1");
        assert_eq!(fact.value["capability_id"], json!("echo"));
        assert_eq!(fact.value["idempotency_key"], json!("k1"));
        assert_eq!(fact.value["authority_ref"], json!("passport:test"));
        assert_eq!(fact.value["outcome_kind"], json!("succeeded"));
        assert_eq!(fact.value["result"], json!({"hi": 1}));
    });
}

// ── D: idempotency — second call replays, executor not re-invoked ─────────────

#[test]
fn idempotency_prevents_second_executor_call() {
    rt().block_on(async {
        let echo = Arc::new(EchoCapabilityExecutor::new("echo"));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(echo.clone());
        let store = receipts();

        let first = run_effect(&reg, &store, &req("echo", "same", json!({"n": 7})), RunMode::Live)
            .await
            .unwrap();
        let second = run_effect(&reg, &store, &req("echo", "same", json!({"n": 7})), RunMode::Live)
            .await
            .unwrap();

        assert_eq!(first.result, json!({"n": 7}));
        assert_eq!(second.result, json!({"n": 7})); // same typed result, replayed
        assert_eq!(second.kind, OutcomeKind::Succeeded);
        assert_eq!(echo.call_count(), 1, "executor must run exactly once for one idempotency key");
    });
}

#[test]
fn distinct_idempotency_keys_each_invoke_executor() {
    rt().block_on(async {
        let echo = Arc::new(EchoCapabilityExecutor::new("echo"));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(echo.clone());
        let store = receipts();

        run_effect(&reg, &store, &req("echo", "a", json!(1)), RunMode::Live).await.unwrap();
        run_effect(&reg, &store, &req("echo", "b", json!(2)), RunMode::Live).await.unwrap();
        assert_eq!(echo.call_count(), 2);
    });
}

// ── E: replay mode — receipt lookup, no executor ──────────────────────────────

#[test]
fn replay_returns_receipt_without_calling_executor() {
    rt().block_on(async {
        let echo = Arc::new(EchoCapabilityExecutor::new("echo"));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(echo.clone());
        let store = receipts();

        // seed a receipt with a Live call
        run_effect(&reg, &store, &req("echo", "seed", json!({"v": 99})), RunMode::Live)
            .await
            .unwrap();
        assert_eq!(echo.call_count(), 1);

        // replay reads the receipt, executor untouched
        let replayed = run_effect(&reg, &store, &req("echo", "seed", json!({"v": 99})), RunMode::Replay)
            .await
            .unwrap();
        assert_eq!(replayed.result, json!({"v": 99}));
        assert_eq!(echo.call_count(), 1, "replay must not invoke the executor");
    });
}

#[test]
fn replay_without_receipt_is_unknown_not_failure() {
    rt().block_on(async {
        let echo = Arc::new(EchoCapabilityExecutor::new("echo"));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(echo.clone());
        let store = receipts();

        // replay for a key that was never executed → epistemic unknown, no executor call
        let out = run_effect(&reg, &store, &req("echo", "never", json!(0)), RunMode::Replay)
            .await
            .unwrap();
        assert_eq!(out.kind, OutcomeKind::UnknownExternalState);
        assert_eq!(echo.call_count(), 0);
    });
}

// ── F: unknown external state stays epistemic ─────────────────────────────────

#[test]
fn timeout_is_unknown_external_state_not_failed() {
    rt().block_on(async {
        let kv = Arc::new(KvReadExecutor::new("kv", HashMap::new()));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(kv.clone());
        let store = receipts();

        let out = run_effect(&reg, &store, &req("kv", "t1", json!({"key": "__timeout__"})), RunMode::Live)
            .await
            .unwrap();
        assert_eq!(out.kind, OutcomeKind::UnknownExternalState);

        // the unknown outcome is itself recorded as a receipt fact (auditable, replayable)
        let fact = store.read_as_of(RECEIPTS_STORE, "kv:t1", f64::MAX).await.unwrap().unwrap();
        assert_eq!(fact.value["outcome_kind"], json!("unknown_external_state"));
    });
}

#[test]
fn missing_key_is_permanent_failure_distinct_from_unknown() {
    rt().block_on(async {
        let kv = Arc::new(KvReadExecutor::new("kv", HashMap::new()));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(kv.clone());
        let store = receipts();

        let out = run_effect(&reg, &store, &req("kv", "m1", json!({"key": "absent"})), RunMode::Live)
            .await
            .unwrap();
        // a definite negative ("not found") is permanent_failure, NOT unknown_external_state
        assert_eq!(out.kind, OutcomeKind::PermanentFailure);
    });
}

#[test]
fn known_key_succeeds() {
    rt().block_on(async {
        let mut kv = HashMap::new();
        kv.insert("greeting".to_string(), json!("hello"));
        let exec = Arc::new(KvReadExecutor::new("kv", kv));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec.clone());
        let store = receipts();

        let out = run_effect(&reg, &store, &req("kv", "g1", json!({"key": "greeting"})), RunMode::Live)
            .await
            .unwrap();
        assert_eq!(out.kind, OutcomeKind::Succeeded);
        assert_eq!(out.result, json!("hello"));
    });
}

// ── G: ServiceLoop boundary — preflight refusal vs denial-as-data ─────────────

#[test]
fn preflight_refuses_unknown_capability_before_executor() {
    rt().block_on(async {
        let echo = Arc::new(EchoCapabilityExecutor::new("echo"));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(echo.clone());
        let store = receipts();

        let out = run_effect(&reg, &store, &req("nope", "k", json!(1)), RunMode::Live)
            .await
            .unwrap();
        assert_eq!(out.kind, OutcomeKind::Denied);
        assert_eq!(echo.call_count(), 0);
        // preflight refusal writes no receipt (nothing happened externally)
        assert!(store.read_as_of(RECEIPTS_STORE, "nope:k", f64::MAX).await.unwrap().is_none());
    });
}

#[test]
fn preflight_refuses_missing_idempotency_key() {
    rt().block_on(async {
        let echo = Arc::new(EchoCapabilityExecutor::new("echo"));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(echo.clone());
        let store = receipts();

        let out = run_effect(&reg, &store, &req("echo", "", json!(1)), RunMode::Live)
            .await
            .unwrap();
        assert_eq!(out.kind, OutcomeKind::Denied);
        assert_eq!(echo.call_count(), 0);
    });
}

#[test]
fn preflight_refuses_missing_authority() {
    rt().block_on(async {
        let echo = Arc::new(EchoCapabilityExecutor::new("echo"));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(echo.clone());
        let store = receipts();

        let no_auth = EffectRequest {
            capability_id: "echo".to_string(),
            idempotency_key: "k".to_string(),
            authority_ref: None,
            args: json!(1),
        };
        let out = run_effect(&reg, &store, &no_auth, RunMode::Live).await.unwrap();
        assert_eq!(out.kind, OutcomeKind::Denied);
        assert_eq!(echo.call_count(), 0);
    });
}

#[test]
fn executor_denial_is_written_as_data() {
    rt().block_on(async {
        // denial INSIDE the executor (authority passed preflight, executor still refuses)
        // must be recorded as a receipt fact — denial-as-data, not a silent drop.
        let kv = Arc::new(KvReadExecutor::new("kv", HashMap::new()));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(kv.clone());
        let store = receipts();

        let out = run_effect(&reg, &store, &req("kv", "d1", json!({"key": "__forbidden__"})), RunMode::Live)
            .await
            .unwrap();
        assert_eq!(out.kind, OutcomeKind::Denied);
        assert_eq!(kv.call_count(), 1, "executor WAS reached (preflight passed)");

        let fact = store.read_as_of(RECEIPTS_STORE, "kv:d1", f64::MAX).await.unwrap().unwrap();
        assert_eq!(fact.value["outcome_kind"], json!("denied"));
    });
}

// ── H: closed surfaces (model-level guard) ────────────────────────────────────

#[test]
fn receipt_lives_in_the_same_tbackend_fact_store() {
    rt().block_on(async {
        // receipts are not a hidden side-log: they are facts in a TBackend store namespace,
        // queryable like any other fact (audit/replay share the substrate).
        let echo = Arc::new(EchoCapabilityExecutor::new("echo"));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(echo.clone());
        let store = receipts();

        run_effect(&reg, &store, &req("echo", "x", json!("y")), RunMode::Live).await.unwrap();

        let all = store.all_facts().await.unwrap();
        assert_eq!(all.len(), 1);
        assert_eq!(all[0].store, RECEIPTS_STORE);
    });
}
