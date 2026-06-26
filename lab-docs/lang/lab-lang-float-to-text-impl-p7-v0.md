# lab-lang-float-to-text-impl-p7-v0

Card: `LAB-LANG-FLOAT-TO-TEXT-IMPL-P7`
Route: standard / language stdlib implementation · Skill: idd-agent-protocol
Status: implemented (`float_to_text : (Float, Integer, String) -> String`, fixed-point, `"half_even"` only) · no implicit `to_text(Float)` · no canon determinism claim
Date: 2026-06-26
Builds on: P4 readiness · **P5 policy** (`lab-docs/lang/lab-lang-float-to-text-policy-p5-v0.md`) · P1 `to_text(Integer)` · P2 `to_text(Decimal)` · P3 `pad_left`

> **Authority boundary.** Lab language surface (igniter-lab `lang/` — the lab's own compiler/VM, NOT canon
> igniter-lang). One explicit Float formatter; no implicit `to_text(Float)`, no locale/currency/grouping/
> exponent, one rounding mode, **no canon determinism claim.**

---

## Accepted public surface

```text
float_to_text(x : Float, decimals : Integer, rounding : String) -> String
stdlib.string.float_to_text(x, decimals, rounding) -> String
```

Closes the P4/P5 Float-formatting gap **without** adding implicit `to_text(Float)` — `to_text` stays
Integer|Decimal-only (a Float arg is still `OOF-TY0`, regression-tested).

## Semantics (exactly P5 §4, no deviation)

```text
float_to_text(x, decimals, mode):
  1. mode == "half_even"   else → error  (only mode in v0)
  2. x.is_finite()         else → error  (NaN / ±Inf never stringified)
  3. 0 <= decimals <= 17   else → error  (17 = f64 round-trip guarantee)
  4. s = format!("{:.*}", decimals as usize, x)        -- std: correctly-rounded ties-to-even, integer-based
  5. negative-zero normalize: if s is all of {'-','.','0'} and starts with '-', drop the leading '-'
  → s
```

- **Rounding** leans on std `{:.N}` — verified (P5 §6, rustc 1.95.0) correctly-rounded **half-even** and
  `flt2dec`-based (no `libm`), so the value is stable across arch/version. The impl adds only the two-line
  negative-zero normalize. No custom rounding (the `2.675`/`1.005` representation traps are why).
- **Fixed-point always** — `{:.N}` never emits an exponent (`1e20 @2 → "100000000000000000000.00"`).
- **f64 reality preserved** — `2.675 @2 → "2.67"`, `1.005 @2 → "1.00"` (the binary value is below the decimal
  literal). Not "fixed" by pretending Float is Decimal; exact money still goes through the typed `Decimal` path.

## Rounding-mode enforcement (two layers, one message family)

- **Literal mode** (a `String` literal in source): the **typechecker rejects** any value ≠ `"half_even"` —
  `OOF-TY0`, message `float_to_text: unsupported rounding mode "<x>"; v0 supports only "half_even"`. **This
  literal compile-rejection was IMPLEMENTED** — the stdlib-call checker already inspects literal args (the
  `decimal(value, scale)` precedent reads `Expr::Literal`), so `args[2]` as a `String` literal is checkable.
- **Dynamic mode** (a runtime `String`): the **VM rejects** it deterministically, **before any output**, with
  the same message. Fail-closed, no silent default.

## Implementation

- **VM** (`lang/igniter-vm/src/vm.rs`): a free `fn float_to_text(x: f64, decimals: i64, mode: &str) ->
  Result<String, String>` next to `decimal_to_text`, plus a `float_to_text` arm INSIDE `eval_math_call` (the
  same single source `to_text` uses). Both dispatch paths reach it: the OP_CALL gate gains `|
  "stdlib.string.float_to_text" | "float_to_text"`; the `eval_ast`/HOF path already tries `eval_math_call`
  for any op (no gate). So OP_CALL and `eval_ast` are byte-identical (single source).
- **Typechecker** (`lang/igniter-compiler/src/typechecker/stdlib_calls.rs`): a `float_to_text` arm — arity 3,
  `(Float, Integer, String) -> String` (`OOF-TY0`, `String` on every path), plus the literal-mode rejection.
- **No `experiment.rs` change** — the stdlib surface routes through `eval_math_call`, not `experiment.rs`.

## Local Rust formatting facts

**No deviation from the P5 §6 probe** (rustc 1.95.0): every pinned value below matched std `{:.N}` exactly —
ties-to-even on clean `.0` ties *and* exact-f64 `.2` ties, sign-preserved rounded-zero (hence the normalize),
fixed-point for large magnitudes, and the `2.675`/`1.005` f64-reality cases. The regression test pins all of
them so a future std change is caught.

## Test matrix

**`lang/igniter-vm/tests/stdlib_float_to_text_tests.rs` (11):** basic/padding (`1.5@2→1.50`, `1.0@3→1.000`,
`3.7@0→4`, `3.14159@2→3.14`); half-even ties (`0.5/1.5/2.5/3.5@0 → 0/2/2/4`, `-2.5@0→-2`, `0.125/0.375@2 →
0.12/0.38`); negative-zero normalized (`-0.0/-0.001@2→0.00`, `-0.4@0→0`, `-0.04@1→0.0`, and `-1.25@1→-1.2`
keeps sign); f64-reality (`2.675@2→2.67`, `1.005@2→1.00`); no-exponent (`1e20@2`); precision bound (`17` ok,
`18`/`-1` rejected); non-finite rejected (NaN/±Inf); dynamic unsupported mode rejected (stable §2 message);
arity/type errors; **compiler→VM e2e** (`3.14159@2→"3.14"` through OP_CALL) + **eval_ast fold parity**
(`2.5@0→"2"` inside a fold lambda).

**`lang/igniter-compiler/tests/stdlib_float_to_text_tests.rs` (5):** valid `(Float,Integer,String)` clean;
wrong arity → `OOF-TY0`; each wrong arg type → `OOF-TY0`; **literal `"half_up"` → `OOF-TY0` with the §2
message**; **negative test** — `to_text(Float)` stays rejected (no implicit Float path).

**Regression (green):** full VM suite (25 ok-blocks, incl. `to_text`/`pad_left`); full compiler suite (31
ok-blocks, incl. `stdlib_version_mirrors_crate` + `lock_stamps_stdlib_version`); igniter-web `--features
machine` green (downstream path-dep recompile, no source change). `git diff --check` clean.

```bash
# from lang/igniter-vm
cargo test --test stdlib_float_to_text_tests   # 11 passed
cargo test                                     # full VM suite green
# from lang/igniter-compiler
cargo test --test stdlib_float_to_text_tests   # 5 passed
cargo test                                     # full compiler suite green (version guards incl.)
```

`STDLIB_VERSION` unchanged (same coarse-milestone precedent as P1/P2/P3; the guards stay green).

## Files changed

| File | Change |
| --- | --- |
| `lang/igniter-vm/src/vm.rs` | `fn float_to_text` helper + `float_to_text` arm in `eval_math_call` + name in the OP_CALL math gate. |
| `lang/igniter-compiler/src/typechecker/stdlib_calls.rs` | `float_to_text` arm `(Float,Integer,String)->String` + literal-mode rejection. |
| `lang/igniter-vm/tests/stdlib_float_to_text_tests.rs` *(new, 11)* | exact values + rejections + compiler→VM + fold parity. |
| `lang/igniter-compiler/tests/stdlib_float_to_text_tests.rs` *(new, 5)* | typecheck accept/reject + literal mode + no-implicit-Float. |

## Held surfaces (confirmed closed)

No implicit `to_text(Float)`; no locale/currency/grouping/exponent; only `"half_even"`; no
`float_to_decimal`/typed `Decimal[N]` conversion (deferred — it needs literal-scale `Decimal[N]`, and would be
built *on top of* `float_to_text`); no broad formatter; no `experiment.rs` change; no canon determinism claim.

## Reporting

- **Accepted surface:** `float_to_text(Float, Integer, String) -> String` (bare + `stdlib.string.*`), single
  `eval_math_call` source. **Held:** everything in §"Held surfaces".
- **Local Rust facts:** no deviation from the P5 §6 probe; all pinned values matched std `{:.N}`.
- **Literal-mode compile rejection:** **implemented** (not deferred) — the checker inspects the `String`
  literal arg.
- **Tests/counts:** VM 11, compiler 5; full VM 25 ok, full compiler 31 ok; downstream igniter-web green; diff
  clean.
- **Next route:** `LAB-LANG-STDLIB-FORMATTING-COMPLETION-P8` — update the front-door docs so future agents stop
  asking whether Float formatting exists (the trio `to_text(Integer)`/`to_text(Decimal)`/`float_to_text` +
  `pad_left` now covers the surface). A `float_to_decimal` quantizer and an optional `pad_right` remain the
  only named follow-ons, each gated on real pressure.
