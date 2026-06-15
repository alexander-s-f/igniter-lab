# LAB-BOOKKEEPING-DECIMAL-MIGRATION-P1

**Status:** CLOSED (PARTIAL) — RUST RESOLVED + VM DECIMAL[2] / RUBY NUMERIC-PARITY + SUM RESIDUALS PINNED (2026-06-15)
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

---

## Closure Summary — CLOSED (PARTIAL) 2026-06-15

**Migrated source hash (dual, 3-file):** `sha256:025731179a24c15fda2109170ed69ae5231e3d3226beb0f58b815f0a1c6c830f`
(Rust and Ruby agree.)

Single app-only edit in `ledger.ig` / `ComputeAccountBalance`:
`fold(txs, 0.00, (acc, tx) -> acc + 0.00)` → `fold(txs, decimal(0, 2), (acc, tx) -> acc + decimal(0, 2))`.
Literal migration only — the placeholder accumulator shape is preserved (no balance-logic
rewrite). `VerifyBalancing`, `api.ig`, and the `Decimal[2]` money type are untouched.

### Done (within authority)
- **Rust ok/0** — BK-P03 RESOLVED; the `expected Decimal[2], got Float` mismatch is gone
  (the money path stays in `Decimal[2]`).
- **VM run `ComputeAccountBalance` → `{value:0, scale:2}`** — a real `Value::Decimal`,
  scale preserved at runtime.

### Residuals pinned (out of this card's authority — no compiler changes)
- **BK-P04**: Ruby `stdlib.collection.sum` 1-arg (scalar) form in `VerifyBalancing` →
  `OOF-COL1` ×2 + `OOF-P1` cascade. Routed to the collection-stdlib parity track.
- **Ruby numeric parity**: homogeneous `Decimal + Decimal` rejected by the Ruby
  typechecker (`OOF-TY0: expected Integer, got Decimal+Decimal @total`) + `OOF-COL4`
  cascade. The numeric-dispatch relaxation was Rust-only; Ruby parity is a separate routed
  gap (same pattern as erp_logistics). NOT a `decimal()`-construction failure — the
  `decimal(0,2)` seed itself types and runs.

### Acceptance reconciliation
- Previous Float → Decimal output mismatch gone — **MET** (Rust ok/0; Ruby mismatch removed).
- No implicit coercion introduced/relied upon — **MET** (explicit `decimal()`; no bare `0.00`).
- `decimal(0, 2)` used only where Decimal is intended — **MET**.
- Ruby + Rust compile results documented — **MET** (Rust ok/0; Ruby oof/5 → 6→5).
- Runtime preserves `Decimal[2]` scale — **MET**.

### Artifacts
- Proof: `igniter-view-engine/proofs/verify_lab_bookkeeping_decimal_migration_p1.rb`
- Lab doc: `lab-docs/governance/lab-bookkeeping-decimal-migration-p1-v0.md`
- Registry: `igniter-apps/bookkeeping/PRESSURE_REGISTRY.md` (BK-P03 resolved + migration section)
- App source: `igniter-apps/bookkeeping/ledger.ig`
