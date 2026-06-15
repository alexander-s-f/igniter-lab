# Lab Doc — LAB-BOOKKEEPING-DECIMAL-MIGRATION-P1 (v0)

**Date:** 2026-06-15
**Route:** lab / app pressure / bookkeeping / Decimal constructor
**Authority:** app source migration only, after `LAB-NUMERIC-DECIMAL-CONSTRUCT-P1`. No
compiler/VM/stdlib change, no rounding policy, no `Money` type, no broad refactor.

## Goal

Migrate `bookkeeping` off the Float fold seed so its money path stays entirely in the
`Decimal[N]` family, using the explicit `decimal(value, scale)` constructor landed by
CONSTRUCT-P1. Primary target: the `0.00` Float seed that caused
`Output type mismatch: expected Decimal[2], got Float` (BK-P03).

## The migration (one contract, app-only)

`ledger.ig` / `ComputeAccountBalance`:

```diff
- compute total = fold(txs, 0.00, (acc, tx) -> acc + 0.00) -- DUMMY ...
+ compute total = fold(txs, decimal(0, 2), (acc, tx) -> acc + decimal(0, 2))
```

`decimal(0, 2)` is `0.00` at scale 2 in exact minor units. The accumulator *shape* is the
original placeholder fold — this is a literal migration, **not** a balance-logic rewrite.
`VerifyBalancing` (filter/map/sum), `api.ig` (Result outcome), and the `Decimal[2]` money
type in `types.ig` are untouched. No legitimate Float domain quantity was changed (there
is none — the only Float literal was the Decimal-intended seed).

**Migrated source hash (dual):** `sha256:025731179a24c15fda2109170ed69ae5231e3d3226beb0f58b815f0a1c6c830f`
(Rust and Ruby agree).

## Outcome — honest, dual-toolchain

### Rust: resolved (BK-P03 gone)

- **Rust compile ok/0** — the prior `expected Decimal[2], got Float` (BK-P03) is gone.
  The fold seeds and accumulates with `decimal(0, 2)`, so the money path stays entirely in
  `Decimal[2]` (`Decimal[2] + Decimal[2]` → `Decimal[2]`, equal scale).
- **VM run** `ComputeAccountBalance` (2 transactions) → `{"value":0,"scale":2}` — a real
  `Value::Decimal { value, scale }`, **scale preserved at runtime**, no Float.

### Ruby: Float→Decimal mismatch gone; two out-of-authority residuals remain

Ruby went **oof/6 → oof/5**; the Float→Decimal output mismatch is gone and `decimal()`
resolves cleanly. The remaining diagnostics are **pre-existing, out-of-authority** gaps —
no compiler change is permitted under this card:

1. **`stdlib.collection.sum` 1-arg form (BK-P04)** — `VerifyBalancing` calls
   `sum(debit_amounts)`; Ruby's `sum` requires the 2-arg field-projection form
   `sum(collection, :field)` → `OOF-COL1` ×2 + an `OOF-P1` cascade (`total_debits`
   unresolved). Unrelated to Decimal; routed to the collection-stdlib parity track.
2. **Ruby numeric parity** — after migration the fold body is `Decimal + Decimal`, which
   Ruby's typechecker still rejects as Integer-only:
   `OOF-TY0: Type mismatch: expected Integer, got Decimal+Decimal @total` (+ an `OOF-COL4`
   accumulator cascade). This is the **same Ruby numeric-parity gap** seen elsewhere: the
   homogeneous numeric relaxation (`LAB-COMPILER-NUMERIC-DISPATCH-UNKNOWN-P1`) was
   **Rust-only**; Ruby parity is a separate routed gap. The migration is correct — Rust
   accepts `Decimal[2] + Decimal[2]` and runs it; Ruby's operator typing has not caught up.

Both residuals are **not Decimal-construction failures** (the `decimal(0, 2)` seed itself
types and runs); they are independent toolchain-parity gaps.

## Acceptance

- Previous Float → Decimal output mismatch gone — **MET** (Rust ok/0; Ruby's
  `expected Decimal[2], got Float` removed).
- No implicit coercion introduced or relied upon — **MET** (explicit `decimal()`; no bare
  `0.00`; implicit Float→Decimal stays `OOF-TY1` per BOUNDARY-P1).
- `decimal(0, 2)` used only where Decimal is semantically intended — **MET** (the money
  fold seed; the dummy accumulator).
- Ruby and Rust compile results documented — **MET** (Rust ok/0; Ruby oof/5 residuals).
- Runtime result preserves `Decimal[2]` scale — **MET** (VM → `{value:0, scale:2}`).

## Closed surfaces (held)

No compiler/VM/stdlib change. No rounding-policy change. No `Money` type. No broad
bookkeeping refactor. No replacement of legitimate Float domain quantities.

## Routed residuals (out of this card)

- **BK-P04** — Ruby `stdlib.collection.sum` 1-arg (scalar) form parity (collection-stdlib track).
- **Ruby numeric parity** — homogeneous `Decimal`/`Float` binary ops rejected by the Ruby
  typechecker (Rust-only relaxation); a Ruby-numeric-parity follow-up.

## Artifacts

- Proof: `igniter-view-engine/proofs/verify_lab_bookkeeping_decimal_migration_p1.rb`
- App source: `igniter-apps/bookkeeping/ledger.ig` (only file changed)
- Registry: `igniter-apps/bookkeeping/PRESSURE_REGISTRY.md`
- Card: `.agents/work/cards/governance/LAB-BOOKKEEPING-DECIMAL-MIGRATION-P1.md`
