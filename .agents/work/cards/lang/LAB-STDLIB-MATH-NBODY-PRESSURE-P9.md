# LAB-STDLIB-MATH-NBODY-PRESSURE-P9 — collection-based simulation pressure after Tier-1

Status: CLOSED
Lane: standard / stdlib math + app pressure
Type: proof / pressure
Delegation code: OPUS-STDLIB-MATH-NBODY-PRESSURE-P9
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

P4 closed a scalar N=2 Kuramoto proof using Tier-1 math. Its proof doc left the next real emergence blocker:
N-body/all-to-all coupling over a collection of oscillators, e.g. `Σ_j sin(theta_j - theta_i)`.

This may pressure math, collection comprehensions, record-field access inside lambdas/folds, loops, and
performance. We should characterize it before broadening math further.

## Goal

Build a bounded pressure proof for collection-based numeric simulation using the current language surface. The
point is to discover the next blocker cleanly, not to ship a full simulator.

## Verify first

- P4 Kuramoto proof doc.
- Existing collection/map/fold/comprehension tests.
- Current record-field access behavior inside lambdas/folds/comprehensions.
- Current loop status if a multi-step simulation is attempted.
- Current math surface after P2/P5 if present.

## Preferred proof shape

Try a minimal N=3 or N=4 scalar calculation:

- `type Oscillator { theta : Float, omega : Float }`
- compute one oscillator's coupling sum over `Collection[Oscillator]` using `sin(other.theta - theta)`
- avoid multi-step loops initially;
- all literals Float where needed;
- assert compile path, and VM execution if the VM can execute the chosen collection form.

If the language cannot express the clean form yet, stop and report the exact blocker with a tiny failing fixture.

## Questions to answer

1. Can record-field access inside collection lambdas/comprehensions typecheck and run?
2. Can `sum/map/fold` over Float values compose with `sin` today?
3. Is the main blocker math, collections, record inference, loops, or VM execution coverage?
4. Does the proof need `abs/min/max/clamp/mod` from Tier-2, or is Tier-1 enough?
5. What is the smallest next card after this pressure proof?

## Acceptance

- [x] A minimal N-body/Kuramoto collection fixture is attempted against the real compiler.
- [x] If it compiles, VM execution is attempted and result/output limitation documented.
- [x] If it fails, exact diagnostic / unsupported VM error is captured.
- [x] Blocker is classified: math vs collection vs record vs loop vs VM.
- [x] No broad language changes in this card.
- [x] Proof doc written with next-card recommendation.
- [x] `git diff --check` clean if files are added.

---

## Closing Report (2026-06-21)

**Attempted** the clean N-body coupling `map(others, other -> sin(other.theta - theta_i))` + `sum` over
`Collection[Oscillator]` (`igniter-home-lab/apps/emergence/kuramoto/nbody_coupling.ig`). It **COMPILES clean**
(parse/typecheck/status ok) — records w/ Float fields, `Collection[T]`, `map` lambda with record-field access,
outer-input capture, and `sum` all infer. **Runtime FAILS:** `VM evaluation failed: Operator sin expects
exactly 2 operands; got 1`. Proof doc: `lab-docs/lang/lab-stdlib-math-nbody-pressure-p9-v0.md`.

**Blocker (precise):** a stdlib **math call inside a HOF lambda body** is evaluated by `eval_ast` (the
tree-walker for lambda/HOF bodies), which lacks the P2/P5 math dispatch — those arms live ONLY in the bytecode
`OP_CALL` path (`vm.rs` ~2060). In `eval_ast` `sin` falls to the **binary-operator** handler (~5274) → "expects
2 operands". This is the **eval_ast↔bytecode parity gap** flagged in P2.

**Isolation control** (`nbody_control.ig`): the SAME lambda minus the math call —
`map(others, other -> other.theta - theta_i)` + `sum` — **runs: result 4.71238898038469** (=0+π/2+π). So
record-field access, closure capture, Float arithmetic, `map`, `sum` ALL execute in eval_ast; the **only**
failure is the math call. Airtight classification.

**Classification:** **VM execution coverage (eval_ast parity)** — NOT math (functions exist), NOT collections
(`map`/`sum`/`fold` work — `sim_framework`), NOT records (field+capture work), NOT loops (single-step), NOT
typecheck (compiles). **No Tier-2 needed** — Tier-1 `sin` surfaces it.

**No language change made** (pressure card). **Next:** `LAB-STDLIB-MATH-EVAL-AST-PARITY-P10` — dispatch P2/P5
math (`sin/cos/sqrt/pi`+`det_*`) in the eval_ast HOF/lambda path (mirror the OP_CALL arms); acceptance =
`CouplingSum` returns ≈1.0. `git diff --check` clean (only home-lab fixtures added).

## Required deliverable

- Proof doc: `lab-docs/lang/lab-stdlib-math-nbody-pressure-p9-v0.md`
- Closing report in this card.

## Closed scope

- No production implementation unless the proof is a tiny fixture/test only.
- No full simulator, charting, or UI.
- No deterministic math implementation.
- No performance benchmark beyond a tiny observation.
