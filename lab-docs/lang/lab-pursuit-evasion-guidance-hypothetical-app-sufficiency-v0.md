# Lab Report: Pursuit/Evasion Guidance — Hypothetical-App Language Sufficiency Probe

**Track:** lab-pursuit-evasion-guidance-hypothetical-app-sufficiency-v0 (out-of-track research)
**Card:** LAB-PURSUIT-P1
**Category:** lang
**Date:** 2026-06-10
**Route:** LAB PROOF / HYPOTHETICAL APPLICATION / LANGUAGE SUFFICIENCY / NO REAL I/O
**Status:** CLOSED — 45/45 PASS; language sufficiency mapped; embed verdict CONDITIONAL

---

## Why this app

Goal: build a hypothetical, genuinely hard application to test the language and gauge its
sufficiency for a future embed. Chosen domain: **one quadcopter intercepts another** — the classic
control-theory benchmark (Kalman 1960 estimation + Isaacs 1965 pursuit-evasion differential games),
covering (a) trajectory estimation + interception, (b) trajectory + evasion, (c) a future Igniter
simulator. The domain is also Igniter's *native habitat*: the Covenant's own examples are
`drone.sensor.reading`, `PositionEstimate { uncertainty_m }`, `DispatchReceipt`.

This is a **language pressure proof**, not a weapon and not a flight controller. No real sensors,
actuators, radios, network, or storage — pure contracts; the physical world lives in the proof
harness. The avionics (Kalman predict/update, ZEM guidance, evasion, epistemic routing) execute in
the lab Rust VM.

---

## What was built

| Artifact | Path |
|----------|------|
| Fixture (8 types/contracts) | `igniter-view-engine/fixtures/pursuit_guidance/pursuit_guidance.ig` |
| Proof runner (45 checks, incl. closed-loop sim) | `igniter-view-engine/proofs/verify_pursuit_guidance_p1.rb` |
| This report | `lab-docs/lang/lab-pursuit-evasion-guidance-hypothetical-app-sufficiency-v0.md` |
| Card | `.agents/work/cards/lang/LAB-PURSUIT-P1.md` |

Contracts: `KalmanPredict`, `KalmanUpdate` (per-axis 2-state constant-velocity filter with explicit
covariance), `TrackStepRouter` (epistemic observation → update/coast/hold), `ZemGuidance`
(sqrt-free proportional navigation), `EvasionGuidance` (bang-bang ZEM-growth), `EngageGuard`
(epistemic honesty gate), `ObservationInspector` (metadata map-chain). Three layers: Ruby TC
(arithmetic-acceptance) + Rust VM (execution, numerics) + Ruby harness (closed-loop world).

---

## Headline finding — the arithmetic boundary is the gating constraint

The single most important sufficiency result, proved as checks (HYP-MATHGAP):

- **`Float` arithmetic is rejected by BOTH typecheckers** — the arithmetic operators are
  Integer-typed; `x * v` on `Float` yields `OOF-TY0 "expected Integer, got Float*Float"`.
- **`Decimal` arithmetic diverges** — the Rust compiler accepts `Decimal+Decimal`/`Decimal*Decimal`;
  the **Ruby TypeChecker rejects** it (same operator-support divergence family as the `==`/`||`
  finding in LAB-EPISTEMIC-OUTCOME-P4 / STAB-P4). Decimal is therefore not dual-toolchain-safe today.
- **The VM stdlib has no `sqrt`/`sin`/`cos`/`atan`** (only add/sub/mul/div/eq/cmp/concat + map/fold/
  filter/reduce).

**Consequence — the design was forced, and it forced a *good* answer:** everything is **integer
fixed-point** (position mm, velocity mm/s, time ms, gains ×1000). This is exactly the
representation a real embedded guidance loop wants — deterministic, FPU-free, replayable. The
algorithms were chosen to be **arithmetic-only by construction**: a constant-velocity Kalman filter
(no matrix inverse — per-axis scalar Riccati) and **sqrt-free ZEM proportional navigation**
(`t_go = r²/(−r·v)`, never `|r|`). Float/Decimal/trig would have needed stdlib work; integer did not.

---

## What the language proved sufficient for (45/45)

**Estimation (HYP-KF, 8 checks).** The integer Kalman filter runs in the VM and its output is
**exactly equal** (bit-for-bit integer equality) to an independent Ruby reference — including the
negative-residual case once the reference matched the VM's **truncation-toward-zero** division
(an important embedded-determinism detail; Ruby's default floor division would *disagree*).
Measurement updates shrink covariance; coasting (sensor lost ⇒ predict-only) grows covariance
monotonically; a 10-step filter converges to within budget; identical input → identical output
(replay-grade).

**Interception (HYP-ZEM, 6 checks).** Sqrt-free PN: perfect collision course ⇒ ZEM 0 ⇒ zero
command at exact `t_go`; offset course ⇒ exact hand-verified corrective accel; commands clamp to
±a_max; `t_go` floors at 1 ms (no point-blank division blow-up). Diverging geometry returns
`kind: "cannot_intercept"` — an **honest terminal**, never a fabricated command, and deliberately
**not** spelled `failed`/`system_error` (PROP-047 namespace discipline).

**Evasion (HYP-EVADE).** Bang-bang push along the ZEM sign (grows the pursuer's predicted miss);
zero command on a dead axis.

**Closed-loop simulation (HYP-SIM, 6 checks) — the simulator-host pattern.** The harness owns
physics (truth integration, deterministic LCG sensor noise); the VM flies the pursuit. Results:
- **Sim A (non-evading):** intercepted at tick 61 (6.1 s), min miss **1.70 m** from an initial
  **111.8 m** range; KF tracked the moving truth to **0.62 m** under ±0.3 m noise.
- **Sim B (evading):** **not intercepted** in 20 s; min miss **62.7 m** — evasion is demonstrably
  effective.
- **Zero VM faults** across all closed-loop calls; **deterministic replay** — same seed reruns to
  the identical trajectory outcome (the latent-replay property from LAB-FRONTIER-EXPEDITION made
  concrete: a guidance run is reproducible bit-for-bit).

*Guidance note:* PN nulls line-of-sight rotation; it does **not** create closing velocity, so the
interceptor begins post-boost with a closing velocity (the standard PN engagement). This is a
property of PN, not a language limit.

**Epistemic honesty (HYP-EPIST + HYP-ENGAGE, 10 checks) — where Igniter earns its keep.** This is
the differentiator a black-box guidance library cannot match:
- `TrackObservation` is a typed envelope requiring `uncertainty_mm` + `evidence_kind` (Covenant
  P11/P13 shape). A lost sensor routes to **coast**, never to a fabricated measurement — the
  unknown-state honesty of the epistemic-outcome arc, applied to a filter.
- `EngageGuard` refuses to guide when track uncertainty exceeds budget (**escalate_human**), and —
  crucially — **model-kind track evidence without human approval routes to `escalate_human`**
  (No-Upward-Coercion, the same VM-executed mechanism proved in LAB-EPISTEMIC-OUTCOME-P4). An
  AI-derived track cannot silently authorize an intercept.

---

## Embed sufficiency verdict: CONDITIONAL — strong fit, two real gaps

**Sufficient today** for an integer fixed-point guidance/estimation embed *as pure decision/                estimation logic*: deterministic, replayable, epistemically honest, dual-toolchain for integer math,
and the contracts compile to a VM that already runs them fault-free in a closed loop.

**Gaps that gate a real embed (none are dead-ends):**

| Gap | Severity for embed | Note |
|-----|--------------------|------|
| No `Float`; `Decimal` Ruby/Rust-divergent | medium | Integer fixed-point is viable and arguably *preferable* for embedded; but a real-number track needs the Decimal divergence resolved (STAB-P4 family) or a blessed fixed-point stdlib |
| No `sqrt`/trig in VM stdlib | medium | Forced sqrt-free algorithms here; full nav (true range, bearings, rotations) needs an integer/CORDIC math stdlib — a clean, bounded PROP target |
| No real I/O (sensors/actuators/timers) | high (for *deployment*) | by design out of scope; an embed needs an effect/capability surface for sensor-in / actuator-out — composes with the existing capability + ESCAPE machinery, not yet exercised for hard-real-time |
| Ruby/Rust operator-support divergence | medium | branching/comparison contracts are Rust-VM-only (Ruby TC blocks `==`/`<`); flagged, same STAB-P4 theme |
| Hard-real-time scheduling / WCET | high (for *flight*) | the VM is not characterized for bounded-latency execution; LAB-CONCURRENCY substrate exists but real-time guarantees are unproven |

**Strategic read:** the language is *unusually* well-matched to the **honest-autonomy** layer of
such a system (estimation + decision + epistemic gating + deterministic replay) and weak on the
**numerical-stdlib + real-time-I/O** layer. That is the right place to be weak for a *decision/
estimation embed*: the hard part (provable honesty about uncertain tracks and AI-derived evidence)
is the part Igniter does natively; the missing parts (sqrt, real I/O) are conventional,
bounded engineering, not language-philosophy problems.

---

## How this composes with the existing arcs

- **Epistemic outcome (P1..P4):** `sensor_lost`/`stale` → coast is the unknown-state honesty applied
  to estimation; `EngageGuard`'s `escalate_human` over model evidence is the *same* No-Upward-
  Coercion mechanism, VM-executed.
- **Decision honesty (FRONTIER-DECISION):** `cannot_intercept`/`escalate_human` are exactly the
  honest-terminal and escalation kinds from the DecisionReceipt surface; a natural P2 follow-on is a
  `DecisionReceipt` recording *why* an intercept was chosen/refused (rejected geometries, constraint
  applications like a_max/keep-out zones, authority chain).
- **Deterministic replay (frontier latent property):** HYP-SIM-06 makes it concrete — a seeded
  guidance run replays bit-identically; the simulator can therefore be an *audit* instrument, not
  just a toy.
- **Future simulator (the user's (c)):** the harness here IS the v0 simulator host pattern — world
  in the harness, avionics in the VM. A Gap-H `SimulationReceipt` (`mode: :synthetic`,
  `honesty_statement`) would let synthetic-world runs be type-distinct from real-sensor runs — the
  honest way to build the simulator the user wants (FRONTIER-SYNTHETIC territory).

---

## Recommended next routes (none authorized)

1. **LAB-MATH-STDLIB-READINESS** — survey the cost of an integer/fixed-point math stdlib
   (`isqrt`, CORDIC `sin/cos/atan2`) + resolve the Ruby/Rust Decimal divergence. This is the
   keystone unblocking *any* numerical embed (not just guidance).
2. **LAB-PURSUIT-P2 — DecisionReceipt over the engagement** — record the intercept decision as a
   `DecisionReceipt` (rejected geometries, a_max/keep-out constraints, model-vs-human authority),
   composing the guidance proof with the FRONTIER-DECISION surface.
3. **FRONTIER-SYNTHETIC-P1 (Gap-H)** — `SimulationReceipt` so the future simulator's synthetic
   worlds cannot type as real-sensor reality — the honest foundation for (c).
4. **Embed-readiness probe** — characterize VM execution latency/determinism for a fixed-rate
   control loop (real-time sufficiency is currently unproven).

---

## Gap Packet

```
report:   lab-pursuit-evasion-guidance-hypothetical-app-sufficiency / v0
status:   CLOSED — 45/45 PASS
authority: lang / lab_only
date:     2026-06-10
domain:   quadcopter pursuit-evasion (Kalman estimation + ZEM PN interception + evasion)

arithmetic_boundary:
  Float:   REJECTED by both typecheckers (operators Integer-typed)
  Decimal: Rust TC accepts, Ruby TC rejects (DIVERGENCE; STAB-P4 family)
  VM math: no sqrt/sin/cos/atan; integer add/sub/mul/div/cmp only
  chosen:  integer fixed-point (mm / mm/s / ms / milli-gain) — embedded-grade, FPU-free
  algos:   CV scalar Kalman (no matrix inverse); sqrt-free ZEM PN (t_go=r²/−r·v)

proved_sufficient:
  estimation: VM Kalman ≡ integer reference EXACTLY (incl. negative residual, truncation-toward-zero);
              coast grows covariance; converges; replay-grade determinism
  interception: sqrt-free PN exact; clamp to ±amax; cannot_intercept = honest terminal (not failed)
  evasion:    bang-bang ZEM-growth effective
  closed_loop: sim A intercept @6.1s miss 1.70m (from 111.8m), est_err 0.62m@±0.3m noise;
               sim B (evading) NOT intercepted, miss 62.7m; zero VM faults; deterministic replay
  epistemic:  sensor_lost→coast (unknown≠failure); model-evidence→escalate_human (No-Upward-Coercion)

embed_verdict: CONDITIONAL — strong on honest-autonomy (estimate/decide/gate/replay);
               weak on numerical stdlib (no sqrt/trig; Decimal divergence) + real I/O + WCET
gaps:     math-stdlib | Decimal divergence | real sensor/actuator I/O surface | hard-real-time/WCET

next:     LAB-MATH-STDLIB-READINESS (keystone) | LAB-PURSUIT-P2 (DecisionReceipt over engagement) |
          FRONTIER-SYNTHETIC-P1 (SimulationReceipt for the simulator) | embed real-time probe
real_world_targeting_claim: NONE — textbook guidance benchmark as language pressure
canon_changed: NO   implementation_authorized: NO   real_io: NONE
```

---

## Authority

lab-only — no canon claim, no stable surface, no framework compat. Language sufficiency probe via a
hypothetical application: no code/canon/Covenant/VM/compiler changes; no PROP authored; no real
sensors, actuators, radios, network, storage, or any I/O (pure contracts + Ruby harness world);
time is an explicit input (no ambient `now()`). Integer fixed-point only; Float/Decimal/trig gaps
documented, not resolved; Ruby/Rust operator divergence flagged (STAB-P4), not resolved. **No
real-world targeting or weapons claim** — this is a textbook estimation/guidance benchmark used as
language pressure. Ch12/proposed surfaces phrased as proposed. Lab behavior not accepted as canon.
This report informs future gate decisions; it does not make them.
