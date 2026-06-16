# lab-frame-ui-kit-forms-p9-v0 — a proto UI-components kit (forms) over igniter-frame

**Card:** `LAB-FRAME-UI-KIT-FORMS-P9` (new crate `igniter-ui-kit`, over `igniter-frame`)
**Status:** CLOSED — proven (native + live browser). A small declarative component vocabulary
compiles/projects into frame nodes; input (pointer + keyboard) routes to component intents; field
state flows through a reducer (never the host); validation appears from state. A compact `LeadForm`
is the DX proof. Machine-free, deterministic, replayable.

## Why a kit (not the IDE) next

P8 proved a GUI is a domain over `igniter-frame`. Before an IDE (which would force navigation,
panels, trace semantics, UX decisions), the missing layer is the AUTHORING MODEL: build UI from a
component vocabulary, not hand-rolled rect facts. With a forms kit proven, the IDE becomes "the first
big app over the components", not an experiment.

## The vocabulary + authoring model

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

`Component` = `Label | Text | Select | Checkbox | Button` (the body `Vec` is the `Stack`). The author
writes a declarative tree; the kit does the rest.

## How it maps onto igniter-frame (the re-use)

| kit concern | igniter-frame primitive |
|---|---|
| component tree → screen | `FormProjector` (a `Projector`): walks the tree + state → frame node boxes |
| layout | vertical stack of boxes + auto `ValidationMessage`/banner rows |
| pointer → intent | box-aware `hit_test` + `derive_intent` (focus / cycle / toggle / submit) via `FrameRuntime::click` |
| keyboard → intent | `FrameRuntime::send("type", {char})` / `send("backspace", …)` — host routes, reducer owns the value |
| field / checkbox / select / validation state | an `IntentReducer` (`form_reducer`) over world facts |
| render | `FormRenderHost` (`RenderHost`): rects, labels, caret, checkbox, red validation, banner |
| frame / digest / lineage / replay | igniter-frame `Frame` + `render_digest` + `input→effect→frame` |

Only one runtime generalization was needed: a **`send(action, params)`** path (a system intent
carrying params, e.g. a keystroke), with lineage `<action>:N` — `dispatch` (the 3D tick) is now
`send(action, Null)`, so 3D lineage `tick:N` is unchanged. State changes only in Rust; the browser
catches DOM `keydown` but merely forwards the character.

## Proof

**Native** (9 tests, `igniter-ui-kit/tests/form_tests.rs`, import only `igniter_ui_kit`):
component tree → frame nodes; focus-then-type updates value via the reducer (focus + 3 keys = 4
effects); typing without focus is a no-op; checkbox toggles + select cycles; submit-empty shows
validation from state; submit-valid shows the banner; deterministic replay of a form event log;
lineage records keystroke events (`type:1 → effect:1 → frame:2`); reset.

**WASM build**: `cargo build --release --target wasm32-unknown-unknown --features wasm` → a 183 KB
`.wasm`; `igniter_ui_kit_bg.wasm` has no `igniter-machine` / `TBackend` / `rocksdb` symbols.

**Live browser** (`igniter-ui-kit/web/index.html`, headless-verified): real `pointerdown` focuses a
field; real `keydown` events type "Ada Lovelace" into it (caret rendered); the select cycles to
`web`; the checkbox toggles; Submit with all required fields filled shows "✓ lead submitted" and no
errors (a clean run lands at exactly `frame_index 15` = 1 focus + 3 keys + 1 + 7 keys + 1 + 1 + 1);
an in-browser "Verify replay" of a 7-event log is byte-identical. The host only routes events.

## Acceptance vs. card

| acceptance | status |
|---|---|
| component tree compiles/projects into frame nodes | ✅ `FormProjector` |
| layout composable: vertical stack + rows | ✅ stack body + validation/banner rows |
| input events routed to component intents | ✅ pointer→`derive_intent`, key→`send("type")` |
| text input state changes through reducer/effect, not the host | ✅ `form_reducer` `type`/`backspace` |
| checkbox / select / button work | ✅ `toggle` / `cycle` / `submit` |
| validation message appears from state | ✅ submit → errors fact → `ValidationMessage` nodes |
| deterministic replay of a form event log | ✅ native + in-browser |
| browser/WASM live form | ✅ live (real pointer + keyboard) |
| frame lineage keeps `input→effect→frame` | ✅ incl. `type:N` keystroke lineage |
| DX proof: one compact declarative example | ✅ `Form::lead_intake()` |

## Decisions

- **layout = projection, all mutation = reducer**: `FormProjector` reads structure + state and lays
  out; every change (type/toggle/cycle/submit/validate) is a pure reducer delta. The host never owns
  state — even text input.
- **keyboard via `send`, not a new port**: a system intent carrying the char; the focused field is
  read from state, so routing stays domain-agnostic.
- **validation is state**: submit writes an `errors` fact; the projector turns it into nodes. Errors
  are data, replayable like everything else.
- **structure static, state factual**: the component tree is the authored structure; only mutable
  values are facts → minimal state, deterministic projection.

## Next

- **P10 `igniter-ide`**: now an app over a mature frame with FOUR domains (2D demo, 3D sim, GUI,
  forms kit) — a time-travel frame viewer + replay strip + lineage inspector + frame diff over
  `__frames__`, built FROM the components kit rather than hand-drawn.
