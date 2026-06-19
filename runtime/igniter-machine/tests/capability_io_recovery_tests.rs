//! LAB-MACHINE-CAPABILITY-IO-DURABLE-RECOVERY-P19 — durable receipts + crash recovery.
//!
//! P18 protected "parallel right now"; P19 protects "the process died mid-effect". Receipts live
//! on a durable backend (RocksDB) so they survive a restart; a recovery sweep reconciles any
//! dangling `prepared` receipt (read-back / correlation) — NEVER blindly re-executes. The center
//! is the "write-succeeded-but-receipt-failed" window: the effect landed but the receipt is stuck
//! at `prepared` → recovery reads the target back and resolves it to `committed`.

use igniter_machine::backend::{RocksDBBackend, TBackend};
use igniter_machine::capability::{
    CapabilityExecutorRegistry, CapabilityPassport, RunMode, RECEIPTS_STORE,
};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::correlation::MapCorrelationResolver;
use igniter_machine::fact::Fact;
use igniter_machine::recovery::{
    recover_dangling_by_correlation, recover_dangling_writes, RecoveryReport,
};
use igniter_machine::single_flight::{run_write_effect_atomic, SingleFlight};
use igniter_machine::write::{
    payload_digest, value_digest, FakeWriteExecutor, WriteBehavior, WriteRequest, WriteState,
};
use serde_json::{json, Value};
use std::path::PathBuf;
use std::sync::Arc;

const CAP: &str = "IO.RecordCapability";

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}
fn clock() -> Arc<dyn ClockProvider> {
    Arc::new(FixedClock::new(100.0))
}
fn tmp() -> PathBuf {
    std::env::temp_dir().join(format!("igniter_p19_{}", uuid::Uuid::new_v4()))
}
fn rocks(dir: &PathBuf) -> Arc<dyn TBackend> {
    Arc::new(RocksDBBackend::new(dir.clone()).unwrap())
}
fn passport() -> CapabilityPassport {
    CapabilityPassport {
        subject: "host".into(),
        capability_id: CAP.into(),
        scopes: vec!["write".into()],
        issued_at: 0.0,
        expires_at: Some(1_000_000.0),
        revoked: false,
        evidence_digest: "s".into(),
    }
}
fn write_req(idem: &str, value: Value) -> WriteRequest {
    WriteRequest {
        capability_id: CAP.into(),
        operation: "put".into(),
        idempotency_key: idem.into(),
        payload: json!({ "store": "orders", "key": format!("ord-{idem}"), "value": value }),
    }
}

/// A DANGLING `prepared` receipt (as if the process crashed after the prepare gate). Digests are
/// set so a subsequent same-key write can replay (auth/payload match the live request).
fn prepared_fact(req: &WriteRequest, correlation: &str, auth_digest: &str) -> Fact {
    let store = req.payload["store"].as_str().unwrap();
    let key = req.payload["key"].as_str().unwrap();
    let v = json!({
        "capability_id": req.capability_id, "operation": req.operation, "idempotency_key": req.idempotency_key,
        "authority_digest": auth_digest, "payload_digest": payload_digest(&req.payload),
        "target_store": store, "target_key": key, "value_digest": value_digest(&req.payload["value"]),
        "correlation_id": correlation, "state": "prepared", "result": Value::Null, "detail": Value::Null,
    });
    Fact {
        id: format!(
            "write-receipt:{}:{}:prepared",
            req.capability_id, req.idempotency_key
        ),
        store: RECEIPTS_STORE.into(),
        key: format!("{}:{}", req.capability_id, req.idempotency_key),
        value: v,
        value_hash: String::new(),
        causation: None,
        transaction_time: 1.0,
        valid_time: None,
        schema_version: 1,
        producer: None,
        derivation: None,
    }
}
fn target_fact(req: &WriteRequest) -> Fact {
    let store = req.payload["store"].as_str().unwrap().to_string();
    let key = req.payload["key"].as_str().unwrap().to_string();
    Fact {
        id: format!("w:{store}:{key}"),
        store,
        key,
        value: req.payload["value"].clone(),
        value_hash: String::new(),
        causation: None,
        transaction_time: 1.0,
        valid_time: None,
        schema_version: 1,
        producer: None,
        derivation: None,
    }
}
async fn state_of(receipts: &Arc<dyn TBackend>, idem: &str) -> String {
    receipts
        .read_as_of(RECEIPTS_STORE, &format!("{CAP}:{idem}"), f64::MAX)
        .await
        .unwrap()
        .unwrap()
        .value["state"]
        .as_str()
        .unwrap()
        .to_string()
}

// ── durability: a receipt survives a restart (RocksDB reload) ──────────────────

#[test]
fn durable_receipt_survives_restart() {
    rt().block_on(async {
        let dir = tmp();
        {
            let receipts = rocks(&dir);
            receipts
                .write_fact(prepared_fact(&write_req("d1", json!({"q": 1})), "c", "a"))
                .await
                .unwrap();
        } // drop = "crash"
          // restart: a fresh backend on the SAME dir reloads the persisted facts
        let receipts2 = rocks(&dir);
        let r = receipts2
            .read_as_of(RECEIPTS_STORE, &format!("{CAP}:d1"), f64::MAX)
            .await
            .unwrap();
        assert!(r.is_some(), "the receipt survived the restart");
        let _ = std::fs::remove_dir_all(&dir);
    });
}

// ── window #2 (the center): effect landed, receipt stuck at prepared → committed ─

#[test]
fn dangling_prepared_recovers_committed_when_landed() {
    rt().block_on(async {
        let (rd, sd) = (tmp(), tmp());
        let req = write_req("w2", json!({"qty": 5}));
        {
            let receipts = rocks(&rd);
            let substrate = rocks(&sd);
            // crash AFTER the executor succeeded but BEFORE the committed receipt:
            substrate.write_fact(target_fact(&req)).await.unwrap(); // the effect DID land
            receipts
                .write_fact(prepared_fact(&req, "c", "a"))
                .await
                .unwrap(); // receipt stuck at prepared
        }
        // restart + recovery sweep
        let receipts2 = rocks(&rd);
        let substrate2 = rocks(&sd);
        let report = recover_dangling_writes(&receipts2, &substrate2, &clock())
            .await
            .unwrap();
        assert_eq!(
            report,
            RecoveryReport {
                scanned: 1,
                committed: 1,
                permanent_failure: 0,
                still_unknown: 0
            }
        );
        assert_eq!(state_of(&receipts2, "w2").await, "committed");
        let _ = std::fs::remove_dir_all(&rd);
        let _ = std::fs::remove_dir_all(&sd);
    });
}

// ── window #1: effect did NOT land → permanent_failure ─────────────────────────

#[test]
fn dangling_prepared_recovers_permanent_failure_when_not_landed() {
    rt().block_on(async {
        let (rd, sd) = (tmp(), tmp());
        let req = write_req("w1", json!({"qty": 9}));
        {
            let receipts = rocks(&rd);
            receipts
                .write_fact(prepared_fact(&req, "c", "a"))
                .await
                .unwrap();
            let _ = rocks(&sd); // empty substrate — the effect never landed
        }
        let receipts2 = rocks(&rd);
        let substrate2 = rocks(&sd);
        let report = recover_dangling_writes(&receipts2, &substrate2, &clock())
            .await
            .unwrap();
        assert_eq!(report.permanent_failure, 1);
        assert_eq!(state_of(&receipts2, "w1").await, "permanent_failure");
        let _ = std::fs::remove_dir_all(&rd);
        let _ = std::fs::remove_dir_all(&sd);
    });
}

// ── recovery never re-executes: it only reads the substrate + writes receipts ──

#[test]
fn recovery_never_reexecutes() {
    rt().block_on(async {
        let (rd, sd) = (tmp(), tmp());
        let req = write_req("ne", json!({"qty": 1}));
        let receipts = rocks(&rd);
        let substrate = rocks(&sd);
        substrate.write_fact(target_fact(&req)).await.unwrap();
        receipts
            .write_fact(prepared_fact(&req, "c", "a"))
            .await
            .unwrap();

        let before = substrate
            .facts_for("orders", "ord-ne", None, None)
            .await
            .unwrap()
            .len();
        recover_dangling_writes(&receipts, &substrate, &clock())
            .await
            .unwrap();
        let after = substrate
            .facts_for("orders", "ord-ne", None, None)
            .await
            .unwrap()
            .len();
        assert_eq!(
            before, after,
            "recovery must not mutate the substrate (no re-execute)"
        );
        let _ = std::fs::remove_dir_all(&rd);
        let _ = std::fs::remove_dir_all(&sd);
    });
}

// ── recovery by correlation id (HTTP/remote effects) ───────────────────────────

#[test]
fn recovery_by_correlation_resolves() {
    rt().block_on(async {
        let rd = tmp();
        let landed = write_req("cl", json!({"q": 1}));
        let lost = write_req("cn", json!({"q": 1}));
        {
            let receipts = rocks(&rd);
            receipts
                .write_fact(prepared_fact(&landed, "corr-landed", "a"))
                .await
                .unwrap();
            receipts
                .write_fact(prepared_fact(&lost, "corr-lost", "a"))
                .await
                .unwrap();
        }
        let receipts2 = rocks(&rd);
        let resolver = MapCorrelationResolver::new(&["corr-landed"]); // only this one landed
        let report = recover_dangling_by_correlation(&receipts2, &resolver, &clock())
            .await
            .unwrap();
        assert_eq!(report.scanned, 2);
        assert_eq!(report.committed, 1);
        assert_eq!(report.permanent_failure, 1);
        assert_eq!(state_of(&receipts2, "cl").await, "committed");
        assert_eq!(state_of(&receipts2, "cn").await, "permanent_failure");
        let _ = std::fs::remove_dir_all(&rd);
    });
}

// ── after recovery → committed, a re-issued same-key write replays (no re-exec) ─

#[test]
fn recovered_committed_then_replays_no_reexecute() {
    rt().block_on(async {
        let (rd, sd) = (tmp(), tmp());
        let p = passport();
        let req = write_req("rr", json!({"qty": 7}));
        {
            let receipts = rocks(&rd);
            let substrate = rocks(&sd);
            substrate.write_fact(target_fact(&req)).await.unwrap();
            receipts
                .write_fact(prepared_fact(&req, "c", &p.authority_digest()))
                .await
                .unwrap();
        }
        let receipts2 = rocks(&rd);
        let substrate2 = rocks(&sd);
        recover_dangling_writes(&receipts2, &substrate2, &clock())
            .await
            .unwrap();
        assert_eq!(state_of(&receipts2, "rr").await, "committed");

        // a re-issued identical write must REPLAY the recovered receipt, never execute again
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Commit));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec.clone());
        let sf = SingleFlight::new();
        let out = run_write_effect_atomic(
            &sf,
            &reg,
            &receipts2,
            &clock(),
            &p,
            "write",
            &req,
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(out.state, WriteState::Committed);
        assert_eq!(
            exec.applied_count(),
            0,
            "recovered-committed write is replayed, never re-executed"
        );
        let _ = std::fs::remove_dir_all(&rd);
        let _ = std::fs::remove_dir_all(&sd);
    });
}

// ── the retry queue survives a restart ─────────────────────────────────────────

#[test]
fn retry_queue_survives_restart() {
    rt().block_on(async {
        let dir = tmp();
        {
            let receipts = rocks(&dir);
            igniter_machine::retry_queue::enqueue_retry(
                &receipts,
                &clock(),
                &write_req("rq", json!(1)),
                "write",
                "auth",
                3,
                10.0,
            )
            .await
            .unwrap();
        }
        let receipts2 = rocks(&dir);
        let intents: Vec<Value> = receipts2
            .all_facts()
            .await
            .unwrap()
            .into_iter()
            .filter(|f| f.store == igniter_machine::retry_queue::RETRY_QUEUE_STORE)
            .map(|f| f.value)
            .collect();
        assert!(!intents.is_empty(), "the retry intent survived the restart");
        assert_eq!(intents[0]["base_key"], json!("rq"));
        let _ = std::fs::remove_dir_all(&dir);
    });
}
