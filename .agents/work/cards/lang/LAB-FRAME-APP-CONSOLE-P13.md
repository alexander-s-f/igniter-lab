# Card: LAB-FRAME-APP-CONSOLE-P13 — an IDE-shell built from the kit

> New crate `igniter-console` over `igniter-ui-kit` / `igniter-frame`. The first app consuming the
> authoring stack. Builds on `LAB-FRAME-VIEWARTIFACT-P12`.

**Status: CLOSED 2026-06-16 — proven (native + live browser).** Replay strip + frame viewer +
lineage inspector + frame diff over the recorded frame history, around a ViewArtifact-authored
workbench. No new layout primitives; machine-free. Design doc:
`lab-docs/lang/lab-frame-app-console-p13-v0.md`.

## Goal (met)

The first app FROM the kit: wrap a ViewArtifact app with developer tooling, consuming the proven
pieces rather than inventing layout.

## Implementation

- new crate `igniter-console` (deps `igniter_frame` default-features=false + `igniter_ui_kit`).
- `Console::from_artifact(json)` runs a `WorkbenchRuntime` (P12) + records the initial frame;
  `FrameRecord` history (frame-as-fact: digest + lineage + nodes).
- chrome = a tiny `igniter-frame` `Frame` (strip chips + viewer box) hit-tested with `hit_test`
  (innermost-box); viewer embeds the target's OWN SVG (nested `<svg>` re-scaled).
- routing: chip → `select_step` (read-only time-travel); viewer → translate to target coords +
  forward (`click`/`key`) → record. `diff()` = node-level changes vs predecessor.
- ONE read-only kit accessor added: `FrameRuntime::frame()` (+ `WorkbenchRuntime::frame()` passthrough).
- `src/wasm.rs` `WasmConsole.from_artifact`.

## Proof

- **Native** (7 tests, `tests/console_tests.rs`): shell built, viewer-forward records, chip scrubs
  without mutation, node-level diff (added/removed/changed), lineage reflects selected step (live +
  scrubbed), typing forwards to reducer, initial frame has no diff.
- **WASM**: `WasmConsole.from_artifact` in the `.wasm`; no machine/TBackend/rocksdb symbols.
- **Live browser** (`web/console.html`): fetch JSON → `from_artifact`; real pointer drives the
  embedded app (type "hi", select Grace) adding replay chips; real keydown types; chip click
  time-travels to initial (len unchanged); lineage `type:2→effect:2→frame:3`; diff `changed
  panel:main`, `added fld:Grace:*`, `removed fld:Ada:priority`. Host maps DOM events only.

## Decisions

- the console is an app, not a kit change (one read-only `frame()` accessor);
- the viewer embeds the target's own SVG → can inspect ANY kit app;
- time-travel is read-only (only viewer interaction advances the live target);
- diff is node-level over frames (the visual-debugger substrate).

## Next

- `LAB-FRAME-IGV-SYNTAX-P14` (.igv DSL over the stable JSON shape);
- `.ig` binding bridge (separate explicit: resolve bind/action to real .ig data/effects);
- console depth (optional): multi-app tabs, frame export/import, in-SVG diff highlight.
