# lab-lang-number-to-text-p1-v0

Card: `LAB-LANG-NUMBER-TO-TEXT-P1`
Route: standard / language DX proof · Skill: idd-agent-protocol
Status: implemented (`to_text : (Integer) -> String`) · Float/Decimal held · no canon claim
Date: 2026-06-25
Builds on: P18 typed-rows→HTML (`meta.count` could not render — the gap this closes) · the `to_float` precedent (LAB-STDLIB-NUMERIC-TO-FLOAT-P8)

> **Authority boundary.** Lab language surface (igniter-lab `lang/` — the lab's own compiler/VM, NOT canon
> igniter-lang). A narrow, total Integer→String builtin mirroring the existing `to_float`; no formatting
> library, no locale, no implicit coercion; **no canon claim.**

---

## Chosen name / signature

```text
to_text(n : Integer) -> String          -- bare alias
stdlib.string.to_text(n : Integer) -> String   -- namespaced form (same single source)
```

`to_text(3)` → `"3"`, `to_text(-7)` → `"-7"`, `to_text(0)` → `"0"`. Base-10, no grouping/padding/sign-pad.
Usable bare (like `concat`/`count`/`to_float`) or namespaced. The DatasetMeta.count use case is
`concat("Count: ", to_text(meta.count))` → `"Count: 3"`.

## Why Integer first

P18 left exactly one gap for typed-rows→HTML UX: `DatasetMeta.count` (Integer) could not land in an escaped
text leaf because `.ig` had no number→text builtin (P18 doc §"How DatasetMeta is used"). `Integer` is the
immediate, total, deterministic case (no precision/format ambiguity), so it is the smallest surface that
unblocks count badges / numeric labels. `Float`/`Decimal` are **held** (below).

## Live wiring (verify-first answers)

1. **Numeric types crossing the VM boundary:** `Integer(i64)`, `Float(f64)`, `Decimal{value:i64, scale:u32}`
   (`lang/igniter-vm/src/value.rs`).
2. **Needed immediately:** `Integer -> String` (P18 `meta.count`). Done.
3. **Pre-existing `to_string`/`format`/`int_to_string`?** None — grep over `lang/igniter-compiler/src` +
   `lang/igniter-vm/src` found no number→string builtin (only Rust-internal `.to_string()`). `to_float` is the
   only numeric *conversion* builtin and was the template.
4. **Where it lives:** the same **single semantic source** `eval_math_call` (`vm.rs:3400`) that `to_float`
   uses — shared by the bytecode `OP_CALL` path (gate list `vm.rs:~2079`) and the `eval_ast`/HOF path
   (`vm.rs:~5731`), so the two execution paths stay byte-identical (the P10 parity invariant). The typechecker
   arm lives beside the string builtins in `typechecker/stdlib_calls.rs` (resolves to `String`, `OOF-TY0`),
   matching `char_at`'s shape. Named `stdlib.string.to_text` (output is a String) + bare `to_text`.
5. **Determinism:** Rust `i64::to_string` is total, base-10, no locale — **identical bits on every target**
   (integer-only; no `f64`/IEEE surface, unlike `to_float` whose large-int rounding is documented). Replay-safe:
   pure function of its argument, no clock/state.

## Determinism story

`to_text` is a pure total function: every `i64` (incl. `i64::MIN`/`i64::MAX`) maps to its exact base-10 string
with no rounding, no locale, no platform variance. This is *stronger* than `to_float` (which rounds beyond the
53-bit mantissa) — integers are exact across the full range. Tested: `to_text(i64::MAX) == "9223372036854775807"`,
`to_text((1<<53)+1) == "9007199254740993"` (the value `to_float` would round).

## Rejected alternatives

| Option | Why rejected |
| --- | --- |
| General `format(value, spec)` / formatting library | Out of scope (card "Closed"); locale/precision/padding explosion. v0 is one total function. |
| `Float`/`Decimal -> String` now | Held: Float formatting has rounding/precision/locale ambiguity (non-deterministic surface area); Decimal needs an exact-string decision. A non-Integer arg is rejected (`OOF-TY0`), not silently formatted. Named follow-on. |
| New `stdlib.number.*` namespace | No `stdlib.number` namespace exists; output is a String, so `stdlib.string.to_text` is discoverable and consistent with the existing string builtins. |
| A separate dispatch surface (not `eval_math_call`) | Would re-introduce the OP_CALL ↔ eval_ast parity risk the single-source design exists to prevent. |
| Implicit Integer→String coercion in `concat` | Card "Closed: no implicit numeric coercion"; explicit `to_text` keeps the boundary visible. |
| Bump `STDLIB_VERSION` 0.1.7→0.1.8 | NOT bumped — consistent with the precedent that `to_float`/`char_at`/`isqrt` and the other incremental P7/P8 stdlib builtins all coexist at `0.1.7` (the version marks coarse milestones, not per-builtin). The `stdlib_version_mirrors_crate` guard stays green (const = crate). A formal surface-version cut is orthogonal hygiene. |

## What remains held

- `Float -> String`, `Decimal -> String` (formatting/precision/locale decisions);
- padding, grouping, width, sign control, radix;
- any localization/timezone.

A non-Integer argument (Float, String, …) is an `OOF-TY0` type error — the held cases fail closed, never
silently format.

## Tests / counts

**`lang/igniter-vm/tests/stdlib_to_text_tests.rs` (6):** basic/zero/negative; exact across i64 range
(`MAX`/`MIN`/`2^53+1`); namespaced alias; arity + non-Integer (Float, String) errors; `to_text(42)` through
the real compiler→VM = `"42"`; `concat("Count: ", to_text(3))` = `"Count: 3"` (the DatasetMeta.count render).

**`lang/igniter-compiler/tests/stdlib_to_text_tests.rs` (4):** valid `to_text(Integer)->String` (assigned to a
String compute + fed to `concat`) compiles clean; wrong arity → `OOF-TY0`; non-Integer (String) arg →
`OOF-TY0`; Float arg → `OOF-TY0` (held). Runs the real `igniter_compiler` binary.

**Regression (green):** VM full suite (23 ok-blocks, incl. `stdlib_to_float`/`stdlib_statistics`); compiler
full suite (29 ok-blocks, incl. `stdlib_math`, `stdlib_math_intmod`, and **`stdlib_version_mirrors_crate`**);
igniter-web `--features machine` green (downstream path-dep recompile). `git diff --check` clean.

```bash
# from lang/igniter-vm
cargo test --test stdlib_to_text_tests        # 6 passed
cargo test                                    # full VM suite green
# from lang/igniter-compiler
cargo test --test stdlib_to_text_tests        # 4 passed
cargo test                                    # full compiler suite green (version guard incl.)
```

## Files changed

| File | Change |
| --- | --- |
| `lang/igniter-vm/src/vm.rs` | `to_text` arm in `eval_math_call` (Integer→String, exact base-10) + the name in the `OP_CALL` gate list. |
| `lang/igniter-compiler/src/typechecker/stdlib_calls.rs` | `to_text` typecheck arm — `(Integer)->String`, `OOF-TY0` on arity / non-Integer. |
| `lang/igniter-vm/tests/stdlib_to_text_tests.rs` *(new)* | 6 runtime/parity tests. |
| `lang/igniter-compiler/tests/stdlib_to_text_tests.rs` *(new)* | 4 typecheck tests. |

`STDLIB_VERSION` deliberately unchanged (see rejected alternatives).

## Reporting

- **Exact function + examples:** `to_text(n : Integer) -> String` (bare or `stdlib.string.to_text`).
  `to_text(3) == "3"`, `to_text(-7) == "-7"`, `concat("Count: ", to_text(3)) == "Count: 3"`.
- **What remains held:** Float/Decimal→String, all formatting/locale/padding. Non-Integer args fail closed
  (`OOF-TY0`).
- **Should Todo typed HTML adopt it immediately?** Yes, low-risk — a `MakeLabel(concat("…", to_text(meta.count)))`
  count badge (or a `MakeLabel` showing total) drops straight into the P18/P19 typed-HTML continuation with no
  new primitive. Left to the next product card so this language card stays narrow and the shared
  `typed_html.ig` fixture (P19-owned) is not cross-edited here.

## Next formatting candidates (if pressure appears)

- `to_text(Decimal) -> String` (exact string from `{value,scale}` — deterministic, the natural next step and a
  prerequisite for money/report labels);
- a bounded `pad_left(s : String, width : Integer, fill : String)` for table columns (string-only, still no
  locale);
- `Float -> String` only behind an explicit, documented rounding mode (last, highest-ambiguity).
