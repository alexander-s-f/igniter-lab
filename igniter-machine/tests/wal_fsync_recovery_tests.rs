//! LAB-MACHINE-WAL-FSYNC-NONSILENT-RECOVERY-P2.
//!
//! The machine WAL is `len(u32 BE) | msgpack(Fact) | crc32(u32 BE)` per record. These tests
//! anchor:
//!   * the explicit durability policy (default = `Sync`/fsync, selectable `Flush`);
//!   * non-silent recovery: a benign torn TAIL recovers the healthy prefix and is FLAGGED, while
//!     mid-stream corruption is REPORTED and makes the boot-facing `replay()` FAIL CLOSED.
//!
//! NO power-loss claim. WAL files are corrupted/truncated deterministically on disk (a stand-in
//! for a torn write), never by pulling power.

use igniter_machine::fact::Fact;
use igniter_machine::wal::{WALWriter, WalCorruptionKind, WalDurability};
use std::path::PathBuf;

fn tmp(tag: &str) -> PathBuf {
    std::env::temp_dir().join(format!("igniter_wal_p2_{}_{}", tag, uuid::Uuid::new_v4()))
}

fn fact(key: &str, n: i64) -> Fact {
    Fact {
        id: format!("recpt:{key}:{n}"),
        store: "receipts".to_string(),
        key: key.to_string(),
        value: serde_json::json!({ "n": n }),
        value_hash: String::new(),
        causation: None,
        transaction_time: n as f64,
        valid_time: None,
        schema_version: 1,
        producer: None,
        derivation: None,
    }
}

/// Frame a raw body the way the WAL does: `len | body | crc32(body)`.
fn frame(body: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();
    out.extend_from_slice(&(body.len() as u32).to_be_bytes());
    out.extend_from_slice(body);
    out.extend_from_slice(&crc32fast::hash(body).to_be_bytes());
    out
}

// ── durability policy is explicit ───────────────────────────────────────────────

#[test]
fn default_durability_is_sync_and_is_selectable() {
    let p = tmp("policy");
    let w = WALWriter::new(&p).unwrap();
    assert_eq!(
        w.durability(),
        WalDurability::Sync,
        "default must be durable fsync"
    );

    let p2 = tmp("policy_flush");
    let w2 = WALWriter::with_durability(&p2, WalDurability::Flush).unwrap();
    assert_eq!(w2.durability(), WalDurability::Flush);
}

// ── clean replay recovers everything and is quiet ───────────────────────────────

#[test]
fn clean_replay_recovers_all_and_reports_no_corruption() {
    let p = tmp("clean");
    let w = WALWriter::new(&p).unwrap();
    for i in 0..3 {
        w.append(&fact("k", i)).unwrap();
    }
    let report = w.replay_reported().unwrap();
    assert_eq!(report.facts.len(), 3);
    assert_eq!(report.recovered, 3);
    assert!(!report.truncated_tail, "a complete log is not a torn tail");
    assert!(
        report.corrupt.is_empty(),
        "no corruption: {:?}",
        report.corrupt
    );

    // The boot-facing API agrees and does not fail closed.
    assert_eq!(w.replay().unwrap().len(), 3);
}

// ── a torn tail is benign: recover the prefix, flag the tail, boot still succeeds ─

#[test]
fn truncated_tail_recovers_prefix_and_is_flagged_not_fatal() {
    let p = tmp("torn");
    {
        let w = WALWriter::new(&p).unwrap();
        w.append(&fact("k", 1)).unwrap();
        w.append(&fact("k", 2)).unwrap();
    }
    // Cut a few bytes off the end → the last record is now incomplete.
    let bytes = std::fs::read(&p).unwrap();
    std::fs::write(&p, &bytes[..bytes.len() - 3]).unwrap();

    let w = WALWriter::new(&p).unwrap();
    let report = w.replay_reported().unwrap();
    assert_eq!(report.facts.len(), 1, "healthy prefix recovered");
    assert!(
        report.truncated_tail,
        "the torn last record must be flagged"
    );
    assert!(
        report.corrupt.is_empty(),
        "a torn tail is not mid-stream corruption"
    );

    // A torn tail must NOT fail boot — the prefix is durable and recoverable.
    assert_eq!(w.replay().unwrap().len(), 1);
}

// ── mid-stream CRC corruption is reported and fails the boot path closed ─────────

#[test]
fn crc_mismatch_is_reported_and_boot_fails_closed() {
    let p = tmp("crc");
    {
        let w = WALWriter::new(&p).unwrap();
        w.append(&fact("k", 1)).unwrap();
        w.append(&fact("k", 2)).unwrap();
    }
    // Flip a byte inside the LAST record's CRC field (the final byte) → stored crc ≠ hash(body).
    let mut bytes = std::fs::read(&p).unwrap();
    let last = bytes.len() - 1;
    bytes[last] ^= 0xFF;
    std::fs::write(&p, &bytes).unwrap();

    let w = WALWriter::new(&p).unwrap();
    let report = w.replay_reported().unwrap();
    assert_eq!(
        report.facts.len(),
        1,
        "the healthy record before the corruption is recovered"
    );
    assert_eq!(
        report.corrupt.len(),
        1,
        "the corrupt record is reported: {:?}",
        report.corrupt
    );
    assert_eq!(report.corrupt[0].kind, WalCorruptionKind::CrcMismatch);
    assert!(
        !report.truncated_tail,
        "a wrong CRC is corruption, not truncation"
    );

    // The boot-facing replay must fail closed rather than silently drop history.
    let err = w.replay().unwrap_err();
    assert!(
        format!("{err}").contains("corrupt"),
        "boot must surface corruption: {err}"
    );
}

// ── a CRC-valid but undecodable body is reported, and the scan CONTINUES past it ──

#[test]
fn deserialize_failure_is_reported_and_scan_continues() {
    let p = tmp("deser");
    // Hand-build: a garbage-but-CRC-valid record (msgpack of an integer, which is not a Fact),
    // followed by a real fact. Proves the scan reports the bad payload and keeps going.
    let garbage = rmp_serde::to_vec(&42u32).unwrap();
    let good = rmp_serde::to_vec(&fact("k", 7)).unwrap();
    let mut file = frame(&garbage);
    file.extend_from_slice(&frame(&good));
    std::fs::write(&p, &file).unwrap();

    let w = WALWriter::new(&p).unwrap();
    let report = w.replay_reported().unwrap();
    assert_eq!(
        report.facts.len(),
        1,
        "the good record AFTER the bad one is still recovered"
    );
    assert_eq!(report.facts[0].key, "k");
    assert_eq!(
        report.corrupt.len(),
        1,
        "the undecodable record is reported"
    );
    assert_eq!(report.corrupt[0].kind, WalCorruptionKind::Deserialize);
    assert_eq!(
        report.corrupt[0].offset, 0,
        "corruption located at the first record"
    );

    // Mid-stream corruption → boot fails closed even though a later record decoded.
    assert!(w.replay().is_err());
}
