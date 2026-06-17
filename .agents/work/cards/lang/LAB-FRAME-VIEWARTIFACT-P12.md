# Card: LAB-FRAME-VIEWARTIFACT-P12 — portable ViewArtifact JSON → kit tree → runtime

> In `igniter-ui-kit`, over `igniter-frame`. Implements the P11 authoring model's first portable
> layer. Builds on `LAB-FRAME-UI-KIT-COMPOSITION-P10` + `LAB-FRAME-DX-AUTHORING-MODEL-P11`.

**Status: CLOSED 2026-06-16 — proven (native + live browser).** A ViewArtifact JSON compiles to the
kit tree and runs byte-identical to the hand-written constructor; machine-free. Design doc:
`lab-docs/lang/lab-frame-viewartifact-p12-v0.md`.

## Goal (met)

Prove the P11 next layer: `ViewArtifact JSON → igniter-ui-kit component tree → FrameRuntime`, with
byte-identical behavior to `Workbench::lead_review()` / `Form::lead_intake()`. Data, not a DSL.

## Implementation

- `src/view_artifact.rs` (machine-free): `compile(json) -> Result<Screen, ViewError>` (validates
  `artifact:"view"`, dispatches on `layout`: workbench→`Workbench`, form→`Form`);
  `compile_workbench`/`compile_form`; `ViewError::{Parse,Schema}` with precise messages.
  serde_json `Value` walking, no derive, no parser beyond serde_json.
- `WorkbenchRuntime::from_artifact` / `FormRuntime::from_artifact`; `WasmWorkbench.from_artifact`.
- `web/lead_review.view.json` + `web/lead_intake.view.json` — the authoring data; the SAME files
  loaded by tests (`include_str!`) and the browser (`fetch`).
- `bind`/`on_select`/`action` keys present (the `.ig`-binding seam) but resolve locally — no `.ig`
  bridge here.

## Proof

- **Native** (9 tests, `tests/view_artifact_tests.rs`): byte-identical workbench + form (full event
  log), compiled screen renders, layout dispatch, and 5 diagnostic tests (parse / not-view /
  unknown-layout / select-without-options / unknown-kind). P9 9 + P10 8 stay green → 26 total.
- **WASM**: `WasmWorkbench.from_artifact` in the `.wasm`; no machine/TBackend/rocksdb symbols.
- **Live browser** (`web/viewartifact.html`): fetch JSON → `from_artifact` → badge "✓ byte-identical
  to hand-written `Workbench::lead_review()`" (in-browser digest compare); real pointer/key drive
  the JSON-built workbench; in-page replay byte-identical over 8 events; host maps DOM events only.

## Decisions

- JSON is the authoring layer (compiles to the kit, IS the runtime), not a description;
- single source of truth (`.view.json` loaded by tests + browser);
- byte-identical is the contract (digest-sequence equality);
- diagnostics required (developer-facing layer rejects bad input with a reason);
- `.ig` binding seam present but not wired (future explicit card).

## Next

- `LAB-FRAME-APP-CONSOLE-P13` (app: operator-console/IDE-shell consuming ViewArtifact screens —
  replay strip / frame viewer / lineage inspector / frame diff over `__frames__`);
- `LAB-FRAME-IGV-SYNTAX-P14` (later: `.igv` DSL over the now-stable JSON shape);
- `.ig` binding bridge (separate explicit card: resolve `bind`/`action` to `.ig` data/effects).
