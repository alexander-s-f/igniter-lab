# lab-machine-capability-io-orchestrator-p20-v0 — host-driven effect orchestrator

**Card:** `LAB-MACHINE-CAPABILITY-IO-ORCHESTRATOR-P20` (production-hardening blocker #3, meta
`LAB-MACHINE-CAPABILITY-IO-PRODUCTION-HARDENING-P17`)
**Status:** CLOSED — explicit host-driven control loop. 6 machine tests
(`tests/capability_io_orchestrator_tests.rs`); default suite green (237).
**Boundary held:** no background daemon, no infinite loop, no live network, compensation NOT
auto-driven.

## What it does

The reliability pieces existed (P7/P13 reconcile, P9 retry queue, P12 compensation, P19 recovery)
but had to be driven by hand. P20 ties them into an EXPLICIT, host-called control loop — the host
owns the cadence:

```text
boot()   -> P19 recovery sweep (reconcile dangling prepared/unknown); dead-letter what stays
            unresolved. Idempotent across restarts.
tick()   -> drain DUE retry intents (P9); dead-letter exhausted/blocked intents.
report() -> a status snapshot (receipt states + distinct dead-lettered keys).
```

`EffectOrchestrator { receipts, substrate, registry, clock, passport, base_delay }` (`orchestrator.rs`).

## Deliberate scope limits (per Meta-Architect)

- **Not a daemon / not an infinite loop.** `tick` does one pass; the host decides when to call it.
- **Compensation stays EXPLICIT.** Reversing a committed effect (P12) is a host decision, never
  driven from the loop — a committed effect is never auto-undone.
- **No silent skip.** Anything stuck — a receipt still `prepared`/`unknown` after recovery, or a
  retry intent `exhausted`/`blocked` — gets a **dead-letter fact** (`__dead_letter__`). Every
  boot/tick also writes an **audit fact** (`__orchestrator_audit__`).
- Enqueueing retry intents stays upstream (the host enqueues on a `retryable` outcome); `tick`
  only drains what is due.

## Proof (6 tests)

| claim | test |
|---|---|
| boot recovers a dangling prepared → committed; the boot is audited | `boot_recovers_dangling_and_audits` |
| boot is idempotent (2nd boot recovers nothing) | `boot_is_idempotent` |
| an unresolvable dangling (substrate down) → dead-letter, not silently skipped | `boot_dead_letters_unresolvable` |
| tick drains a due retry intent (effect performed); tick is audited | `tick_drains_due_retry_intent` |
| exhausted retries → dead-letter | `tick_dead_letters_exhausted_retries` |
| report reflects receipt states (prepared before boot → committed after) | `report_reflects_state` |

## Closed

No background worker / infinite loop. No automatic compensation. No live network. Enqueue is the
host's call. The loop only composes existing primitives — no new effect logic.

## Next (P17 hardening order)

#4 real authority verification (signed passport / token; `evidence_digest` opaque today) + real
`SecretProvider` (vault/env) → #5 observability + richer dead-letter routing → #6 load test 2–5k
rpm → (#7 human-gated live). After P20 the runtime not only handles individual effects correctly
but can operationally LIVE through unknown / retry / crash.
