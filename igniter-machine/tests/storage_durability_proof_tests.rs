//! LAB-MACHINE-ROCKSDB-DURABILITY-P2 (audit) → HARDENED by P3.
//!
//! These tests anchor the durability boundary of the `.mpk` file store (`MpkFileBackend`, aliased
//! `RocksDBBackend` — a pure-Rust filesystem store, NOT the real RocksDB crate):
//!
//!   * graceful-restart durability is real: facts fully written before a clean drop survive a reopen
//!     (the level P19 recovery relies on);
//!   * P2's OPEN RISK (a truncated/corrupt `.mpk` SILENTLY dropped on reopen) is now CLOSED by P3:
//!     corruption is observable via `corrupt_files()` and a write to a corrupt key refuses with
//!     `EngineError::Corruption` instead of silently dropping history. The two tests below assert the
//!     HARDENED behaviour (they previously documented the silent-loss bug).
//!
//! Deeper hardening proofs (atomic write, receipt-spine path, retry/dead-letter survival) live in
//! `storage_durability_hardening_tests.rs`. NO network, NO live, NO power-loss claim. Truncation is a
//! deterministic stand-in for a torn write, not a power-loss test.

use igniter_machine::backend::{RocksDBBackend, TBackend};
use igniter_machine::fact::Fact;
use std::path::PathBuf;
use std::sync::Arc;

fn tmp() -> PathBuf {
    std::env::temp_dir().join(format!("igniter_durability_p2_{}", uuid::Uuid::new_v4()))
}

fn fact(store: &str, key: &str, n: i64, tt: f64) -> Fact {
    Fact {
        id: format!("{store}:{key}:{n}"),
        store: store.to_string(),
        key: key.to_string(),
        value: serde_json::json!({ "n": n }),
        value_hash: String::new(),
        causation: None,
        transaction_time: tt,
        valid_time: None,
        schema_version: 1,
        producer: None,
        derivation: None,
    }
}

/// PROVEN: a fully-written fact survives a clean process restart (drop + reopen on the same dir).
/// This is exactly the durability level P19 recovery is built on — graceful restart, not power loss.
#[tokio::test]
async fn durable_across_graceful_reopen() {
    let dir = tmp();
    {
        let be = RocksDBBackend::new(dir.clone()).unwrap();
        be.write_fact(fact("s", "k1", 1, 100.0)).await.unwrap();
        be.write_fact(fact("s", "k1", 2, 200.0)).await.unwrap();
        be.write_fact(fact("s", "k1", 3, 300.0)).await.unwrap();
        // drop -> simulates a CLEAN shutdown (OS has the bytes; this process is gone)
    }
    let reopened = RocksDBBackend::new(dir.clone()).unwrap();
    // all three versions are preloaded from the .mpk file
    let all = reopened.facts_for("s", "k1", None, None).await.unwrap();
    assert_eq!(all.len(), 3, "all written versions survive a graceful reopen");
    // latest-as-of reads the most recent
    let latest = reopened.read_as_of("s", "k1", f64::MAX).await.unwrap().unwrap();
    assert_eq!(latest.value, serde_json::json!({ "n": 3 }));

    let _ = std::fs::remove_dir_all(&dir);
}

/// HARDENED (P3): a truncated `.mpk` file — the shape a legacy/external torn write leaves — is no
/// longer SILENTLY dropped. On reopen it is recorded in `corrupt_files()` (observable) rather than
/// presenting as a successfully-empty key. (Was `truncated_mpk_silently_dropped_on_reopen` in P2,
/// which documented the OLD silent-loss behaviour now closed.)
#[tokio::test]
async fn corrupt_mpk_is_observable_not_silently_dropped() {
    let dir = tmp();
    {
        let be = RocksDBBackend::new(dir.clone()).unwrap();
        be.write_fact(fact("s", "k1", 1, 100.0)).await.unwrap();
        be.write_fact(fact("s", "k1", 2, 200.0)).await.unwrap();
        be.write_fact(fact("s", "k1", 3, 300.0)).await.unwrap();
    }
    // Corrupt the key's file the way a torn/legacy write would: keep only the first half.
    let mpk = dir.join("s").join("k1.mpk");
    let bytes = std::fs::read(&mpk).unwrap();
    assert!(bytes.len() > 4, "fixture sanity: file has content");
    std::fs::write(&mpk, &bytes[..bytes.len() / 2]).unwrap();

    let reopened = RocksDBBackend::new(dir.clone()).unwrap();
    // OBSERVABLE: corruption is surfaced, not silent.
    let corrupt = reopened.corrupt_files();
    assert_eq!(corrupt.len(), 1, "corrupt .mpk is recorded, not silently skipped");
    assert!(corrupt[0].ends_with("k1.mpk"));
    // The corrupt file is left on disk for forensics (not deleted, not overwritten-as-empty).
    assert!(mpk.exists(), "corrupt file preserved on disk");

    let _ = std::fs::remove_dir_all(&dir);
}

/// HARDENED (P3): a write to a key whose file is corrupt now REFUSES with `EngineError::Corruption`
/// instead of `unwrap_or_default()`-ing the unreadable file and persisting only the new fact (which
/// in P2 permanently erased prior history). The corrupt bytes are preserved for recovery.
#[tokio::test]
async fn write_to_corrupt_key_refuses_instead_of_dropping_history() {
    let dir = tmp();
    {
        let be = RocksDBBackend::new(dir.clone()).unwrap();
        be.write_fact(fact("s", "k1", 1, 100.0)).await.unwrap();
        be.write_fact(fact("s", "k1", 2, 200.0)).await.unwrap();
    }
    let mpk = dir.join("s").join("k1.mpk");
    let corrupt_bytes = {
        let bytes = std::fs::read(&mpk).unwrap();
        bytes[..bytes.len() / 2].to_vec()
    };
    std::fs::write(&mpk, &corrupt_bytes).unwrap(); // external corruption

    let reopened = RocksDBBackend::new(dir.clone()).unwrap();
    let err = reopened.write_fact(fact("s", "k1", 3, 300.0)).await;
    assert!(
        matches!(err, Err(igniter_machine::errors::EngineError::Corruption(_))),
        "write to a corrupt key must refuse loudly, got {err:?}"
    );
    // The corrupt file is untouched (not overwritten to drop history) and observable.
    assert_eq!(std::fs::read(&mpk).unwrap(), corrupt_bytes, "corrupt bytes preserved, not replaced");
    assert!(!reopened.corrupt_files().is_empty(), "corruption recorded");

    let _ = std::fs::remove_dir_all(&dir);
}
