# Card: LAB-MACHINE-CAPABILITY-IO-WRITE-P6 — receipt-gated write substrate

> **Front door:** [`LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1`](LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1.md) — read the milestone card first for the whole P1–P6b picture; this is one slice of it.

**Status: P6a + P6b CLOSED 2026-06-15 — lifecycle (fake) + real local TBackend write both
proven.** Route: `LAB-MACHINE-CAPABILITY-IO-FOCUS-P1`, branch A. 9 (P6a) + 8 (P6b) machine
tests; full suite green (`cargo test --no-default-features`: **70 passed total**). Design docs:
`lab-docs/lang/lab-machine-capability-io-write-p6a-v0.md`, `…-write-p6b-v0.md`.

## P6b closure — real local TBackend write executor

`executors::TBackendWriteExecutor` (over on-disk `RocksDBBackend`) + `write::FactWrite` behind
the UNCHANGED P6a protocol (leaf change, like P3 for reads). Forced-identity decision honored:
`payload_digest` covers store+key+value+valid_time (`FactWrite::to_payload`). Outcome: write
ok→committed (fact read-back); backend error/injected failure→`unknown_external_state` (no
blind retry). 8 tests (`tests/capability_io_write_real_tests.rs`): success+read-back,
duplicate-same-payload (one backend write), duplicate-different-payload refused,
missing-authority no-write, injected-failure→unknown+no-retry, replay no-write,
contract-body-cannot-write, payload-digest-includes-identity.

**Milestone:** igniter-machine now has real read + write local capability IO with receipts,
idempotency, typed-passport authority, and a host clock. (Design doc has the full diagram.)

## The asymmetry P6 exists for

Read records what happened; **write must gate whether the mutation may happen.** P6a models
the write failure states (timeout-after-dispatch, receipt-vs-write ordering, duplicate-key-
different-payload, no-blind-retry) instead of "just writing."

## Two-phase receipt lifecycle (P6a)

`prepared` (gate, before executor) → `committed` | `denied` | `unknown_external_state`;
`aborted` reserved (host compensation, not driven in P6a). The terminal fact wins the read; a
dangling `prepared` reads back as unknown.

## Must-decide (answered in P6a)

1. lifecycle = prepared/committed/denied/unknown_external_state (+aborted reserved).
2. idempotency binds `capability_id + operation + authority_digest + payload_digest`.
3. duplicate same key + same payload → replay (executor not reached).
4. duplicate same key + different payload → refuse before executor, no write.
5. timeout after dispatch → unknown; **no blind retry** on re-call.
6. prepare-receipt failure → executor not called (the gate).
7. P6a target = fake write executor only.

## Implementation (P6a)

`igniter-machine/src/write.rs`: `WriteState`, `WriteRequest`, `WriteResult`, `payload_digest`,
`run_write_effect` (authority → duplicate/replay resolution → prepare gate → execute once →
finalize; reuses `verify_passport` + `ClockProvider`), `FakeWriteExecutor`
(Commit/Deny/Timeout).

## Proof

`commit_lifecycle_writes_two_phase_receipt`, `duplicate_same_payload_replays_no_second_write`,
`duplicate_different_payload_refused`, `executor_denial_is_denied_state_with_receipt`,
`timeout_is_unknown_and_not_blindly_retried`, `prepare_receipt_failure_blocks_executor`,
`authority_refused_writes_no_receipt`, `replay_with_different_authority_refused`,
`replay_mode_without_receipt_is_unknown`.

## Closed (P6a)

Fake executor only. No real substrate/DB/HTTP/queue. No retry scheduler. No compensation engine
(`aborted` reserved). No language change. No contract-body IO. No MCP hot path.

## Next (after P6b — each its own bounded card; none started)

- reconciliation of `unknown_external_state` (read-back / verify after an unknown write);
- compensation (`aborted`) for explicit host rollback after prepare;
- `retryable` + bounded retry (safe only with reconciliation);
- the write-succeeded-but-receipt-failed window (executor-side idempotency / two-way handshake);
- HTTP / SparkCRM API executor — only after retry + reconciliation are mature.
