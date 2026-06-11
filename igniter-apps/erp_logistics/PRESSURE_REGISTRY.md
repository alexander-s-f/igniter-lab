# ERP Logistics Pressure Registry

**Date:** 2026-06-11  
**App:** `igniter-lab/igniter-apps/erp_logistics`  
**Purpose:** compact registry of language/compiler pressures surfaced by the ERP logistics domain fixture.

This registry is evidence routing, not implementation authority.

---

## Pressure Entries

| ID | Pressure | Current Evidence | Status | Suggested Route |
|---|---|---|---|---|
| ERP-P01 | Multi-file compile with explicit source closure | Rust compiles a logical universe when all required source files are passed. | positive / tooling caveat | Keep as app-level compile pattern. |
| ERP-P02 | Float comparison | Rust: `Float < Float` rejected as Integer-only `<`. | active | `LAB-STDLIB-FLOAT-P1` |
| ERP-P03 | Float multiplication | Rust: `Float*Float` path reports Integer/Float mismatch. | active | `LAB-STDLIB-FLOAT-P1` |
| ERP-P04 | Unary negative Float | Original report mentions `-1.0` parser failure; current fixture does not exercise it. | historical / needs fresh proof | include in `LAB-STDLIB-FLOAT-P1` negative fixtures |
| ERP-P05 | Collection `filter`/`fold` parity | Optimizer uses both; Ruby reports unknown functions. | active | `LAB-STDLIB-COLLECTION-P1` |
| ERP-P06 | Stringly composition | `api.ig` uses `call_contract("CheckCapacity", shipment)`. | design pressure | typed-ref/forms migration route |
| ERP-P07 | Import-closure build tooling | Compiler core works with full batch; build tool must collect closure. | tooling pressure | `LAB-IMPORT-CLOSURE-TOOLING-P1` |
| ERP-P08 | Ruby multi-file diagnostic attribution | Ruby appears to attribute non-entrypoint nodes to `DispatchShipment`. | suspected toolchain issue | `LAB-RUBY-MULTIFILE-DIAGNOSTICS-P1` |

---

## Evidence Commands

Rust documented subset compile:

```bash
cd ../../igniter-compiler
cargo run -- compile ../igniter-apps/erp_logistics/types.ig ../igniter-apps/erp_logistics/warehouse.ig ../igniter-apps/erp_logistics/api.ig --out /tmp/erp-logistics-subset.igapp
```

Rust full multi-file compile:

```bash
cd ../../igniter-compiler
cargo run -- compile ../igniter-apps/erp_logistics/types.ig ../igniter-apps/erp_logistics/warehouse.ig ../igniter-apps/erp_logistics/optimizer.ig ../igniter-apps/erp_logistics/api.ig --out /tmp/erp-logistics-full.igapp
```

Ruby full multi-file compile:

```bash
cd ../../../igniter-lang
ruby -Ilib -e 'require "igniter_lang/compiler_orchestrator"; c=IgniterLang::CompilerOrchestrator.new; p c.compile_sources(source_paths: ["../igniter-lab/igniter-apps/erp_logistics/types.ig", "../igniter-lab/igniter-apps/erp_logistics/warehouse.ig", "../igniter-lab/igniter-apps/erp_logistics/optimizer.ig", "../igniter-lab/igniter-apps/erp_logistics/api.ig"], out_path: "/tmp/erp-logistics-ruby.igapp")'
```

---

## Routing Notes

- ERP-P02 and ERP-P03 should stay together: comparison and multiplication are one Float operator parity pressure.
- ERP-P04 should be rechecked with a minimal current fixture before used as a blocker.
- ERP-P05 aligns with bookkeeping/spreadsheet collection parity pressure.
- ERP-P07 is tooling, not a reason to change import semantics.
- ERP-P08 should be minimized separately from numeric/std-lib work.
