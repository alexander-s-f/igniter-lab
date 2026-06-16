# Card: LAB-MACHINE-CAPABILITY-IO-ORCHESTRATOR-P20 — host-driven effect orchestrator

> **Front door:** [`LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1`](LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1.md);
> meta focus [`…-PRODUCTION-HARDENING-P17`](LAB-MACHINE-CAPABILITY-IO-PRODUCTION-HARDENING-P17.md) (blocker #3).

**Status: CLOSED 2026-06-16 — explicit host-driven control loop.** 6 machine tests
(`tests/capability_io_orchestrator_tests.rs`); default suite green (237). Design doc:
`lab-docs/lang/lab-machine-capability-io-orchestrator-p20-v0.md`.

## Goal (met)

Tie the existing reliability primitives (P19 recovery, P9 retry queue, P7/P13 reconcile) into an
EXPLICIT host-called loop — not a daemon, not an infinite loop.

`orchestrator.rs::EffectOrchestrator { receipts, substrate, registry, clock, passport, base_delay }`:
- `boot()` → P19 recovery sweep; dead-letter receipts still `prepared`/`unknown` after; idempotent.
- `tick()` → drain DUE retry intents (P9); dead-letter `exhausted`/`blocked`.
- `report()` → status snapshot (receipt states + distinct dead-lettered keys).

Every boot/tick writes an audit fact (`__orchestrator_audit__`); stuck items get dead-letter facts
(`__dead_letter__`) — no silent skip.

## Scope limits

No background daemon / infinite loop (host owns cadence). **Compensation NOT auto-driven** (P12
stays explicit — a committed effect is never auto-undone). Enqueue stays upstream (tick only
drains). No live network.

## Proof (6)

boot recovers dangling + audited; boot idempotent; unresolvable→dead-letter; tick drains due
intent (effect performed) + audited; exhausted→dead-letter; report reflects states.

## Next

#4 real auth verification (signed passport) + real SecretProvider → #5 observability + dead-letter
routing → #6 load test → (#7 human-gated live).
