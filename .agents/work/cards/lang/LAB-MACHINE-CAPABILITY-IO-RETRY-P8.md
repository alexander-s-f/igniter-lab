# Card: LAB-MACHINE-CAPABILITY-IO-RETRY-P8 — bounded reconciliation-gated write retry

> **Front door:** [`LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1`](LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1.md) — read the milestone card first for the whole picture; P8 is the milestone's tail #2.

**Status: CLOSED 2026-06-15 — bounded reconcile-gated retry implemented + proven.** Route:
`LAB-MACHINE-CAPABILITY-IO-FOCUS-P1`. 7 machine tests
(`igniter-machine/tests/capability_io_retry_tests.rs`); full suite green
(`cargo test --no-default-features`: **83 passed total**). Design doc:
`lab-docs/lang/lab-machine-capability-io-retry-p8-v0.md`.

## Goal (met)

Retry a write safely: never retry an `unknown` blindly. Retry proceeds only when the prior
attempt is KNOWN not to have landed (executor `retryable`, or P7 reconcile says not-landed).
Fresh idempotency key per attempt → at most one commits.

## Implementation

- `capability.rs`: `EffectOutcome::retryable()`.
- `write.rs`: `WriteState::Retryable`; finalize split (Succeeded→committed, Denied→denied,
  Retryable→retryable, PermanentFailure→permanent_failure, Unknown→unknown); retryable is a
  terminal-per-key (replayed under the same key; scheduler uses fresh keys).
- `retry.rs`: `RetryPolicy { max_attempts }`, `run_write_with_retry(...) -> RetryOutcome
  { Committed{n} | Denied | PermanentFailure{n} | Unresolved{n} | Exhausted{n} }`. Each attempt
  = `base_key:a{n}` → `run_write_effect`; on unknown → `reconcile_unknown_write`, continue only
  on reconciled "did not land".

Executor contract: return `retryable`/`permanent_failure` ONLY when no-mutation is known; else
`unknown`.

## Decisions

- fresh key per attempt (genuine re-issue, not replay);
- unknown → reconcile → landed=Committed / not-landed=continue / still-unknown=Unresolved (bail);
- denial + hard permanent not retried;
- bound = attempt count only (no timer/backoff — later slice).

## Proof (7 tests)

`retries_transient_then_commits`, `exhausts_on_persistent_transient`,
`unknown_reconciled_not_landed_then_commits`, `unknown_but_landed_resolves_committed_without_retry`,
`unknown_unreconcilable_bails_unresolved`, `denial_is_not_retried`, `hard_permanent_is_not_retried`.
Uses a `ScriptedWriteExecutor` (programmed outcome sequence incl. write-then-unknown).

## Closed

Retry logic only (attempt-count bound). No timer/backoff/delay. No durable retry queue /
cross-restart scheduling. No compensation. No network. No language change. No contract-body IO.

## Next

- time-based backoff + durable retry queue; compensation (`aborted`); fact↔receipt correlation
  id (closes P7 same-value caveat); write-succeeded-but-receipt-failed window; HTTP/SparkCRM
  executor (both prerequisites — reconciliation + safe retry — now in place).
