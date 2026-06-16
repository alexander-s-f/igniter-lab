# lab-machine-capability-io-observability-p23-v0 — operator visibility as a fact projection

**Card:** `LAB-MACHINE-CAPABILITY-IO-OBSERVABILITY-P23` (production-hardening blocker #5, meta
`LAB-MACHINE-CAPABILITY-IO-PRODUCTION-HARDENING-P17`)
**Status:** CLOSED — operator visibility + dead-letter inbox, projected from facts. 6 machine
tests (`tests/capability_io_observability_tests.rs`); default suite green (259).
**Boundary held:** no metrics daemon, no Prometheus dependency, no side-log, no live network.

## What it is (and isn't)

Operator VISIBILITY, not a monitoring STACK. "Can we understand what's happening?" — before any
load test or live. Metrics are **aggregated FROM the existing facts** (receipts / retry queue /
dead-letters) by a pure read-only projection. The audit facts remain the single source of truth;
`observe()` never writes a counter side-log.

## Implementation

`observability.rs`:
- `observe(facts) -> ObservabilitySnapshot` — reads `all_facts`, takes the latest fact per key in
  each store, and aggregates:
  - `EffectMetrics` — effects by latest receipt state (committed / denied / unknown /
    permanent_failure / retryable / prepared / aborted), `compensation` (= aborted), retry-queue
    intents by state (pending / exhausted / done / blocked / abandoned), `dead_letters`, plus
    `secret_missing` / `auth_refusals` DERIVED from receipt details.
  - `DeadLetterInbox { total, by_reason, entries }` — stuck items grouped by reason; each entry
    carries `key`, `kind`, `reason`, and the `correlation` id JOINED from the matching receipt.
- `ObservabilitySnapshot::to_json()` — export as a plain JSON struct for a host / operator UI.

## Honest limit (a finding, not a gap to paper over)

`auth_refusals` and `secret_missing` are derived from receipt details, so they only count
**executor-reached** events (e.g. a missing-credential `permanent_failure` receipt). Refusals
BEFORE the executor (a bad passport, a missing secret on the direct path) write NO receipt by
design — denial-as-data is executor-reached only. To observe those, a deployment would have the
host emit an audit fact at the refusal point; that stays a documented host choice, not a hidden
side-log added here.

## Proof (6 tests)

| claim | test |
|---|---|
| metrics aggregate receipt states (committed/unknown/aborted/permanent + secret_missing) | `metrics_aggregate_receipt_states` |
| dead-letter inbox grouped by reason (+ total) | `dead_letter_inbox_grouped_by_reason` |
| a dead-letter is joined to the receipt's correlation id | `dead_letter_joins_correlation` |
| retry intent counts (pending/exhausted/done) | `retry_intent_counts` |
| snapshot exports as a JSON struct | `snapshot_exports_json` |
| projection is read-only + idempotent (writes no facts; deterministic) | `projection_is_readonly_and_idempotent` |

## Closed

No metrics daemon / Prometheus / side-log. Pure projection — `observe` writes nothing. Audit
facts remain the source of truth. No live network.

## Next (P17 order)

#6 **load test 2–5k rpm** — exercise the atomic gate (P18) + durable recovery (P19) +
orchestrator (P20) under the real target throughput; surface contention / latency via this
snapshot. Then (#7) human-gated live. After #6, all in-lab hardening blockers are closed.
