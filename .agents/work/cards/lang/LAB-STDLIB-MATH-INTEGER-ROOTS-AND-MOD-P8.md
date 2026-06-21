# LAB-STDLIB-MATH-INTEGER-ROOTS-AND-MOD-P8 — integer roots, powers, and modulo

Status: CLOSED
Lane: standard / stdlib math / science
Type: implementation proof
Delegation code: OPUS-STDLIB-MATH-INTEGER-ROOTS-AND-MOD-P8
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

Depends on:

- `LAB-STDLIB-MATH-TIER2-READINESS-P6` — evidence-ranked Tier-2 plan.
- `LAB-STDLIB-MATH-NUMERIC-BASICS-P7` — N0 basics landed (`abs/min/max/clamp/sign`).
- `LAB-STDLIB-INTEGER-BITOPS-READINESS-P1` — bitops deferred; `bloom_filter` actually needs `mod`.

P6 ranked N1 integer math as the next high-pressure science/control slice: `isqrt` lifts the forced
sqrt-free constraint from pursuit/guidance; `ipow` supports exact integer kernels; `mod` unblocks CA/sandpile
and `bloom_filter`'s real hash pressure. These are deterministic by construction and do not need `det_*`
variants.

## Goal

Implement the smallest integer N1 surface:

- `isqrt(x: Integer) -> Integer`
- `ipow(base: Integer, exp: Integer) -> Integer`
- `mod(a: Integer, b: Integer) -> Integer`

Optional only if live code shows a trivial pairing with `mod`: `rem(a,b)` with clearly documented semantics.
Do not open bitops, Float `powf`, Decimal, or generic numeric coercion.

## Verify first

- `lab-docs/lang/lab-stdlib-math-tier2-readiness-p6-v0.md`
- `lab-docs/lang/lab-stdlib-math-numeric-basics-p7-v0.md`
- `lab-docs/lang/lab-stdlib-integer-bitops-readiness-p1-v0.md`
- `apps/igniter-apps/bloom_filter/hash.ig`
- `lab-docs/governance/igniter-stdlib-numeric-coverage-proposal-readiness-v0.md`
- `lang/igniter-stdlib/stdlib/math.ig`
- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs`
- `lang/igniter-vm/src/vm.rs`
- current tests under `lang/igniter-compiler/tests/stdlib_math_tests.rs` and `lang/igniter-vm/tests/`.

Before implementation, confirm whether any `mod`/`rem` spelling already exists in parser, VM, or apps as a
manual helper. Live code wins over docs.

## Semantics

- `isqrt(x)` = floor integer square root. Domain: `x >= 0`; `x < 0` is deterministic runtime domain error.
- `ipow(base, exp)` = exact integer exponentiation by squaring. Domain: `exp >= 0`; `exp < 0` is deterministic
  runtime domain error.
- `ipow` overflow policy: prefer deterministic runtime error via checked multiplication. Do not wrap silently.
- `mod(a,b)` = Euclidean-style non-negative remainder for positive modulus is preferred; if choosing Rust `%`
  semantics instead, justify with examples and document negative cases. `b == 0` is runtime domain error.
- No implicit Integer/Float coercion. No Float or Decimal overloads in this card.

## Diagnostics

Reuse the math compile diagnostics:

- `OOF-MATH1` — wrong arity.
- `OOF-MATH2` — non-Integer argument.

Runtime domain errors must be deterministic and tested:

- `isqrt(-1)`
- `ipow(2,-1)`
- `mod(1,0)`
- `ipow` overflow, if checked overflow is implemented.

If the codebase already has a named runtime diagnostic channel for math domain errors, use it; otherwise record
the exact VM error strings in the proof doc and do not invent a broad diagnostic framework here.

## Required implementation

- Add declarations to `lang/igniter-stdlib/stdlib/math.ig`.
- Wire compiler typechecker support in `stdlib_calls.rs`.
- Wire VM support through the shared `eval_math_call` path so OP_CALL and eval_ast/HOF paths remain in parity.
- Bump `igniter-stdlib` version and compiler `STDLIB_VERSION`.
- Add compiler tests for valid calls, arity, non-Integer type errors.
- Add VM tests for exact values, domain errors, overflow behavior, and one compiler→VM expression.
- Add one pressure test proving `bloom_filter`-style hash can use `mod` instead of manual modulo.

## Acceptance

- [x] `isqrt`, `ipow`, and `mod` compile for valid Integer arguments.
- [x] Wrong arity emits `OOF-MATH1`.
- [x] Non-Integer arguments emit `OOF-MATH2`.
- [x] `isqrt(0)=0`, `isqrt(1)=1`, `isqrt(15)=3`, `isqrt(16)=4`, large perfect/non-perfect cases tested.
- [x] `isqrt(<0)` errors deterministically.
- [x] `ipow(2,0)=1`, `ipow(2,10)=1024`, negative bases tested.
- [x] `ipow(exp<0)` and overflow error deterministically.
- [x] `mod` by zero errors deterministically.
- [x] `mod` negative-case semantics are explicitly chosen and tested (Euclidean: `-1,3→2`).
- [x] OP_CALL and eval_ast/HOF parity are tested through shared `eval_math_call`.
- [x] `bloom_filter` pressure is represented by a small compiled/VM proof (`mod((31*42+17),64)=39`).
- [x] `STDLIB_VERSION` mirror guard remains green (0.1.4).
- [x] Proof doc written: `lab-docs/lang/lab-stdlib-math-integer-roots-and-mod-p8-v0.md`.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-21)

**Implemented** `isqrt`/`ipow`/`mod` as **Integer-only** stdlib math, **deterministic by construction** (pure
i64, no f64, no `det_*` variant needed). Wiring: `def`s in `math.ig`; Integer-only typecheck arm in
`stdlib_calls.rs` (Integer result, OOF-MATH1 arity / OOF-MATH2 non-Integer); `num_isqrt/num_ipow/num_mod` in
the single-source `eval_math_call` + the OP_CALL name-list arm extended → **OP_CALL ⇄ eval_ast parity**;
`STDLIB_VERSION` 0.1.3→**0.1.4** (compiler const + Cargo.toml, mirror guard green). Proof doc:
`lab-docs/lang/lab-stdlib-math-integer-roots-and-mod-p8-v0.md`.

**Key decisions:** `isqrt` = integer-Newton floor sqrt (no f64). `ipow` = exponentiation by squaring with
**`checked_mul`** (overflow → error, never wraps). `mod` = **Euclidean** (`checked_rem_euclid`) — non-negative
for a positive modulus (`-1 mod 3 = 2`, not Rust `%`'s `-1`), the right semantics for hashing/CA/clock.
Domain errors (`isqrt(<0)`, `ipow(exp<0)`, overflow, `mod(_,0)`) are deterministic runtime `Err(String)`.

**Proof:** `stdlib_math_intmod_tests` — **7 VM** (values/domain/overflow, non-math-fallthrough, compiler→VM
nested `mod(ipow(2,10),7)=2`, bloom-style `mod((31*42+17),64)=39`, `isqrt`-in-fold HOF parity) + **4 compiler**
(valid clean; OOF-MATH1 arity; OOF-MATH2 non-Integer ×2). Full compiler suite green; full VM suite green
**except** the pre-existing, unrelated `vmg13` service-loop failure (git-stash-proven on clean HEAD earlier;
my diff is math-only). `git diff --check` clean.

**Concurrent-edit note:** stdlib is under active parallel work — a neighbor's edit reverted `math.ig` + the
version mid-card; re-applied. The load-bearing dispatch (typechecker + VM match arms — the registry IS the
match, not the `.ig def`) carried through regardless.

**Deferred:** Decimal overloads; Float `powf`/`atan2/exp/ln/floor/ceil/round` (advanced tier); `.ig` bitops;
`rem` (Rust-`%` sibling, no live pairing). **Next:** `LAB-STDLIB-NUMERIC-TO-FLOAT` follow-ons + descriptive
statistics can now use integer counts + modulo-backed examples.

## Proof doc requirements

The proof doc must include:

- final semantics table (`isqrt`/`ipow`/`mod`);
- overflow and negative-input policy;
- Euclidean vs Rust `%` modulo decision;
- diagnostic matrix;
- exact tests and counts;
- OP_CALL/eval_ast parity statement;
- pressure note for `bloom_filter`;
- what remains for Decimal, Float `powf`, and bitops.

## Closed scope

- No bitwise/shift operators.
- No `wrap_*` bitops surface.
- No Float `powf`, `atan2`, `exp`, `ln`, `floor`, `ceil`, or `round`.
- No Decimal.
- No numeric tower or implicit coercion.
- No performance benchmark.
- No canon claim.

## Next

After this lands, `LAB-STDLIB-NUMERIC-TO-FLOAT-P8` and `LAB-STDLIB-STATISTICS-DESCRIPTIVE-P2` can use integer
counts and modulo-backed science examples with less hand-rolled arithmetic.
