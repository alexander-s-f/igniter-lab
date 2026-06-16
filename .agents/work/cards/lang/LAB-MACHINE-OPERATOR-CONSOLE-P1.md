# Card: LAB-MACHINE-OPERATOR-CONSOLE-P1 — first operator-console surface (design)

**Lane:** readiness / product-ops / operator UX · **Skill:** idd-agent-protocol
**Status: CLOSED 2026-06-16.** Design/readiness artifact — **no code, no UI, no daemon.**

> **Deliverable:** [`lab-docs/lang/lab-machine-operator-console-p1-v0.md`](../../../../lab-docs/lang/lab-machine-operator-console-p1-v0.md)
> Designs the first operator surface over P20 orchestrator + P23 observability: what an operator
> sees and safely does around receipts, retry queue, dead letters, boot/tick/report, pools, routes.

## Goal

Design (not implement) the minimum operator console for igniter-machine after P25: read-only views,
safe host-loop actions, gated actions, the facts-vs-process boundary, a CLI/API-first surface, and a
daily checklist — all over the existing substrate.

## Authority boundary

- **Source of truth:** `igniter-machine/IMPLEMENTED_SURFACE.md`, P20 `orchestrator.rs`, P23
  `observability.rs`, P25 capstone.
- **Agent authority:** design/readiness only.
- **Closed (held):** no code, no UI, no live/staging, no new authority model, no automatic daemon.

## Verify-first evidence (2026-06-16)

Read the live modules, anchored the design on real signatures:
- `observability.rs` → `observe()` → `ObservabilitySnapshot{ EffectMetrics, DeadLetterInbox }`,
  `to_json()`; pure projection from `__receipts__`/`__retry_queue__`/`__dead_letter__`.
- `orchestrator.rs` → `EffectOrchestrator::{boot, tick, report}` → `OrchestratorStatus`; host-called,
  audited, **not** a daemon; compensation explicitly NOT loop-driven; boot has no executor param →
  cannot re-perform an effect.
- Redaction confirmed in `http.rs`/`sparkcrm.rs` — secrets never enter receipts (references only).

## Key design decisions

- **Facts are the console** — every view is a read-only projection; live process state is advisory.
- Read-only views (§1) vs safe host-loop actions `boot`/`tick`/note (§2) vs **gated** compensate/
  reissue/live/credentials (§3) cleanly separated.
- **CLI-first** surface (`opcon …`) before any frontend; same verbs → JSON API later (§5).
- SparkCRM effects: state/outcome/correlation/duplicate-context/retry-trail visible; **credential
  never** (§6–§7). Export re-asserts redaction + records the exporter.

## Acceptance (all met)

Read-only vs mutating separated · facts/projections = truth · redaction/secret notes included ·
CLI/API defined before UI · compensation/reissue/live gated · no frontend/code.

## Next route

Design only. If pursued: implement the read verbs first (pure `observe()`/`report()` wrappers),
then `boot`/`tick` triggers with audit, behind a host boundary (not the vendor ingress). Compensation
stays a separate confirmation-bearing path. Optional pairing with the live-gate packet.
