# LAB-LANG-DECIMAL-TO-TEXT-P2

Status: CLOSED (2026-06-25) — `to_text` extended to exact `Decimal->String`; Float still held
Route: standard / language stdlib implementation
Skill: idd-agent-protocol

## Goal

Extend the freshly implemented `to_text` surface from `Integer -> String` to exact
`Decimal -> String`, using the live VM representation:

```rust
Value::Decimal { value: i64, scale: u32 }
```

This is for money/report/table output. It must be exact, deterministic, and not
confused with Float formatting.

## Current Authority

Read first:

- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs`
- `lang/igniter-vm/src/vm.rs`
- `lang/igniter-vm/src/value.rs`
- `lang/igniter-compiler/tests/stdlib_to_text_tests.rs`
- `lang/igniter-vm/tests/stdlib_to_text_tests.rs`
- prior card/proof:
  - `.agents/work/cards/lang/LAB-LANG-NUMBER-TO-TEXT-P1.md`
  - `lab-docs/lang/lab-lang-number-to-text-p1-v0.md`

Live code wins over this card.

## Required Semantics

`to_text(decimal(value, scale))` returns a canonical base-10 decimal string:

| Value | Scale | Text |
| --- | ---: | --- |
| `12345` | `2` | `"123.45"` |
| `1200` | `2` | `"12.00"` |
| `5` | `2` | `"0.05"` |
| `0` | `2` | `"0.00"` |
| `-5` | `2` | `"-0.05"` |
| `-12345` | `2` | `"-123.45"` |
| `42` | `0` | `"42"` |

Rules:

- preserve exactly `scale` fractional digits;
- never use exponent notation;
- never use locale/grouping/currency symbols;
- no rounding;
- no trimming trailing zeroes;
- negative sign applies to the whole decimal, including `-0.xx` when needed;
- keep `Integer -> String` behavior unchanged;
- keep `Float -> String` rejected/held.

## Implementation Notes

Likely minimal path:

- typechecker: allow `to_text` for `Integer` and `Decimal`; still reject `Float`
  and other types with `OOF-TY0`;
- VM: update the same single `eval_math_call` arm to handle `Value::Decimal`;
- helper should use integer/string arithmetic only. Avoid `f64`.

Potential helper shape:

```rust
fn decimal_to_text(value: i64, scale: u32) -> String
```

Be careful with `i64::MIN`: `value.abs()` overflows. Use `i128` or string-based
sign handling.

## Closed Surfaces

- No Float formatting.
- No rounding modes.
- No currency formatting.
- No implicit numeric coercion.
- No Decimal parser.
- No change to `Value::to_json`.
- No app/web/server changes unless a tiny proof fixture genuinely needs them.

## Acceptance

- [x] Compiler accepts `to_text(decimal(12345, 2))` as `String`. — `valid_to_text_decimal_compiles_clean_as_string`
- [x] Compiler rejects `to_text(1.2)` / Float as before. — `float_argument_is_held` (OOF-TY0)
- [x] VM direct tests cover positive, negative, zero, padding, `scale = 0`, and `i64::MIN`. — `to_text_decimal_canonical_table`, `_padding_and_scales`, `_i64_min_boundary` (i64::MIN @ scale 0 & 2, i64::MAX @ 2)
- [x] Compiler→VM test proves `to_text(decimal(...))` through real compiled program. — `to_text_decimal_through_compiler_vm` = "123.45"
- [x] `Integer -> String` tests remain green. — P1 tests unchanged (VM 6 + compiler 4)
- [x] No Float/rounding/currency claim. — Float held (OOF-TY0); no rounding mode, no currency, no parser, no to_json change
- [x] `cargo test --test stdlib_to_text_tests` passes in both crates. — VM **10**, compiler **5**
- [x] `git diff --check` clean.

## Closing Report (2026-06-25)

**Exact formatting rules:** canonical base-10, exactly `scale` zero-padded fractional digits (never trimmed),
no exponent, no locale/grouping/currency, **no rounding** (lossless reflect of `(value, scale)`), whole-number
sign incl. `-0.xx`; `scale = 0` → no point. Integer→String unchanged.

**Edge cases tested:** `12345/2=123.45`, `1200/2=12.00` (trailing zeros kept), `5/2=0.05`, `0/2=0.00`,
`-5/2=-0.05`, `-12345/2=-123.45`, `42/0=42`, `7/4=0.0007`, `123/5=0.00123`, and the `i64::MIN` boundary
(`-9223372036854775808` @0, `-92233720368547758.08` @2) via `i128::unsigned_abs` (the only overflow hazard).

**Files changed:**
- `lang/igniter-vm/src/vm.rs` — `decimal_to_text` helper (integer/string arithmetic, no `f64`) + `Value::Decimal` case in the single `eval_math_call` `to_text` arm.
- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs` — `to_text` widened to `(Integer|Decimal)->String`; Float held.
- `lang/igniter-vm/tests/stdlib_to_text_tests.rs` (+4), `lang/igniter-compiler/tests/stdlib_to_text_tests.rs` (+1).
- `lab-docs/lang/lab-lang-decimal-to-text-p2-v0.md` — proof doc.

**Commands/counts:** VM `stdlib_to_text_tests` **10**, compiler **5**; full VM **23 ok**, full compiler **29 ok**
(version guard incl.), igniter-web `--features machine` green; `git diff --check` clean. `STDLIB_VERSION`
unchanged (coarse-milestone precedent). Lab `lang/` only — NOT canon.

**Float formatting remains HELD** — a Float arg is OOF-TY0, never silently formatted. No rounding/currency/parser claim.

**Next candidates:** `pad_left` (table columns), `Float->String` (only behind explicit rounding mode, last),
grouping/thousands separator (view-layer presentation over `to_text`, not a stdlib numeric primitive).

## Reporting

Close with:

- exact formatting rules implemented;
- edge cases tested;
- exact commands/counts;
- explicit statement that Float formatting remains held.
