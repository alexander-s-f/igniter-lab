# lab-machine-capability-io-retry-queue-p9-v0 — durable, auditable retry over time

**Card:** `LAB-MACHINE-CAPABILITY-IO-RETRY-QUEUE-P9` (route:
`LAB-MACHINE-CAPABILITY-IO-FOCUS-P1` / milestone tail)
**Status:** CLOSED — durable retry intents + explicit drain implemented + proven. 8 machine
tests (`tests/capability_io_retry_queue_tests.rs`); full machine suite green
(`cargo test --no-default-features`: **91 passed total**).
**Boundary held:** no background worker (explicit `drain_due_retries`), no HTTP, no network.

## What P9 adds

P8 retried within a single call. Production traffic needs **retry over time**:

```text
attempt fails retryably / unknown-then-not-landed
-> enqueue a durable retry INTENT as a fact (with due_at = now + backoff)
-> later: drain_due_retries(now) drains DUE intents, runs the next attempt
-> same reconcile-gated rules as P8 (never retry an unknown blindly)
-> every transition (enqueue/reschedule/done/exhausted/abandoned/blocked) is an auditable fact
```

`drain_due_retries` is explicit (called by a host tick / cron / test) — P9 deliberately has no
background thread. The whole queue is durable TBackend state, so it survives restarts.

## Implementation

`igniter-machine/src/retry_queue.rs`:
- `RetryIntent { base_key, capability_id, operation, payload, required_scope, authority_digest,
  attempt, max_attempts, due_at, state }`; `IntentState ∈ {pending, done, exhausted, abandoned,
  blocked}`. Stored as facts in `__retry_queue__`, key = base idempotency key; the live state is
  the latest fact at that key.
- `backoff_due(now, attempt, base_delay)` = `now + base_delay * 2^attempt`.
- `enqueue_retry(...)` — writes a pending intent (attempt 0) with `due_at`.
- `drain_due_retries(registry, receipts, substrate, clock, passport, base_delay)` — for each
  PENDING intent that is DUE (`due_at <= clock.now()`) and whose `authority_digest` matches the
  drainer's passport, runs the next attempt via `run_write_effect` (fresh key `base:a{n}`) and
  transitions the intent. On `unknown` it reconciles (P7) before deciding.

Drain transitions: `Committed→done`, `Retryable→reschedule(attempt+1, new due_at)`,
`Unknown→reconcile→{committed→done | not-landed→reschedule | still-unknown→blocked}`,
`Denied/PermanentFailure→abandoned`, bound reached → `exhausted`.

## Decisions

- **Intent = fact; queue is durable + auditable.** Every transition appends a fact; the history
  at the key is the audit trail.
- **Explicit drain, no worker.** P9 is the queue + drain semantics; a real timer/cron tick that
  calls drain is host glue, out of scope.
- **Authority continuity.** The intent records `authority_digest`; only a drainer presenting a
  matching passport drains it (and `run_write_effect` re-verifies the passport).
- **Reconcile-gated, same as P8.** An `unknown` attempt is reconciled before any reschedule —
  never a blind retry. Fresh key per attempt → at most one commits.
- **The queue stores the payload** (unlike receipts, which keep only digests) — it must, to
  re-issue. Noted as a privacy consideration for a real substrate.

## Proof (8 tests, `tests/capability_io_retry_queue_tests.rs`)

| # | acceptance | test |
|---|---|---|
| 1 | retry intent fact created with `due_at` | `enqueue_creates_intent_fact_with_due_at` |
| 2 | drain before `due_at` does nothing | `drain_before_due_does_nothing` |
| 3 | drain at/after `due_at` runs the next attempt; commit → done | `drain_at_due_runs_and_commits` |
| 4 | unknown is reconciled before scheduling a retry → reschedule | `unknown_is_reconciled_then_rescheduled` |
| 4b | unknown + unreconcilable substrate → blocked (no reschedule) | `unknown_unreconcilable_is_blocked` |
| 5 | committed terminal cancels future drains (no-op) | `committed_terminal_is_not_redrained` |
| 6 | max attempts → exhausted terminal | `max_attempts_exhausts` |
| 7 | every scheduler operation is an auditable fact | `all_operations_are_auditable_facts` |

## Closed (held)

No background worker / thread (explicit drain only). No wall-clock timer (the host decides when
to call drain; backoff arithmetic uses the injected clock). No HTTP/network. No compensation
(`aborted` reserved). No language change. No contract-body IO.

## Next route (each its own bounded card; none started)

- a host tick that calls `drain_due_retries` on a real cadence (cron/loop) — host glue;
- compensation (`aborted`) — explicit host rollback after prepare;
- fact↔receipt correlation id — close the P7 same-value reconciliation caveat;
- write-succeeded-but-receipt-failed window — executor-side idempotency / two-way handshake;
- **HTTP / SparkCRM API executor** — now genuinely unblocked: receipts, idempotency, authority,
  clock, reconciliation, in-call retry, AND durable retry-over-time are all in place. This is the
  next real-substrate expansion (it brings TLS/DNS/status-mapping/timeouts/redaction/credentials).
