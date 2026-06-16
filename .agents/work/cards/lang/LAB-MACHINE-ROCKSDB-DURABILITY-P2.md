# Card: LAB-MACHINE-ROCKSDB-DURABILITY-P2 — storage durability audit + bounded proof

**Lane:** readiness / proof / storage-hardening · **Skill:** idd-agent-protocol
**Status: CLOSED 2026-06-16.** Audit + one bounded proof — **no broad storage rewrite, no live.**

> **Deliverable:** [`lab-docs/lang/lab-machine-rocksdb-durability-p2-v0.md`](../../../../lab-docs/lang/lab-machine-rocksdb-durability-p2-v0.md)
> **Proof:** `igniter-machine/tests/storage_durability_proof_tests.rs` (3 tests, green).
> Validates what "receipt committed on disk" actually means and maps the remaining crash windows.

## Goal

Verify-first audit of the durability assumptions behind the production-shaped topology: the exact
fact/receipt write path, flush/fsync semantics, crash windows, what P19 covers, backup consistency,
the invariants for a committed receipt across restart, and a bounded non-invasive proof.

## Authority boundary

- **Source of truth:** live `backend.rs` / `wal.rs` / `machine.rs` / `write.rs` / `capability.rs` /
  `recovery.rs` / `Cargo.toml`; P19 recovery tests; deployment-topology P1.
- **Agent authority:** audit/readiness + bounded proof only.
- **Closed (held):** no live/staging, no SparkCRM, no deployment changes, no distributed lock/CAS,
  no broad storage rewrite, no power-loss durability claim.

## Two load-bearing findings (verified)

1. **"RocksDBBackend" is NOT RocksDB.** No `rocksdb`/`sled`/`redb` crate (`Cargo.toml`). It is a
   pure-Rust `.mpk` file store doing **non-atomic, non-fsync'd** read-modify-write via `std::fs::write`.
2. **The receipt spine bypasses the WAL.** The good append-only+CRC WAL (`wal.rs`) is wired only
   into `IgniterMachine::write_fact` (kernel facts). `run_write_effect`/`run_effect` write receipts
   directly to the bare `Arc<dyn TBackend>` (`write.rs:207`, `capability.rs:315`) — the most
   safety-critical store gets the weakest durability path.

## Result

- **Proven:** graceful-restart durability is real (`durable_across_graceful_reopen`).
- **Open risk (proven):** torn `.mpk` → silent total loss on reopen
  (`truncated_mpk_silently_dropped_on_reopen`); writes after corruption don't recover history
  (`write_after_corruption_drops_prior_history`). No fsync anywhere → page-cache-only durability.
- **Residual hole:** after-executor-before-terminal-receipt **with a torn prepare receipt** →
  effect landed, no receipt to reconcile → P19 blind → possible double-execute. (§4 of the doc.)
- **Recommended (not implemented):** stop silent `unwrap_or_default` loss; atomic temp+rename;
  `sync_all` fsync; put receipts on the WAL/real engine; rename or adopt a real RocksDB/redb. Each is
  a future gated hardening card.

## Verify / test

`cargo test --no-default-features --test storage_durability_proof_tests` → **3 passed**.
Full default suite remains green (now 259).

## Acceptance (all met)

Verify-first on live code · separates proven restart durability from unproven fsync/power-loss ·
each crash window → mitigation or open risk · recommends code changes without implementing a rewrite ·
added test is bounded + no network/live · P25 live-gate boundary intact.

## Next route

A storage-hardening card could take recommendation #1 (stop silent loss) + #2 (atomic write) as the
smallest high-leverage slice, behind the live gate. Naming correction (`RocksDBBackend` →
`MpkFileBackend`) is anti-drift and cheap. Flagged separately as a spawn task. Pointer added to
deployment-topology P1 + IMPLEMENTED_SURFACE backends row.
