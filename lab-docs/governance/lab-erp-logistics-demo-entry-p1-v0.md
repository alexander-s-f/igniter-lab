# Lab Doc — LAB-ERP-LOGISTICS-DEMO-ENTRY-P1 (v0)

**Date:** 2026-06-15
**Route:** lab / app pressure / erp_logistics
**Authority:** app fixture/entrypoint work only. This is **evidence baseline only**,
a companion runtime **fixture**, **not** language authority. No compiler, VM,
stdlib, numeric-coercion, IO, clock, scheduler, DB, or queue change was made.

## Goal

Classify and, if safe, add a zero-input demo/orchestrator entry for `erp_logistics`
so runtime checks can exercise the app without external `routes` / `shipment` /
`warehouse` inputs. The gate (`LAB-COMPILER-NUMERIC-DISPATCH-UNKNOWN-P1` cluster 1)
left `erp_logistics` with contracts that execute on the VM but whose chosen entry
needs inputs — an entry/UX blocker, not a numeric one.

## What was added

One new source unit, `igniter-apps/erp_logistics/example.ig` (`module ErpExample`):

- `entrypoint RunBestRoute` — a single bare entrypoint (ERP-P09).
- Factories `MakeWarehouse`, `MakeShipment`, `MakeRoute` — `pure` contracts that take
  typed inputs and build the typed record from them (ERP-P10, see below).
- Scenarios:
  - `RunBestRoute` (the entry) — builds a shipment and three routes, calls the
    production `CalculateBestRoute`.
  - `RunCapacity` — calls the production `CheckCapacity`.
  - `RunDispatchDemo` — calls the production orchestrator `DispatchShipment`.

The production contracts `CheckCapacity`, `CalculateBestRoute`, `DispatchShipment`
and the type model (`Warehouse`, `Route`, `Shipment`, all `Text`/`Float`) are
**untouched**.

**Source hash (5-file closure, absolute paths):**
`sha256:dafbf1eb358fc7e13e1458b12c5e7f81a61f514017ea714cd548ae23b52d3041`
— Rust and Ruby agree on the closure hash; only their status differs.

## Outcome — honest and partial

### Rust + VM: green through the demo entry

- **Rust compile ok/0**, 9 contracts, entrypoint `RunBestRoute` resolved in both
  `manifest.json` and `semantic_ir_program.json`
  (`contract_path: contracts/run_best_route.json`).
- **VM run `RunBestRoute` → `{"status":"success","result":2437.5}`** (= 3.25 × 750.0).
  This exercises `filter` (matching routes), `fold` (min-cost, with an in-fold
  `Float < Float` comparison), and a top-level `Float * Float` multiply — all on the
  VM. The numeric-dispatch entry/UX blocker is resolved for this toolchain.

### Ruby: oof/4 — pre-existing, out-of-authority residual

- **Ruby compile oof/4.** All four diagnostics are in the pre-existing production
  contracts; the demo entry adds **zero** new diagnostics:
  - `CalculateBestRoute/node:best_cost` — OOF-TY0 `Float<Float`
  - `CalculateBestRoute/node:total_cost` — OOF-TY0 `Float*Float`
  - `CalculateBestRoute/node:total_cost` — OOF-TY1 output `Float` vs `Integer`
  - `CheckCapacity/node:is_valid` — OOF-TY0 `Float<Float`
- The blocker is the **Ruby typechecker's Float-operator over-restriction**. The
  Rust numeric-dispatch relaxation in `LAB-COMPILER-NUMERIC-DISPATCH-UNKNOWN-P1`
  cluster 1 was **Rust-only**; there is no Ruby parity. Closing it requires a
  **compiler change**, which is a **Closed Surface** for this card. → routes to a
  Ruby numeric-parity follow-up.

### ERP-P11 (new): VM direct Float comparison is Integer-only

`RunCapacity` and `RunDispatchDemo` compile dual-closure-clean but **trap at the VM**
with `Expected Integer, got: Float(750.0)` on `shipment.weight < 1000.0`. So:

- Float arithmetic (`*`, `+`) runs on the VM.
- In-fold `Float < Float` runs on the VM (proven by `RunBestRoute`).
- A **direct, top-level `Float < Float`** does not — the comparison opcode lowering
  is still Integer-only.

This is a **VM gap, not an app defect**, and a **Closed Surface** for this card. It
is why `RunBestRoute` (the route-optimization path) was chosen as the entry rather
than the capacity orchestrator. → routes to a VM Float-comparison opcode parity
follow-up.

## Pressures registered

- **ERP-P09** — single bare `entrypoint`; named run-profiles want `PROP-029`.
- **ERP-P10** — `String` literal accepted as a `Text` *argument* at call sites but
  **not** in record-field position; factories take typed inputs to work around it.
  → record-literal / entity surface, or extend the String→Text coercion to fields.
- **ERP-P11** — VM direct (non-fold) `Float` comparison Integer-only.

## Classification

The card's **entry/UX goal is achieved** for the Rust+VM toolchain (zero-input demo
entry, VM run success). Full dual-clean green is **not** reachable within authority:
Ruby numeric parity (compiler) and the VM Float-comparison gap (VM) are both Closed
Surfaces here and are pinned as routed residuals.

## Closed surfaces (held)

No compiler change. No VM change. No numeric-coercion change. No stdlib change. No
IO / clock / scheduler / DB / queue. No edits to the production contracts or the type
model. No migration of other apps.

## Artifacts

- Proof: `igniter-view-engine/proofs/verify_lab_erp_logistics_demo_entry_p1.rb`
- App source: `igniter-apps/erp_logistics/example.ig` (only new file)
- Registry: `igniter-apps/erp_logistics/PRESSURE_REGISTRY.md`
- Card: `.agents/work/cards/governance/LAB-ERP-LOGISTICS-DEMO-ENTRY-P1.md`

## Toolchain note

The lab release compiler exhibits a documented **fd/timing flake** ("Internal
compiler error: No such file or directory") under very rapid successive spawns (e.g.
a tight shell loop). Open3 from a fresh interpreter is reliable; the proof retries
the Rust compile to stay robust under host load.
