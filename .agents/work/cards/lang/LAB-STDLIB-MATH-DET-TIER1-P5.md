# LAB-STDLIB-MATH-DET-TIER1-P5 — deterministic Tier-1 math surface

Status: CLOSED
Lane: standard / stdlib math
Type: implementation proof
Delegation code: OPUS-STDLIB-MATH-DET-TIER1-P5
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

Depends on:

- `LAB-STDLIB-MATH-TRANSCENDENTALS-P2` — fast platform f64 `sin/cos/sqrt/pi`.
- `LAB-STDLIB-MATH-DETERMINISM-READINESS-P3` — decision: two honest surfaces; fast `stdlib.Math.*` is not a
  cross-architecture determinism claim; deterministic math should be explicit and lock/provenance relevant.

P3 recommended a deterministic surface for replay/swarm/emergence. It also left one open grammar question:
can a 3-level spelling like `stdlib.Math.det.sin` be parsed/dispatched, or should v0 use a 2-level module such
as `stdlib.DetMath.sin` or flat names like `det_sin`?

## Goal

Implement the smallest deterministic Tier-1 surface that is compatible with the live grammar and dispatch path:

- deterministic `sin`
- deterministic `cos`
- deterministic `sqrt`

The exact public spelling must be chosen by verify-first against live parser/typechecker/VM behavior.

## Verify first

- `lab-docs/lang/lab-stdlib-math-determinism-readiness-p3-v0.md`
- `lang/igniter-stdlib/stdlib/math.ig`
- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs`
- `lang/igniter-vm/src/vm.rs`
- `lang/igniter-compiler/tests/stdlib_math_tests.rs`
- `lang/igniter-vm/tests/stdlib_math_tests.rs`
- Test whether the parser/typechecker can accept 3-level names (`stdlib.Math.det.sin`) before choosing the
  surface. If not, choose the least surprising 2-level or flat fallback and document why.

## Design constraints

- Do not change or weaken the fast P2 surface.
- Do not claim deterministic behavior for platform `sin/cos`.
- Do not introduce implicit numeric coercions.
- Do not introduce NaN/Inf as accepted deterministic outputs.
- Do not use external network or system libm at runtime. If adding a crate, it must be an explicit normal dep
  only where needed, with the dependency boundary documented.
- Deterministic output is part of stdlib semantics: if algorithm changes, it should be governed by
  `STDLIB_VERSION` / package lock provenance.

## Implementation options to compare live

1. Use a pure Rust deterministic libm crate for `sin/cos` and std `f64::sqrt` for `sqrt` with finite-domain guard.
2. Implement a bounded polynomial/CORDIC directly in VM/stdlib code for Tier-1.
3. Defer implementation if no acceptable deterministic dependency/algorithm is available offline.

Bias from P3: prefer a fixed pure Rust libm/MUSL-style algorithm for `sin/cos`; `sqrt` can use IEEE-correct
`f64::sqrt` with domain guard.

## Semantics to settle

- Surface spelling.
- Return shape: plain `Float` vs `Result[Float, MathError]` / runtime error. P3 strongly warns against silent
  NaN because JSON can collapse non-finite values.
- Negative `det.sqrt` behavior: should be a deterministic error, never NaN/null.
- Non-finite input behavior: deterministic error or explicit refusal.
- Error taxonomy if runtime errors are used.

## Acceptance

- [x] Surface spelling chosen and justified by live parser/typechecker behavior.
- [x] `det.sin/det.cos/det.sqrt` or chosen equivalents compile cleanly for `Float` inputs.
- [x] Wrong arity/type rejected deterministically.
- [x] Negative `det.sqrt` does not produce NaN/null silently.
- [x] Golden-vector VM tests prove repeatability within the stated tolerance or exact bit equality if claimed.
- [x] Fast P2 math tests still pass.
- [x] `igniter-compiler` relevant tests green.
- [x] `igniter-vm` relevant tests green; full VM failures, if any, isolated precisely.
- [x] `igniter-stdlib` tests/build green if touched.
- [x] Proof doc states exactly what determinism is and is not proven locally.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-21)

**Surface (live-grammar verdict):** **flat `det_sin/det_cos/det_sqrt`** — verify-first showed dotted
`det.sin(x)` is a **parse error (OOF-P0)** while flat `det_sin(x)` parses; flat is the honest v0 spelling.

**Implementation:** added normal dep **`libm = "0.2"`** (pure-Rust MUSL-port, no system libm/network — boundary
documented; embed-friendly). VM (`vm.rs`): `det_sin/det_cos`→`libm::sin/cos`, `det_sqrt`→`f64::sqrt`; guards
make non-finite input and `det_sqrt(<0)` deterministic **errors, never NaN/null**. Typecheck: `det_*` share
the P2 `(Float)->Float` arm (OOF-MATH1/2). `math.ig`: det decls + fast-surface relabelled "not a determinism
claim". Return = plain `Float` (determinism in the algorithm, safety by refusal). Proof doc:
`lab-docs/lang/lab-stdlib-math-det-tier1-p5-v0.md`.

**Governance fix during Codex harvest:** this is a real stdlib surface change, so `igniter-stdlib` version and
compiler mirror `STDLIB_VERSION` were bumped **`0.1.0` → `0.1.1`**. Package P6's mirror guard now passes, and
new locks will record the deterministic math surface instead of silently reusing the old stdlib provenance.

**Determinism proven LOCALLY:** golden-vector **exact bit equality** (`det_sin(0.5)=0x3fdeaee8744b05f0`,
`det_cos(0.5)=0x3fec1528065b7d50`, `det_sin(1.0)=0x3feaed548f090cee`, `det_sqrt(2.0)=0x3ff6a09e667f3bcd`),
independently cross-checked vs Python/system libm — all match; repeatability; finite-only. **NOT proven
locally:** actual cross-arch bit-identity (rests on pure-Rust libm + Rust-no-auto-FMA + golden lock; needs
qemu CI — next card). Golden vectors = the governance lock (libm change → test fails → STDLIB_VERSION bump).

**Live e2e:** `det_sin(0.5)`→0.479425538604203; Kuramoto order param on `det_*`→r=1.0 (synchronized). One-call
swap `sin`→`det_sin` makes emergence sims a fixed-algorithm/golden-vector swarm-portability candidate;
physical multi-arch identity remains pending until a hardware/swarm proof records it.

**Tests/green:** igniter-vm `stdlib_math_det_tests` **6**, `stdlib_math_tests` **5** (P2); igniter-compiler
`stdlib_math_tests` **5** (3 P2 + 1 P4 + 1 P5); igniter-compiler `package_workspace_tests` **46**
(`STDLIB_VERSION` mirror/provenance); igniter-stdlib **11**. One pre-existing unrelated VM failure (`vmg13`)
isolated (same as P2, git-stash-proven). `git diff --check` clean.

**Next:** `LAB-STDLIB-MATH-DET-CROSSARCH-CI-P6` (qemu aarch64/riscv64 golden-vector run → upgrade claim to
cross-arch-confirmed); then Tier-2 + full Kuramoto sweep on det surface.

## Required deliverable

- Proof doc: `lab-docs/lang/lab-stdlib-math-det-tier1-p5-v0.md`
- Closing report in this card.

## Closed scope

- No fixed-point integer math surface.
- No Decimal transcendentals.
- No `tan/exp/ln/pow` yet.
- No broad numeric tower.
- No simulation benchmark.
