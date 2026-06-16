# Card: LAB-MACHINE-CAPABILITY-IO-OBSERVABILITY-P23 — operator visibility as a fact projection

> **Front door:** [`LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1`](LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1.md);
> meta focus [`…-PRODUCTION-HARDENING-P17`](LAB-MACHINE-CAPABILITY-IO-PRODUCTION-HARDENING-P17.md) (blocker #5).

**Status: CLOSED 2026-06-16 — operator visibility + dead-letter inbox, projected from facts.** 6
machine tests (`tests/capability_io_observability_tests.rs`); default suite green (259). Design
doc: `lab-docs/lang/lab-machine-capability-io-observability-p23-v0.md`.

## Goal (met)

Operator visibility (not a monitoring stack). Metrics aggregated FROM facts — pure read-only
projection, no side-log, no daemon, no Prometheus.

## Implementation

`observability.rs`: `observe(facts) -> ObservabilitySnapshot { metrics, dead_letters }`:
- `EffectMetrics` — effects by latest receipt state; compensation (=aborted); retry intents by
  state; dead_letters; secret_missing/auth_refusals derived from receipt details.
- `DeadLetterInbox { total, by_reason, entries[{key, kind, reason, correlation}] }` — grouped by
  reason; correlation joined from the matching receipt.
- `to_json()` export for an operator UI.

Honest limit: pre-executor refusals write no receipt (denial-as-data is executor-reached only),
so auth_refusals/secret_missing only count executor-reached events; observing pre-executor
refusals is a documented host choice (emit an audit fact), not a hidden side-log.

## Proof (6)

metrics aggregate receipt states (+ secret_missing); dead-letter inbox grouped by reason;
dead-letter joins correlation; retry intent counts; JSON export; projection read-only + idempotent.

## Closed

No metrics daemon / Prometheus / side-log. `observe` writes nothing. Facts remain the source of
truth. No live network.

## Next

#6 load test 2–5k rpm (exercise atomic gate + recovery + orchestrator under throughput; surface
via this snapshot) → after #6 all in-lab hardening closed → (#7 human-gated live).
