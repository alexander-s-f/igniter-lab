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
| BK-P03 | Decimal literal typing | Rust full multi-file: `0.00` inferred as Float, output expects `Decimal[2]`. | active | `LAB-STDLIB-DECIMAL-P1` |
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
