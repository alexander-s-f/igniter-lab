# lab-frame-ui-kit-composition-p10-v0 — composable workbench screens over igniter-frame

**Card:** `LAB-FRAME-UI-KIT-COMPOSITION-P10` (in `igniter-ui-kit`, over `igniter-frame`)
**Status:** CLOSED — proven (native + live browser). A nested component tree (Sidebar[List] /
Main[Form] / Inspector[KeyValuePanel]) composes into a multi-region screen over the SAME runtime:
stable ids, nested event routing, focus survival across layout changes, scoped (per-record)
validation, selection driving another panel, deterministic replay. Machine-free.

## Why composition before the IDE

P9 proved a single declarative `LeadForm`. An IDE would immediately need split views, lists,
inspectors, selection state, and per-form errors — and would invent those ad hoc, drifting the kit
shape inside the first app. P10 crystallizes the screen-composition model first, so the IDE becomes a
CONSUMER of a mature kit.

## The DX example

```rust
Workbench::lead_review()
//  sidebar  List[Ada, Grace, Linus]            (selectable)
//  main     Form[priority(text,req), stage(select,req), hot(checkbox), Submit]   (per selected lead)
//  inspector KeyValuePanel  (derived from the selected lead's state)
```

`WorkbenchRuntime::lead_review()` is the whole app. The author writes structure; the kit lays out
three regions, routes events to nested components, and derives the inspector from state.

## How it composes over igniter-frame

| composition concern | igniter-frame mechanism |
|---|---|
| nested tree → screen | `WorkbenchProjector` (a `Projector`): panels (background) + per-region widget stacks |
| 3-region layout | sidebar / main / inspector columns, each a vertical stack |
| nested event routing | box `hit_test` (**innermost-box wins**) + `derive_intent`; ids encode nesting (`lead:Ada`, `fld:Ada:stage`, `act:submit`, `kv:*`) |
| keyboard | `FrameRuntime::send("type",{char})` → the `__focus__` field |
| state (select / focus / type / toggle / cycle / submit+validate) | one `IntentReducer` (`workbench_reducer`) |
| render | `WorkbenchRenderHost` (`RenderHost`): panels, list items, fields, checkbox, button, kv rows |
| frame / digest / lineage / replay | igniter-frame `Frame` + `render_digest` + `input→effect→frame` |

**Stable ids**: components are addressed by explicit ids (`fld:<lead>:<field>`), so per-lead state is
keyed and survives re-selection — not positional. **Scoped validation**: submit writes an
`err:<lead>` fact; the projector reads only the selected lead's errors (no global error string).
**Focus survival**: focus is a `__focus__` fact; selecting a different lead (a layout change) clears
it because the focused field no longer exists — re-selecting preserves the value but not the focus.
**Selection drives the inspector**: the KeyValuePanel is derived from `__selection__` + that lead's
field facts.

## One domain-neutral runtime generalization

`hit_test` now returns the **innermost (smallest-area) containing box** (tie-broken by node order),
so a panel background behind interactive children routes the click to the child. Point scenes and
the P8/P9 single-box scenes are unaffected (a single containing box is still chosen).

## Proof

**Native** (8 tests, `igniter-ui-kit/tests/workbench_tests.rs`): nested tree → three regions;
selection routes + updates the inspector; nested field editing updates the inspector via the
reducer; stable ids preserve per-lead state across selection; focus survives within a lead but
clears when its component leaves (keystroke then no-ops); validation is scoped per lead (Grace shows
`errors: 0` while Ada shows `errors: 2`); deterministic replay of a multi-panel event log; an
empty-panel click is a no-op (hits the panel, no intent). **P9's 9 form tests stay green.**

**WASM build**: `cargo build --release --target wasm32-unknown-unknown --features wasm` → a 248 KB
`.wasm`; `igniter_ui_kit_bg.wasm` has no `igniter-machine` / `TBackend` / `rocksdb` symbols.

**Live browser** (`igniter-ui-kit/web/workbench.html`, headless-verified): real `pointerdown`
selects a lead and focuses/cycles/toggles fields; real `keydown` types into the focused field; the
inspector follows selection + edits; selecting a different lead clears focus (next keystroke is a
no-op) and re-selecting preserves the value; Submit shows per-lead validation (`errors: 2` for the
empty lead, `errors: 0` for another); an in-browser "Verify replay" of an 8-event multi-panel log is
byte-identical. The host only maps DOM events.

## Acceptance vs. card (all 12)

| # | acceptance | status |
|---|---|---|
| 1 | nested tree projects to frame nodes | ✅ `WorkbenchProjector` |
| 2 | layout composition (sidebar/main/inspector) | ✅ 3 columns |
| 3 | component ids stable across re-render/layout | ✅ `fld:<lead>:<field>`, per-lead persistence |
| 4 | focus survives if component exists, clears if not | ✅ clears on selection change → keystroke no-op |
| 5 | event routing through nested components | ✅ listitem / field / button / kv |
| 6 | validation scoped per form/panel, not global | ✅ `err:<lead>` fact |
| 7 | selection updates another panel | ✅ inspector derived from selection |
| 8 | text/checkbox/select/button via reducer, not host | ✅ `workbench_reducer` |
| 9 | deterministic replay of a multi-panel event log | ✅ native + in-browser |
| 10 | live browser, host only maps events | ✅ |
| 11 | no machine/TBackend/RocksDB in the wasm | ✅ |
| 12 | P9 form tests stay green; P10 adds tests | ✅ 9 + 8 |

## Decisions

- **layout = projection, all mutation = reducer** (incl. selection, focus, text) — the host never
  owns component state or computes intent.
- **ids are explicit + stable**; per-record state is keyed by id, so it persists across selection and
  re-layout.
- **validation + focus are state** (`err:<lead>`, `__focus__`) → replayable like everything else.
- **innermost hit-test** is the only runtime change — domain-neutral, needed for nesting.
- composition is kit-level; product/IDE semantics are deferred.

## Next

- **`LAB-FRAME-IDE-P11`**: a small IDE prototype built FROM these components (replay strip, frame
  viewer, lineage inspector, frame diff over `__frames__`) — consuming P10 layout primitives rather
  than inventing them.
