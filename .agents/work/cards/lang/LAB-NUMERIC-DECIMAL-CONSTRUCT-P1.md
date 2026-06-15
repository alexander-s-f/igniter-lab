# LAB-NUMERIC-DECIMAL-CONSTRUCT-P1

**Status:** OPEN — IMPLEMENTATION
**Route:** lab / numeric / Decimal construction / dual-toolchain
**Date:** 2026-06-15
**Authority:** dual-toolchain stdlib + VM implementation authorized after the decimal-boundary policy; no implicit coercion

## Goal

Implement an explicit Decimal constructor so a pure contract can mint a `Decimal[N]`
constant — the gap classified by `LAB-NUMERIC-DECIMAL-BOUNDARY-P1`:

```igniter
decimal(value, scale) -> Decimal[scale]
-- decimal(0, 2)      : Decimal[2]
-- decimal(150, 2)    : Decimal[2]   -- 1.50 in scale-2 minor units (exact)
```

`value : Integer` (exact minor units), `scale : Integer` literal (the number of decimal
places). Result `Decimal[scale]`, scale-carrying at runtime (`Value::Decimal{value, scale}`).
This unblocks `bookkeeping` BI-P03/BK-P03: the fold seed `0.00` (Float) becomes
`decimal(0, 2)` (Decimal[2]), keeping the money path entirely in the Decimal family.

## Gate

Start after:

- `LAB-NUMERIC-DECIMAL-BOUNDARY-P1` CLOSED — policy: NO implicit Float→Decimal v0; route =
  explicit `decimal(value, scale)`.

## Scope

1. **Rust lab** typechecker: a `decimal` stdlib arm — arity 2, `value:Integer`,
   `scale:Integer literal`; result `Decimal[scale]`. Diagnostics: arity/operand-type
   (reuse an existing numeric family, e.g. OOF-TY0/OOF-DM*) — non-literal scale rejected.
2. **Rust lab** VM/stdlib: lower `decimal(value, scale)` to `Value::Decimal{value, scale}`
   (the substrate already exists in `igniter_stdlib::decimal`).
3. **Ruby canon** typechecker: mirror the `decimal` arm AND **fix the `Decimal[N]` input
   annotation crash** (`undefined method 'fetch' for <scale>:Integer`) surfaced in P1 — the
   integer scale param must be handled in `type_ir`/annotation parsing.
4. Inventory entry `stdlib.decimal.decimal` (or canonical name) + digest, ch3 wording.

## Out of scope

- Implicit `Float`/`Integer` → `Decimal` coercion (stays rejected, `OOF-TY1`).
- `round_decimal(Float, scale)` — the explicit rounding bridge (a later card).
- A `Money` type; any rounding-policy change.
- `bookkeeping` app migration (a separate app card after this lands).
- Decimal literal syntax (`0.00` stays `Float`).

## Deliverables

- Ruby + Rust compiler edits; VM/stdlib lowering; inventory + ch3.
- Proof runner: `igniter-view-engine/proofs/verify_lab_numeric_decimal_construct_p1.rb`
  (dual-toolchain, ≥70 checks): `decimal(0,2):Decimal[2]` clean dual; scale propagation;
  non-literal scale rejected; Ruby `Decimal[N]` annotation no longer crashes; implicit
  Float→Decimal still rejected (regression); VM run yields `Value::Decimal{0,2}`.
- Lab doc + card closure + portfolio index.

## Acceptance

- `decimal(0, 2)` compiles to `Decimal[2]` in both toolchains and runs to
  `Value::Decimal{value:0, scale:2}`.
- Implicit `Float/Integer → Decimal` remains rejected (no regression of the boundary).
- Ruby `Decimal[N]` input annotation no longer crashes.
- No `bookkeeping` source change in this card.

## Agent Recommendation

Give this to **Codex GPT 5.5** or **Claude Opus 4.8**. Well-bounded after the P1 boundary;
the only subtlety is the Ruby `Decimal[N]` annotation fix and scale-literal validation.
