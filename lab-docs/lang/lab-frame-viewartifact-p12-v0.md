# lab-frame-viewartifact-p12-v0 — portable ViewArtifact JSON → kit tree → runtime

**Card:** `LAB-FRAME-VIEWARTIFACT-P12` (in `igniter-ui-kit`, over `igniter-frame`)
**Status:** CLOSED — proven (native + live browser). A structured **ViewArtifact JSON** compiles to
the proven Rust kit (`Form` / `Workbench`) and runs on `FrameRuntime` with **byte-identical**
behavior to the hand-written constructor. This is the first portable app-authoring layer from the
P11 model — data, not a DSL. Machine-free.

## What this proves

P11 named the next authoring layer: a **ViewArtifact JSON** that compiles to the kit tree, *before*
any text DSL, because data is inspectable/diffable/generatable. P12 builds and proves exactly that
lowering:

```text
ViewArtifact JSON  →  igniter-ui-kit component tree (Form / Workbench)  →  igniter-frame FrameRuntime
```

The compile is deterministic: the canonical `lead_review.view.json` yields a runtime whose frames
are **byte-identical** to `Workbench::lead_review()` — same initial digest and same digest sequence
over a full multi-panel event log. The JSON is genuinely the authoring layer, not a description.

## The artifact (the authoring data)

`igniter-ui-kit/web/lead_review.view.json` (the SAME file tests and the browser load):

```json
{
  "artifact": "view", "version": 0, "screen": "lead_review", "layout": "workbench",
  "data": { "leads": ["Ada", "Grace", "Linus"] },
  "regions": {
    "sidebar":   { "component": "List", "bind": "leads", "on_select": "select" },
    "main":      { "component": "Form", "for_each": "selected", "fields": [
        { "id": "priority", "kind": "text",     "label": "Priority", "required": true },
        { "id": "stage",    "kind": "select",   "label": "Stage", "options": ["new","qualified","won"], "required": true },
        { "id": "hot",      "kind": "checkbox", "label": "Hot lead", "required": false } ],
      "submit": { "label": "Submit", "action": "submit" } },
    "inspector": { "component": "KeyValuePanel", "bind": "selected" }
  }
}
```

A second artifact, `lead_intake.view.json` (`"layout": "form"`), compiles to the P9 `Form`.

## The compiler (`src/view_artifact.rs`)

A deterministic lowering with diagnostics — `serde_json::Value` walking, no derive, no parser
beyond serde_json:

- `compile(json) -> Result<Screen, ViewError>` validates `"artifact":"view"` and dispatches on
  `"layout"` (`workbench` → `Workbench`, `form` → `Form`).
- `compile_workbench` / `compile_form` convenience.
- `ViewError::{Parse, Schema}` carries a human-readable reason (it is a developer-facing authoring
  layer): malformed JSON, not-a-view-artifact, unknown layout, a `select` field missing `options`,
  an unknown field/component kind — each a precise message.
- Runtimes get `WorkbenchRuntime::from_artifact(json)` / `FormRuntime::from_artifact(json)`.

No `.ig`, no `.igv`, no canon change. The `bind`/`on_select`/`action` keys are present in the schema
(the P11 `.ig`-binding seam) but resolve to local data + reducer actions here — the `.ig` bridge
stays a future card.

## Proof

**Native** (9 tests, `igniter-ui-kit/tests/view_artifact_tests.rs`, machine-free):

| acceptance | test |
|---|---|
| workbench JSON ≡ hand-written, byte-identical over a full event log | `workbench_json_compiles_to_byte_identical_runtime` |
| form JSON ≡ `lead_intake()`, byte-identical | `form_json_compiles_to_byte_identical_runtime` |
| the compiled screen renders the authored components | `workbench_json_renders_the_authored_screen` |
| `compile` dispatches on layout | `compile_dispatches_on_layout` |
| malformed JSON → `Parse` error | `malformed_json_is_a_parse_error` |
| not a view artifact → `Schema` error | `not_a_view_artifact_is_rejected` |
| unknown layout / select-without-options / unknown field kind → `Schema` errors (precise) | 3 tests |

P9 (9) + P10 (8) tests stay green → 26 in the crate.

**WASM build**: `cargo build --release --target wasm32-unknown-unknown --features wasm` → the
`.wasm` exposes `WasmWorkbench.from_artifact`; no `igniter-machine`/`TBackend`/`rocksdb` symbols.

**Live browser** (`igniter-ui-kit/web/viewartifact.html`, headless-verified): the page `fetch`es
`lead_review.view.json`, calls `WasmWorkbench.from_artifact(json)` (no Rust constructor), and shows
a badge **"✓ byte-identical to hand-written `Workbench::lead_review()`"** by comparing the
JSON-built runtime's digest to a hand-built one — true in-browser. Real `pointerdown`/`keydown`
drive the JSON-built workbench (select Grace, type into a field), and the in-page replay of an
8-event multi-panel log is byte-identical. The host only maps DOM events.

## Acceptance vs. card

| acceptance | status |
|---|---|
| ViewArtifact JSON → ui-kit tree → FrameRuntime | ✅ `compile` + `from_artifact` |
| byte-identical to the hand-written constructor | ✅ native + in-browser badge |
| real compile with diagnostics (not just happy path) | ✅ `ViewError::{Parse,Schema}`, 5 error tests |
| machine-free (no machine in core/browser path) | ✅ wasm has no machine symbols |
| live browser proof | ✅ `from_artifact` from fetched JSON, interactive |
| P9/P10 tests stay green | ✅ 26 total |
| no `.ig`/`.igv`/canon changes | ✅ data + serde_json only |

## Decisions

- **JSON is the authoring layer**, not a description: it compiles to the kit and IS the runtime.
- **single source of truth**: the `.view.json` files are loaded by BOTH the tests (`include_str!`)
  and the browser (`fetch`) — no drift between proof and demo.
- **byte-identical is the contract**: the lowering must reproduce the hand-written constructor
  exactly (proven by digest-sequence equality), so the artifact is a faithful authoring layer.
- **diagnostics matter**: a developer-facing authoring layer must reject bad input with a reason.
- **`.ig` binding seam present but not wired**: `bind`/`action` keys exist; resolving them to `.ig`
  contracts/effects is a named future card, not silent drift.

## Next

- **`LAB-FRAME-APP-CONSOLE-P13`** *(app)* — an operator-console / IDE-shell that consumes
  ViewArtifact-authored screens (replay strip / frame viewer / lineage inspector / frame diff over
  `__frames__`), built FROM the kit rather than inventing layout primitives.
- **`LAB-FRAME-IGV-SYNTAX-P14`** *(later)* — an `.igv` ergonomic DSL over this now-stable JSON shape.
- **`.ig` binding bridge** *(separate, explicit)* — resolve `bind`/`action` to real `.ig`
  data-sources/effects; only when intended, never implicit.
