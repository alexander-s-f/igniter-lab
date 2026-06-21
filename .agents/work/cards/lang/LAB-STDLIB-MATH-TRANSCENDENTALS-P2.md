# LAB-STDLIB-MATH-TRANSCENDENTALS-P2 — Tier-1 Float transcendentals

Status: CLOSED
Lane: standard / stdlib math
Type: implementation proof
Delegation code: OPUS-STDLIB-MATH-TRANSCENDENTALS-P2
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

`LAB-STDLIB-MATH-PRESSURE-KURAMOTO-P1` proved the emergence/Kuramoto workload hits a real stdlib wall:
`stdlib.Math` currently exposes only Decimal `add/sub/mul/div`, while the language/VM substrate already supports
`Float` arithmetic. Kuramoto needs at least `sin` and `sqrt`; practical scientific/visual work also needs `cos`
and `pi`.

This card implements the **fast f64 Tier-1** surface only. Deterministic cross-architecture math is deliberately
a separate readiness card (`LAB-STDLIB-MATH-DETERMINISM-READINESS-P3`).

## Goal

Add Tier-1 `stdlib.Math` Float operations:

- `sin(x: Float) -> Float`
- `cos(x: Float) -> Float`
- `sqrt(x: Float) -> Float`
- `pi() -> Float` or an equivalent zero-arg `pi` surface, based on the live parser/typechecker conventions

The functions must compile, typecheck, and execute through the real compiler/VM path.

## Verify first

Do not assume the declarative `.ig` stdlib file is enough. Read live wiring and follow the existing pattern:

- `lang/igniter-stdlib/stdlib/math.ig`
- `lang/igniter-stdlib/src/lib.rs` and current Decimal FFI/export shape
- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs`
- VM/evaluator builtins in `runtime/igniter-machine/src/`
- Existing regexp integration docs/tests if helpful:
  - `lab-docs/lang/lab-stdlib-regexp-p3-v0.md`
  - regexp typecheck / VM tests
- Existing Float operator behavior tests/fixtures.

## Questions to answer

1. What is the minimal wiring path for stdlib math today: declarative `.ig`, typechecker builtin, VM builtin, FFI,
   or some combination?
2. Should the surface be `stdlib.Math.sin(x)`-style, `math.sin(x)`, or current call syntax around imported defs?
3. How should `pi` be expressed in the current grammar: zero-arg function, constant-like function, or builtin call?
4. What exact error/edge semantics should v0 choose for non-finite results (`sqrt(-1.0)`, NaN/Inf JSON issues)?
5. Should Integer or Decimal inputs coerce to Float? Bias: **no implicit coercion** in P2.
6. Does this change `igniter-stdlib` normal dependency footprint? Bias: no new external deps.

## Required implementation

- Add the stdlib declarations needed for `sin/cos/sqrt/pi`.
- Add typechecking so valid calls infer `Float` and wrong arity/type is rejected with existing diagnostic style.
- Add VM/runtime evaluation using Rust `f64` intrinsics.
- Add compiler tests for valid and invalid calls.
- Add VM tests for known finite values.
- Add a tiny pressure fixture that replaces hand-rolled Taylor `sin` with `stdlib.Math.sin`.

## Numeric acceptance

Use tolerances, not exact bit equality, for the fast f64 path:

- `sin(0.0) ~= 0.0`
- `sin(pi()/2.0) ~= 1.0`
- `cos(0.0) ~= 1.0`
- `sqrt(4.0) ~= 2.0`
- `pi() ~= 3.141592653589793`

Document the tolerance used and why.

## Acceptance

- [x] Live wiring path documented in proof doc.
- [x] `sin/cos/sqrt/pi` valid Float calls compile cleanly.
- [x] Wrong arity/type is rejected deterministically.
- [x] VM/runtime executes finite known-value tests within a documented tolerance.
- [x] No implicit Integer/Decimal -> Float coercion added.
- [x] No deterministic `det.*` claim in this card.
- [x] Existing compiler/VM/stdlib tests green, or unrelated failures isolated precisely.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-21)

**Implementation:** `sin/cos/sqrt` `(Float)->Float` + `pi()` `()->Float`, **fast platform-`f64`**. Wired in
two hot places (no whitelist gate — `infer_stdlib_call`'s match IS the registry): typecheck arms in
`typechecker/stdlib_calls.rs` (resolve `Float`, `OOF-MATH1` arity / `OOF-MATH2` non-Float) + VM arms in
`igniter-vm/src/vm.rs` OP_CALL dispatch (`f64` intrinsics); plus declarative `def`s in `stdlib/math.ig`.
Surface = **bare** `sin(x)`/`pi()` (existing stdlib idiom); qualified `stdlib.math.*` also dispatches. Proof
doc: `lab-docs/lang/lab-stdlib-math-transcendentals-p2-v0.md`.

**Decisions (card Q1–Q6):** no inventory whitelist → match-arm is the registry; bare call surface; `pi()`
zero-arg fn; non-finite UNguarded on fast path (deferred to `det.*`, where VM's f64→JSON-null hazard matters);
**no implicit coercion** (Float-only); **no new crate dep** (std f64).

**Proof — green:** `igniter-vm/tests/stdlib_math_tests` **5** (known values within 1e-12, `pi()` zero-arg,
qualified dispatch, arity err, non-Float err); `igniter-compiler/tests/stdlib_math_tests` **3** (valid clean,
OOF-MATH1, OOF-MATH2); compiler suite green; live smoke compile+run (`sin(pi()/2.0)`) ok; `git diff --check`
clean. **One pre-existing unrelated VM failure** isolated precisely: `vmg13_local_loops_and_service_loops`
(`OP_GET_FIELD: expected Record, got Integer(<unix-ts>)`) **still fails after `git stash`-ing only my vm.rs**
→ not introduced by this card (transcendentals touch the call dispatch, not OP_GET_FIELD/temporal).

**Pressure loop closed:** the P1 hand-rolled Taylor `sin` (`igniter-home-lab/.../kuramoto/sin.ig`) is now
obsolete — `compute s : Float = sin(x)` compiles+runs natively. Kuramoto `sin`/`sqrt` unblocked (fast path).

**Next:** `LAB-STDLIB-MATH-DET-TIER1-P4` (deterministic `det.*` per P3 readiness) → then Tier-2 + clean Kuramoto sim.

## Required deliverable

- Proof doc: `lab-docs/lang/lab-stdlib-math-transcendentals-p2-v0.md`
- Closing report in this card.

## Closed scope

- No deterministic fixed-point/CORDIC/LUT implementation.
- No Decimal transcendentals.
- No numeric tower or implicit coercions.
- No broad scientific stdlib (`tan/pow/exp/ln`) yet.
- No app-level Kuramoto rewrite beyond a tiny pressure fixture.
