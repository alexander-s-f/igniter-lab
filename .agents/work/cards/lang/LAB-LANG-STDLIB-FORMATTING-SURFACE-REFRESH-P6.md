# LAB-LANG-STDLIB-FORMATTING-SURFACE-REFRESH-P6

Status: CLOSED (2026-06-26)
Route: fast_lane / documentation hygiene
Skill: idd-agent-protocol

## Goal

Refresh the active language/lab surface docs after the formatting wave:

- P1 `to_text(Integer)`;
- P2 `to_text(Decimal)`;
- P3 `pad_left`;
- P4 Float readiness / held implementation.

This is a hygiene card: make front-door docs and current wave notes say the same
thing as live code, without rewriting historical proof packets.

## Current Authority

Read first:

- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs`
- `lang/igniter-vm/src/vm.rs`
- `lab-docs/lang/lab-lang-number-to-text-p1-v0.md`
- `lab-docs/lang/lab-lang-decimal-to-text-p2-v0.md`
- `lab-docs/lang/lab-lang-string-pad-left-p3-v0.md`
- `lab-docs/lang/lab-lang-float-to-text-readiness-p4-v0.md`
- `lab-docs/lang/current-waves-index.md`
- any active `IMPLEMENTED_SURFACE.md` / front-door language status doc if one
  exists in this repo

Live code wins over old docs.

## Task

Update only active front-door/current docs so agents stop rediscovering:

- `to_text` is exact-only: `Integer | Decimal -> String`;
- `Float` is still held and should route through P5 policy and a separate
  implementation card only after that policy;
- `pad_left` exists and is rune-counted;
- `pad_left(to_text(x), width, pad)` is the intended report/table composition.

## Closed Surfaces

- No code changes.
- No edits to old proof packets unless they are explicitly active front doors.
- No Float implementation.
- No canon claim.

## Acceptance

- [x] Active current-wave/front-door docs mention `to_text(Integer|Decimal)`.
- [x] Active docs mention `pad_left` and rune-counting.
- [x] Active docs state `Float` remains held pending policy/implementation.
- [x] Historical docs are left alone or explicitly marked superseded only when
      they are active front doors.
- [x] `git diff --check` clean.

## Reporting

Close with:

- exact docs touched;
- stale claims removed;
- remaining open formatting surfaces.

## Closing Report (2026-06-26)

Status: formatting surface refresh complete.

Docs touched:

- `lang/igniter-vm/IMPLEMENTED_SURFACE.md`
  - refreshed the surface note to 2026-06-26;
  - added `to_text(Integer|Decimal) -> String` as the exact current text conversion surface;
  - added `pad_left(String,Integer,String) -> String` as a rune-counted table primitive;
  - stated explicitly that `Float` remains held and must route through explicit `float_to_text(...)`
    policy/implementation rather than `to_text(Float)`.
- `lab-docs/lang/current-waves-index.md`
  - moved the current formatting wave into the Stdlib science/front-door row;
  - routed report/table payoff through `pad_left(to_text(x), width, pad)`;
  - kept Float formatting in readiness/policy, not implemented.
- `LAB-LANG-STDLIB-FORMATTING-SURFACE-REFRESH-P6.md`
  - closed this card and marked acceptance.

Stale claims removed:

- Active front doors no longer route agents to `LAB-LANG-NUMBER-TO-TEXT-P1` as if only Integer text exists;
  they now state the current exact surface is `Integer|Decimal`.
- Active docs no longer omit `pad_left` or its rune-counting rule.
- Active docs no longer leave Float as a vague future; they point to explicit `float_to_text` policy and a
  separate implementation path.

Historical docs left alone:

- P1/P2/P3/P4/P5 proof packets/cards are historical evidence and already carry their own scoped status; they
  were not rewritten.

Remaining open formatting surfaces:

- `float_to_text(x:Float, decimals:Integer, rounding:String)` implementation after P4/P5 policy.
- No implicit `to_text(Float)`.
- No broad formatter, locale/currency/grouping, exponent/scientific notation, `pad_right`/center, or
  display-width/cell-width policy.
- No `float_to_decimal` quantization helper until literal-scale `Decimal[N]` design is explicit.

Verification:

- Live source grep checked `to_text`, `pad_left`, and Float rejection anchors in
  `lang/igniter-compiler/src/typechecker/stdlib_calls.rs` and `lang/igniter-vm/src/vm.rs`.
- Current front-door grep checked `lab-docs/lang/current-waves-index.md` and
  `lang/igniter-vm/IMPLEMENTED_SURFACE.md`.
- `git diff --check` clean.
