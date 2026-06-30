//! LAB-MACHINE-CAPABILITY-IO-P3 — first REAL substrate (read-only local TBackend).
//!
//! The fake executors of P1/P2 are replaced by `TBackendReadExecutor` over a real
//! `RocksDBBackend` (on-disk) for reads, and a real `RemoteTcpBackend` (pointed at a dead
//! port) to prove the unavailable→`unknown_external_state` mapping. `run_service` and the
//! receipt/idempotency machinery are UNCHANGED — only a real executor replaces the fake.
//! Read-only: no writes, no HTTP, no scheduler.

use igniter_machine::backend::{RemoteTcpBackend, RocksDBBackend, TBackend};
use igniter_machine::capability::{
    CapabilityExecutorRegistry, OutcomeKind, RunMode, RECEIPTS_STORE,
};
use igniter_machine::executors::TBackendReadExecutor;
use igniter_machine::fact::Fact;
use igniter_machine::machine::IgniterMachine;
use igniter_machine::service_loop::{run_service, HostRequest};
use serde_json::json;
use std::path::PathBuf;
use std::sync::Arc;

const FIXTURE: &str =
    "tests/fixtures/storage_capability/storage_capability_exec.ig";
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

fn temp_dir() -> PathBuf {
    std::env::temp_dir().join(format!("igniter_p3_{}", uuid::Uuid::new_v4()))
}

fn fact(store: &str, key: &str, value: serde_json::Value) -> Fact {
    Fact {
        id: format!("{}:{}", store, key),
        store: store.to_string(),
        key: key.to_string(),
        value,
        value_hash: String::new(),
        causation: None,
        transaction_time: 1.0,
        valid_time: None,
        schema_version: 1,
        producer: None,
        derivation: None,
    }
}

fn read_req(key: &str, store: &str, record: &str) -> HostRequest {
    HostRequest {
        contract: "ExecuteQuery".to_string(),
        effect: "read_file".to_string(),
        idempotency_key: key.to_string(),
        authority_ref: Some("passport:test".to_string()),
        args: json!({ "store": store, "key": record }),
    }
}

// ── #1: first call reads the REAL backend and writes a receipt ─────────────────

#[test]
fn real_rocksdb_read_succeeds_and_writes_receipt() {
    rt().block_on(async {
        let dir = temp_dir();
        let backend: Arc<dyn TBackend> = Arc::new(RocksDBBackend::new(dir.clone()).unwrap());
        // seed the "external" data store (setup — not the executor writing)
        backend
            .write_fact(fact(
                "catalog",
                "sku-1",
                json!({"name": "widget", "qty": 7}),
            ))
            .await
            .unwrap();

        let m = load_machine();
        let exec = Arc::new(TBackendReadExecutor::new(STORAGE_CAP, backend));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec.clone());

        let out = run_service(&m, &reg, &read_req("r1", "catalog", "sku-1"), RunMode::Live)
            .await
            .unwrap();

        assert_eq!(out.kind, OutcomeKind::Succeeded);
        assert_eq!(out.result, json!({"name": "widget", "qty": 7}));
        assert_eq!(exec.read_count(), 1);

        // receipt persisted in the MACHINE's store (separate from the read substrate)
        let receipt = m
            .storage
            .read_as_of(RECEIPTS_STORE, "IO.StorageCapability:r1", f64::MAX)
            .await
            .unwrap()
            .expect("receipt must exist");
        assert_eq!(receipt.value["outcome_kind"], json!("succeeded"));

        let _ = std::fs::remove_dir_all(&dir);
    });
}

// ── #2: second call same idempotency key replays, backend NOT read again ───────

#[test]
fn real_read_idempotency_replays_without_backend() {
    rt().block_on(async {
        let dir = temp_dir();
        let backend: Arc<dyn TBackend> = Arc::new(RocksDBBackend::new(dir.clone()).unwrap());
        backend
            .write_fact(fact("catalog", "sku-2", json!({"qty": 42})))
            .await
            .unwrap();

        let m = load_machine();
        let exec = Arc::new(TBackendReadExecutor::new(STORAGE_CAP, backend));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec.clone());

        let first = run_service(
            &m,
            &reg,
            &read_req("same", "catalog", "sku-2"),
            RunMode::Live,
        )
        .await
        .unwrap();
        let second = run_service(
            &m,
            &reg,
            &read_req("same", "catalog", "sku-2"),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(first.result, json!({"qty": 42}));
        assert_eq!(second.result, json!({"qty": 42}));
        assert_eq!(
            exec.read_count(),
            1,
            "real backend read must happen once per idempotency key"
        );

        // explicit replay mode also bypasses the real backend
        let replay = run_service(
            &m,
            &reg,
            &read_req("same", "catalog", "sku-2"),
            RunMode::Replay,
        )
        .await
        .unwrap();
        assert_eq!(replay.result, json!({"qty": 42}));
        assert_eq!(exec.read_count(), 1);

        let _ = std::fs::remove_dir_all(&dir);
    });
}

// ── #3: missing record → typed permanent_failure, no panic ─────────────────────

#[test]
fn missing_record_is_permanent_failure_not_panic() {
    rt().block_on(async {
        let dir = temp_dir();
        let backend: Arc<dyn TBackend> = Arc::new(RocksDBBackend::new(dir.clone()).unwrap());
        let m = load_machine();
        let exec = Arc::new(TBackendReadExecutor::new(STORAGE_CAP, backend));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec.clone());

        let out = run_service(
            &m,
            &reg,
            &read_req("m1", "catalog", "absent"),
            RunMode::Live,
        )
        .await
        .unwrap();
        // definite "not found" — permanent, NOT unknown_external_state
        assert_eq!(out.kind, OutcomeKind::PermanentFailure);
        assert_eq!(exec.read_count(), 1);

        let _ = std::fs::remove_dir_all(&dir);
    });
}

// ── #4: backend unavailable → unknown_external_state (explicitly decided) ───────

#[test]
fn backend_unavailable_is_unknown_external_state() {
    rt().block_on(async {
        // a real RemoteTcpBackend pointed at a dead port → connection refused on read
        let backend: Arc<dyn TBackend> = Arc::new(RemoteTcpBackend::new("127.0.0.1:1".to_string()));
        let m = load_machine();
        let exec = Arc::new(TBackendReadExecutor::new(STORAGE_CAP, backend));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec.clone());

        let out = run_service(&m, &reg, &read_req("u1", "catalog", "sku-x"), RunMode::Live)
            .await
            .unwrap();
        // the substrate did not answer — epistemic, NOT a failure
        assert_eq!(out.kind, OutcomeKind::UnknownExternalState);

        // the unknown outcome is itself recorded (auditable / replayable)
        let receipt = m
            .storage
            .read_as_of(RECEIPTS_STORE, "IO.StorageCapability:u1", f64::MAX)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(
            receipt.value["outcome_kind"],
            json!("unknown_external_state")
        );
    });
}

// ── #5: contract body still cannot perform IO through dispatch ─────────────────

#[test]
fn contract_body_cannot_read_real_backend() {
    rt().block_on(async {
        let dir = temp_dir();
        let backend: Arc<dyn TBackend> = Arc::new(RocksDBBackend::new(dir.clone()).unwrap());
        backend
            .write_fact(fact("catalog", "sku-3", json!({"qty": 1})))
            .await
            .unwrap();

        let m = load_machine();
        let exec = Arc::new(TBackendReadExecutor::new(STORAGE_CAP, backend));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec.clone());

        // dispatch runs only the VM — no executor registry, so no real read can happen
        let _ = m.dispatch("ExecuteQuery", json!({"plan": {}})).await;
        assert_eq!(
            exec.read_count(),
            0,
            "contract body must not read the real backend"
        );

        // only the host entrypoint reaches the real substrate
        run_service(
            &m,
            &reg,
            &read_req("io1", "catalog", "sku-3"),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(exec.read_count(), 1);

        let _ = std::fs::remove_dir_all(&dir);
    });
}
