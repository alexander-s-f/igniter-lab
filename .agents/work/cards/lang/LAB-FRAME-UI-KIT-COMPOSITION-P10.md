# Card: LAB-FRAME-UI-KIT-COMPOSITION-P10 — composable UI kit screens before IDE

> New layer over `igniter-ui-kit` + `igniter-frame`: prove screen/panel composition and DX
> before building `igniter-ide`. Builds on `LAB-FRAME-UI-KIT-FORMS-P9`.

**Status: CLOSED 2026-06-16 — proven (native + live browser).** Implemented as
`igniter-ui-kit/src/composition.rs` (`Workbench`/`WorkbenchProjector`/`workbench_reducer`/
`WorkbenchRenderHost`/`WorkbenchRuntime`) + `Workbench::lead_review()`. All 12 acceptance points met.
8 native tests (`tests/workbench_tests.rs`) + P9's 9 form tests stay green; WASM build 248 KB
no-machine; live browser `web/workbench.html`. One domain-neutral runtime change: `hit_test` now
returns the innermost (smallest-area) containing box (nesting). Design doc:
`lab-docs/lang/lab-frame-ui-kit-composition-p10-v0.md`.

## Result vs. acceptance

1 nested tree → frame nodes ✅ (`WorkbenchProjector`) · 2 sidebar/main/inspector layout ✅ · 3 stable
ids `fld:<lead>:<field>` (per-lead persistence across selection) ✅ · 4 focus survives within a lead,
clears when its field leaves on selection (keystroke then no-ops) ✅ · 5 nested routing listitem/
field/button/kv ✅ · 6 scoped validation `err:<lead>` (Grace `errors:0` vs Ada `errors:2`) ✅ · 7
selection drives the inspector ✅ · 8 text/checkbox/select/button via reducer ✅ · 9 deterministic
replay of a multi-panel log (native + in-browser, 8 events) ✅ · 10 live browser, host maps events
only ✅ · 11 no machine/TBackend/RocksDB in the wasm ✅ · 12 P9 tests green, P10 adds tests ✅.

## Goal

Prove that Igniter UI apps can be authored from a small composable component vocabulary, not as
single-form demos or hand-written rect facts. The target is a compact workbench-style UI:

```text
Workbench[
  Sidebar[List]
  Main[Form]
  Inspector[KeyValuePanel]
]
```

This is the missing DX layer before IDE: panels, nested components, stable ids, event routing,
scoped validation, deterministic replay, and live browser proof.

## Why now

P9 proved a declarative `LeadForm`. IDE would immediately need split views, lists, inspectors,
selection state, and scoped form errors. If IDE builds those ad hoc, the kit shape will drift inside
the first app. P10 crystallizes the composition model first, so IDE becomes a consumer of a mature
kit rather than a place where the kit is invented.

## Authority / Boundaries

- `igniter-machine` remains closed: no machine dependency in browser/core path.
- `igniter-frame` may receive only domain-neutral runtime generalizations if required.
- `igniter-ui-kit` owns the component vocabulary, projection, reducers, render host, and examples.
- No `igniter-ide`, no product UX, no trace semantics, no persistence beyond existing frame state.
- No GPU, no heavy UI framework, no network. Browser proof must stay localhost/static/WASM.

## Required component vocabulary

Add or prove the minimum useful composition set:

- `Panel`
- `SplitView` or `Workbench`
- `List`
- `ListItem`
- `KeyValuePanel` or `Inspector`
- existing `Form`, `Text`, `Select`, `Checkbox`, `Button`, `Label`, `ValidationMessage`

Names may vary if local code style suggests better names, but the proof must include a
multi-region screen with nested interactive components.

## Proposed DX proof

Use a small lead/workbench example, not IDE yet:

```rust
Workbench::lead_review()
  .sidebar(List::leads(["Ada", "Grace", "Linus"]))
  .main(Form::lead_intake())
  .inspector(KeyValuePanel::selected_lead())
```

Interactions should include selection in the list, editing form fields, scoped validation, and an
inspector update driven by state.

## Acceptance

1. A nested component tree projects to frame nodes through `igniter-frame` ports/runtime.
2. Layout composition works for at least a sidebar/main/inspector or split-view shape.
3. Component ids remain stable across re-render and layout changes.
4. Focus survives layout changes when the focused component still exists; focus clears when it does
   not.
5. Event routing works through nested components (`ListItem`, form field, button, inspector-safe
   display nodes).
6. Validation/errors are scoped per form or panel, not global string state.
7. Selection state updates another panel (for example, sidebar selection changes inspector/details).
8. Text/checkbox/select/button behavior from P9 still routes through reducers/effects, not host
   mutation.
9. Deterministic replay of a multi-panel event log yields byte-identical frame/render digests.
10. Live browser/WASM proof: click/type/select across panels; host only maps DOM events and calls
    Rust runtime APIs.
11. No `igniter_machine`, `TBackend`, or RocksDB symbols in the browser/core WASM artifact.
12. Existing P9 form tests remain green; P10 adds focused composition tests instead of replacing P9.

## Proof shape

- Native tests for the composition model and reducer behavior.
- WASM build proof, machine-free.
- Live browser smoke with real pointer/keyboard events across at least two panels.
- README update showing the authoring example and explaining the component tree → frame → intent
  route.
- Design doc: `lab-docs/lang/lab-frame-ui-kit-composition-p10-v0.md`.

## Design decisions to preserve

- Layout is projection; mutation is reducer/effect.
- Host never owns component state or computes domain intent.
- Component identity is explicit and stable; generated ids must be deterministic.
- Validation is state and therefore replayable.
- Composition is kit-level; IDE/product-specific semantics are deferred.

## Closed surfaces

- Do not build `igniter-ide`.
- Do not add machine dependency to `igniter-ui-kit` core or browser path.
- Do not introduce a JS app framework or move reducer/intent logic into JS.
- Do not implement network, persistence, trace viewer, frame diff, or IDE replay strip here.
- Do not re-home additional domains in this card.

## Next if proven

`LAB-FRAME-IDE-P11` can start as a small IDE prototype built from the kit: replay strip,
frame viewer, lineage inspector, and frame diff. P11 should consume P10 components rather than
inventing layout primitives.
