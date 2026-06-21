# lab-stdlib-math-integer-roots-and-mod-p8-v0 — isqrt / ipow / mod (N1 integer math)

**Card:** `LAB-STDLIB-MATH-INTEGER-ROOTS-AND-MOD-P8` · **Type:** implementation proof
**Status:** CLOSED — `isqrt`, `ipow`, `mod` land as Integer-only stdlib math, deterministic by construction
(pure i64, no f64, no `det_*` variant), wired through the shared `eval_math_call` so OP_CALL and the
eval_ast/HOF path are in parity. `isqrt` lifts the forced sqrt-free constraint (LAB-PURSUIT); `mod` gives
`bloom_filter`-style hashing a real modulo.

## Final semantics

| Fn | Signature | Definition | Domain error (runtime, deterministic) |
|---|---|---|---|
| `isqrt` | `(Integer) -> Integer` | floor integer square root, **integer Newton** (no f64) | `x < 0` → `"isqrt: domain error (negative input)"` |
| `ipow` | `(Integer, Integer) -> Integer` | exponentiation by squaring, **`checked_mul`** (never wraps) | `exp < 0` → domain error; overflow → `"ipow: Integer overflow"` |
| `mod` | `(Integer, Integer) -> Integer` | **Euclidean** remainder (`checked_rem_euclid`) | `b == 0` → `"mod: domain error (division by zero)"`; `i64::MIN % -1` → overflow error |

Integer-only: **no Float/Decimal overload, no implicit coercion** (a non-Integer argument is rejected at
compile time, OOF-MATH2).

## Overflow & negative-input policy

- **`isqrt`** is total on `x ≥ 0`; `x < 0` is a deterministic runtime error (not `NaN`, not a panic). The
  integer-Newton algorithm uses no `f64`, so the result is exact and bit-identical across architectures.
- **`ipow`** uses `checked_mul` on every multiply (both the accumulator and the base-squaring step) → an
  overflow is a deterministic runtime error, **never a silent wrap**. `exp < 0` is a domain error (integer
  exponentiation has no negative-exponent result).
- **`mod`** uses `checked_rem_euclid`, which returns `None` for `b == 0` (→ division-by-zero error) and for
  the `i64::MIN.rem_euclid(-1)` overflow (→ overflow error). No panic path.

## Euclidean vs Rust `%` (decision)

**Euclidean** (`i64::rem_euclid`), not Rust `%`. For a positive modulus the result is always in `[0, b)`:

| a, b | Euclidean `mod` (chosen) | Rust `%` (rejected) |
|---|---|---|
| `7, 3` | `1` | `1` |
| `-1, 3` | **`2`** | `-1` |
| `-7, 3` | **`2`** | `-1` |

The non-negative result is what hashing (`bloom_filter`), clock/wrap arithmetic, and CA/sandpile index math
want; the Rust `%` sign-follows-dividend behavior is a footgun for those uses. Tested explicitly.

## Diagnostic matrix

| Condition | Rule | When |
|---|---|---|
| wrong arity (`isqrt/2`, `ipow/1`, `mod/1`) | **OOF-MATH1** | compile time (typechecker) |
| non-Integer argument (`isqrt(Float)`, `ipow(Float,_)`, `mod(Float,_)`) | **OOF-MATH2** | compile time |
| `isqrt(<0)`, `ipow(exp<0)`, `ipow` overflow, `mod(_,0)` | (runtime error string, see table) | VM execution |

Reuses the existing math compile diagnostics (OOF-MATH1 arity, OOF-MATH2 non-numeric — here specialized to
"must be Integer"). Runtime domain errors use deterministic `Err(String)` on the existing VM error path (no
new diagnostic framework invented, per card guidance).

## OP_CALL / eval_ast parity

Both dispatch paths route through the **single source `eval_math_call`** (`vm.rs`). The new `num_isqrt`/
`num_ipow`/`num_mod` helpers live there; the eval_ast/HOF path calls `eval_math_call` unconditionally (so
`isqrt` composes inside a `fold` lambda — tested), and the **OP_CALL bytecode arm's name list was extended**
with `isqrt/ipow/mod` so the bytecode path delegates to the same source (tested: a top-level `mod(ipow(2,10),7)`
expression compiled+run). Identical semantics and error messages on both paths.

## bloom_filter pressure

`bloom_filter/hash.ig` documents `hash(key,in) = mod(in.a*key + in.b, filter_size)` but had no `mod`
primitive. Proven here through real compiler+VM: `mod((31*42 + 17), 64) = 1319 mod 64 = 39`
(`bloom_filter_style_hash_uses_mod`). The hand-rolled modulo can now be a single `mod` call.

## Tests & commands — exact counts

```text
$ cd lang/igniter-vm && cargo test --test stdlib_math_intmod_tests        → 7 passed
  (isqrt values+domain, ipow values+domain+overflow, mod Euclidean+zero, non-math-falls-through,
   compiler→VM nested mod(ipow), bloom-style mod, isqrt inside fold lambda [eval_ast parity])
$ cd lang/igniter-compiler && cargo test --test stdlib_math_intmod_tests  → 4 passed
  (valid integer calls compile clean; isqrt/2 → OOF-MATH1; isqrt(Float) → OOF-MATH2; ipow/mod(Float) → OOF-MATH2)
$ cd lang/igniter-compiler && cargo test                                  → full suite green (0 failed)
$ cd lang/igniter-vm && cargo test                                        → green EXCEPT pre-existing vmg13 (below)
$ git diff --check                                                        → clean
```

**Pre-existing unrelated failure (isolated):** `test_proof_vmg13_local_loops_and_service_loops` fails — a
known service-loop / `OP_GET_FIELD`-on-unix-timestamp issue, git-stash-proven to fail on clean HEAD earlier
this session (LAB-STDLIB-MATH-TRANSCENDENTALS-P2). My diff only adds math match arms (no loops / service /
`OP_GET_FIELD` / timestamp code), so it is unrelated.

## Wiring

- `lang/igniter-stdlib/stdlib/math.ig` — `def isqrt/ipow/mod` (Integer→Integer).
- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs` — Integer-only arm (Integer result, OOF-MATH1/2).
- `lang/igniter-vm/src/vm.rs` — `num_isqrt`/`num_ipow`/`num_mod` in `eval_math_call` + the OP_CALL name-list
  arm extended (single-source parity).
- `STDLIB_VERSION` 0.1.3 → **0.1.4** (compiler const + `igniter-stdlib/Cargo.toml`, mirror guard green).

**Concurrent-edit note (honest):** stdlib is under active parallel work; during this card a neighbor's edit
reverted `math.ig` (and the version) mid-flight. The load-bearing dispatch is the typechecker + VM match arms
(the registry IS the match, not the `.ig` `def`), which carried through; the `.ig` declarations + version were
re-applied. Final state: all my tests green, mirror guard green.

## What remains (deferred, per scope)

- **Decimal** `isqrt`/`ipow`/`mod` overloads (the fixed-point world) — separate.
- **Float `powf`** + `atan2/exp/ln/floor/ceil/round` — the advanced-Float tier (P6-deferred).
- **`.ig` bitwise/shift operators** — separate readiness (`LAB-STDLIB-INTEGER-BITOPS-READINESS-P1`); not
  needed for these three (the impl uses Rust-side bit ops internally).
- `rem` (Rust `%`-semantics sibling) — not added; no live code paired it with `mod` (card's optional clause).

## Acceptance — mapping

- [x] `isqrt`, `ipow`, `mod` compile for valid Integer arguments.
- [x] Wrong arity → OOF-MATH1; non-Integer → OOF-MATH2.
- [x] `isqrt(0)=0,(1)=1,(15)=3,(16)=4,(17)=4`, large perfect/non-perfect (10¹²→10⁶, 10¹⁸→10⁹) tested.
- [x] `isqrt(<0)` errors deterministically.
- [x] `ipow(2,0)=1,(2,10)=1024`, negative base `(-2,3)=-8` tested.
- [x] `ipow(exp<0)` and overflow (`10^19`) error deterministically.
- [x] `mod` by zero errors deterministically; Euclidean negative-case (`-1,3→2`) chosen + tested.
- [x] OP_CALL and eval_ast/HOF parity through shared `eval_math_call` (top-level call + fold-lambda tested).
- [x] `bloom_filter`-style hash uses `mod` (compiled+VM proof).
- [x] `STDLIB_VERSION` mirror guard green (0.1.4).
- [x] `git diff --check` clean.

---

*Lab proof. 2026-06-21. `isqrt`/`ipow`/`mod` — Integer-only, deterministic-by-construction (pure i64, checked,
no f64, no det variant), Euclidean modulo, OP_CALL⇄eval_ast parity via the single `eval_math_call` source.
11 tests (7 VM + 4 compiler). `isqrt` lifts the sqrt-free constraint; `mod` unblocks bloom/CA hashing.*
