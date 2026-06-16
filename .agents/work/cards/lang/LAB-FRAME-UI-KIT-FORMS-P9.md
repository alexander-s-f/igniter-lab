# Card: LAB-FRAME-UI-KIT-FORMS-P9 — a proto UI-components kit (forms) over igniter-frame

> New crate `igniter-lab/igniter-ui-kit`, over `igniter-frame` ports/runtime (NOT the machine).
> Builds on `LAB-FRAME-GUI-ENGINE-REHOME-P8`. Related: [[project-gui-3d-exploration]].

**Status: CLOSED 2026-06-16 — proven (native + live browser).** A declarative component vocabulary
compiles/projects into frame nodes; pointer + keyboard route to component intents; field state flows
through a reducer (not the host); validation appears from state; a `LeadForm` is the DX proof.
Machine-free, deterministic, replayable. Design doc: `lab-docs/lang/lab-frame-ui-kit-forms-p9-v0.md`.

## Goal (met)

Prove the AUTHORING model over igniter-frame: build UI from `Form/Label/Text/Select/Checkbox/Button`,
not rect facts. Text input + keyboard is the new capability; host stays thin.

## Vocabulary + example

`Component = Label | Text | Select | Checkbox | Button` (body Vec = the Stack). DX example:
`Form::lead_intake()` (name, phone, source-select, qualified-checkbox, submit + validation).

## Mapping onto igniter-frame

tree→nodes = `FormProjector` (a `Projector`) · pointer→intent = box `hit_test`+`derive_intent` via
`FrameRuntime::click` · keyboard→intent = `FrameRuntime::send("type",{char})`/`send("backspace")` ·
state (focus/type/toggle/cycle/submit+validate) = `IntentReducer` (`form_reducer`) · render =
`FormRenderHost` (`RenderHost`) · frame/digest/lineage/replay = igniter-frame. One runtime
generalization: `send(action, params)` (system intent w/ params, lineage `<action>:N`); `dispatch`
= `send(action, Null)` → 3D `tick:N` unchanged.

## Proof

- **Native** (9 tests `form_tests.rs`): tree→nodes, focus+type via reducer (4 effects), type-without-
  focus no-op, checkbox/select, submit-empty validation, submit-valid banner, deterministic replay,
  keystroke lineage `type:1→effect:1→frame:2`, reset.
- **WASM build**: release wasm32 183 KB, no machine symbols.
- **Live browser**: real `pointerdown` focus + real `keydown` typing ("Ada Lovelace", caret),
  select→web, checkbox toggle, valid Submit → "✓ lead submitted" (clean run = frame 15); in-browser
  Verify-replay byte-identical over 7 events. Host routes only.

## Acceptance

tree→frame nodes ✅ · composable stack+rows ✅ · input→component intents ✅ · text state via
reducer not host ✅ · checkbox/select/button ✅ · validation from state ✅ · deterministic replay ✅
(native+browser) · browser/WASM live ✅ · lineage input→effect→frame (incl type:N) ✅ · DX compact
declarative LeadForm ✅.

## Decisions

- layout = projection, ALL mutation (incl text input) = reducer; host never owns state;
- keyboard via `send` (system intent w/ char), focused field read from state — routing stays
  domain-agnostic;
- validation is state (errors fact → projector nodes), replayable;
- structure static (component tree), only values are facts.

## Next

- P10 `LAB-FRAME-UI-KIT-COMPOSITION-P10`: prove composition and DX first — panels, lists,
  inspectors, scoped validation, stable ids, nested event routing, deterministic replay, live
  browser proof. IDE is intentionally deferred until the kit has a mature screen-composition model.
