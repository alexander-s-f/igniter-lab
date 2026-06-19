//! LAB-MACHINE-FACTSTORE-DURABILITY-HARDENING-P3 — storage hardening proofs.
//!
//! Closes the LAB-MACHINE-ROCKSDB-DURABILITY-P2 hole: atomic writes, observable corruption, and the
//! receipt spine going through the hardened `MpkFileBackend`. NO network, NO live endpoint, NO
//! power-loss claim (truncation/leftover-temp are deterministic stand-ins for a torn/crashed write).

use igniter_machine::backend::{MpkFileBackend, TBackend};
use igniter_machine::capability::{
    CapabilityExecutorRegistry, CapabilityPassport, RunMode, RECEIPTS_STORE,
};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::fact::Fact;
use igniter_machine::recovery::recover_dangling_writes;
use igniter_machine::retry_queue::{enqueue_retry, RETRY_QUEUE_STORE};
use igniter_machine::write::{
    payload_digest, value_digest, run_write_effect, FakeWriteExecutor, WriteBehavior, WriteRequest,
    WriteState,
};
use serde_json::{json, Value};
use std::path::PathBuf;
use std::sync::Arc;

const CAP: &str = "IO.RecordCapability";

fn clock() -> Arc<dyn ClockProvider> {
    Arc::new(FixedClock::new(100.0))
}
fn tmp() -> PathBuf {
    std::env::temp_dir().join(format!("igniter_p3_{}", uuid::Uuid::new_v4()))
}
fn be(dir: &PathBuf) -> Arc<dyn TBackend> {
    Arc::new(MpkFileBackend::new(dir.clone()).unwrap())
}
fn fact(store: &str, key: &str, n: i64, tt: f64) -> Fact {
    Fact {
        id: format!("{store}:{key}:{n}"),
        store: store.into(),
        key: key.into(),
        value: json!({ "n": n }),
        value_hash: String::new(),
        causation: None,
        transaction_time: tt,
        valid_time: None,
        schema_version: 1,
        producer: None,
        derivation: None,
    }
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
/// A dangling `prepared` receipt — as if the process crashed after the prepare gate but before the
/// terminal receipt. Auth/payload digests match a live request so recovery can resolve it.
fn prepared_fact(req: &WriteRequest, auth: &str) -> Fact {
    let store = req.payload["store"].as_str().unwrap();
    let key = req.payload["key"].as_str().unwrap();
    Fact {
        id: format!("write-receipt:{}:{}:prepared", req.capability_id, req.idempotency_key),
        store: RECEIPTS_STORE.into(),
        key: format!("{}:{}", req.capability_id, req.idempotency_key),
        value: json!({
            "capability_id": req.capability_id, "operation": req.operation,
            "idempotency_key": req.idempotency_key, "authority_digest": auth,
            "payload_digest": payload_digest(&req.payload), "target_store": store,
            "target_key": key, "value_digest": value_digest(&req.payload["value"]),
            "correlation_id": "c", "state": "prepared", "result": Value::Null, "detail": Value::Null,
        }),
        value_hash: String::new(), causation: None, transaction_time: 1.0, valid_time: None,
        schema_version: 1, producer: None, derivation: None,
    }
}
fn target_fact(req: &WriteRequest) -> Fact {
    let store = req.payload["store"].as_str().unwrap().to_string();
    let key = req.payload["key"].as_str().unwrap().to_string();
    Fact {
        id: format!("w:{store}:{key}"), store, key, value: req.payload["value"].clone(),
        value_hash: String::new(), causation: None, transaction_time: 1.0, valid_time: None,
        schema_version: 1, producer: None, derivation: None,
    }
}

/// Corruption is isolated + observable: a corrupt `.mpk` for one key does NOT silently empty it, and
/// a healthy sibling key still loads fine. (Card name.)
#[tokio::test]
async fn corrupt_fact_file_is_not_silently_dropped() {
    let dir = tmp();
    {
        let b = be(&dir);
        b.write_fact(fact("s", "good", 1, 100.0)).await.unwrap();
        b.write_fact(fact("s", "bad", 1, 100.0)).await.unwrap();
        b.write_fact(fact("s", "bad", 2, 200.0)).await.unwrap();
    }
    let bad = dir.join("s").join("bad.mpk");
    let bytes = std::fs::read(&bad).unwrap();
    std::fs::write(&bad, &bytes[..bytes.len() / 2]).unwrap();

    let re = MpkFileBackend::new(dir.clone()).unwrap();
    // corruption surfaced, not silent
    assert_eq!(re.corrupt_files().len(), 1);
    // the healthy key is unaffected — corruption is isolated per file
    let good = re.read_as_of("s", "good", f64::MAX).await.unwrap();
    assert_eq!(good.unwrap().value, json!({ "n": 1 }));

    let _ = std::fs::remove_dir_all(&dir);
}

/// A crashed/interrupted replace (leftover sibling temp) leaves the prior valid `.mpk` intact and is
/// ignored on reopen — the atomic temp→fsync→rename never half-writes the live file.
#[tokio::test]
async fn atomic_write_preserves_previous_version_on_failed_replace() {
    let dir = tmp();
    {
        let b = be(&dir);
        b.write_fact(fact("s", "k", 1, 100.0)).await.unwrap();
        b.write_fact(fact("s", "k", 2, 200.0)).await.unwrap();
    }
    // Simulate a crash mid-replace: a partial temp file is left next to the valid .mpk.
    let store_dir = dir.join("s");
    std::fs::write(store_dir.join(".k.mpk.999.tmp"), b"partial-garbage").unwrap();
    // Live .mpk must be a complete, valid file (the prior version is intact).
    let live = std::fs::read(store_dir.join("k.mpk")).unwrap();
    assert!(rmp_serde::from_slice::<Vec<Fact>>(&live).is_ok(), "prior .mpk still valid");

    let re = MpkFileBackend::new(dir.clone()).unwrap();
    assert!(re.corrupt_files().is_empty(), "leftover .tmp is not read as a fact file");
    let all = re.facts_for("s", "k", None, None).await.unwrap();
    assert_eq!(all.len(), 2, "both prior versions survive an interrupted replace");

    let _ = std::fs::remove_dir_all(&dir);
}

/// The dangerous P2 window converted to a safe one: with atomic writes a prepared receipt is either
/// fully durable (→ P19 recovery reconciles it, never re-executing) or never landed (→ no effect).
/// Here the prepare survived + the effect landed; recovery resolves it to `committed` WITHOUT an
/// executor (no re-exec) after reopen.
#[tokio::test]
async fn receipt_prepare_torn_write_blocks_or_recovers_without_reexec() {
    let dir = tmp();
    let sub = tmp();
    let req = write_req("torn", json!({ "q": 7 }));
    {
        let receipts = be(&dir);
        let substrate = be(&sub);
        receipts.write_fact(prepared_fact(&req, "a")).await.unwrap(); // prepared, durable
        substrate.write_fact(target_fact(&req)).await.unwrap(); // the effect DID land
    } // drop = crash before the terminal receipt
    let receipts2 = be(&dir);
    let substrate2 = be(&sub);
    let before = substrate2.facts_for("orders", "ord-torn", None, None).await.unwrap().len();
    let report = recover_dangling_writes(&receipts2, &substrate2, &clock()).await.unwrap();
    let after = substrate2.facts_for("orders", "ord-torn", None, None).await.unwrap().len();

    assert_eq!(report.committed, 1, "dangling prepared reconciled to committed");
    assert_eq!(before, after, "recovery never re-executes (substrate unchanged)");
    let state = receipts2
        .read_as_of(RECEIPTS_STORE, &format!("{CAP}:torn"), f64::MAX)
        .await.unwrap().unwrap().value["state"].as_str().unwrap().to_string();
    assert_eq!(state, "committed");

    let _ = std::fs::remove_dir_all(&dir);
    let _ = std::fs::remove_dir_all(&sub);
}

/// The receipt SPINE (`run_write_effect` → `receipts.write_fact`) writes through the hardened
/// `MpkFileBackend`, so a committed receipt is durable across a reopen — it does not bypass the
/// hardened path.
#[tokio::test]
async fn receipt_spine_uses_hardened_factstore_path() {
    let dir = tmp();
    let mut reg = CapabilityExecutorRegistry::new();
    reg.register(Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Commit)));
    let reg = Arc::new(reg);
    {
        let receipts = be(&dir);
        let res = run_write_effect(
            &reg, &receipts, &clock(), &passport(), "write",
            &write_req("spine", json!({ "q": 1 })), RunMode::Live,
        ).await.unwrap();
        assert_eq!(res.state, WriteState::Committed);
    } // drop = crash
    let receipts2 = be(&dir);
    let r = receipts2
        .read_as_of(RECEIPTS_STORE, &format!("{CAP}:spine"), f64::MAX)
        .await.unwrap();
    assert!(r.is_some(), "committed receipt from the spine survives reopen");
    assert_eq!(r.unwrap().value["state"].as_str().unwrap(), "committed");

    let _ = std::fs::remove_dir_all(&dir);
}

/// Retry-queue intents and dead-letter facts survive a restart through the hardened backend.
#[tokio::test]
async fn retry_queue_and_deadletter_survive_reopen() {
    let dir = tmp();
    {
        let receipts = be(&dir);
        enqueue_retry(&receipts, &clock(), &write_req("rq", json!(1)), "write", "auth", 3, 10.0)
            .await.unwrap();
        // a dead-letter fact (same shape the orchestrator writes)
        receipts.write_fact(Fact {
            id: "__dead_letter__:receipt:dl".into(),
            store: "__dead_letter__".into(),
            key: "receipt:dl".into(),
            value: json!({ "kind": "receipt", "key": "dl", "reason": "unresolved" }),
            value_hash: String::new(), causation: None, transaction_time: 1.0, valid_time: None,
            schema_version: 1, producer: None, derivation: None,
        }).await.unwrap();
    } // drop = crash
    let re = be(&dir);
    let rq = re.facts_for(RETRY_QUEUE_STORE, "rq", None, None).await.unwrap();
    assert!(!rq.is_empty(), "retry intent survived reopen");
    let dl = re.facts_for("__dead_letter__", "receipt:dl", None, None).await.unwrap();
    assert!(!dl.is_empty(), "dead-letter fact survived reopen");

    let _ = std::fs::remove_dir_all(&dir);
}
