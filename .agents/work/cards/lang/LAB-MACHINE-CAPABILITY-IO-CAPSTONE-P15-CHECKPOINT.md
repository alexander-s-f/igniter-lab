# Card: LAB-MACHINE-CAPABILITY-IO-CAPSTONE-P15-CHECKPOINT — wave stop + live gate

> **Front door:** the routing/index view is [`LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1`](LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1.md) (the full P1–P15 table + tail). THIS card is the wave-stop checkpoint: it declares the implementation wave COMPLETE and names the gate before live external network.

**Status: CHECKPOINT — capability-IO implementation wave P1–P15 COMPLETE and STOPPED here.**
2026-06-16. Default suite green (`cargo test --no-default-features`: 171) + TLS suite green
(`--features tls`: 186). This is a coordination artifact, not an implementation card.

## One truth

P1–P15 are **one coherent, composable capability-IO substrate**. The capstone (P15 SparkCRM
domain executor) proved the decisive property:

> A real domain executor plugged into the entire stack — receipts, idempotency, authority,
> clock, retry queue, reconciliation, compensation, real TLS — with **NO new primitives**.
> One `SparkCrmExecutor` implements `CapabilityExecutor` (forward) + `CorrelationResolver`
> (lookup) + `CompensatableExecutor` (cancel). The boundary design composes.

## Proof status — explicit

- **COMPLETE**: local / fake / staged proofs. Every layer proven on in-process fakes, a real
  on-disk RocksDB substrate, a real loopback HTTP server, and a real **local self-signed TLS**
  server (rustls, offline-cached deps behind the opt-in `tls` feature).
- **NOT done, NOT authorized**: any **live external network**. No production endpoint, no real
  credential, no public internet, no SparkCRM staging/prod has been touched — by design. The
  whole stack is exercised against local fakes only.

## What is CLOSED (P1–P15)

P1 executor+receipt · P2 declared-effect host entrypoint · P3 real read substrate · P4 host
clock · P5 typed passport authority · P6 receipt-gated write (a+b real) · P7 reconcile-by-value
· P8 bounded in-call retry · P9 durable retry queue · P10 HTTP policy · P11 real loopback HTTP ·
P12 compensation/`aborted` · P13 reconcile-by-correlation · P14 external HTTP policy · P14-impl
real TLS transport · P15 SparkCRM domain executor (capstone). Per-slice detail + the test table:
the milestone front door.

## STOP / live gate (do NOT just continue)

`P16 live / staging / prod smoke` is an **operational + security boundary**, NOT a continuation
of this engineering wave. It introduces, all at once: a real external endpoint, a real (vaulted)
product credential, real DNS/TLS to a third party, network flakiness, and rate/cost exposure. It
**requires explicit human authorization** and a credential the host operator provisions. An agent
must NOT open it as "the next step."

## Next gates (the non-live branches are open; live is gated)

1. **`LAB-MACHINE-EFFECT-ORCHESTRATOR-P16`** — host-driven reconcile-then-compensate loop over
   receipts/facts; explicit manual drain/tick; NO live external endpoint. (Reliability of
   effects. Fully in-lab.)
2. **Coordination-bridge integration** — the coordination track's serving line is COMPLETE
   (`coordination`/`ingress.rs`: vendor webhook → passport → production pool → capsule activation
   → HTTP response, real 127.0.0.1 round-trip). A natural integration: a served capsule's declared
   effect flows through THIS capability-IO substrate. (See `[[project-agent-coordination-substrate]]`.)
3. **SparkCRM additional actions** (update / lookup) on the same P15 shape — still local fake.
4. **`P16-live` (human-gated only)** — allowlisted staging/prod HTTPS smoke; requires the gate
   above. Optional, flaky; the durable proof remains the local TLS capstone.

## Anti-drift rules for agents

- This is the EFFECT/IO front-line. Read the milestone front door before pulling any single slice
  (P8/P12/P14/…) out of context.
- Do NOT route production IO through MCP (control/debug plane only).
- Do NOT add IO / clock / authority to the language or contract bodies — all host-side.
- Do NOT open a live external endpoint without an explicit human gate + vaulted credential.
- Do NOT blindly retry an `unknown` — reconcile (value P7 or correlation P13) first.
- Do NOT treat the domain executor as a new primitive — it is composition of the existing stack.

## Governance

Portfolio checkpoint: `igniter-gov/portfolio/governance/2026-06-16-lab-machine-capability-io-capstone-p15-v0.md`.
Live index: `igniter-machine/IMPLEMENTED_SURFACE.md`. Routing: the milestone front door.
