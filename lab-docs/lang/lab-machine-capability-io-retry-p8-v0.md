# lab-machine-capability-io-retry-p8-v0 — bounded, reconciliation-gated write retry

**Card:** `LAB-MACHINE-CAPABILITY-IO-RETRY-P8` (route:
`LAB-MACHINE-CAPABILITY-IO-FOCUS-P1` / milestone tail #2)
**Status:** CLOSED — bounded reconcile-gated retry implemented + proven. 7 machine tests
(`tests/capability_io_retry_tests.rs`); full machine suite green
(`cargo test --no-default-features`: **83 passed total**).
**Boundary held:** retry *logic* only (bounded by attempt count). No timer / backoff / durable
cross-restart scheduling; no network; no compensation.

## The safety invariant

```text
NEVER retry an `unknown_external_state` blindly.
A retry proceeds only when the prior attempt is KNOWN not to have landed:
  - the executor returned `retryable` (transient, guaranteed no mutation), OR
  - reconciliation (P7) read the target back and resolved it to "did not land".
Each attempt uses a fresh idempotency key → at most ONE attempt can ever commit.
```

This is why P8 had to come after P7: without reconciliation, an `unknown` outcome would have
no safe path forward and a bounded retry would risk a double-write.

## The transient/permanent split (introduced here)

P6a/P6b conservatively folded every non-success into `unknown_external_state`. P8 lets the
executor's failure taxonomy carry through, with a strict contract:

| executor outcome | write state | retry meaning |
|---|---|---|
| `Succeeded` | `committed` | done |
| `Denied` | `denied` | boundary/refusal — NOT retried |
| `Retryable` | `retryable` | transient, **guaranteed no mutation** — safe to retry |
| `PermanentFailure` | `permanent_failure` | hard reject — retry won't help, stop |
| `UnknownExternalState` | `unknown_external_state` | status unknown — reconcile before any retry |

**Executor contract:** return `retryable`/`permanent_failure` ONLY when no-mutation is known;
when in doubt, return `unknown`. (`retryable` is its own terminal-per-key receipt; the scheduler
moves to a new key.)

## Implementation

- `capability.rs`: `EffectOutcome::retryable()`.
- `write.rs`: `WriteState::Retryable`; finalize mapping split (above); retryable joins the
  terminal-replay arm (a reused key replays it; the scheduler uses fresh keys).
- `retry.rs`: `RetryPolicy { max_attempts }`, `run_write_with_retry(registry, receipts,
  substrate, clock, passport, scope, base, policy) -> RetryOutcome`. Each attempt derives
  `base_key:a{n}` and calls `run_write_effect`; on `unknown` it calls
  `reconcile_unknown_write` and only continues on a reconciled "did not land".

`RetryOutcome ∈ { Committed{attempts} | Denied | PermanentFailure{attempts} |
Unresolved{attempts} | Exhausted{attempts} }`.

## Decisions

- **Fresh key per attempt** (`base:a1`, `base:a2`, …) — retries are genuine re-issues, not
  replays; combined with "only retry when prior didn't land", at most one commits.
- **Unknown → reconcile, then branch**: landed → `Committed`; not-landed → continue; still
  unknown → `Unresolved` (bail — proceeding could double-write).
- **Denied / hard PermanentFailure are not retried** (refusal / won't-help).
- **Bounded by attempt count.** No wall-clock backoff — there is no timer in P8; time-based
  scheduling and durable retry queues are a later slice.

## Proof (7 tests, `tests/capability_io_retry_tests.rs`)

| claim | test |
|---|---|
| transient retries then commits (attempts=3) | `retries_transient_then_commits` |
| persistent transient exhausts the bound | `exhausts_on_persistent_transient` |
| unknown → reconcile not-landed → retry → commit (one version) | `unknown_reconciled_not_landed_then_commits` |
| unknown but landed → reconcile resolves committed, no retry, one version | `unknown_but_landed_resolves_committed_without_retry` |
| unknown + unreconcilable substrate → bail `Unresolved`, no retry | `unknown_unreconcilable_bails_unresolved` |
| boundary denial not retried | `denial_is_not_retried` |
| hard permanent not retried | `hard_permanent_is_not_retried` |

Uses a `ScriptedWriteExecutor` returning a programmed outcome sequence (incl. a
write-then-unknown step that mutates but reports unknown — the ack-lost case).

## Closed (held)

Retry logic only (attempt-count bound). No timer / backoff / delay. No durable retry queue or
cross-restart scheduling. No compensation (`aborted` reserved). No network. No language change.
No contract-body IO.

## Next route (each its own bounded card; none started)

- time-based backoff + durable retry queue (the "scheduler over time" beyond the safe logic);
- compensation (`aborted`) — explicit host rollback after prepare;
- fact↔receipt correlation id — close the P7 same-value reconciliation caveat (would also make
  reconcile-after-retry exact);
- write-succeeded-but-receipt-failed window — executor-side idempotency / two-way handshake;
- HTTP / SparkCRM API executor — both prerequisites (reconciliation + safe retry) now in place;
  this is the next *real-substrate* expansion when chosen.
