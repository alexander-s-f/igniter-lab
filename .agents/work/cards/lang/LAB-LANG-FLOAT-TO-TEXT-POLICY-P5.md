# LAB-LANG-FLOAT-TO-TEXT-POLICY-P5

Status: CLOSED (policy packet delivered 2026-06-26)
Route: standard / language stdlib policy
Skill: idd-agent-protocol

## Closing report (2026-06-26)

Packet: `lab-docs/lang/lab-lang-float-to-text-policy-p5-v0.md`. **Rust facts verified locally (rustc 1.95.0
probe `/tmp/fmt_probe.rs`), not memory.**

**Policy table:**
1. **Negative zero → normalize:** any output whose rounded magnitude is zero emits *unsigned* zero
   (`-0.0`→`"0.00"`, `-0.001`→`"0.00"`, `-0.4`→`"0"`). Std *preserves* the sign (verified) → `"-0.00"` is a
   report wart (breaks naive equality/diff); a zero magnitude's sign is unrecoverable to a reader; science
   needing the IEEE sign uses a value-level predicate, not the display string.
2. **Rounding validation:** literal ≠ `"half_even"` → compile-reject (`OOF-TY0`); dynamic `String` →
   deterministic runtime-reject **before** output; one stable message `float_to_text: unsupported rounding
   mode "<x>"; v0 supports only "half_even"`.
3. **Decimal bound `0..=17`:** 17 = f64 round-trip guarantee, covers science `{:.16}`; beyond 17 = binary
   noise (verified `0.1` at `.20`→`0.10000000000000000555`).
4. **Impl route: direct `format!("{:.*}", decimals, x)` + post-processing** (validate mode/finite/bound →
   format → strip sign if all-zero). Std `{:.N}` verified correctly-rounded half-even + integer-based
   (cross-arch deterministic) → no custom rounding. **Defer** `float_to_decimal` (needs literal-scale typed
   `Decimal[N]`; `float_to_text` is its foundation).

**Verified facts:** half-even confirmed (`0.5`→`0`, `2.5`→`2`, `0.125`→`0.12`, `0.375`→`0.38`); std preserves
zero-sign (`-0.001`→`"-0.00"`); no exponent (`1e20`→`100000000000000000000.00`); f64-reality (`2.675`→`"2.67"`,
`1.005`→`"1.00"` — f64 below the literal, correct, the reason exact-money uses Decimal).

**Future implementation card:** `LAB-LANG-FLOAT-TO-TEXT-IMPL-P7` (surface `float_to_text(x:Float, decimals:
Integer, rounding:String) -> String`; acceptance matrix in packet §5 — typecheck arity/type/literal-mode +
Integer/Decimal regression; VM exact values incl. pinned half-even ties + normalized negative-zero +
f64-reality + non-finite reject + dynamic-mode reject + bound + no-exponent; compiler→VM e2e; determinism
regression pinning exact strings).

**Held surfaces:** implicit `to_text(Float)`; any mode but `half_even`; exponent/scientific; locale/currency/
grouping; non-finite-as-string; `float_to_decimal` (until literal-scale `Decimal[N]`); canon determinism
upgrade; `experiment.rs` changes.

**Boundary honored.** Policy only — no code. `git diff --check` clean; probe under `/tmp` (uncommitted).

## Goal

Resolve the last policy questions before any Float->String implementation:

- negative zero output;
- dynamic vs literal rounding validation;
- decimal precision bound;
- whether P5 implementation should use std `format!("{:.*}")` directly or a
  shared quantization helper.

This is a policy/decision card, **not implementation**.

## Current Authority

Read first:

- `.agents/work/cards/lang/LAB-LANG-FLOAT-TO-TEXT-READINESS-P4.md`
- `lab-docs/lang/lab-lang-float-to-text-readiness-p4-v0.md`
- `lang/igniter-vm/src/vm.rs`
- `lang/igniter-vm/src/experiment.rs` for pressure only, not authority

Verify Rust's current formatting behavior locally if needed; do not rely only
on memory.

## Questions To Decide

1. Negative zero:
   - preserve std behavior (`-0`) as sign-faithful fixed-point output?
   - normalize all rounded zero outputs to `0`/`0.00`?
   - recommendation must name report/science tradeoff.
2. Dynamic rounding:
   - literal `"half_even"` can be compile-rejected if unknown;
   - dynamic `rounding : String` must runtime-reject unsupported modes.
   Decide exact diagnostic/runtime error wording expectations.
3. Decimal bound:
   - choose max decimals for v0 (likely `0..=17`, but verify);
   - explain why.
4. Implementation route:
   - direct `format!("{:.*}", decimals, x)`;
   - custom helper around std formatting plus post-processing;
   - shared `float_to_decimal` quantization helper held until literal-scale
     typed Decimal is designed.

## Closed Surfaces

- No code changes.
- No implementation card edits unless adding a "next card" section.
- No implicit `to_text(Float)`.
- No locale/currency/grouping/exponent.
- No canon determinism claim.

## Acceptance

- [x] Local Rust formatting facts are verified for half-even ties and negative zero.
- [x] Negative-zero policy is chosen.
- [x] Runtime behavior for dynamic unsupported rounding is specified.
- [x] Decimal bound is chosen and justified.
- [x] Implementation route is selected.
- [x] Follow-up implementation card name and acceptance matrix are provided.
- [x] No production code changes.
- [x] `git diff --check` clean.

## Reporting

Close with:

- the policy table;
- the future implementation card name;
- exact local facts used (commands/snippets OK);
- explicit held surfaces.
