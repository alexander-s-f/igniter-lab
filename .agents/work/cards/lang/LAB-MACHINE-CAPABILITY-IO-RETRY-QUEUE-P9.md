# Card: LAB-MACHINE-CAPABILITY-IO-RETRY-QUEUE-P9 — durable, auditable retry over time

> **Front door:** [`LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1`](LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1.md) — read the milestone card first for the whole picture; P9 is a milestone tail item.

**Status: CLOSED 2026-06-15 — durable retry intents + explicit drain proven.** Route:
`LAB-MACHINE-CAPABILITY-IO-FOCUS-P1`. 8 machine tests
(`igniter-machine/tests/capability_io_retry_queue_tests.rs`); full suite green
(`cargo test --no-default-features`: **91 passed total**). Design doc:
`lab-docs/lang/lab-machine-capability-io-retry-queue-p9-v0.md`.

## Goal (met)

Retry over time, not just within one call: durable retry intents as facts + an explicit
`drain_due_retries(now)` under the same reconcile-gated rules. No background worker, no HTTP.

## Implementation

`retry_queue.rs`: `RetryIntent` (+`IntentState` pending/done/exhausted/abandoned/blocked) stored
as facts in `__retry_queue__` (key = base idempotency key, latest fact = live state);
`backoff_due(now, attempt, base_delay) = now + base_delay*2^attempt`; `enqueue_retry(...)`;
`drain_due_retries(registry, receipts, substrate, clock, passport, base_delay)`.

Drain (per DUE pending intent matching the drainer's authority_digest): run `run_write_effect`
with fresh key `base:a{n}` → Committed=done / Retryable=reschedule / Unknown→reconcile
(committed=done | not-landed=reschedule | still-unknown=blocked) / Denied|Permanent=abandoned;
bound reached → exhausted. Every transition is an auditable fact.

## Acceptance (all proven, 8 tests)

1. enqueue → intent fact with `due_at` — `enqueue_creates_intent_fact_with_due_at`.
2. drain before due → nothing — `drain_before_due_does_nothing`.
3. drain at due → runs + commit→done — `drain_at_due_runs_and_commits`.
4. unknown reconciled before reschedule — `unknown_is_reconciled_then_rescheduled`;
   unreconcilable → blocked — `unknown_unreconcilable_is_blocked`.
5. committed terminal not re-drained — `committed_terminal_is_not_redrained`.
6. max attempts → exhausted — `max_attempts_exhausts`.
7. all operations auditable facts — `all_operations_are_auditable_facts`.

## Closed

No background worker (explicit drain). No wall-clock timer. No HTTP/network. No compensation.
No language change. No contract-body IO.

## Next

- host tick calling `drain_due_retries` on a cadence (cron/loop glue); compensation (`aborted`);
  fact↔receipt correlation id; write-succeeded-but-receipt-failed window; **HTTP/SparkCRM
  executor** — now genuinely unblocked (receipts + idempotency + authority + clock +
  reconciliation + in-call retry + durable retry-over-time all in place).
