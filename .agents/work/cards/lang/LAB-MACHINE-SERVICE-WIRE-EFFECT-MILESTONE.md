# Card: LAB-MACHINE-SERVICE-WIRE-EFFECT-MILESTONE — wire-to-effect production contour proven in lab

**Status: MILESTONE / WAVE CREST — the coordination serving line is proven end-to-end, in lab,
to a real socket.** 2026-06-16. This is the moment igniter-machine stops being "an interesting
architecture" and looks like a server platform. Read this before pulling any single P-card.

> **One truth:** a real HTTP request, through an audited host boundary, deterministically selects
> a replica of an immutable content-addressed service image, activates it for a pure intent,
> performs **exactly one** declared effect with a receipt, and returns a real HTTP response — and
> the whole thing is reconstructable from facts. dev-time coordination built it; prod-time is
> dumb, agentless serving.

## The contour (proven, glass box)

```text
real HTTP POST (127.0.0.1)
  → ingress parser                       (P6 serve_once / P11 serve_once_effect)
  → passport (serving authority)         (P5/P6)
  → duplicate policy (business strategy) (P7 — idempotency=safety, duplicate=business)
  → ONE replica selected (deterministic) (P9 — never fanout)
  → capsule activation → pure intent     (P5 — content-addressed homogeneous image, P8)
  → ONE declared effect → receipt        (P10 + capability-IO; effect idem = key:attempt)
  → real HTTP response + audit links
```

## What is CLOSED (coordination serving line)

| card | what it added | tests |
|---|---|---|
| P2 | agent/pool registry + ACL + audit | 9 |
| P3 | messenger bus (facts + audit + ACL) | 9 |
| P4 | capsule transfer envelopes (two-phase) | 9 |
| P5 | ServiceRecipe + agentless serving (dev→prod handoff) | 7 |
| P6 | HTTP ingress front door (real loopback) | 9 |
| P7 | configurable duplicate policy (auction lever) | 8 |
| P8 | homogeneous pool fanout (server-arch hypothesis) | 8 |
| P9 | replica selection in the ingress hot path (single replica) | 7 |
| P10 | selected-replica × bridge effect (one request → one effect) | 6 |
| P11 | real loopback HTTP × handle_effect (wire-to-effect) | 5 |

**77 coordination tests; full machine suite 219 green** (incl. the neighbour's capability-IO
P1–P15 + service↔effect bridge).

> **Host shell (follow-on):** `LAB-MACHINE-SERVING-LOOP-P12` CLOSED — a host-owned bounded loop
> over `serve_once_effect` + `EffectOrchestrator::{boot,tick}` (loopback only, no daemon, fake
> executor). Shows the machine living as a process without inventing a background daemon. Proof:
> `lab-docs/lang/lab-machine-serving-loop-p12-v0.md`.

## The two convergent tracks

```text
capability-IO (P1–P15): receipts · idempotency · authority · clock · reconcile · retry · queue · HTTP · TLS · compensation · SparkCRM executor
coordination  (P2–P11): pools · ACL · messenger · transfer · recipe · ingress · duplicate-policy · fanout · replica · bridge · wire
```

They JOIN at `bridge_effect.rs` (neighbour) + `handle_effect` (this line): one served request →
one committed effect.

## Load-bearing invariants (do not regress)

- **idempotency = safety; duplicate policy = business** — dedup is NOT a canon default; the
  auction lever (same vendor event → distinct UPI/offer code per attempt) is explicit + audited.
- **effect idempotency key = `duplicate_key:attempt_index`** — the policy controls effect count
  (`dedup_strict` = one effect ever; `bounded_fresh(n)` = up to n distinct-keyed effects).
- **single replica on the hot path; fanout never performs an effect** — scaling compute never
  multiplies downstream effects.
- **two authorities** — vendor serving passport vs host effect passport.
- **homogeneous = content-addressed** — N replicas, one stored image, identical by construction.
- **contract body does no IO** — capsule yields a pure intent; the host performs the effect.

## The honest staging gate (do NOT cross without a human)

```text
local wire-proven contour (HERE)
  → SparkCRM executor over local TLS (neighbour P15)   ← swap the fake executor only
  → human-approved staging                             ← LIVE is gated, NOT a continuation
```

The whole contour is proven against fake / local executors. Binding the real SparkCRM domain
executor and pointing it at a live vendor is a **human-approved** step, mirroring the
capability-IO capstone checkpoint (`LAB-MACHINE-CAPABILITY-IO-CAPSTONE-P15-CHECKPOINT`). Do not
treat it as the next implementation card.

## Governance

Front door: `LAB-MACHINE-AGENT-COORDINATION-META-P1` (+ addendum). Live index:
`igniter-machine/IMPLEMENTED_SURFACE.md`. Boundary: lab-only, pre-v1 change-freedom; intended for
production as a SparkCRM companion kernel.
