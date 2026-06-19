# ERP Logistics Domain Pressure Report

**Date:** 2026-06-11
**Target:** Igniter multi-file compilation, Float operators, collection stdlib, and app composition
**App:** ERP Logistics Engine (`igniter-lab/igniter-apps/erp_logistics`)
**Status:** living pressure report / not a production app

---

## Summary

This ERP logistics fixture is a compact pressure test for physical quantities and route
optimization. It stresses:

- multi-file application compilation;
- Float comparison and arithmetic;
- collection `filter` and `fold` over `Route` records;
- stringly contract composition;
- build tooling that must pass the full source closure explicitly.

Current Rust multi-file compilation confirms that module/type/contract resolution works when all
source files are supplied together. The active blockers are Float operator typing and collection
stdlib parity, not import visibility.

---

## Current Files

| File | Role |
|---|---|
| `types.ig` | Defines `Warehouse`, `Route`, and `Shipment`. |
| `warehouse.ig` | Defines `CheckCapacity`, a Float comparison capacity check. |
| `optimizer.ig` | Defines `CalculateBestRoute`, a route filtering/folding optimizer. |
| `api.ig` | Defines `DispatchShipment`, intended as the orchestration entrypoint. |
| `PRESSURE_REGISTRY.md` | Structured pressure registry derived from this report. |

---

## Fresh Live Check

Commands run on 2026-06-11 against current local toolchains.

Rust documented subset compile:

```bash
cd ../../igniter-compiler
cargo run -- compile ../igniter-apps/erp_logistics/types.ig ../igniter-apps/erp_logistics/warehouse.ig ../igniter-apps/erp_logistics/api.ig --out /tmp/erp-logistics-subset.igapp
```

Result: `status: oof`.

Key diagnostic:

- `Type mismatch for <: expected Integer on both sides, got Float < Float`

Rust full multi-file compile:

```bash
cd ../../igniter-compiler
cargo run -- compile ../igniter-apps/erp_logistics/types.ig ../igniter-apps/erp_logistics/warehouse.ig ../igniter-apps/erp_logistics/optimizer.ig ../igniter-apps/erp_logistics/api.ig --out /tmp/erp-logistics-full.igapp
```

Result: `status: oof`.

Key diagnostics:

- `Type mismatch for <: expected Integer on both sides, got Float < Float`
- `Type mismatch: expected Integer, got Float*Float`
- `Type mismatch: expected Float, got Integer`

Ruby canon full multi-file compile:

```bash
cd ../../../igniter-lang
ruby -Ilib -e 'require "igniter_lang/compiler_orchestrator"; c=IgniterLang::CompilerOrchestrator.new; p c.compile_sources(source_paths: ["../igniter-lab/igniter-apps/erp_logistics/types.ig", "../igniter-lab/igniter-apps/erp_logistics/warehouse.ig", "../igniter-lab/igniter-apps/erp_logistics/optimizer.ig", "../igniter-lab/igniter-apps/erp_logistics/api.ig"], out_path: "/tmp/erp-logistics-ruby.igapp")'
```

Result: `status: oof`.

Key diagnostics:

- `Unknown function: call_contract`
- `Unknown function: filter`
- `Unknown function: fold`
- `Unsupported operator: <`

Ruby diagnostics also appear to attribute some warehouse/optimizer nodes to `DispatchShipment`,
which is the same merged-universe diagnostic-context smell seen in bookkeeping. Treat that as a
separate diagnostics quality pressure.

---

## Updated Findings

### 1. Multi-File Compile Works When Full Closure Is Supplied

The Rust compiler accepts multiple source paths and builds a logical source universe. This fixture
confirms that type and contract names are visible across files when the caller supplies the complete
file set.

Status: positive / tooling caveat.

Pressure registry entry: `ERP-P01`.

---

### 2. Float Comparison Is Open

`warehouse.ig` uses:

```igniter
compute is_valid = shipment.weight < 1000.0
```

Rust reports:

```text
Type mismatch for <: expected Integer on both sides, got Float < Float
```

This blocks basic physical bound checks for weight, volume, distance, and cost.

Status: active numeric/operator pressure.

Pressure registry entry: `ERP-P02`.

---

### 3. Float Multiplication Is Open

`optimizer.ig` uses:

```igniter
compute total_cost = best_cost * shipment.weight
output total_cost : Float
```

Rust reports:

```text
Type mismatch: expected Integer, got Float*Float
Type mismatch: expected Float, got Integer
```

The typechecker appears to treat multiplication as Integer-oriented in this path. Logistics and
scientific domains need Float arithmetic semantics or a deliberate alternative.

Status: active numeric/operator pressure.

Pressure registry entry: `ERP-P03`.

---

### 4. Unary Negative Float Is Historical / Needs Fresh Minimal Fixture

The original report noted parser rejection for `-1.0`. The current fixture does not exercise this
shape. Keep it as historical pressure until a current minimal fixture proves it.

Status: historical / needs fresh proof.

Pressure registry entry: `ERP-P04`.

---

### 5. Collection `filter` / `fold` Parity Remains Open

`optimizer.ig` uses `filter` and `fold`. Rust gets far enough to reveal Float operator gaps. Ruby
canon reports these functions as unknown. This aligns with the stdlib collection parity pressure
also seen in bookkeeping and spreadsheet.

Status: active stdlib parity pressure.

Pressure registry entry: `ERP-P05`.

---

### 6. Stringly `call_contract` Remains App Composition Pressure

`api.ig` uses:

```igniter
compute capacity_ok = call_contract("CheckCapacity", shipment)
```

This should eventually route through typed contract refs/forms/composition surfaces, not ad hoc
runtime string dispatch.

Status: design pressure.

Pressure registry entry: `ERP-P06`.

---

### 7. Build Tooling Still Needs Import-Closure Collection

The compiler can compile multi-file applications when every required source file is passed. The
build tool still needs to collect import closure and pass the full set. This is tooling, not a
language semantics failure.

Status: tooling pressure.

Pressure registry entry: `ERP-P07`.

---

### 8. Ruby Multi-File Diagnostic Attribution Needs A Sanity Check

Ruby diagnostics in this and bookkeeping appear to report some nodes under the entrypoint contract
rather than their original declaring contract. Confirm with a minimal fixture before treating this as
a product-facing diagnostic issue.

Status: suspected toolchain diagnostic issue.

Pressure registry entry: `ERP-P08`.

---

## Current Pressure Ranking

| Rank | Pressure | Why |
|---:|---|---|
| 1 | Float comparison and arithmetic | Blocks logistics, science, optimization, cost calculation. |
| 2 | Collection `filter`/`fold` parity | Required for route optimization and Ruby parity. |
| 3 | Import-closure build tooling | Required for app ergonomics, though compiler core can handle full batches. |
| 4 | Stringly `call_contract` | Composition pressure; route through typed refs/forms. |
| 5 | Ruby diagnostic attribution | Debuggability issue if confirmed. |
| 6 | Unary negative Float | Historical; needs fresh minimal proof. |

---

## Recommended Next Routes

1. **LAB-STDLIB-FLOAT-P1** or **LAB-STDLIB-NUMERIC-P1**
   Float comparison/arithmetic operator parity.

2. **LAB-STDLIB-COLLECTION-P1**
   `filter`/`fold` signatures and Ruby/Rust parity.

3. **LAB-IMPORT-CLOSURE-TOOLING-P1**
   Tooling-level source closure collection; no new import semantics.

4. **Typed-ref/forms migration route**
   Later replacement for stringly `call_contract` in app-level orchestration.

5. **LAB-RUBY-MULTIFILE-DIAGNOSTICS-P1**
   Minimal proof for diagnostic contract attribution under merged multi-file universes.

---

## Non-Goals

This app does not authorize:

- production ERP/logistics runtime;
- route optimizer execution;
- implicit Float/Decimal unification;
- `call_contract` canonization;
- collection stdlib implementation without entry contracts;
- build tool behavior changes;
- VM/runtime changes.

---

## Operating Decision

Keep ERP logistics as a numeric/operator and route-optimization pressure fixture. Do not weaken type
checking locally to make it compile. Use it to route focused Float/numeric, collection, and tooling slices.
