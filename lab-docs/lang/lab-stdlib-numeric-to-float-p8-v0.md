# lab-stdlib-numeric-to-float-p8-v0 — explicit Integer→Float conversion

**Card:** `LAB-STDLIB-NUMERIC-TO-FLOAT-P8` · **Type:** implementation proof
**Status:** CLOSED — `to_float(Integer) -> Float` is live: a single **named** widening boundary. **No implicit
coercion added** — `+ - * / min/max/clamp` stay same-type; `Float / Integer` is still rejected, while
`Float / to_float(Integer)` works. Unblocks `sum / to_float(count)`-style normalization (the statistics gap).

## Live absence check (verify-first)

No prior `to_float` / `as_float` / `float` / implicit-cast surface existed (grep across `stdlib_calls.rs`,
`vm.rs`, `math.ig` — the only `Float`-return hits were unrelated arms). `count` returns `Integer`; the mixed
`Integer op Float` rule is deliberately deferred in `typechecker.rs` (the "no implicit coercion" rule we
preserve). So `to_float` is the first, named widening — not a numeric tower.

## Semantics

- `to_float(x: Integer) -> Float`, via Rust `i as f64`.
- **Rounding (documented):** integers beyond the IEEE-754 53-bit mantissa may round — e.g. `to_float(2^53+1)
  == 2^53` (`9007199254740992.0`). Acceptable for counts/normalization; tested with a stable expectation.
- **No implicit coercion anywhere else.** This is the *only* widening, and it is explicit at the call site.

## Diagnostic matrix

| Case | Result |
|---|---|
| `to_float(3)` | `3.0` |
| `to_float(-7)` | `-7.0` |
| `to_float(2^53+1)` | `9007199254740992.0` (rounded, documented) |
| `to_float()` / `to_float(a,b)` | **`OOF-MATH1`** (arity) |
| `to_float(1.0)` (Float arg) | **`OOF-MATH2`** (non-Integer) |
| `9.0 / k` (k: Integer) | **`OOF-TY0`** — mixed numeric still rejected (no coercion) |
| `9.0 / to_float(k)` | **ok** — `Float / Float` |

## Wiring

- VM: arm in **`eval_math_call`** (the single source shared by `OP_CALL` + eval_ast/HOF, P10) → `Value::Integer(i)
  => Value::Float(i as f64)`; `OP_CALL` mirror name-list extended. OP_CALL/eval_ast parity for free.
- Typechecker (`stdlib_calls.rs`): `to_float` → `Float`; `OOF-MATH1` arity, `OOF-MATH2` non-Integer.
- `stdlib/math.ig`: `def to_float(x: Integer) -> Float`.
- `STDLIB_VERSION` / `igniter-stdlib` at **0.1.4** (surface change; synced with the concurrent N1 `isqrt/ipow/
  mod` work — guard `stdlib_version_mirrors_crate` green).

## The statistics unblock (proof)

`Float / Integer` was the descriptive-stats blocker. Now the mean is expressible:
`9.0 / to_float(3) == 3.0` (mirrors `sum(xs) / to_float(count(xs))` with aggregates inlined) — runs through
the **real compiler→VM** (`Compiler`→`VM::execute`). The blocker is removed without any implicit coercion.

## Tests & commands — exact counts

```text
$ cd lang/igniter-vm && cargo test --test stdlib_to_float_tests   → 5 passed; 0 failed
  (to_float_basic_and_negative, to_float_large_integer_rounds_as_f64, to_float_arity_and_type_errors,
   to_float_through_compiler_vm, float_div_to_float_count_normalizes)
$ math/random/nbody/hof/det regression                            → 6/7/5/6/5 passed (parity intact)
$ cd lang/igniter-compiler && cargo test stdlib_version_mirrors_crate → 1 passed (0.1.4 mirror)
$ igc compile (good: 9.0/to_float(k))                            → status: ok
$ igc compile (mixed: 9.0/k)                                     → OOF-TY0 (still rejected)
$ igc compile (to_float(k,k))                                    → OOF-MATH1
$ igc compile (to_float(x:Float))                                → OOF-MATH2
$ git diff --check                                               → clean
```

## Acceptance — mapping

- [x] `to_float(Integer)->Float` compiles cleanly (`igc` status ok).
- [x] `to_float(3)` executes as `3.0`.
- [x] negative integer conversion works (`to_float(-7) = -7.0`).
- [x] large-integer rounding documented + tested (`2^53+1 → 2^53`).
- [x] wrong arity → `OOF-MATH1`; non-Integer → `OOF-MATH2`.
- [x] OP_CALL + eval_ast/HOF parity (shared `eval_math_call`; compiler→VM test).
- [x] normalization proof executes: `9.0 / to_float(3) = 3.0` (mirrors `sum / to_float(count)`).
- [x] no binary numeric operator gained implicit coercion (`9.0 / k` still `OOF-TY0`).
- [x] `STDLIB_VERSION` mirror guard green (0.1.4).
- [x] Proof doc written; `git diff --check` clean.

## Decimal — deferred (live blocker)

`to_float(Decimal)` was **not** included: `Decimal{value:i64, scale:u32}` has a scale, so a `Decimal→Float`
conversion has a precision/representation policy question (which scale, rounding) that is not trivially
unambiguous in live code. Integer-only first (per the card's bias); Decimal deferred until a consumer + policy
exist.

## Files

- `lang/igniter-vm/src/vm.rs` (`eval_math_call` to_float arm + OP_CALL mirror).
- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs` (to_float typecheck arm).
- `lang/igniter-stdlib/stdlib/math.ig` (`def to_float`).
- `lang/igniter-compiler/src/lib.rs` + `lang/igniter-stdlib/Cargo.toml` (`STDLIB_VERSION` 0.1.4, shared with N1).
- `lang/igniter-vm/tests/stdlib_to_float_tests.rs` (new; 5 tests).

## Closed scope (honored)

No implicit coercion; no `to_integer`/`floor`/`ceil`/`round`/`parse_float`; no Decimal conversion; no stats
implementation (only unblocked); no canon claim.

## Next

`LAB-STDLIB-STATISTICS-DESCRIPTIVE-P2` — now unblocked (`mean = sum / to_float(count)`). Emergence: the
N-body order parameter can use a real variable `N = to_float(count(phases))` instead of a fixed literal.

---

*Lab proof. 2026-06-21. `to_float(Integer)->Float` — the single named widening; `Float/Integer` stays rejected
(`OOF-TY0`), `Float/to_float(Integer)` works, large-i64 rounding documented, OP_CALL/eval_ast parity,
`OOF-MATH1/2`, `STDLIB_VERSION` 0.1.4. The statistics blocker (`sum/count`) is removed with zero implicit
coercion.*
