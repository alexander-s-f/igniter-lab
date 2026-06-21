# lab-stdlib-math-transcendentals-p2-v0 — Tier-1 Float transcendentals (sin/cos/sqrt/pi)

**Card:** `LAB-STDLIB-MATH-TRANSCENDENTALS-P2` · **Delegation:** `OPUS-STDLIB-MATH-TRANSCENDENTALS-P2`
**Status:** CLOSED (implementation proof) — `stdlib.Math` grows from four Decimal functions to also expose
**`sin`, `cos`, `sqrt`** `(Float)->Float` and **`pi()`** `()->Float`, on the **fast platform-`f64`** path.
They compile, typecheck, and execute through the real compiler + VM. **No deterministic `det.*` claim
(separate card); no implicit Integer/Decimal coercion; no new crate dependency.**

## Live wiring path (the verify-first answer to the card's Q1–Q3)

There is **no whitelist/inventory gate** for stdlib calls — `infer_stdlib_call`'s `match fn_name` *is* the
registry (a name with no arm falls through to user-fn lookup → `OOF-TY0`). So Tier-1 is wired in exactly two
hot places, plus the declarative spec:

1. **Typecheck** — `lang/igniter-compiler/src/typechecker/stdlib_calls.rs`: new arms in `infer_stdlib_call`
   set `resolved_type = Float` and validate arity/argument type. Dispatch order (typechecker.rs:4475+):
   sealed constructors → user functions → `infer_stdlib_call`, so a user-defined `sin` still shadows.
2. **Execute** — `lang/igniter-vm/src/vm.rs`: new arms in the OP_CALL function-call dispatch (the
   `match fn_name` block) compute via Rust `f64` intrinsics (`x.sin()`, `x.cos()`, `x.sqrt()`,
   `std::f64::consts::PI`). This is the bytecode path `igniter-vm trace` exercises.
3. **Declarative spec** — `lang/igniter-stdlib/stdlib/math.ig`: `def sin/cos/sqrt/pi` added (documentation;
   the wiring above is what actually resolves/executes — the card's "declarative `.ig` is not enough" warning
   confirmed).

**Call surface (Q2):** **bare** `sin(x)`, `cos(x)`, `sqrt(x)`, `pi()` — matching the existing stdlib idiom
(`map`/`filter`/`count`/`add` are all called bare). The qualified `stdlib.math.sin` name also dispatches
(both forms in each arm), but bare is the canonical surface. **`pi` (Q3)** is a **zero-arg function** `pi()`
returning the `Float` constant — consistent with the call grammar, no new constant syntax.

## Semantics (Q4–Q6)

- **Q4 non-finite:** the fast path returns whatever `f64` yields — `sqrt(-1.0)` → `NaN`. This is **not**
  guarded in P2 (documented limit). It matters because the VM's observation stream serializes non-finite
  `f64` to JSON `null`; the deterministic `det.*` card is where finite-guarantee (`det.sqrt(<0)=error`) lives.
  For P2 (fast path) the caller owns domain validity.
- **Q5 coercion:** **none.** `sin/cos/sqrt` accept **only** `Float`; an `Integer`/`Decimal` argument is a type
  error (`OOF-MATH2`) at compile time and a runtime error in the VM. Integer×Float coercion stays deferred.
- **Q6 deps:** **no new dependency** — Rust `std` `f64` intrinsics only.

## Diagnostics

New rule codes layered into the existing diagnostic style (`ClassifierDiagnostic{rule,message,node,line}`):
- **`OOF-MATH1`** — wrong arity (`sin`/`cos`/`sqrt` ≠ 1 arg; `pi` ≠ 0 args).
- **`OOF-MATH2`** — non-`Float` argument to `sin`/`cos`/`sqrt`.
Float is the resolved type on **all** paths (including error paths), so a bad call still types as `Float`
and does not cascade `Unknown`.

## Numeric acceptance (tolerance, not bit-equality)

Fast path = platform `f64`, so the VM tests assert `|got − exact| < 1e-12` at exact-representable /
well-conditioned points (not cross-arch bit-identity — that is the `det.*` track):

| call | result |
|---|---|
| `sin(0.0)` | 0.0 |
| `sin(π/2)` | 1.0 |
| `cos(0.0)` | 1.0 |
| `sqrt(4.0)` | 2.0 (exact) |
| `sqrt(9.0)` via `stdlib.math.sqrt` | 3.0 (exact) |
| `pi()` | 3.141592653589793 |

`1e-12` chosen as comfortably tighter than `f64` rounding at these points yet not asserting exact bits (the
honest line for a fast f64 path).

## Tests & commands — exact counts

```text
$ cd lang/igniter-vm && cargo test --test stdlib_math_tests              → 5 passed (values, pi zero-arg, qualified dispatch, arity err, non-Float err)
$ cd lang/igniter-compiler && cargo test --test stdlib_math_tests        → 3 passed (valid compiles clean, OOF-MATH1, OOF-MATH2)
$ cd lang/igniter-compiler && cargo test                                 → suite green (23 ok result lines)
$ cd lang/igniter-vm && cargo test                                       → green EXCEPT one PRE-EXISTING, unrelated failure (below)
$ git diff --check                                                       → clean
```

**Live end-to-end smoke:** a contract using `sin(x)`, `cos(x)`, `sqrt(x)`, `pi()`, and `sin(pi()/2.0)`
compiles (`status: ok`, all stages) and runs (`result_status: ok`) through `igniter_compiler` + `igniter-vm
trace`.

## Pre-existing unrelated failure (isolated precisely, per acceptance)

`igniter-vm` `vm_candidate_proof_tests::test_proof_vmg13_local_loops_and_service_loops` fails with
`OP_GET_FIELD: expected Record, got Integer(1710000000)` — a service-loop/temporal (`as_of`/tick) test on a
unix-timestamp. **Isolation proof:** `git stash`-ing only my `vm.rs` and re-running the test **still fails on
clean HEAD** — so it is pre-existing and unrelated to transcendentals (which touch only the call dispatch,
not `OP_GET_FIELD`/temporal logic). Flagged, not introduced.

## Pressure loop closed (P1 → P2)

`LAB-STDLIB-MATH-PRESSURE-KURAMOTO-P1` had to hand-roll an 11-line Taylor `sin` in `.ig`
(`igniter-home-lab/apps/emergence/kuramoto/sin.ig`) because `stdlib.Math` lacked transcendentals. That
workaround is now obsolete: `compute s : Float = sin(x)` compiles and runs natively (the
`valid_transcendental_calls_compile_clean` fixture is exactly the Taylor replacement). Kuramoto's `sin`/`sqrt`
needs are unblocked on the fast path.

## Acceptance — mapping

- [x] Live wiring path documented (typecheck arm + VM arm + declarative `.ig`; no whitelist gate).
- [x] `sin/cos/sqrt/pi` valid Float calls compile cleanly (status ok, Float inferred).
- [x] Wrong arity/type rejected deterministically (`OOF-MATH1`/`OOF-MATH2`).
- [x] VM executes finite known values within a documented tolerance (1e-12).
- [x] No implicit Integer/Decimal → Float coercion added.
- [x] No deterministic `det.*` claim in this card.
- [x] Existing tests green except one pre-existing unrelated VM failure, isolated precisely.
- [x] `git diff --check` clean.

## Files changed

- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs` (sin/cos/sqrt/pi arms; OOF-MATH1/2).
- `lang/igniter-vm/src/vm.rs` (sin/cos/sqrt/pi arms in the OP_CALL dispatch; f64 intrinsics).
- `lang/igniter-stdlib/stdlib/math.ig` (declarative `def sin/cos/sqrt/pi`).
- `lang/igniter-vm/tests/stdlib_math_tests.rs` (new, 5 numeric/error tests).
- `lang/igniter-compiler/tests/stdlib_math_tests.rs` (new, 3 typecheck tests).

## Closed scope

No deterministic fixed-point/CORDIC/LUT; no Decimal transcendentals; no numeric tower / implicit coercions;
no `tan/pow/exp/ln`; no non-finite guards (fast path); no broad Kuramoto rewrite beyond the replacement fixture.

## Next

`LAB-STDLIB-MATH-DET-TIER1-P4` — the deterministic `stdlib.Math.det.*` surface (per the P3 determinism
readiness): IEEE-mandated `f64::sqrt` + vendored pure-Rust libm for `det.sin/cos`, finite-guaranteed,
golden-vector + cross-arch CI. Then Tier-2 (`tan/pow/exp/ln/abs/mod`) and the clean Kuramoto sim.

---

*Implementation proof. 2026-06-21. `stdlib.Math` now exposes fast-f64 `sin/cos/sqrt/pi`; compiles + typechecks
(`OOF-MATH1/2`) + executes within 1e-12; 5 VM + 3 compiler tests green; one pre-existing unrelated VM failure
isolated; `git diff --check` clean. The Kuramoto Taylor-`sin` workaround is obsolete — the P1 pressure is
resolved on the fast path.*
