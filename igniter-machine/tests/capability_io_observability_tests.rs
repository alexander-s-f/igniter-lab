//! LAB-MACHINE-CAPABILITY-IO-OBSERVABILITY-P23 — operator visibility as a fact projection.
//!
//! Metrics + a dead-letter inbox aggregated FROM the fact stores (receipts / retry queue /
//! dead-letters), never a side-log. Pure read-only projection; facts remain the source of truth.

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::RECEIPTS_STORE;
use igniter_machine::fact::Fact;
use igniter_machine::observability::observe;
use igniter_machine::orchestrator::DEAD_LETTER_STORE;
use igniter_machine::retry_queue::RETRY_QUEUE_STORE;
use serde_json::{json, Value};
use std::sync::Arc;

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}
fn mem() -> Arc<dyn TBackend> {
    Arc::new(InMemoryBackend::new())
}
fn fact(store: &str, key: &str, value: Value) -> Fact {
    Fact {
        id: format!("{store}:{key}"),
        store: store.into(),
        key: key.into(),
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
fn receipt(idem: &str, state: &str, detail: Option<&str>, correlation: Option<&str>) -> Fact {
    fact(
        RECEIPTS_STORE,
        &format!("IO.X:{idem}"),
        json!({
            "capability_id": "IO.X", "idempotency_key": idem, "state": state,
            "detail": detail, "correlation_id": correlation,
        }),
    )
}
fn dead(kind: &str, key: &str, reason: &str) -> Fact {
    fact(
        DEAD_LETTER_STORE,
        &format!("{kind}:{key}"),
        json!({ "kind": kind, "key": key, "reason": reason }),
    )
}
fn intent(base_key: &str, state: &str) -> Fact {
    fact(
        RETRY_QUEUE_STORE,
        base_key,
        json!({ "base_key": base_key, "state": state }),
    )
}

// ── metrics aggregate receipt states ───────────────────────────────────────────

#[test]
fn metrics_aggregate_receipt_states() {
    rt().block_on(async {
        let b = mem();
        for f in [
            receipt("c1", "committed", None, None),
            receipt("c2", "committed", None, None),
            receipt("u1", "unknown_external_state", None, None),
            receipt("a1", "aborted", None, None),
            receipt(
                "s1",
                "permanent_failure",
                Some("missing credential: tok"),
                None,
            ),
        ] {
            b.write_fact(f).await.unwrap();
        }
        let snap = observe(&b).await.unwrap();
        assert_eq!(snap.metrics.committed, 2);
        assert_eq!(snap.metrics.unknown, 1);
        assert_eq!(snap.metrics.aborted, 1);
        assert_eq!(snap.metrics.compensation, 1);
        assert_eq!(snap.metrics.permanent_failure, 1);
        assert_eq!(
            snap.metrics.secret_missing, 1,
            "permanent_failure + credential detail → secret_missing"
        );
    });
}

// ── dead-letter inbox grouped by reason ────────────────────────────────────────

#[test]
fn dead_letter_inbox_grouped_by_reason() {
    rt().block_on(async {
        let b = mem();
        for f in [
            dead("retry_intent", "k1", "Exhausted"),
            dead("retry_intent", "k2", "Exhausted"),
            dead("receipt", "IO.X:u1", "unresolved after recovery"),
        ] {
            b.write_fact(f).await.unwrap();
        }
        let snap = observe(&b).await.unwrap();
        assert_eq!(snap.dead_letters.total, 3);
        assert_eq!(snap.metrics.dead_letters, 3);
        assert_eq!(snap.dead_letters.by_reason.get("Exhausted"), Some(&2));
        assert_eq!(
            snap.dead_letters.by_reason.get("unresolved after recovery"),
            Some(&1)
        );
    });
}

// ── a dead-letter is joined to the receipt's correlation id ────────────────────

#[test]
fn dead_letter_joins_correlation() {
    rt().block_on(async {
        let b = mem();
        b.write_fact(receipt(
            "u1",
            "unknown_external_state",
            None,
            Some("corr-77"),
        ))
        .await
        .unwrap();
        b.write_fact(dead("receipt", "IO.X:u1", "unresolved after recovery"))
            .await
            .unwrap();
        let snap = observe(&b).await.unwrap();
        let entry = snap
            .dead_letters
            .entries
            .iter()
            .find(|e| e.key == "IO.X:u1")
            .unwrap();
        assert_eq!(entry.correlation.as_deref(), Some("corr-77"));
    });
}

// ── retry intent counts ────────────────────────────────────────────────────────

#[test]
fn retry_intent_counts() {
    rt().block_on(async {
        let b = mem();
        b.write_fact(intent("p1", "pending")).await.unwrap();
        b.write_fact(intent("e1", "exhausted")).await.unwrap();
        b.write_fact(intent("d1", "done")).await.unwrap();
        let snap = observe(&b).await.unwrap();
        assert_eq!(snap.metrics.retry_pending, 1);
        assert_eq!(snap.metrics.retry_exhausted, 1);
        assert_eq!(snap.metrics.retry_done, 1);
    });
}

// ── snapshot exports as a JSON struct ──────────────────────────────────────────

#[test]
fn snapshot_exports_json() {
    rt().block_on(async {
        let b = mem();
        b.write_fact(receipt("c1", "committed", None, None))
            .await
            .unwrap();
        b.write_fact(dead("retry_intent", "k1", "Exhausted"))
            .await
            .unwrap();
        let j = observe(&b).await.unwrap().to_json();
        assert_eq!(j["metrics"]["committed"], json!(1));
        assert_eq!(j["metrics"]["dead_letters"], json!(1));
        assert_eq!(j["dead_letters"]["total"], json!(1));
        assert_eq!(j["dead_letters"]["by_reason"]["Exhausted"], json!(1));
    });
}

// ── projection is read-only + idempotent (facts are the source of truth) ───────

#[test]
fn projection_is_readonly_and_idempotent() {
    rt().block_on(async {
        let b = mem();
        b.write_fact(receipt("c1", "committed", None, None))
            .await
            .unwrap();
        let before = b.all_facts().await.unwrap().len();
        let a = observe(&b).await.unwrap();
        let c = observe(&b).await.unwrap();
        let after = b.all_facts().await.unwrap().len();
        assert_eq!(a, c, "the projection is deterministic");
        assert_eq!(
            before, after,
            "observe writes no facts — facts stay the source of truth"
        );
    });
}
