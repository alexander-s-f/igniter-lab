# lab-lang-decimal-to-text-p2-v0

Card: `LAB-LANG-DECIMAL-TO-TEXT-P2`
Route: standard / language stdlib implementation · Skill: idd-agent-protocol
Status: implemented (`to_text` extended to exact `Decimal -> String`) · Float still held · no canon claim
Date: 2026-06-25
Builds on: P1 `LAB-LANG-NUMBER-TO-TEXT` (Integer→String) · the live `Value::Decimal`/`decimal(v,s)` surface

> **Authority boundary.** Lab language surface (igniter-lab `lang/` — the lab's own compiler/VM, NOT canon
> igniter-lang). Extends the P1 `to_text` builtin to `Decimal`; no Float formatting, no rounding modes, no
> currency, no Decimal parser, no `Value::to_json` change; **no canon claim.**

---

## Headline

`to_text` now accepts `Decimal` as well as `Integer`, producing an **exact, canonical base-10 string** for the
live `Value::Decimal { value: i64, scale: u32 }` — for money / report / table output. Integer→String is
unchanged; **Float stays held** (a Float arg is `OOF-TY0`). One new VM helper (`decimal_to_text`, integer/string
arithmetic only — no `f64`), one widened typechecker arm, both on the same single `eval_math_call` source.

---

## Exact formatting rules implemented

`to_text(decimal(value, scale))` → canonical decimal text:

| value | scale | text | rule shown |
| ---: | ---: | --- | --- |
| `12345` | 2 | `123.45` | split integer/fraction at `scale` |
| `1200` | 2 | `12.00` | **no trailing-zero trimming** |
| `5` | 2 | `0.05` | leading `0` integer digit + zero-padded fraction |
| `0` | 2 | `0.00` | zero |
| `-5` | 2 | `-0.05` | sign on the whole, including `-0.xx` |
| `-12345` | 2 | `-123.45` | negative |
| `42` | 0 | `42` | `scale = 0` → no decimal point |

- exactly `scale` fractional digits, zero-padded, never trimmed;
- never exponent notation; never locale/grouping/currency;
- **no rounding** — a lossless reflection of the stored `(value, scale)`;
- the sign applies to the whole number;
- `Integer -> String` behaviour unchanged; `Float -> String` rejected/held.

## Implementation

The minimal path the card predicted:

- **VM** (`lang/igniter-vm/src/vm.rs`): the single `to_text` arm in `eval_math_call` now matches
  `Value::Decimal { value, scale }` → `decimal_to_text(value, scale)`. New module-level helper:

  ```rust
  fn decimal_to_text(value: i64, scale: u32) -> String {
      let neg = value < 0;
      let mut digits = (value as i128).unsigned_abs().to_string(); // i128 magnitude — safe for i64::MIN
      let s = scale as usize;
      let body = if s == 0 { digits } else {
          while digits.len() <= s { digits.insert(0, '0'); }       // ≥1 integer digit
          let split = digits.len() - s;
          format!("{}.{}", &digits[..split], &digits[split..])
      };
      if neg { format!("-{body}") } else { body }
  }
  ```

  Both VM execution paths (bytecode `OP_CALL`, `eval_ast`/HOF) route through `eval_math_call`, so the new arm
  is byte-identical on both — no parity surface added. `Value::to_json` is untouched.
- **Typechecker** (`lang/igniter-compiler/src/typechecker/stdlib_calls.rs`): the `to_text` arm accepts
  `arg_name == "Integer" || arg_name == "Decimal" || arg_name == "Unknown"`; anything else (Float, String, …)
  is `OOF-TY0` "argument must be Integer or Decimal". A bare `Decimal` value names `"Decimal"` (scale lives in
  `params`), the same convention the Decimal `+`/`-` arm relies on (`stdlib_calls.rs:144`).

## Determinism / `i64::MIN` story

Integer/string arithmetic only — **no `f64`**, so the result is exact and identical on every target.
`i64::MIN` is the documented boundary: a plain `i64::abs()` overflows, so the magnitude is taken as
`(value as i128).unsigned_abs()` (u128). Tested exact:

- `to_text(decimal(i64::MIN, 0)) == "-9223372036854775808"`;
- `to_text(decimal(i64::MIN, 2)) == "-92233720368547758.08"`;
- `to_text(decimal(i64::MAX, 2)) == "92233720368547758.07"`.

No rounding occurs anywhere; the stored integer and scale are reflected verbatim.

## Edge cases tested

positive (`123.45`), negative (`-123.45`, `-0.05`, `-0.001`), zero (`0.00`), trailing zeros kept (`12.00`,
`1.00`), all-fraction zero-pad (`0.05`, `0.0007`, `0.00123`), `scale = 0` (`42`), and the `i64::MIN`/`i64::MAX`
magnitude boundary at scale 0 and 2.

## Tests / counts

**`lang/igniter-vm/tests/stdlib_to_text_tests.rs` (10 = 6 P1 + 4 P2):** P2 adds the canonical table,
padding/scales, the `i64::MIN`/`MAX` boundary, and `to_text(decimal(12345, 2))` → `"123.45"` through the real
compiler→VM (`decimal(...)` constructs `Value::Decimal`, then `to_text`).

**`lang/igniter-compiler/tests/stdlib_to_text_tests.rs` (5 = 4 P1 + 1 P2):** P2 adds
`to_text(decimal(12345, 2))` assigned to `String` compiles clean; the P1 Float-held / arity / non-numeric
rejections are unchanged and green.

**Regression (green):** VM full suite (23 ok-blocks, incl. `stdlib_to_float`, Decimal arithmetic); compiler
full suite (29 ok-blocks, incl. the Decimal construct/boundary tests and **`stdlib_version_mirrors_crate`**);
igniter-web `--features machine` green (downstream path-dep recompile). `git diff --check` clean.

```bash
# from lang/igniter-vm
cargo test --test stdlib_to_text_tests        # 10 passed
cargo test                                    # full VM suite green
# from lang/igniter-compiler
cargo test --test stdlib_to_text_tests        # 5 passed
cargo test                                    # full compiler suite green (version guard incl.)
```

`STDLIB_VERSION` again deliberately unchanged (same coarse-milestone rationale as P1; the guard stays green).

## Files changed

| File | Change |
| --- | --- |
| `lang/igniter-vm/src/vm.rs` | `decimal_to_text` helper + `Value::Decimal` case in the `to_text` arm of `eval_math_call`. |
| `lang/igniter-compiler/src/typechecker/stdlib_calls.rs` | `to_text` arm widened to `(Integer\|Decimal)->String`; Float held. |
| `lang/igniter-vm/tests/stdlib_to_text_tests.rs` | +4 Decimal tests (table, padding, boundary, compiler→VM). |
| `lang/igniter-compiler/tests/stdlib_to_text_tests.rs` | +1 valid-Decimal typecheck test; headers updated. |

## Reporting

- **Exact formatting rules:** canonical base-10, exactly `scale` fractional digits (zero-padded, never
  trimmed), no exponent, no locale/grouping/currency, no rounding, whole-number sign incl. `-0.xx`; `scale = 0`
  → no point. Integer behaviour unchanged.
- **Edge cases tested:** positive/negative/zero, trailing zeros, all-fraction padding, `scale = 0`, and the
  `i64::MIN`/`i64::MAX` magnitude boundary (via `i128`, the only overflow hazard).
- **Float formatting remains HELD.** A Float argument is rejected (`OOF-TY0`), not silently formatted; no
  rounding mode, no currency, no Decimal parser, no `to_json` change were added or implied.
- **Adoption:** `to_text(Decimal)` is ready for money/report labels in the typed-HTML view layer (e.g. a price
  badge) exactly like the P1 count badge — left to the next product card so this language card stays narrow.

## Next formatting candidates (only if pressure appears)

- bounded `pad_left(s : String, width : Integer, fill : String)` for table-column alignment (string-only, no
  locale);
- `Float -> String` strictly behind an explicit, documented rounding mode (last — highest ambiguity);
- a grouping/thousands separator helper would be a *presentation* concern (likely a view-layer helper over
  `to_text`, not a stdlib numeric primitive).
