//! LAB-MACHINE-CAPABILITY-IO-P2 — declared-effect host entrypoint proof.
//!
//! Proves the ServiceLoop host path on a REAL declared-effect contract (`ExecuteQuery`
//! from the storage_capability fixture): the host discovers the contract's declared effect
//! surface from its IR, resolves effect → capability → executor, and routes through
//! `run_effect`. Receipts land in the machine's own TBackend. The contract body never
//! performs IO — only the host's executor does. Fake executors only; no real DB/HTTP.

use igniter_machine::backend::TBackend;
use igniter_machine::capability::{
    CapabilityExecutorRegistry, KvReadExecutor, OutcomeKind, RunMode, RECEIPTS_STORE,
};
use igniter_machine::machine::IgniterMachine;
use igniter_machine::service_loop::{discover_effect_surface, run_service, HostRequest};
use serde_json::json;
use std::collections::HashMap;
use std::sync::Arc;

const FIXTURE: &str =
    "../../frame-ui/igniter-view-engine/fixtures/storage_capability/storage_capability_exec.ig";
// the declared capability type of ExecuteQuery's `storage` capability = the executor id
const STORAGE_CAP: &str = "IO.StorageCapability";

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}

fn load_machine() -> IgniterMachine {
    let m = IgniterMachine::new(None, "in_memory").unwrap();
    m.load_program(&[FIXTURE.to_string()], "ExecuteQuery")
        .expect("fixture must load");
    m
}

/// A fake storage-read executor bound to the declared capability type.
fn storage_executor(kv: HashMap<String, serde_json::Value>) -> Arc<KvReadExecutor> {
    Arc::new(KvReadExecutor::new(STORAGE_CAP, kv))
}

fn host_req(effect: &str, key: &str, args: serde_json::Value) -> HostRequest {
    HostRequest {
        contract: "ExecuteQuery".to_string(),
        effect: effect.to_string(),
        idempotency_key: key.to_string(),
        authority_ref: Some("passport:test".to_string()),
        args,
    }
}

// ── §A verify-first: declared effect surface discovered from live IR ───────────

#[test]
fn discovers_declared_effect_surface() {
    let m = load_machine();

    let s = discover_effect_surface(&m, "ExecuteQuery").unwrap();
    assert_eq!(s.modifier, "effect");
    assert!(!s.is_pure());
    assert!(s
        .capabilities
        .iter()
        .any(|(n, t)| n == "storage" && t == STORAGE_CAP));
    assert!(s
        .effects
        .iter()
        .any(|(n, r)| n == "read_file" && r == "storage"));
    // effect → capability type resolution (what the executor id must be)
    assert_eq!(
        s.capability_type_for("read_file").as_deref(),
        Some(STORAGE_CAP)
    );
    assert_eq!(s.capability_type_for("not_an_effect"), None);

    // a pure contract from the same program declares no effect surface
    let pure = discover_effect_surface(&m, "BuildGrantedReceipt").unwrap();
    assert_eq!(pure.modifier, "pure");
    assert!(pure.is_pure());
    assert!(pure.effects.is_empty());
}

// ── the P2 path: host performs the declared effect, receipt in machine storage ─

#[test]
fn host_entrypoint_performs_declared_effect_and_writes_receipt() {
    rt().block_on(async {
        let m = load_machine();
        let mut kv = HashMap::new();
        kv.insert("users".to_string(), json!({"rows": 3}));
        let exec = storage_executor(kv);
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec.clone());

        let out = run_service(
            &m,
            &reg,
            &host_req("read_file", "q1", json!({"key": "users"})),
            RunMode::Live,
        )
        .await
        .unwrap();

        assert_eq!(out.kind, OutcomeKind::Succeeded);
        assert_eq!(out.result, json!({"rows": 3}));
        assert_eq!(exec.call_count(), 1);

        // receipt is a fact in the MACHINE's own TBackend (data-plane, shared substrate)
        let fact = m
            .storage
            .read_as_of(RECEIPTS_STORE, "IO.StorageCapability:q1", f64::MAX)
            .await
            .unwrap()
            .expect("receipt must exist in machine storage");
        assert_eq!(fact.value["capability_id"], json!(STORAGE_CAP));
        assert_eq!(fact.value["outcome_kind"], json!("succeeded"));
    });
}

// ── §Q5: contract body does NOT perform IO — only the host does ────────────────

#[test]
fn contract_body_does_not_perform_io() {
    rt().block_on(async {
        let m = load_machine();
        let exec = storage_executor(HashMap::new());
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec.clone());

        // Dispatching the contract runs only the VM. The VM has NO access to the executor
        // registry by construction — so the contract body cannot perform the effect.
        let _ = m.dispatch("ExecuteQuery", json!({"plan": {}})).await;
        assert_eq!(
            exec.call_count(),
            0,
            "contract execution must not touch the executor"
        );

        // Only the host entrypoint performs the effect.
        run_service(
            &m,
            &reg,
            &host_req("read_file", "io1", json!({"key": "x"})),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(exec.call_count(), 1, "only the host entrypoint performs IO");
    });
}

// ── §Q6: idempotency + replay through the host entrypoint ──────────────────────

#[test]
fn idempotency_and_replay_through_host() {
    rt().block_on(async {
        let m = load_machine();
        let mut kv = HashMap::new();
        kv.insert("k".to_string(), json!("v"));
        let exec = storage_executor(kv);
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec.clone());

        let first = run_service(
            &m,
            &reg,
            &host_req("read_file", "same", json!({"key": "k"})),
            RunMode::Live,
        )
        .await
        .unwrap();
        let second = run_service(
            &m,
            &reg,
            &host_req("read_file", "same", json!({"key": "k"})),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(first.result, json!("v"));
        assert_eq!(second.result, json!("v")); // replayed from receipt
        assert_eq!(
            exec.call_count(),
            1,
            "idempotency: executor runs once per key"
        );

        // replay mode reconstructs the typed response from the receipt, no executor
        let replay = run_service(
            &m,
            &reg,
            &host_req("read_file", "same", json!({"key": "k"})),
            RunMode::Replay,
        )
        .await
        .unwrap();
        assert_eq!(replay.result, json!("v"));
        assert_eq!(exec.call_count(), 1);
    });
}

// ── §Q3/Q4: preflight refusals (no executor, no receipt) ───────────────────────

#[test]
fn preflight_refuses_undeclared_effect() {
    rt().block_on(async {
        let m = load_machine();
        let exec = storage_executor(HashMap::new());
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec.clone());

        let out = run_service(
            &m,
            &reg,
            &host_req("write_everything", "u1", json!({})),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(out.kind, OutcomeKind::Denied);
        assert_eq!(exec.call_count(), 0);
        assert!(m
            .storage
            .read_as_of(RECEIPTS_STORE, "IO.StorageCapability:u1", f64::MAX)
            .await
            .unwrap()
            .is_none());
    });
}

#[test]
fn preflight_refuses_pure_contract() {
    rt().block_on(async {
        let m = load_machine();
        let exec = storage_executor(HashMap::new());
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec.clone());

        let req = HostRequest {
            contract: "BuildGrantedReceipt".to_string(),
            effect: "read_file".to_string(),
            idempotency_key: "p1".to_string(),
            authority_ref: Some("passport:test".to_string()),
            args: json!({}),
        };
        let out = run_service(&m, &reg, &req, RunMode::Live).await.unwrap();
        assert_eq!(out.kind, OutcomeKind::Denied);
        assert_eq!(
            exec.call_count(),
            0,
            "pure contract declares no effect to perform"
        );
    });
}

#[test]
fn preflight_refuses_missing_authority_through_host() {
    rt().block_on(async {
        let m = load_machine();
        let exec = storage_executor(HashMap::new());
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec.clone());

        let req = HostRequest {
            contract: "ExecuteQuery".to_string(),
            effect: "read_file".to_string(),
            idempotency_key: "a1".to_string(),
            authority_ref: None,
            args: json!({"key": "x"}),
        };
        let out = run_service(&m, &reg, &req, RunMode::Live).await.unwrap();
        assert_eq!(out.kind, OutcomeKind::Denied);
        assert_eq!(exec.call_count(), 0);
    });
}

#[test]
fn unregistered_capability_refused_before_executor() {
    rt().block_on(async {
        let m = load_machine();
        // registry is EMPTY — the declared capability has no bound executor
        let reg = CapabilityExecutorRegistry::new();
        let out = run_service(
            &m,
            &reg,
            &host_req("read_file", "n1", json!({"key": "x"})),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(out.kind, OutcomeKind::Denied); // preflight: unknown capability
        assert!(m
            .storage
            .read_as_of(RECEIPTS_STORE, "IO.StorageCapability:n1", f64::MAX)
            .await
            .unwrap()
            .is_none());
    });
}

// ── §Q7: in-process data-plane, NOT an MCP hot path ────────────────────────────

#[test]
fn host_entrypoint_is_in_process_data_plane() {
    rt().block_on(async {
        // This whole path is a direct in-process library call: IgniterMachine + executor
        // registry, no MCP/JSON-RPC transport anywhere (none is imported). The receipt
        // landing in the machine's own fact store is the data-plane evidence.
        let m = load_machine();
        let mut kv = HashMap::new();
        kv.insert("k".to_string(), json!(1));
        let exec = storage_executor(kv);
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);

        run_service(
            &m,
            &reg,
            &host_req("read_file", "dp1", json!({"key": "k"})),
            RunMode::Live,
        )
        .await
        .unwrap();

        let all = m.storage.all_facts().await.unwrap();
        assert!(all
            .iter()
            .any(|f| f.store == RECEIPTS_STORE && f.key == "IO.StorageCapability:dp1"));
    });
}
