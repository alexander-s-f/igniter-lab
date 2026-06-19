//! LAB-MACHINE-CAPABILITY-IO-ORCHESTRATOR-P20 — host-driven control loop.
//!
//! Explicit boot/tick/report over the existing primitives (P19 recovery, P9 retry queue). No
//! background daemon, no infinite loop, compensation NOT auto-driven. Everything is audited;
//! nothing stuck is silently skipped (dead-letter facts).

use igniter_machine::backend::{InMemoryBackend, RemoteTcpBackend, TBackend};
use igniter_machine::capability::{CapabilityExecutorRegistry, CapabilityPassport, RECEIPTS_STORE};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::fact::Fact;
use igniter_machine::orchestrator::{
    EffectOrchestrator, DEAD_LETTER_STORE, ORCHESTRATOR_AUDIT_STORE,
};
use igniter_machine::retry_queue::enqueue_retry;
use igniter_machine::write::{
    payload_digest, value_digest, FakeWriteExecutor, WriteBehavior, WriteRequest,
};
use serde_json::{json, Value};
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
fn mem() -> Arc<dyn TBackend> {
    Arc::new(InMemoryBackend::new())
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
fn prepared_fact(req: &WriteRequest) -> Fact {
    let v = json!({
        "capability_id": req.capability_id, "operation": req.operation, "idempotency_key": req.idempotency_key,
        "authority_digest": "a", "payload_digest": payload_digest(&req.payload),
        "target_store": req.payload["store"], "target_key": req.payload["key"],
        "value_digest": value_digest(&req.payload["value"]), "state": "prepared",
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
    Fact {
        id: format!("w-{}", req.idempotency_key),
        store: "orders".into(),
        key: req.payload["key"].as_str().unwrap().into(),
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
async fn count_in_store(b: &Arc<dyn TBackend>, store: &str) -> usize {
    b.all_facts()
        .await
        .unwrap()
        .into_iter()
        .filter(|f| f.store == store)
        .count()
}

// ── boot recovers dangling + audits ────────────────────────────────────────────

#[test]
fn boot_recovers_dangling_and_audits() {
    rt().block_on(async {
        let receipts = mem();
        let substrate = mem();
        let req = write_req("b1", json!({"qty": 5}));
        substrate.write_fact(target_fact(&req)).await.unwrap(); // effect landed
        receipts.write_fact(prepared_fact(&req)).await.unwrap(); // receipt stuck at prepared
        let reg = CapabilityExecutorRegistry::new();
        let p = passport();
        let orch = EffectOrchestrator {
            receipts: &receipts,
            substrate: &substrate,
            registry: &reg,
            clock: &clock(),
            passport: &p,
            base_delay: 0.0,
        };

        let report = orch.boot().await.unwrap();
        assert_eq!(report.committed, 1);
        let r = receipts
            .read_as_of(RECEIPTS_STORE, "IO.RecordCapability:b1", f64::MAX)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(r.value["state"], json!("committed"));
        assert!(
            count_in_store(&receipts, ORCHESTRATOR_AUDIT_STORE).await >= 1,
            "boot is audited"
        );
    });
}

// ── boot is idempotent ─────────────────────────────────────────────────────────

#[test]
fn boot_is_idempotent() {
    rt().block_on(async {
        let receipts = mem();
        let substrate = mem();
        let req = write_req("b2", json!({"qty": 1}));
        substrate.write_fact(target_fact(&req)).await.unwrap();
        receipts.write_fact(prepared_fact(&req)).await.unwrap();
        let reg = CapabilityExecutorRegistry::new();
        let p = passport();
        let orch = EffectOrchestrator {
            receipts: &receipts,
            substrate: &substrate,
            registry: &reg,
            clock: &clock(),
            passport: &p,
            base_delay: 0.0,
        };

        let first = orch.boot().await.unwrap();
        let second = orch.boot().await.unwrap();
        assert_eq!(first.scanned, 1);
        assert_eq!(
            second.scanned, 0,
            "after recovery everything is terminal — boot recovers nothing"
        );
    });
}

// ── unresolvable dangling → dead-letter (no silent skip) ───────────────────────

#[test]
fn boot_dead_letters_unresolvable() {
    rt().block_on(async {
        let receipts = mem();
        let dead_substrate: Arc<dyn TBackend> =
            Arc::new(RemoteTcpBackend::new("127.0.0.1:1".into()));
        let req = write_req("b3", json!({"qty": 1}));
        receipts.write_fact(prepared_fact(&req)).await.unwrap();
        let reg = CapabilityExecutorRegistry::new();
        let p = passport();
        let orch = EffectOrchestrator {
            receipts: &receipts,
            substrate: &dead_substrate,
            registry: &reg,
            clock: &clock(),
            passport: &p,
            base_delay: 0.0,
        };

        orch.boot().await.unwrap();
        // substrate unavailable → still unresolved → dead-lettered, not silently skipped
        assert_eq!(count_in_store(&receipts, DEAD_LETTER_STORE).await, 1);
        assert_eq!(orch.report().await.unwrap().dead_letters, 1);
    });
}

// ── tick drains a due retry intent ─────────────────────────────────────────────

#[test]
fn tick_drains_due_retry_intent() {
    rt().block_on(async {
        let receipts = mem();
        let substrate = mem();
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Commit));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec.clone());
        let p = passport();
        // an intent due immediately (base_delay 0)
        enqueue_retry(
            &receipts,
            &clock(),
            &write_req("t1", json!({"qty": 1})),
            "write",
            &p.authority_digest(),
            3,
            0.0,
        )
        .await
        .unwrap();
        let orch = EffectOrchestrator {
            receipts: &receipts,
            substrate: &substrate,
            registry: &reg,
            clock: &clock(),
            passport: &p,
            base_delay: 0.0,
        };

        let reports = orch.tick().await.unwrap();
        assert_eq!(reports.len(), 1, "the due intent was drained");
        assert_eq!(exec.applied_count(), 1, "the retried effect was performed");
        assert!(
            count_in_store(&receipts, ORCHESTRATOR_AUDIT_STORE).await >= 1,
            "tick is audited"
        );
    });
}

// ── exhausted retries → dead-letter ────────────────────────────────────────────

#[test]
fn tick_dead_letters_exhausted_retries() {
    rt().block_on(async {
        let receipts = mem();
        let substrate = mem();
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Retryable));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        let p = passport();
        enqueue_retry(
            &receipts,
            &clock(),
            &write_req("t2", json!({"qty": 1})),
            "write",
            &p.authority_digest(),
            2,
            0.0,
        )
        .await
        .unwrap();
        let orch = EffectOrchestrator {
            receipts: &receipts,
            substrate: &substrate,
            registry: &reg,
            clock: &clock(),
            passport: &p,
            base_delay: 0.0,
        };

        // max_attempts=2, always retryable → tick until exhausted
        for _ in 0..4 {
            orch.tick().await.unwrap();
        }
        assert!(
            count_in_store(&receipts, DEAD_LETTER_STORE).await >= 1,
            "an exhausted intent is dead-lettered"
        );
        assert!(orch.report().await.unwrap().dead_letters >= 1);
    });
}

// ── report snapshot reflects receipt states ────────────────────────────────────

#[test]
fn report_reflects_state() {
    rt().block_on(async {
        let receipts = mem();
        let substrate = mem();
        let req = write_req("r1", json!({"qty": 5}));
        substrate.write_fact(target_fact(&req)).await.unwrap();
        receipts.write_fact(prepared_fact(&req)).await.unwrap();
        let reg = CapabilityExecutorRegistry::new();
        let p = passport();
        let orch = EffectOrchestrator {
            receipts: &receipts,
            substrate: &substrate,
            registry: &reg,
            clock: &clock(),
            passport: &p,
            base_delay: 0.0,
        };

        // before boot: a dangling prepared
        assert_eq!(orch.report().await.unwrap().receipts_prepared, 1);
        orch.boot().await.unwrap();
        // after boot: committed, no dangling
        let s = orch.report().await.unwrap();
        assert_eq!(s.receipts_committed, 1);
        assert_eq!(s.receipts_prepared, 0);
    });
}
