# Card: LAB-MACHINE-CAPABILITY-IO-WRITE-P6 — receipt-gated write substrate

**Status: P6a CLOSED 2026-06-15 — readiness/design + lifecycle proven on a fake write
executor. P6b (real local TBackend write) = NEXT.** Route:
`LAB-MACHINE-CAPABILITY-IO-FOCUS-P1`, branch A. 9 machine tests
(`igniter-machine/tests/capability_io_write_tests.rs`); full suite green
(`cargo test --no-default-features`: 9 + 5 + 9 + 5 + 13 + 9 + 12 = 62). Design doc:
`lab-docs/lang/lab-machine-capability-io-write-p6a-v0.md`.

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

## Next — P6b

`LAB-MACHINE-CAPABILITY-IO-WRITE-P6b` — local TBackend write executor behind this exact
protocol (no HTTP/queue, no retry scheduler). Protocol unchanged; a real write
`CapabilityExecutor` replaces the fake (the P3-shape leaf change). Then: reconciliation of
`unknown_external_state`, compensation (`aborted`), `retryable` + bounded retry, the
write-succeeded-but-receipt-failed window.
