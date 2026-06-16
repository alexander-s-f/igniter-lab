# Card: LAB-MACHINE-CAPABILITY-IO-DURABLE-RECOVERY-P19 — durable receipts + crash recovery

> **Front door:** [`LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1`](LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1.md);
> meta focus [`…-PRODUCTION-HARDENING-P17`](LAB-MACHINE-CAPABILITY-IO-PRODUCTION-HARDENING-P17.md) (blocker #2).

**Status: CLOSED 2026-06-16 — durability + crash recovery.** 7 machine tests
(`tests/capability_io_recovery_tests.rs`); default suite green (231). Design doc:
`lab-docs/lang/lab-machine-capability-io-durable-recovery-p19-v0.md`.

## Gap

P18 protected "parallel right now"; P19 protects "the process died mid-effect". A `prepared`
receipt after restart is DANGLING. Center = **write-succeeded-but-receipt-failed**: the effect
landed but the receipt is stuck at `prepared`. Resolve by RECONCILE (read-back), never blind retry.

## Fix

`recovery.rs`: `recover_dangling_writes(receipts, substrate, clock)` (P7 value read-back) +
`recover_dangling_by_correlation(receipts, resolver, clock)` (P13) — scan durable receipts for
latest-state `prepared`/`unknown` and reconcile each → `RecoveryReport{scanned, committed,
permanent_failure, still_unknown}`. **No executor → cannot re-execute.** Durability: receipts/
queue/dedup on RocksDB survive restart (fresh backend on same dir reloads). One-line guard widened
in `reconcile_unknown_write`/`…_by_correlation` to accept dangling `prepared`.

## Proof (7 tests, RocksDB)

receipt survives restart; window #2 (landed→committed); window #1 (not-landed→permanent_failure);
recovery never mutates substrate; recovery by correlation (committed/permanent); recovered-committed
then replays (no re-exec); retry queue survives restart. Restart = drop backend, reopen same dir.

## Closed

RocksDB/tempdir only, no live network. Recovery has no executor. No background worker (sweep is
explicit, host calls on boot). No language change.

## Next

#3 host-driven orchestrator + tick (drive unknown→reconcile→commit|re-issue|compensate; run this
sweep on boot) → #4 real auth/secrets → #5 observability+dead-letter → #6 load test → (#7 human-gated live).
