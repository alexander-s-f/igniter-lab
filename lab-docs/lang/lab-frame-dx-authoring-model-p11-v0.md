# lab-frame-dx-authoring-model-p11-v0 — what does a developer write?

**Card:** `LAB-FRAME-DX-AUTHORING-MODEL-P11` (readiness/design — NO code changes)
**Status:** CLOSED — the authoring model is formalized below so future agents do not invent it
inside the first app. All of it is **lab-only implementation evidence, not Igniter Lang canon.**

P2–P10 proved the mechanics (`state → frame → input → intent → state`; component tree → frame
nodes; host maps DOM events only; Rust owns hit-test/intent/reducer/projection). The open question
is the developer DX: **when someone wants to build a UI, what do they actually write?**

## 1. Current proven DX (Rust, today)

Today the authoring layer is Rust. A whole screen is one constructor.

```rust
// a single form (P9)
let mut ui = FormRuntime::lead_intake();        // Form { title, body: Vec<Component> }
ui.click(cx, cy);  ui.key("A");  ui.backspace(); // host routes events; reducer owns state
let svg = ui.render_svg();

// a composed multi-panel screen (P10)
let mut wb = WorkbenchRuntime::lead_review();    // Workbench { leads, fields }
wb.click(cx, cy);  wb.key("P");                  // select lead / focus / type / cycle / toggle / submit
```

The authoring vocabulary the developer touches:

| piece | role | example |
|---|---|---|
| `Component` / `Form` | declarative widget tree (the form body is a `Stack`) | `text("name","Name",true)`, `select(...)`, `checkbox(...)`, `button("submit","Submit","submit")` |
| `Workbench` | a composed screen (regions + per-record fields) | `Workbench::lead_review()` |
| `Projector` | layout: world facts → frame nodes (boxes) | `FormProjector`, `WorkbenchProjector`, `CameraProjector` |
| `IntentReducer` | the update logic: `(intent, world) → deltas` | `form_reducer`, `workbench_reducer` |
| `RenderHost` | frame → artifact (SVG today) | `FormRenderHost`, `WorkbenchRenderHost`, `WireframeRenderHost` |
| `FrameRuntime` | the runtime: `click`/`key`/`send`/`dispatch` → frame + lineage | `with_projector(world, reducer, projector, viewport, host)` |

So **today a developer writes Rust** — and there are really two developer roles already (see §3):
extending the *platform* (new components/projectors/hosts/reducers) vs. *authoring an app screen*
(composing existing components into a `Form`/`Workbench`).

## 2. Layer taxonomy

```text
Rust kit API          platform/widget authoring — PROVEN. Components, Projector, RenderHost,
                      IntentReducer, FrameRuntime ports. This is where new capability is added.

ViewArtifact JSON     the first PORTABLE app-authoring artifact — PROPOSED (lab). A structured,
                      inspectable, diffable screen description that compiles to the Rust kit tree.
                      Comes before a text DSL precisely because it is data (easy to generate, diff,
                      validate, round-trip).

.igv                  a future ergonomic view DSL — CANDIDATE (lab-only), sugar over ViewArtifact.
                      Not canon. Only worth a parser AFTER the JSON shape is stable.

.ig                   business logic / state / effects / contracts — the data + action authority.
                      NOT a UI markup language by default. It supplies data sources, validation
                      contracts, actions, and effect bindings that a view binds to.

browser/host glue     thin. Maps DOM pointer/keyboard events to runtime API calls and draws the
                      returned SVG. Owns no state, computes no intent. (P6/P9/P10 proven.)
```

## 3. Authority boundaries

- **Lab-only.** Everything in `igniter-frame` / `igniter-3d` / `igniter-gui` / `igniter-ui-kit` is
  frontier evidence. None of it is Igniter Lang canon; there is no stable public UI API claim.
- **Implementation evidence vs. proposal.** The Rust kit API + runtime are *proven* (native + live
  browser). `ViewArtifact JSON` and `.igv` are *design artifacts* in this doc — not implemented
  syntax.
- **`.ig` must NOT silently become a UI markup language.** `.ig` is the contract/state/effect
  language. A view *binds* to `.ig` (data source, action → effect, validation contract); it does not
  live inside `.ig`. Keeping layout/interaction in the view layer (ViewArtifact/.igv/kit) preserves
  `.ig`'s authority as business logic and prevents the canon language from accreting presentation
  concerns. Any `.ig`↔view bridge must be an explicit, named card — never an implicit drift.
- **No machine dependency** in the UI-kit core or browser path (all kit crates depend on
  `igniter_frame` with `default-features = false`; the wasm artifacts carry no `igniter-machine`
  symbols).

## 4. Authoring pipeline

```text
.ig   contracts / state / effects / validation rules / data sources
  ▲
  │  bindings:  data source (e.g. `leads`),  action → effect (e.g. `submit`),  validation contract
  │
ViewArtifact JSON   ── portable, diffable screen ──   (── or ──  .igv   ergonomic DSL, future)
  │
  │  compile  (a deterministic lowering — the P12 proof)
  ▼
igniter-ui-kit component tree     Form / Workbench / Component / Panel / List / KeyValuePanel
  │
  │  project (layout) · reduce (update) · render
  ▼
igniter-frame FrameRuntime        state → frame → input → intent → state ; lineage ; replay
  │
  │  host maps DOM events only
  ▼
browser / WASM host               render_svg() → DOM ;  pointerdown/keydown → rt.click()/key()
```

- **Where state facts live:** in the runtime world (`__world__`-shaped facts inside `FrameRuntime`):
  field values, `__focus__`, `__selection__`, `err:<scope>`. These are VIEW-LOCAL runtime state.
- **Where reducer/effect ownership lives:** the `IntentReducer` owns view-local updates (focus,
  typing, toggle, cycle, scoped validation). A `.ig`-bound action (e.g. a real `submit`) is where a
  reducer action would invoke an `.ig` effect/contract — that bridge is a *future* card, not built
  here. Today `submit` validates locally.

## 5. Minimal example — the lead-review workbench, three ways

**(a) Current Rust API (PROVEN):**

```rust
Workbench {
    leads: vec!["Ada".into(), "Grace".into(), "Linus".into()],
    fields: vec![
        FieldSpec { id: "priority".into(), label: "Priority".into(), kind: FieldKind::Text, required: true },
        FieldSpec { id: "stage".into(), label: "Stage".into(),
                    kind: FieldKind::Select(vec!["new".into(), "qualified".into(), "won".into()]), required: true },
        FieldSpec { id: "hot".into(), label: "Hot lead".into(), kind: FieldKind::Checkbox, required: false },
    ],
}
// → WorkbenchRuntime::new(wb): WorkbenchProjector + workbench_reducer + WorkbenchRenderHost over FrameRuntime
```

**(b) Proposed ViewArtifact JSON (DESIGN ONLY — not implemented):**

```json
{
  "artifact": "view", "version": 0, "screen": "lead_review", "layout": "workbench",
  "regions": {
    "sidebar":   { "component": "List", "bind": "leads", "on_select": "select" },
    "main":      { "component": "Form", "for_each": "selected", "fields": [
        { "id": "priority", "kind": "text",     "label": "Priority", "required": true },
        { "id": "stage",    "kind": "select",   "label": "Stage", "options": ["new","qualified","won"], "required": true },
        { "id": "hot",      "kind": "checkbox", "label": "Hot lead" }
      ], "submit": { "label": "Submit", "action": "submit" } },
    "inspector": { "component": "KeyValuePanel", "bind": "selected" }
  }
}
```

**(c) Optional `.igv` sketch (CANDIDATE — not implemented, no parser):**

```text
view lead_review = workbench {
  sidebar:   list(leads) on select -> select
  main:      form for selected {
    text   priority "Priority" required
    select stage    "Stage" [new, qualified, won] required
    check  hot      "Hot lead"
    button submit   "Submit" -> submit
  }
  inspector: keyvalue(selected)
}
```

(b) and (c) describe the SAME screen as (a). The JSON is preferred as the first portable artifact
because it is inspectable, diffable, and trivially generated/validated; `.igv` is sugar over it.

## 6. State and binding model

- **Stable ids.** Components are addressed by explicit ids (`fld:<record>:<field>`, `lead:<name>`,
  `act:submit`, `kv:<key>`). Ids are deterministic and stable across re-render/re-layout, so
  per-record state is keyed and survives selection changes (P10 proved Ada's value persists across a
  Grace round-trip).
- **Mapping to state facts:**
  - field value → `fld:<record>:<field>` fact (`{kind:"text"|"select"|"checkbox", value/selected/checked}`)
  - focus → `__focus__` fact (`{id}`); cleared when the focused component leaves on layout change
  - validation → `err:<record>` fact (scoped per record/panel, NOT a global string)
  - selection → `__selection__` fact (`{lead}`)
  - inspector data → DERIVED in the projector from `__selection__` + the record's facts (no own state)
- **UI action → intent → update:** a pointer hit → `derive_intent` (from the node's declared
  `on_click`) → reducer action; a keystroke → `FrameRuntime::send("type",{char})` routed to the
  `__focus__` field. A `.ig`-bound action would be where the reducer calls an `.ig` effect/contract
  (future bridge). Everything advances the runtime with `input → effect → frame` lineage and is
  byte-identical on replay.

## 7. What NOT to build yet

- No `.igv` parser/compiler.
- No `igniter-lang` canon changes; no `.ig`-as-UI-markup.
- No `igniter-ide` product UX.
- No JS app framework; no reducer/intent logic in JS.
- No `igniter-machine` dependency in the UI-kit core or browser path.
- No stable public UI API claim.

## 8. Next-card recommendations (named, not started)

1. **`LAB-FRAME-VIEWARTIFACT-P12`** *(implementation)* — a proof-local structured **ViewArtifact
   JSON → `igniter-ui-kit` component tree → `igniter-frame` runtime** lowering, using this model.
   Acceptance shape: the lead-review JSON compiles to the same runtime behavior as the hand-written
   `Workbench::lead_review()` (ideally byte-identical frame digests), machine-free, with a live
   browser proof. This comes BEFORE any `.igv` syntax.
2. **`LAB-FRAME-APP-CONSOLE-P13`** *(app)* — a small operator-console / IDE-shell that CONSUMES the
   authoring model (ViewArtifact-driven screens), rather than inventing layout primitives. This is
   where a replay strip / frame viewer / lineage inspector / frame diff over `__frames__` would
   live — as a consumer of the kit.
3. **`LAB-FRAME-IGV-SYNTAX-P14`** *(later)* — an `.igv` ergonomic DSL over ViewArtifact, ONLY after
   the JSON artifact shape is stable. Lab candidate, not canon.

## Answer, in one line

> Today a developer writes **Rust** (platform authoring) and composes existing components into a
> `Form`/`Workbench` (app authoring). The next portable app-authoring layer is a **ViewArtifact
> JSON** that compiles to the kit tree; `.igv` is a future sugar; `.ig` stays the
> business-logic/state/effect authority that views *bind to*, never a UI markup language.
