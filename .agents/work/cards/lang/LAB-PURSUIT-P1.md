# Card: LAB-PURSUIT-P1
**Category:** lang
**Track:** lab-pursuit-evasion-guidance-hypothetical-app-sufficiency-v0 (out-of-track research)
**Status:** CLOSED — PROVED
**Gate result:** 45/45 PASS
**Date closed:** 2026-06-10
**Route:** LAB PROOF / HYPOTHETICAL APPLICATION / LANGUAGE SUFFICIENCY / NO REAL I/O

---

## Goal

Build a hard hypothetical application to probe language sufficiency for a future embed: one
quadcopter intercepts another — Kalman estimation + ZEM proportional-navigation interception +
evasion, with a future Igniter simulator in view. Pure contracts; no real I/O.

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Fixture (8 types/contracts) | `igniter-view-engine/fixtures/pursuit_guidance/pursuit_guidance.ig` | ✅ DONE |
| Proof runner (45 checks + closed-loop sim) | `igniter-view-engine/proofs/verify_pursuit_guidance_p1.rb` | ✅ DONE |
| Report | `lab-docs/lang/lab-pursuit-evasion-guidance-hypothetical-app-sufficiency-v0.md` | ✅ DONE |
| This card | `.agents/work/cards/lang/LAB-PURSUIT-P1.md` | ✅ DONE |
| Portfolio update | `.agents/portfolio-index.md` | ✅ DONE |

---

## Headline Finding — arithmetic boundary forced (a good) design

- `Float` arithmetic REJECTED by BOTH typecheckers (operators Integer-typed).
- `Decimal` arithmetic DIVERGES: Rust TC accepts, Ruby TC rejects (STAB-P4 operator-divergence family).
- VM stdlib has NO sqrt/sin/cos/atan.
- ⇒ **integer fixed-point** (mm / mm/s / ms / milli-gain) — embedded-grade, FPU-free, deterministic.
  Algorithms chosen arithmetic-only: scalar constant-velocity Kalman (no matrix inverse), **sqrt-free
  ZEM PN** (`t_go = r²/(−r·v)`). Integer division truncates toward zero — reference impl matched it.

## Proof Sections (45/45)

```
HYP-COMPILE (4)  SIR 7 contracts; Ruby TC ACCEPTS integer KF; routers blocked by ==/< divergence; no variants
HYP-MATHGAP (4)  Float rejected (both); Decimal Rust-accepts/Ruby-rejects; no sqrt/trig in VM
HYP-KF      (8)  VM Kalman ≡ integer reference EXACTLY (incl. neg residual truncation); coast grows P; converges; deterministic
HYP-ZEM     (6)  sqrt-free PN exact (collision→0, offset hand-verified); clamp ±amax; cannot_intercept honest terminal (≠ failed); tgo floor
HYP-EVADE   (2)  bang-bang ZEM-growth; dead-axis zero
HYP-EPIST   (5)  measured→update, sensor_lost/stale→coast, garbage→hold; uncertainty_mm+evidence_kind required (P11/P13)
HYP-ENGAGE  (5)  cannot_intercept first; blur→escalate_human; model-evidence+no-approval→escalate_human (No-Upward-Coercion); model+human→guide
HYP-SIM     (6)  sim A intercept @6.1s miss 1.70m (from 111.8m) est_err 0.62m; sim B (evading) NOT intercepted miss 62.7m; zero VM faults; deterministic replay
HYP-CLOSED  (5)  no Float literals; no real I/O; no now(); lab-only
```

## Embed Verdict — CONDITIONAL

Strong on the **honest-autonomy** layer (estimate / decide / epistemic-gate / deterministic replay) —
the part Igniter does natively. Weak on the **numerical-stdlib + real-I/O + WCET** layer — conventional
bounded engineering, not language-philosophy gaps.

Gaps: no Float / Decimal-divergent; no sqrt/trig; no real sensor/actuator I/O surface; hard-real-time
unproven; Ruby/Rust operator divergence (branching contracts Rust-VM-only).

## Composition

`sensor_lost→coast` = unknown-state honesty (P1..P4) applied to a filter; `escalate_human` over
model evidence = the SAME No-Upward-Coercion VM mechanism (P4); `cannot_intercept`/`escalate_human`
= DecisionReceipt honest-terminal/escalation kinds (FRONTIER-DECISION); HYP-SIM-06 = the frontier
deterministic-replay property made concrete; the harness = v0 simulator-host pattern (→ Gap-H
SimulationReceipt for synthetic worlds).

## Next Routes (none authorized)

1. **LAB-MATH-STDLIB-READINESS** (keystone — isqrt/CORDIC + resolve Decimal divergence)
2. **LAB-PURSUIT-P2** — DecisionReceipt over the engagement (rejected geometries, a_max/keep-out, authority)
3. **FRONTIER-SYNTHETIC-P1** — SimulationReceipt for the future simulator
4. Embed real-time/WCET characterization probe

## Gap Packet

```
proof:  lab-pursuit-evasion-guidance-hypothetical-app-sufficiency / v0
status: CLOSED — 45/45 PASS
arithmetic: Float rejected(both) | Decimal Rust-yes/Ruby-no | no sqrt/trig ⇒ integer fixed-point
proved: VM Kalman ≡ ref EXACTLY; sqrt-free ZEM PN exact; sim A intercept 6.1s/1.70m, sim B evades 62.7m;
        sensor_lost→coast; model→escalate_human; zero VM faults; deterministic replay
embed:  CONDITIONAL — strong honest-autonomy; weak numerical-stdlib/real-I/O/WCET
next:   LAB-MATH-STDLIB-READINESS | LAB-PURSUIT-P2 | FRONTIER-SYNTHETIC-P1 | real-time probe
targeting_claim: NONE (textbook benchmark)   canon_changed: NO   real_io: NONE
```

---

## Authority

lab-only — language sufficiency probe via hypothetical app. No code/canon/Covenant/VM/compiler
changes; no PROP; no real sensors/actuators/radios/network/storage/IO (pure contracts + harness
world); explicit time inputs. Integer fixed-point only; Float/Decimal/trig gaps documented;
Ruby/Rust operator divergence flagged (STAB-P4). **No real-world targeting/weapons claim** —
textbook estimation/guidance benchmark as language pressure. Lab behavior not accepted as canon.
Informs future gate decisions; does not make them.
