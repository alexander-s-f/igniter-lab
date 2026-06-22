# LAB-STDLIB-MATH-PRESSURE-KURAMOTO-P1 — stdlib.Math pressure from the emergence workload

Status: CLOSED
Lane: standard / lab pressure-finding
Type: pressure / readiness (evidence, design-only)
Delegation code: OPUS-STDLIB-MATH-PRESSURE-KURAMOTO-P1
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

The new emergence research line (private `igniter-home-lab`,
`LAB-IGNITER-EMERGENCE-RESEARCH-CHARTER-P1`) opened Stage 1 with the Kuramoto synchronization model. As
predicted, the workload presses on `stdlib.Math`. This card captures that pressure against the live
toolchain — evidence + a prioritized recommendation, **no language change**.

## Finding (verify-first)

- `lang/igniter-stdlib/stdlib/math.ig` is, in full, **four** functions: `add/sub/mul/div` on fixed-point
  `Decimal`. No `sin/cos/tan/sqrt/pow/exp/ln/pi/abs/floor/ceil/mod`. The VM has no native trig/sqrt either.
- The substrate DOES have: `Float` (`f64`) with operator `+ − × ÷` and comparisons in the VM, and
  `map/fold/sum/range`. (Integer×Float mixing is deliberately deferred → Float expressions stay all-Float.)
- Kuramoto needs `sin` (coupling) and `sqrt` (order parameter) at minimum → **hard wall today.**

## Proof the gap is *only* transcendentals (live run)

Hand-rolled `sin` (bounded Taylor, all-Float) in `igniter-home-lab/apps/emergence/kuramoto/sin.ig`:
- `igniter_compiler compile sin.ig --out sin.igapp` → `status: ok` (all stages).
- `igniter-vm trace sin.igapp --entry SinApprox --inputs '{"x":0.5}'` → `result_status: ok` (42 instr).
- Numerically sound (IEEE f64): Taylor(0.5)=0.4794255 vs sin(0.5)=0.4794255.

So Kuramoto is expressible/runnable **if** transcendentals are hand-rolled — the argument for adding them to
`stdlib.Math`. Adjacent minor finding: `igniter-vm trace` surfaces execution, not the return value (a small
runner gap; a `run`/`eval` that prints the output would help).

## Recommendation (design-only; full packet in proof doc)

- **Tier 1 (unblocks Kuramoto):** `sin`, `cos`, `sqrt`, `pi`.
- **Tier 2:** `tan`, `pow`, `exp`, `ln`, `abs`, `floor`/`ceil`/`round`, `mod`.
- **Determinism fork (load-bearing):** provide BOTH a default `f64` `stdlib.Math.sin` (fast, not
  cross-arch-deterministic) and a deterministic `stdlib.Math.det.sin` (fixed-point/LUT/CORDIC, designed for
  bit-identical replay across architectures; physical swarm identity still requires proof). The emergence line
  AND the embedded-swarm line (`LAB-IGNITER-EMBEDDED-VM-SWARM-READINESS-P1`) both depend on this choice —
  decide it once.

## Acceptance

- [x] Verify-first established the exact `stdlib.Math` surface (4 Decimal fns; no transcendentals).
- [x] Proven (live compile+run) that transcendentals are the sole blocker for the workload.
- [x] Prioritized recommendation (Tier 1/2) + the f64-vs-deterministic fork documented.
- [x] No language/stdlib code changed; Float-only path; Integer×Float coercion stays deferred.
- [x] Proof doc written; workload + hand-rolled `sin` cross-referenced to the private research line.

## Proof doc

`lab-docs/lang/lab-stdlib-math-pressure-kuramoto-p1-v0.md`.

## Next card

`LAB-STDLIB-MATH-TRANSCENDENTALS-P2` — implement Tier-1 (`sin/cos/sqrt/pi`) with the determinism fork
(A `f64` default + B `det.*` fixed-point), conformance tests vs known values, and a cross-arch determinism
check for `det.*`. Unblocks the clean Kuramoto implementation.
