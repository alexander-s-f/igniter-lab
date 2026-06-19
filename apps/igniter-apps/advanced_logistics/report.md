# Advanced Logistics Domain Pressure Report

**Date:** 2026-06-12
**Target:** Igniter stdlib import surface, collection helpers, app composition, and operator parity
**App:** Advanced Logistics (`igniter-lab/igniter-apps/advanced_logistics`)
**Status:** living pressure report / not a production app

---

## Summary

This advanced logistics fixture models route planning over transports and orders. It stresses:

- multi-file application composition;
- selective stdlib imports for collection helpers;
- collection `map` and `filter` over records;
- stringly contract composition through `call_contract`;
- comparison operators inside lambda predicates;
- parser ambiguity around inline record construction in higher-order contexts;
- math/geometry pressure without `sqrt`.

The current source files parse, but both Rust and Ruby compilers stop at `multifile_resolve` because
`stdlib.collection` is not yet an importable module. A probe copy with only the two
`import stdlib.collection.{ ... }` lines removed shows the next layer: Rust compiles cleanly, while
Ruby reports `call_contract` and `<` operator gaps. That makes this app a useful pressure fixture for
stdlib import surface and composition, not a signal that the domain model itself is broken.

---

## Current Files

| File | Role |
|---|---|
| `types.ig` | Defines `Location`, `Warehouse`, `Package`, `Transport`, `Order`, and `RoutePlan`. |
| `spatial.ig` | Computes squared Euclidean distance using integer arithmetic; avoids `sqrt`. |
| `router.ig` | Filters feasible orders for a transport with capacity predicates. |
| `api.ig` | Maps transports to feasible route plans and creates order IDs. |
| `PRESSURE_REGISTRY.md` | Structured pressure registry derived from this report. |

---

## Fresh Live Check

Commands run on 2026-06-12 against current local toolchains.

Rust full multi-file compile:

```bash
cd ../../igniter-compiler
cargo run -- compile ../igniter-apps/advanced_logistics/types.ig ../igniter-apps/advanced_logistics/spatial.ig ../igniter-apps/advanced_logistics/router.ig ../igniter-apps/advanced_logistics/api.ig --out /tmp/advanced-logistics-rust.igapp
```

Result: `status: oof` at `multifile_resolve`.

Key diagnostics:

- `OOF-IMP2 unknown import path 'stdlib.collection' from module 'AdvancedLogisticsApi'`
- `OOF-IMP2 unknown import path 'stdlib.collection' from module 'AdvancedLogisticsRouter'`

Ruby canon full multi-file compile:

```bash
cd ../../../igniter-lang
ruby -Ilib -e 'require "igniter_lang/compiler_orchestrator"; c=IgniterLang::CompilerOrchestrator.new; p c.compile_sources(source_paths: ["../igniter-lab/igniter-apps/advanced_logistics/types.ig", "../igniter-lab/igniter-apps/advanced_logistics/spatial.ig", "../igniter-lab/igniter-apps/advanced_logistics/router.ig", "../igniter-lab/igniter-apps/advanced_logistics/api.ig"], out_path: "/tmp/advanced-logistics-ruby.igapp")'
```

Result: `status: oof` at `multifile_resolve` with the same `OOF-IMP2` diagnostics.

Probe check, source unchanged:

A temporary `/tmp` probe copy was made with only the `import stdlib.collection.{ map }` and
`import stdlib.collection.{ filter }` lines removed. This was used only to reveal the next blocker
layer; app sources were not edited.

Rust probe result: `status: ok`, zero diagnostics.

Ruby probe result: `status: oof` at `typecheck`.

Key Ruby probe diagnostics:

- `Unknown function: call_contract`
- `Unsupported operator: <`

---

## Updated Findings

### 1. `stdlib.collection` Is Not Yet Importable

The app uses:

```igniter
import stdlib.collection.{ map }
import stdlib.collection.{ filter }
```

Both Rust and Ruby reject this with `OOF-IMP2`. This is now the first visible blocker in the real
source files. It is distinct from regular-call support for `map` and `filter`: the helpers may be
recognized as bare aliases, but `stdlib.collection` is not a source module.

Status: active import-surface pressure.

Pressure registry entry: `AL-P01`.

---

### 2. Bare `map` / `filter` Work As A Probe Path In Rust

After removing only the stdlib import lines in a temporary probe copy, Rust compiles the full
application successfully. That means the current Rust path can typecheck the app's bare `map` and
`filter` calls when import resolution is not blocking first.

Status: positive / import barrier confirmed.

Pressure registry entry: `AL-P02`.

---

### 3. Ruby Still Has Composition And Operator Gaps Under The Import Barrier

The same probe copy reaches Ruby typechecking and reports:

- `Unknown function: call_contract`
- `Unsupported operator: <`

This shows that after the collection helper work, the next Ruby blockers for this app are
composition and operator parity, not collection `map`/`filter` itself.

Status: active Ruby parity pressure.

Pressure registry entries: `AL-P03`, `AL-P04`.

---

### 4. Stringly `call_contract` Remains A Composition Pressure

`api.ig` uses:

```igniter
call_contract("FindFeasibleOrders", t, order_queue)
```

This is intentionally app-pressure evidence. It should eventually route through typed contract refs,
forms, or a composition surface, not ad hoc string dispatch.

Status: design pressure.

Pressure registry entry: `AL-P03`.

---

### 5. Ruby `<` Operator Parity Is Still Open

`router.ig` uses `<` inside the filter predicate:

```igniter
(transport.cur_mass + order.pkg.mass) < transport.max_mass
```

The Rust probe accepts this path. Ruby reports `Unsupported operator: <`. This aligns with numeric
and operator parity pressure from ERP logistics, but this app uses Integer capacity checks rather
than Float/Decimal.

Status: active operator parity pressure.

Pressure registry entry: `AL-P04`.

---

### 6. Inline Record Construction In Higher-Order Contexts Remains Awkward

The app avoids constructing a nested record inside the `map` lambda because prior attempts were
reported as parser failures around `{ ... }` inside higher-order expression bodies. The current
source documents the workaround by passing multiple arguments to `call_contract` directly.

Status: historical / needs minimal current fixture.

Pressure registry entry: `AL-P05`.

---

### 7. Method-Like Qualified Calls Remain Closed

The report originally noted that `stdlib.collection.map(...)` is not valid because call targets are
bare names, not field-access expressions. This remains a source-surface design question, but it
should not be solved casually. It overlaps with stdlib import surface and form/vocabulary work.

Status: design pressure / no implementation route yet.

Pressure registry entry: `AL-P06`.

---

### 8. `sqrt` / Math Stdlib Is Deferred

`spatial.ig` computes squared Euclidean distance:

```igniter
compute sq_dist = (dx * dx) + (dy * dy)
```

This avoids requiring `sqrt`. The workaround is acceptable for this fixture. Treat it as math stdlib
pressure only after numeric operator/literal work is better grounded.

Status: deferred.

Pressure registry entry: `AL-P07`.

---

## Current Pressure Ranking

| Rank | Pressure | Why |
|---:|---|---|
| 1 | `stdlib.collection` import surface | Blocks real source files before typechecking. |
| 2 | Stringly `call_contract` | Blocks Ruby probe and remains composition debt. |
| 3 | Ruby `<` operator parity | Blocks capacity predicates after import barrier is removed. |
| 4 | Inline record construction in HOF context | Keeps app composition awkward; needs minimal proof. |
| 5 | Method-like qualified calls | Design pressure; likely not a direct syntax fix. |
| 6 | `sqrt` / math stdlib | Useful later; current squared-distance workaround is fine. |

---

## Recommended Next Routes

1. **LANG-STDLIB-IMPORT-SURFACE-P1**
   Decide whether stdlib namespaces should become importable source modules, remain aliases only, or
   be represented through a registry/prelude mechanism.

2. **Typed-ref/forms composition route**
   Replace stringly `call_contract` with typed refs/forms/composition once the relevant track is ready.

3. **LAB-RUBY-OPERATOR-PARITY-P1**
   Cover `<` and related comparison parity. This app contributes an Integer comparison pressure case.

4. **LAB-PARSER-RECORD-IN-HOF-P1**
   Minimal proof for inline record literals inside lambda/block expression contexts.

5. **LAB-STDLIB-MATH-P1**
   Only after numeric readiness; `sqrt` is useful but not blocking this app today.

---

## Non-Goals

This app does not authorize:

- production logistics runtime;
- real routing or optimization execution;
- stdlib module import semantics;
- method-call syntax changes;
- `call_contract` canonization;
- parser recovery rewrites;
- math stdlib implementation;
- VM/runtime changes.

---

## Operating Decision

Keep Advanced Logistics as a high-signal app-pressure fixture for stdlib import surface and
composition. Do not mutate the app to hide `OOF-IMP2`; the import failure is the current primary
signal. Use probe copies only to reveal downstream blockers.
