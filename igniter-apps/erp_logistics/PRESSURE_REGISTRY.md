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
| ERP-P09 | Single bare entrypoint | `example.ig` declares one bare `entrypoint RunBestRoute`; `RunBestRoute` / `RunCapacity` / `RunDispatchDemo` each want a named run-profile with its own `args`/`output`/`default`. | active / DX | `PROP-029` rich entrypoint (run-profiles) |
| ERP-P10 | String literal not assignable to `Text` record field | An inline literal record (`{ id: "WH-1", ... }`) fails Rust TC with `field 'id' expects Text, got String`; a `String` literal is accepted as a `Text` **argument** at a call site (ch3 §3.x) but not in record-field position. Demo factories (`MakeWarehouse`/`MakeShipment`/`MakeRoute`) take typed inputs to work around it. | design pressure | record-literal / entity surface, or extend String→Text coercion to field position |
| ERP-P11 | VM direct (non-fold) Float comparison is Integer-only | After the Rust numeric-dispatch TC relaxation, `Float * Float` and in-fold `Float < Float` run on the VM, but a direct `shipment.weight < 1000.0` traps with `Expected Integer, got: Float`. `RunBestRoute` runs end-to-end; `RunCapacity`/`RunDispatchDemo` trap. VM gap, not an app defect. | active / runtime | VM Float-comparison opcode parity follow-up |

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

## Wave P13 Appendix Check (2026-06-15)

Ruby: oof/4. Rust: ok/0. Source files: 4. outside active fleet; Ruby Float/operator blockers remain. This directory has a pressure registry but remains outside the 20-app active fleet metric inherited from Wave P12, so it is not counted as a P13 regression or resolution.

## Demo Entry Baseline — LAB-ERP-LOGISTICS-DEMO-ENTRY-P1 (2026-06-15)

**Source hash (5-file closure, absolute paths):** `sha256:dafbf1eb358fc7e13e1458b12c5e7f81a61f514017ea714cd548ae23b52d3041`
(Rust and Ruby agree on the closure hash; status differs.)

A companion `example.ig` was added (the only new source unit): a zero-input demo
fixture with a bare `entrypoint RunBestRoute`, three `Make*` record factories, and
three `Run*` scenarios. The production contracts (`CheckCapacity`,
`CalculateBestRoute`, `DispatchShipment`) are untouched.

**Outcome (honest, partial):**

- **Rust ok/0** (9 contracts) and the **VM runs the demo entry `RunBestRoute`
  end-to-end → `2437.5`** (= 3.25 × 750.0). filter + fold + Float comparison +
  Float multiplication all execute. The entry/UX blocker from the numeric-dispatch
  card ("contracts execute but need `routes`/`shipment` inputs") is **resolved** for
  the Rust+VM toolchain.
- **Ruby oof/4 — residual blocker, out of this card's authority.** All four
  diagnostics sit in the pre-existing production contracts (`CalculateBestRoute` ×3,
  `CheckCapacity` ×1); the demo entry adds **zero** new diagnostics. The blocker is
  the Ruby typechecker's Float-operator over-restriction — the Rust numeric-dispatch
  relaxation (`LAB-COMPILER-NUMERIC-DISPATCH-UNKNOWN-P1` cluster 1) was Rust-only and
  has no Ruby parity. Routes to a Ruby numeric-parity follow-up; **no compiler change
  is permitted under this card.**
- **ERP-P11 (new):** `RunCapacity` / `RunDispatchDemo` compile dual-closure-clean but
  trap at the VM on a direct (non-fold) `Float < Float`. Routes to a VM
  Float-comparison opcode parity follow-up; **no VM change under this card.**

**Proof:** `igniter-view-engine/proofs/verify_lab_erp_logistics_demo_entry_p1.rb`.
**Lab doc:** `lab-docs/governance/lab-erp-logistics-demo-entry-p1-v0.md`.

**Toolchain note:** the lab release compiler shows a documented fd/timing flake
("Internal compiler error: No such file or directory") under very rapid successive
spawns; Open3 from a fresh interpreter is reliable, and the proof retries.
