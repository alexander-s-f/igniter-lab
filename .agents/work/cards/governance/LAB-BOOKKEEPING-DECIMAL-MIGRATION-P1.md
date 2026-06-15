# LAB-BOOKKEEPING-DECIMAL-MIGRATION-P1

**Status:** OPEN - APP MIGRATION
**Route:** lab / app pressure / bookkeeping / Decimal constructor
**Date:** 2026-06-15
**Authority:** app migration after explicit Decimal constructor lands; no compiler or VM changes

## Goal

Migrate `bookkeeping` from Float seeds/literals to explicit `decimal(value, scale)` so
its money path stays entirely in the `Decimal[N]` family.

Primary target: replace fold seed / constants like `0.00` that currently infer `Float`
and cause `Output type mismatch: expected Decimal[2], got Float`.

## Gate

Start after:

- `LAB-NUMERIC-DECIMAL-CONSTRUCT-P1` CLOSED.
- `LAB-NUMERIC-DECIMAL-BOUNDARY-P1` CLOSED — implicit Float/Integer -> Decimal remains rejected.

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-NUMERIC-DECIMAL-CONSTRUCT-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/lang/lab-numeric-decimal-boundary-p1-v0.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/bookkeeping/PRESSURE_REGISTRY.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/bookkeeping/`

## Work

1. Locate every Float literal used as money/Decimal seed or expected Decimal output input.
2. Replace only Decimal-intended literals with `decimal(minor_units, scale)`.
3. Keep non-money Float calculations as Float.
4. Compile with Ruby and Rust.
5. Run VM entry if the app has a zero-input/demo entry; otherwise record compile-level resolution and route demo-entry separately.
6. Update pressure registry and source hash.

## Deliverables

- Minimal app source edits under `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/bookkeeping/`.
- Proof runner: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_bookkeeping_decimal_migration_p1.rb`, target at least 70 checks.
- Lab doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/governance/lab-bookkeeping-decimal-migration-p1-v0.md`.
- Update this card, app pressure registry, and portfolio index.

## Acceptance

- The previous Float -> Decimal output mismatch is gone.
- No implicit coercion is introduced or relied upon.
- `decimal(0, 2)` / related constants are used only where Decimal is semantically intended.
- Ruby and Rust compile results are documented.
- Runtime result, if runnable, preserves `Decimal[2]` scale.

## Closed Surfaces

- No compiler/VM changes.
- No rounding policy changes.
- No Money type.
- No broad bookkeeping refactor.
- No replacement of legitimate Float domain quantities.

## Agent Recommendation

Give this to **Sonnet 4.6** or **Codex GPT 5.5** after Decimal construct closes.
