# LAB-LANG-STDLIB-FORMATTING-COMPLETION-P8

Status: CLOSED (2026-06-26)
Route: fast_lane / documentation hygiene
Skill: idd-agent-protocol

## Goal

After `LAB-LANG-FLOAT-TO-TEXT-IMPL-P7` lands, crystallize the formatting
surface so agents have one current answer to:

> What text/report formatting exists today?

This is a post-implementation hygiene card. It should not invent behavior; it
only reconciles front-door docs, current waves, and proof packets with live code.

## Current Authority

Read first:

- `.agents/work/cards/lang/LAB-LANG-FLOAT-TO-TEXT-IMPL-P7.md`
- the P7 closing report and proof doc, if created;
- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs`
- `lang/igniter-vm/src/vm.rs`
- `lang/igniter-vm/IMPLEMENTED_SURFACE.md`
- `lab-docs/lang/current-waves-index.md`
- P1/P2/P3/P5 formatting proof packets for historical context only.

Live code wins. Historical packets are evidence, not current surface authority.

## Task

Update the active front-door/current docs to state the whole formatting slice:

- `to_text(Integer) -> String`;
- `to_text(Decimal[N]) -> String` or the exact current Decimal surface shape;
- `pad_left(String,Integer,String) -> String`, rune-counted;
- `float_to_text(Float,Integer,String) -> String`, explicit only;
- no implicit `to_text(Float)`;
- no locale/currency/grouping/exponent;
- no broad formatter or `float_to_decimal`.

If P7 lands with any explicit deferral, name it plainly instead of smoothing it
over.

## Closed Surfaces

- No implementation changes unless the docs expose a tiny missed test-only
  typo from P7; otherwise stop and report.
- No historical proof packet rewrites, except adding a short superseded/current
  pointer if an active front door still routes agents through a stale claim.
- No canon claim.
- No new formatting features.

## Acceptance

- [x] `IMPLEMENTED_SURFACE.md` names all live formatting primitives and held
      surfaces.
- [x] `current-waves-index.md` routes future report/table work to the live
      primitives, not old gaps.
- [x] The docs explicitly say `Float` is available only through
      `float_to_text(...)`, not `to_text(Float)`.
- [x] The docs explicitly name the current unsupported surfaces:
      locale/currency/grouping/exponent, additional rounding modes,
      `float_to_decimal`, broad formatter.
- [x] Any stale claim like "Float formatting held/missing" is removed or
      replaced with the new P7 status.
- [x] `git diff --check` clean.

## Closing Report

Docs touched:

- `lang/igniter-vm/IMPLEMENTED_SURFACE.md`
- `lab-docs/lang/current-waves-index.md`
- `.agents/work/cards/lang/LAB-LANG-STDLIB-FORMATTING-COMPLETION-P8.md`

Stale claims removed:

- Active front doors no longer route Float formatting through the pre-P7
  implementation gap.
- The old P4/P5 readiness/policy shape remains historical evidence only; current
  live surface now points to the P7 implementation proof.
- The no-implicit-Float boundary is preserved: `to_text(Float)` remains rejected.

Final formatting surface:

| Primitive | Current surface |
| --- | --- |
| `to_text(Integer) -> String` | Exact base-10 integer text; no grouping, locale, currency, or rounding. |
| `to_text(Decimal) -> String` | Exact `Decimal { value, scale }` fixed decimal text with exactly `scale` fractional digits. |
| `float_to_text(Float, Integer, String) -> String` | Explicit fixed-point Float text; `"half_even"` only; finite Float only; decimals `0..=17`; negative rounded zero normalized; no exponent form. |
| `pad_left(String, Integer, String) -> String` | Rune-counted table primitive; compose explicitly with text conversion for reports. |

Remaining open surfaces:

- No implicit `to_text(Float)`.
- No locale/currency/grouping/exponent/scientific notation.
- No broad formatter.
- No additional rounding modes.
- No `float_to_decimal`.
- No `pad_right`/center/display-width policy.

Known next-card routes:

- `LAB-TODOAPP-VIEW-MONEY-REPORT-P20`
- `LAB-LANG-FLOAT-TO-DECIMAL-READINESS-P*`
- `LAB-LANG-STRING-PAD-RIGHT-READINESS-P*`

Verification:

- Read P7 card and proof doc before updating current docs.
- Source-grepped compiler/VM/test anchors for `to_text`, `float_to_text`, and
  `pad_left`.
- `git diff --check` passed on 2026-06-26.

## Reporting

Close with:

- exact docs touched;
- stale claims removed;
- final formatting surface table;
- remaining open surfaces and their next-card names if known.

## Why This Card Exists

This is the anti-archaeology step. P7 makes the behavior real; P8 makes it
discoverable. Do not leave future agents to infer "implemented or not?" from
old readiness packets.
