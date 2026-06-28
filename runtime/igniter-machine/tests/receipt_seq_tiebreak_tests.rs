//! LAB-MACHINE-RECEIPT-SEQ-TIEBREAK-P4 — machine receipt "latest" selection must be deterministic at
//! equal `transaction_time` via a per-process `receipt_seq` tie-breaker (NOT the TBackend daemon
//! seq_id; not durable/global). `transaction_time` stays the primary audit order; `receipt_seq` only
//! breaks equal-timestamp ties. DB-free (in-memory backend + FixedClock).

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{
    CapabilityExecutorRegistry, CapabilityPassport, RunMode, RECEIPTS_STORE,
};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::fact::Fact;
use igniter_machine::recovery::recover_dangling_writes;
use igniter_machine::write::{
    run_write_effect, FakeWriteExecutor, WriteBehavior, WriteRequest, WriteState,
};
use serde_json::{json, Value};
use std::sync::Arc;

const CAP: &str = "IO.Record";

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}
fn clock() -> Arc<dyn ClockProvider> {
    Arc::new(FixedClock::new(100.0)) // FixedClock ⇒ prepared and terminal share transaction_time
}
fn store() -> Arc<dyn TBackend> {
    Arc::new(InMemoryBackend::new())
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
fn registry(behavior: WriteBehavior) -> CapabilityExecutorRegistry {
    let mut reg = CapabilityExecutorRegistry::new();
    reg.register(Arc::new(FakeWriteExecutor::new(CAP, behavior)));
    reg
}
fn write_req(key: &str) -> WriteRequest {
    WriteRequest {
        capability_id: CAP.into(),
        operation: "insert".into(),
        idempotency_key: key.into(),
        payload: json!({ "store": "s", "key": key, "value": { "n": 1 }, "correlation_id": "c" }),
    }
}

/// All receipt facts on a key, as `(state, transaction_time, receipt_seq)`.
async fn receipt_rows(s: &Arc<dyn TBackend>, rkey: &str) -> Vec<(String, f64, u64)> {
    s.facts_for(RECEIPTS_STORE, rkey, None, None)
        .await
        .unwrap()
        .into_iter()
        .map(|f| {
            (
                f.value
                    .get("state")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string(),
                f.transaction_time,
                f.value
                    .get("receipt_seq")
                    .and_then(|v| v.as_u64())
                    .unwrap_or(0),
            )
        })
        .collect()
}

// ── equal-tx: the terminal receipt beats its own `prepared` deterministically (Q: equal-timestamp) ──

#[test]
fn equal_timestamp_terminal_outranks_prepared_via_receipt_seq() {
    rt().block_on(async {
        let s = store();
        let out = run_write_effect(
            &registry(WriteBehavior::Commit),
            &s,
            &clock(),
            &passport(),
            "write",
            &write_req("k1"),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(out.state, WriteState::Committed);

        let rows = receipt_rows(&s, &format!("{CAP}:k1")).await;
        assert_eq!(
            rows.len(),
            2,
            "prepared + terminal facts on the key: {rows:?}"
        );
        // Both at the SAME transaction_time (FixedClock) — so only receipt_seq can order them.
        assert!(
            rows.iter().all(|(_, tx, _)| *tx == 100.0),
            "equal tx expected: {rows:?}"
        );
        let prepared_seq = rows.iter().find(|(st, ..)| st == "prepared").unwrap().2;
        let committed_seq = rows.iter().find(|(st, ..)| st == "committed").unwrap().2;
        assert!(
            committed_seq > prepared_seq,
            "terminal must carry a higher seq than its prepared ({committed_seq} > {prepared_seq})"
        );
    });
}

// ── replay: no new receipt, no seq increment ──────────────────────────────────────────────────────

#[test]
fn replay_writes_no_new_receipt_and_does_not_increment_seq() {
    rt().block_on(async {
        let s = store();
        let reg = registry(WriteBehavior::Commit);
        let first = run_write_effect(
            &reg,
            &s,
            &clock(),
            &passport(),
            "write",
            &write_req("k2"),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(first.state, WriteState::Committed);
        let before = receipt_rows(&s, &format!("{CAP}:k2")).await;

        // Same key + same payload → replay: returns the recorded outcome, writes NO new receipt.
        let replay = run_write_effect(
            &reg,
            &s,
            &clock(),
            &passport(),
            "write",
            &write_req("k2"),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(replay.state, WriteState::Committed);
        let after = receipt_rows(&s, &format!("{CAP}:k2")).await;

        assert_eq!(
            before.len(),
            after.len(),
            "replay must not append a receipt fact"
        );
        assert_eq!(before, after, "replay must not rewrite tx or receipt_seq");
    });
}

// ── recovery sweep: equal-tx ordering is decided by receipt_seq, NOT incidental push/iteration order ─

/// Build a receipt fact directly (adversarial ordering control for the recovery sweep).
fn receipt_fact(idem: &str, state: &str, tx: f64, seq: u64) -> Fact {
    Fact {
        id: format!("write-receipt:{CAP}:{idem}:{state}"),
        store: RECEIPTS_STORE.into(),
        key: format!("{CAP}:{idem}"),
        value: json!({
            "capability_id": CAP, "idempotency_key": idem,
            "authority_digest": "a", "payload_digest": "p",
            "state": state, "result": Value::Null, "detail": Value::Null,
            "receipt_seq": seq,
        }),
        value_hash: String::new(),
        causation: None,
        transaction_time: tx,
        valid_time: None,
        schema_version: 1,
        producer: None,
        derivation: None,
    }
}

#[test]
fn recovery_equal_tx_higher_seq_terminal_is_latest_not_dangling() {
    rt().block_on(async {
        let s = store();
        let substrate = store(); // unused when nothing is dangling
                                 // Adversarial PUSH order: terminal FIRST, prepared LAST — so the old wall-clock-only `>=`
                                 // (last-equal wins) would pick `prepared` and mis-classify it as dangling. The higher
                                 // receipt_seq on `committed` must win regardless of push order.
        s.write_fact(receipt_fact("won", "committed", 100.0, 10))
            .await
            .unwrap();
        s.write_fact(receipt_fact("won", "prepared", 100.0, 5))
            .await
            .unwrap();

        // Deterministic across repeated runs.
        for _ in 0..3 {
            let report = recover_dangling_writes(&s, &substrate, &clock())
                .await
                .unwrap();
            assert_eq!(
                report.scanned, 0,
                "committed (higher seq) is latest → nothing dangling: {report:?}"
            );
        }
    });
}

#[test]
fn recovery_equal_tx_higher_seq_prepared_is_latest_and_dangling() {
    rt().block_on(async {
        let s = store();
        let substrate = store();
        // Negative control: this time `prepared` carries the higher seq, so it IS the latest at the
        // equal tx and is correctly seen as dangling (proves seq genuinely orders — not "terminal
        // always wins").
        s.write_fact(receipt_fact("pend", "committed", 100.0, 5))
            .await
            .unwrap();
        s.write_fact(receipt_fact("pend", "prepared", 100.0, 10))
            .await
            .unwrap();

        let report = recover_dangling_writes(&s, &substrate, &clock())
            .await
            .unwrap();
        assert_eq!(
            report.scanned, 1,
            "prepared (higher seq) is latest → one dangling receipt: {report:?}"
        );
    });
}
