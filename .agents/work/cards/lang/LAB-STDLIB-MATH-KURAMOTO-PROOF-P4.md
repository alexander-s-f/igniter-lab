# LAB-STDLIB-MATH-KURAMOTO-PROOF-P4 — clean Kuramoto pressure proof using Tier-1 math

Status: CLOSED
Lane: standard / stdlib math + emergence pressure
Type: proof / downstream pressure
Delegation code: OPUS-STDLIB-MATH-KURAMOTO-PROOF-P4
Date: 2026-06-21
Skill: idd-agent-protocol

## Dependency

Do not start until `LAB-STDLIB-MATH-TRANSCENDENTALS-P2` is closed or at least has a working branch with
`sin/cos/sqrt/pi` available through the real compiler/VM path.

## Context

P1 proved Kuramoto can compile/run only by hand-rolling `sin` in pure `.ig`. P2 should remove that workaround by
adding Tier-1 math. P4 closes the loop: a minimal Kuramoto-style model should use `stdlib.Math.sin` and
`stdlib.Math.sqrt` directly, with no Taylor helper embedded in app code.

## Goal

Create a clean pressure proof that the emergence/Kuramoto workload is unblocked by Tier-1 math.

This is not a full emergence product app. It is a bounded compile/runtime proof using a tiny oscillator/order
parameter slice.

## Verify first

- P1 proof doc and any home-lab Kuramoto artifacts mentioned there.
- P2 implementation/proof doc and exact call syntax.
- Current compiler/VM runner behavior for output visibility (`trace` vs `run` if available).
- Existing collection/map/fold/range support if the fixture uses a collection slice.

## Required proof shape

Preferred minimal fixture:

- Uses all-Float values (`0.0`, `1.0`, `6.0`, etc.) to avoid Integer*Float coercion pressure.
- Calls `stdlib.Math.sin` for phase coupling.
- Calls `stdlib.Math.sqrt` for a tiny order-parameter or magnitude calculation.
- Optionally calls `stdlib.Math.cos`/`pi` if they naturally fit; do not force complexity.
- Compiles through the real compiler.
- Executes through the real VM/machine path and proves result status/output shape.

## Questions to answer

1. What is the smallest meaningful Kuramoto slice: one-step phase update, pair coupling, or tiny order parameter?
2. Can the proof assert a numeric output, or does current runner only expose `result_status`?
3. Does P2's math surface remove all hand-rolled Taylor code from the fixture?
4. Does collection processing introduce unrelated pressure? If yes, keep P4 scalar and defer collection model.
5. What remains blocked after P4: output runner, plotting, simulation loop, deterministic math, or performance?

## Acceptance

- [x] Fixture contains no hand-rolled Taylor/trig approximation.
- [x] Fixture uses P2 `stdlib.Math` Tier-1 calls through the real language surface.
- [x] Compiler path green.
- [x] VM/machine execution path green.
- [x] Numeric assertion included if output runner supports it; otherwise result status plus exact limitation
      documented.
- [x] Remaining emergence blockers listed precisely.
- [x] Existing P2 tests still green.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-21)

**Built:** a scalar, all-Float, collection-free N=2 Kuramoto slice —
`igniter-home-lab/apps/emergence/kuramoto/kuramoto_proof.ig`: `KuramotoR2` (order parameter
`r=(1/2)·sqrt((cos ti+cos tj)²+(sin ti+sin tj)²)`) + `KuramotoStep2` (one Euler coupling step
`ti'=ti+dt·(ω+(K/N)·sin(tj−ti))`). Native `sin/cos/sqrt`, **no Taylor**, no collections. Proof doc:
`lab-docs/lang/lab-stdlib-math-kuramoto-proof-p4-v0.md`.

**Numeric proof (live, real compiler + VM `run`):** `KuramotoR2`(0,0)=**1.0**, (π/2,π/2)=**1.0**,
(0,π)=**6.12e-17≈0**; `KuramotoStep2`(0,π/2)=**0.15**. r→{1 synchronized, 0 anti-phase} = a tiny emergence
signature on native math.

**Q-answers:** (Q1) smallest slice = tiny order parameter + pair-coupling step; (Q2) **`igniter-vm run
--json` DOES surface the numeric `result`** (corrects the P2 trace-only note); (Q3) Taylor fully removed;
(Q4) kept scalar — collections are the next pressure; (Q5) remaining = N-body collections, sim loop, det.*,
seeded ω, plotting.

**Tests/green:** igniter-compiler `stdlib_math_tests` **4** (3 P2 + 1 P4 compile-lock incl. no-Taylor
assertion); igniter-vm `stdlib_math_tests` **5** (P2, unaffected); `git diff --check` clean. Compile-lock +
P2 VM numeric tests together lock the order parameter.

**Pressure loop CLOSED** (P1→P2→P4): hand-rolled Taylor obsolete; Kuramoto runs on Tier-1 with asserted
numerics. **Next:** N-body collection pressure (`…NBODY-PRESSURE-P5`) and/or deterministic `det.*` before the
Stage-3 swarm.

## Required deliverable

- Proof doc: `lab-docs/lang/lab-stdlib-math-kuramoto-proof-p4-v0.md`
- Closing report in this card.

## Closed scope

- No full simulation UI or charting.
- No deterministic `det.*` implementation.
- No performance benchmark beyond a tiny smoke observation.
- No Integer/Float coercion changes.
