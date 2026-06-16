# igniter-ui-kit — a proto UI-components kit (forms) over igniter-frame

`igniter-ui-kit` proves the AUTHORING model over the **`igniter-frame`** runtime: build UI from a
small declarative component vocabulary instead of hand-rolled rect facts. It is the fourth thing
over one runtime (2D demo, 3D sim, GUI engine, and now a components kit), and the layer an
`igniter-ide` will be built FROM.

```text
igniter-machine     = state kernel                        (NOT a dependency here)
igniter-frame       = FrameRuntime + Projector + hit_test + send/click + RenderHost + lineage/replay
igniter-ui-kit      = component vocabulary + FormProjector + form_reducer + FormRenderHost
```

Depends on `igniter_frame` with **`default-features = false`** → no `igniter-machine` in the
core/browser path.

## Vocabulary + the DX example

`Component = Label | Text | Select | Checkbox | Button` (the form body is a vertical `Stack`):

```rust
Form::lead_intake() = Form { title: "Lead Intake", body: Stack[
    label("New Lead"),
    text("name",  "Name",  /*required*/ true),
    text("phone", "Phone", true),
    select("source", "Source", &["web", "referral", "ad"], true),
    checkbox("qualified", "Qualified"),
    button("submit", "Submit", "submit"),
]}
```

## How it uses igniter-frame

| concern | igniter-frame primitive |
|---|---|
| component tree → screen | `FormProjector` (a `Projector`) |
| pointer → intent | box `hit_test` + `derive_intent` via `FrameRuntime::click` |
| keyboard → intent | `FrameRuntime::send("type",{char})` / `send("backspace")` — host routes, reducer owns the value |
| field/checkbox/select/validation state | `form_reducer` (an `IntentReducer`) |
| render | `FormRenderHost` (a `RenderHost`) |
| frame / digest / lineage / replay | `Frame` + `render_digest` + `input → effect → frame` |

The host stays thin: a browser catches DOM pointer + keyboard events but only ROUTES them; layout,
hit-test, intent routing, field state, and validation all run in Rust.

## Proof

```bash
cargo test                                                     # 9 native tests (machine-free)
cargo build --release --target wasm32-unknown-unknown --features wasm   # WASM build proof
```

Focus a field and type (the reducer mutates the value, not the host); cycle the select; toggle the
checkbox; Submit validates required fields and shows a banner or per-field validation messages — all
from state. Deterministic replay of a form event log yields identical frames.

## Live browser

```bash
cargo install wasm-bindgen-cli --version 0.2.125   # match the wasm-bindgen dep
web/build.sh                                        # build wasm + glue + serve 127.0.0.1:8734
# open http://127.0.0.1:8734/index.html
```

Click a field, type, cycle the select, toggle, Submit. JS only maps the pointer + forwards key
events; the form runs in Rust (WASM). "Verify replay" replays a form event log twice and confirms
byte-identical frames. The generated `web/igniter_ui_kit.js` + `igniter_ui_kit_bg.wasm` are build
artifacts (gitignored); `index.html` + `build.sh` are sources.

## Composition (P10): the Lead Review workbench

`composition.rs` proves screen composition over the same runtime — a nested `Workbench` of three
panels:

```rust
Workbench::lead_review()
//  sidebar   List[Ada, Grace, Linus]   (selectable)
//  main      Form[priority, stage, hot, Submit]   (the selected lead's form)
//  inspector KeyValuePanel             (derived from the selected lead's state)
```

`WorkbenchProjector` lays out the three columns (panel backgrounds + per-region widget stacks);
`hit_test` (innermost-box) routes clicks to nested children; ids encode nesting
(`lead:Ada`, `fld:Ada:stage`, `act:submit`). Component ids are **stable** (per-lead state persists
across selection), validation is **scoped** per lead (`err:<lead>`, not a global string), **focus**
is a `__focus__` fact that clears when its field leaves on a selection change, and the inspector is
**derived from selection**. `cargo test` runs 8 composition tests; the P9 form tests stay green.

Live: `web/build.sh` then open `http://127.0.0.1:8734/workbench.html` (the form demo is at
`/index.html`). Select a lead, edit its fields, Submit; the host only maps DOM events.

## Boundary / status

Lab-only. No window, no GPU, no network beyond localhost, no UI framework. Not Igniter Lang canon.
A proto kit, not a design system; it proves the authoring model that an IDE would consume.
