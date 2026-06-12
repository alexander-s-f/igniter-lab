# Vector Editor Pressure Report

Updated: 2026-06-12

This app models a layered vector editor as pure Igniter contracts. It is a useful pressure fixture because it compresses UI command handling, document-tree updates, optional payload records, and collection transforms into a small multi-file program.

## Live Check

Source files checked:

- `types.ig`
- `transform.ig`
- `document.ig`
- `tools.ig`

Real multi-file compile currently stops before typechecking in both toolchains:

| Toolchain | Result | First blocking diagnostic |
| --- | --- | --- |
| Rust lab compiler | `status: oof` | `OOF-IMP2 unknown import path 'stdlib.collection' from module 'VectorDocument'` |
| Ruby canon compiler | `status: oof` | `OOF-IMP2 unknown import path 'stdlib.collection' from module 'VectorDocument'` |

Probe method: a temporary copy removed only `import stdlib.collection.{ append, map }` from `document.ig` to expose downstream pressure without editing the app.

| Toolchain | Probe result | Downstream signal |
| --- | --- | --- |
| Rust lab compiler | `status: oof` | `OOF-TY0 call_contract: unknown callee 'append'` |
| Ruby canon compiler | `status: oof` | `Unknown function: call_contract`; `Unsupported operator: ==`; cascading unresolved-symbol diagnostics |

## Findings

### VE-P01 - `stdlib.collection` import surface is missing

`document.ig` imports `stdlib.collection.{ append, map }`. Both toolchains reject the module path with `OOF-IMP2` before classification/typechecking. This is the first real blocker and should not be confused with collection helper implementation itself.

Route: `LANG-STDLIB-IMPORT-SURFACE-P1` or equivalent stdlib-as-import design slice.

### VE-P02 - `append` is separate collection pressure

The app needs an append operation for `Collection[GraphicObject]`. After the stdlib import line is removed in a probe, Rust reaches `call_contract("append", layer.objects, obj)` and rejects it as an unknown callee. This is not covered by the current `map/filter/count` line.

Route: `LANG-STDLIB-COLLECTION-APPEND-P1`.

### VE-P03 - Stringly `call_contract` blocks UI command composition

`tools.ig` and `document.ig` use `call_contract("AddObjectToDoc", ...)`, `call_contract("CreateAndAppendRect", ...)`, and `call_contract("AppendObjectToLayer", ...)`. This is exactly the pain that typed contract references and invocation forms are meant to relieve.

Route: typed contract refs / form-assisted invocation follow-up, not a runtime dispatch feature.

### VE-P04 - Text equality parity is app-visible

The UI command reducer compares `state.active_tool == "draw_rect"`, and document updates compare `layer.id == target_layer_id`. Ruby currently reports `Unsupported operator: ==` in the probe. A vector editor needs equality over stable IDs and tool names before it can express ordinary UI commands cleanly.

Route: `LANG-STDLIB-TEXT-EQUALITY-P1` or broader operator parity, scoped to deterministic equality only.

### VE-P05 - Optional record fields are ergonomically valuable, but not enough

`GraphicObject` uses `kind : String` plus optional payload fields (`path_pts`, `rect_data`, `text_data`) to simulate heterogeneous shapes. This is workable and ergonomic for omitted optional fields, but it is not safe: `kind: "text"` can still be paired with `rect_data`.

Route: variant/ADT surface pressure. This should reuse the existing variant/match VM proof lineage rather than inventing another union encoding.

### VE-P06 - UI command reducers want an app-state composition model

`HandleCanvasClick` is already a pure command reducer: `(Document, ToolState, Point) -> Document`. The app wants the language to distinguish durable document state, ephemeral tool state, and command dispatch without introducing runtime authority into pure contracts.

Route: app-state / app-assembly follow-up, connected to the earlier application state research.

### VE-P07 - Integer geometry is a practical workaround, not a final numeric model

`Point`, `RectData`, and transforms use `Integer` coordinates. This avoids Float/Decimal arithmetic and comparison gaps while preserving deterministic geometry. The workaround is acceptable for this pressure app, but real editors will eventually need a declared fixed-point or decimal geometry story.

Route: numeric/fixed-point stdlib track after higher-priority collection/import blockers.

## Current Pressure Ranking

1. `stdlib.collection` import surface (`OOF-IMP2`) - blocks both toolchains before typechecking.
2. Collection `append` - required for document-tree updates, not covered by map/filter/count.
3. Stringly `call_contract` - blocks clean command composition and form-assisted invocation.
4. Text equality - required for tool dispatch and stable ID matching.
5. Variant/ADT surface - removes unsafe `kind` plus optional payload encoding.
6. App-state/app-assembly model - clarifies `Document` versus `ToolState` ownership.
7. Numeric geometry - important later, but integer coordinates keep this app useful today.

## Non-goals

- Do not introduce real UI runtime or canvas drawing authority from this app.
- Do not treat `kind` string routing as a canonical ADT substitute.
- Do not solve stdlib imports by making imports grant capability or runtime authority.
- Do not promote `call_contract` string dispatch as the final composition surface.

## Recommended Next Cards

- `LAB-VECTOR-EDITOR-PRESSURE-P1` - freeze this app as a pressure fixture with proof-local compile probes.
- `LANG-STDLIB-IMPORT-SURFACE-P1` - define how stdlib modules are imported without package/runtime authority.
- `LANG-STDLIB-COLLECTION-APPEND-P1` - propose and prove `stdlib.collection.append`.
- `LANG-STDLIB-TEXT-EQUALITY-P1` - narrow deterministic equality over Text/String IDs.
