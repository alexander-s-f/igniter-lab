# lab-machine-capability-io-durable-recovery-p19-v0 — durable receipts + crash recovery

**Card:** `LAB-MACHINE-CAPABILITY-IO-DURABLE-RECOVERY-P19` (production-hardening blocker #2, meta
`LAB-MACHINE-CAPABILITY-IO-PRODUCTION-HARDENING-P17`)
**Status:** CLOSED — durable receipts + a crash-recovery sweep. 7 machine tests
(`tests/capability_io_recovery_tests.rs`); default suite green (`cargo test --no-default-features`:
231).
**Boundary held:** RocksDB/tempdir only, no live network; recovery NEVER re-executes.

## The gap

P18 protected "two requests in parallel right now." P19 protects "the process died mid-effect."
A receipt whose latest state is `prepared` after a restart is **dangling** — a crash happened
between the prepare gate and the terminal receipt. Two crash windows both land here:

- crash AFTER prepare, BEFORE the executor → the effect did NOT happen;
- crash AFTER the executor succeeded, BEFORE the committed receipt → the effect DID happen, but
  the receipt still says `prepared`. This is the **"write-succeeded-but-receipt-failed"** hole —
  the next silent gap after concurrency, and the center of P19.

Both are resolved the same way: a dangling `prepared` is treated as an `unknown` and **reconciled**
(read the target back), never blind-retried.

## Fix

1. **Durability**: receipts / retry-queue / dedup live on a durable backend (RocksDB), so they
   survive the restart. A fresh `RocksDBBackend` on the same dir reloads the persisted facts.
2. **Recovery sweep** (`recovery.rs`):
   - `recover_dangling_writes(receipts, substrate, clock)` — scans the durable receipt store for
     latest-state `prepared`/`unknown` receipts and reconciles each by **reading the target back**
     (P7 value reconcile). It has **no executor** — it cannot re-execute by construction.
   - `recover_dangling_by_correlation(receipts, resolver, clock)` — the same sweep via
     `correlation_id` (P13) for HTTP/remote effects whose fate is learned from a status-by-request-id
     endpoint, not a local read-back.
   - `RecoveryReport { scanned, committed, permanent_failure, still_unknown }`.
   - `reconcile_unknown_write` / `reconcile_unknown_by_correlation` now accept a dangling
     `prepared` (not only `unknown`) as reconcilable — a one-line guard widening that makes the
     crash window reuse the existing P7/P13 machinery.

## Why recovery, not retry

The "write-succeeded-but-receipt-failed" window is exactly where a blind retry would double-execute
(the effect already landed). Recovery **reads the truth back** instead: landed → `committed`; not
landed → `permanent_failure` (safe to re-issue under a new key); undecidable → still `unknown`.

## Proof (7 tests)

| claim | test |
|---|---|
| a receipt survives a restart (RocksDB reload) | `durable_receipt_survives_restart` |
| **window #2**: effect landed, receipt stuck at prepared → recovered to `committed` | `dangling_prepared_recovers_committed_when_landed` |
| window #1: effect did not land → `permanent_failure` | `dangling_prepared_recovers_permanent_failure_when_not_landed` |
| recovery never mutates the substrate (no re-execute) | `recovery_never_reexecutes` |
| recovery by correlation id (landed→committed / not-found→permanent) | `recovery_by_correlation_resolves` |
| after recovery→committed, a re-issued same-key write replays (no re-exec) | `recovered_committed_then_replays_no_reexecute` |
| the retry queue survives a restart | `retry_queue_survives_restart` |

All on a real on-disk `RocksDBBackend`; restart = drop the backend, reopen a fresh one on the same
dir.

## Closed

RocksDB/tempdir only, no live network. Recovery has no executor (cannot re-execute). No durable
*scheduler* (the recovery sweep is explicit — the host calls it on boot; no background worker).
No language change.

## Next (P17 hardening order)

#3 host-driven orchestrator + tick (drive `unknown → reconcile → commit | re-issue (P9) |
compensate (P12)`, incl. running this recovery sweep on boot) → #4 real authority verification +
real SecretProvider → #5 observability + dead-letter → #6 load test → (#7 human-gated live).
