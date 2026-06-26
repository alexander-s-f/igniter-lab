# LAB-LANG-FLOAT-TO-TEXT-READINESS-P4

Status: CLOSED (readiness packet delivered 2026-06-26)
Route: standard / language stdlib readiness
Skill: idd-agent-protocol

## Closing report (2026-06-26)

Packet: `lab-docs/lang/lab-lang-float-to-text-readiness-p4-v0.md`.

**Core finding:** Float is the only number→text case that is *lossy*, so it must be a **distinct
contract-bearing function**, never an overload of the exact `to_text` (P1 Integer `i64::to_string`,
`vm.rs:3704-3718`; P2 Decimal exact/no-rounding). Float needs mandatory precision + rounding + non-finite
policy.

**Recommended signature:** `float_to_text(x:Float, decimals:Integer, rounding:String) -> String` (bare +
`stdlib.string.*`, single `eval_math_call` arm — the P1 pattern). Principled fast-follow:
`float_to_decimal(x, decimals, rounding) -> Decimal[decimals]` **only when `decimals` is literal/static**
(otherwise bare `Decimal` or reject; no dependent typing claim). The lossy step → a reusable EXACT Decimal;
text reuses P2's `to_text(Decimal)`. Rejected `to_text_float` (awkward) + options-record (premature).

**Rounding:** v0 = ONE mode `"half_even"` — unbiased over many roundings (science/report sums), and Rust std
`{:.N}` is **already correctly-rounded ties-to-even + integer-based** (cross-arch deterministic, no libm) → so
half_even is both principled AND cheapest-correct. Other modes → OOF-reject, reserved.

**Non-finite:** NaN/±Inf → **deterministic domain error, NOT a string** (a "NaN" cell is a silent data-quality
failure; aligns with det-math error posture `vm.rs:3397-3421`; Decimal can't hold non-finite either → one
rule).

**Exponent:** none in v0 (fixed-point only; scientific notation a separate held future surface — science uses
fixed `{:.16}` in `experiment.rs`).

**Determinism boundary (honest):** the formatter does NOT add nondeterminism (pure integer algorithm on f64
bits) but INHERITS it — output is only as deterministic as the input f64 (det-math wave's job). A public
cross-arch claim needs explicit x86_64+aarch64 byte-identity evidence; **no canon determinism-claim upgrade.**

**Next card:** `LAB-LANG-FLOAT-TO-TEXT-P5` (impl; surface A first — self-contained via std `{:.N}`, no P2
dep; D after P2 Decimal→text lands). Test matrix in packet §7 (typecheck arity/type/unknown-mode reject +
Integer/Decimal regression; VM exact values incl. **half-even tie cases**; non-finite reject; decimals-bound;
negative-zero policy; no-exponent; compiler→VM e2e; gated cross-arch determinism). Unknown literal rounding
should compile-reject; dynamic rounding must runtime-reject fail-closed.

**Boundary honored.** Design only — no implementation, no implicit `to_text(Float)`, no locale/currency, no
change to `experiment.rs`, no canon claim. `git diff --check` clean.

> **Scope note:** working tree also carries the team's in-flight **P2 Decimal→text** implementation
> (`lang/igniter-{compiler,vm}/{src,tests}` `to_text` files) — NOT mine. My only change is the packet doc.

## Goal

Design the explicit Float -> String formatting surface without implementing it
yet.

This must **not** be a casual `f64.to_string()` addition. Float formatting affects
determinism, reports, science output, and replay claims. It needs an explicit
rounding/precision contract.

## Current Authority

Read first:

- `lang/igniter-vm/src/vm.rs` math/string stdlib calls;
- `lang/igniter-vm/src/experiment.rs` host-side science CSV formatting, as a
  pressure source but not language authority;
- Decimal/Integer string cards:
  - `LAB-LANG-NUMBER-TO-TEXT-P1`
  - `LAB-LANG-DECIMAL-TO-TEXT-P2` if implemented by the time this card runs;
- emergence determinism docs only as evidence, not canon authority.

Live code wins over docs.

## Questions To Answer

1. What is the minimal Float formatting surface?
   - `float_to_text(x, decimals, mode)`?
   - `to_text_float(x, decimals, mode)`?
   - a record/options argument?
2. Which rounding modes are allowed in v0?
   - likely one explicit mode first, e.g. `HalfEven` or `HalfAwayFromZero`;
   - name the reason and deterministic implementation requirement.
3. How are non-finite values handled?
   - reject as domain error?
   - `"NaN"`/`"Infinity"` strings?
   - align with existing science/domain-error rules.
4. Does v0 allow exponent notation?
   - likely no for reports; maybe separate future scientific notation.
5. How does this interact with deterministic math claims?
   - formatting should be deterministic on fixed toolchain;
   - cross-arch claim requires explicit evidence if used in public science.
6. What tests would prove enough for implementation?

## Bias / Recommendation To Pressure-Test

Recommended likely v0:

```ig
float_to_text(x: Float, decimals: Integer, rounding: String) -> String
```

with only one accepted rounding string in v0, no exponent notation, non-finite
rejected, and `decimals` bounded.

But this card should verify whether a smaller or cleaner surface exists before
implementation.

## Closed Surfaces

- No implementation in this readiness card.
- No implicit `to_text(Float)`.
- No locale/currency/grouping.
- No changing host-side experiment output.
- No canon determinism claim upgrade.

## Acceptance

- [x] At least three surface alternatives compared.
- [x] Rounding policy recommended and justified.
- [x] Non-finite policy recommended.
- [x] Determinism/replay boundary stated honestly.
- [x] Implementation card named with concrete acceptance tests.
- [x] No production code changes.
- [x] `git diff --check` clean.

## Reporting

Close with:

- recommended function signature;
- exact held surfaces;
- test matrix for the future implementation card.
