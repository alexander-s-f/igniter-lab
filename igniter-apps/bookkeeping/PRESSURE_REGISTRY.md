# Bookkeeping Pressure Registry

**Date:** 2026-06-11  
**App:** `igniter-lab/igniter-apps/bookkeeping`  
**Purpose:** compact registry of language/compiler pressures surfaced by the bookkeeping domain fixture.

This registry is evidence routing, not implementation authority.

---

## Pressure Entries

| ID | Pressure | Current Evidence | Status | Suggested Route |
|---|---|---|---|---|
| BK-P01 | Multi-file import/type visibility | Rust single-file `ledger.ig` reports `Transaction.postings`; Rust full multi-file does not. | improved / monitor | Keep using multi-file compile for app-level checks. |
| BK-P02 | Decimal equality | Rust full multi-file: `Type mismatch for ==: cannot compare Decimal with Decimal`. | active | `LAB-STDLIB-DECIMAL-P1` |
| BK-P03 | Decimal literal typing | RESOLVED 2026-06-15: the `0.00` Float fold seed migrated to `decimal(0, 2)` (LAB-NUMERIC-DECIMAL-CONSTRUCT-P1 constructor); Rust full multi-file now ok/0, VM runs `ComputeAccountBalance` to a `Decimal[2]` value. | resolved | `LAB-BOOKKEEPING-DECIMAL-MIGRATION-P1` |
| BK-P04 | Collection stdlib parity | Bookkeeping needs `filter`, `map`, `sum`, `fold`; Ruby reports unknown functions. | active | `LAB-STDLIB-COLLECTION-P1` |
| BK-P05 | Result constructors | `ok(tx)` / `err(text)` unknown in Ruby; canonical Result constructor model unsettled. | active | `LAB-STDLIB-RESULT-P1` or `LAB-STDLIB-OPTION-P1` |
| BK-P06 | Stringly composition | `call_contract("VerifyBalancing", tx)` is app composition pressure; typed refs/forms are better substrate. | design pressure | typed-ref/forms migration route |
| BK-P07 | Ruby multi-file diagnostic attribution | Ruby diagnostics appear to attribute ledger nodes to `PostTransaction`. | suspected toolchain issue | `LAB-RUBY-MULTIFILE-DIAGNOSTICS-P1` |

---

## Evidence Commands

Rust type-only compile:

```bash
cd ../../igniter-compiler
cargo run -- compile ../igniter-apps/bookkeeping/types.ig --out /tmp/bookkeeping-types.igapp
```

Rust full multi-file compile:

```bash
cd ../../igniter-compiler
cargo run -- compile ../igniter-apps/bookkeeping/types.ig ../igniter-apps/bookkeeping/ledger.ig ../igniter-apps/bookkeeping/api.ig --out /tmp/bookkeeping-full.igapp
```

Ruby full multi-file compile:

```bash
cd ../../../igniter-lang
ruby -Ilib -e 'require "igniter_lang/compiler_orchestrator"; c=IgniterLang::CompilerOrchestrator.new; p c.compile_sources(source_paths: [\"../igniter-lab/igniter-apps/bookkeeping/types.ig\", \"../igniter-lab/igniter-apps/bookkeeping/ledger.ig\", \"../igniter-lab/igniter-apps/bookkeeping/api.ig\"], out_path: "/tmp/bookkeeping-ruby.igapp")'
```

---

## Routing Notes

- BK-P02 and BK-P03 should probably stay together: Decimal equality without Decimal literal ergonomics still leaves bookkeeping awkward.
- BK-P04 should wait until `LANG-STDLIB-ENTRY-CONTRACT-P3` creates the first registry inventory, unless collection is intentionally split earlier.
- BK-P05 should not be solved by inventing local `ok`/`err`; route through Result/Option stdlib reconciliation.
- BK-P06 belongs to typed-ref/forms composition work, not stdlib.
- BK-P07 should be minimized before treated as a product-facing diagnostic issue.

## Wave P13 Appendix Check (2026-06-15)

Ruby: oof/6. Rust: oof/1. Source files: 3. outside active fleet; Decimal/sum/fold blockers remain. This directory has a pressure registry but remains outside the 20-app active fleet metric inherited from Wave P12, so it is not counted as a P13 regression or resolution.

## Decimal Migration — LAB-BOOKKEEPING-DECIMAL-MIGRATION-P1 (2026-06-15)

**Migrated source hash (dual, 3-file):** `sha256:025731179a24c15fda2109170ed69ae5231e3d3226beb0f58b815f0a1c6c830f`
(Rust and Ruby agree on the closure hash; status differs.)

`ComputeAccountBalance`'s fold seed/accumulator migrated `0.00` → `decimal(0, 2)`
(LAB-NUMERIC-DECIMAL-CONSTRUCT-P1 constructor) so the money path stays entirely in
`Decimal[2]`. App-only edit (`ledger.ig`); no compiler/VM change.

**Outcome (honest, partial):**

- **Rust ok/0** — BK-P03 RESOLVED; the `expected Decimal[2], got Float` mismatch is gone.
  **VM runs `ComputeAccountBalance` → `{value:0, scale:2}`** (Decimal[2], scale preserved).
- **Ruby oof/5** (was 6) — the Float→Decimal mismatch is gone, but two pre-existing,
  **out-of-authority** residuals remain (no compiler change permitted here):
  - **BK-P04**: `stdlib.collection.sum` 1-arg (scalar) form in `VerifyBalancing` →
    `OOF-COL1` ×2 + `OOF-P1` cascade. Ruby wants `sum(collection, :field)`.
  - **Ruby numeric parity**: homogeneous `Decimal + Decimal` rejected by the Ruby
    typechecker (`OOF-TY0: expected Integer, got Decimal+Decimal @total`) + `OOF-COL4`
    cascade. The numeric-dispatch relaxation was **Rust-only**; Ruby parity is a separate
    routed gap (same pattern as erp_logistics). Not a `decimal()`-construction failure.

**Proof:** `igniter-view-engine/proofs/verify_lab_bookkeeping_decimal_migration_p1.rb`.
**Lab doc:** `lab-docs/governance/lab-bookkeeping-decimal-migration-p1-v0.md`.
