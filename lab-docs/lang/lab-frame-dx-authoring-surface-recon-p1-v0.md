# LAB-FRAME-DX-AUTHORING-SURFACE-RECON-P1 — what do we hand a developer? (`.ig` / `.igv`)

Status: RECON COMPLETE — verify-first survey of the real `.ig` logic surface + both `.igv` view
dialects, with a recommended direction. Decision pending.
Lane: igniter-lab / frame-ui / DX
Date: 2026-06-27

## The question

We built a frame-ui runtime + a layout DSL (P4) + a canonical widget vocabulary (P8). Now: **from the
developer's side, what do they author?** Today a screen costs ~**285–307 lines of Rust** (projector +
reducer + runtime wrapper) **+ a WASM binding + an HTML page** — and of those ~300 lines only two
things are domain-specific: the **layout tree** and the **reducer logic**. The rest is boilerplate.
The authoring surface splits into two halves: **logic** (`.ig`) and **view** (`.igv`).

## Half 1 — logic in `.ig` (verified)

`.ig` is a real, widely-used language (570 files). For interactive-app LOGIC it already has the right
shapes:

- **State** = `type Record { field: T }` + sealed `variant Outcome { Arm { fields } }`
  (`apps/igniter-apps/arch_patterns/types.ig:25-35`).
- **Reducer** = a pure contract `(state, event) -> new_state` with a match on the event —
  `arch_patterns/event_sourcing.ig:12-53` (`contract ApplyEvent { input state, input event … output
  new_state }`). **This IS our `IntentReducer: (intent, world) -> deltas`.** The logic half already
  has a language idiom; we don't invent it.
- **`.ig` already emits views as data**: `server/igniter-web/examples/todo_view_app/todo_views.ig:8-62`
  builds a typed `ViewArtifact { artifact:"view", layout:"form", body:[HtmlNode…] }` and returns
  `RenderView`/`RespondView`. So a `.ig`↔view seam exists today (one-way, no reactivity).
- **Effects** are NOT a language feature — they're **injected as contract inputs** (pure core);
  capabilities live in the runtime (`lead_router/service.ig:22-46`).

Gaps for interactive logic: no event-dispatch registry (manual `if event.kind ==` chains), no effect
surface, no view reactivity, and ergonomic paper cuts (no string escapes, required-only fields, no
match-arm `let`, one entrypoint/module). None block a reducer; they bite at scale.

## Half 2 — view in `.igv` (verified): two worlds

| | **World A — ui-kit ViewArtifact** | **World B — view-engine `.igv`** |
|---|---|---|
| form | JSON (`view_artifact.rs`) | Ruby DSL via `instance_eval` (`igv_compiler.rb`) |
| expresses | 2 layouts (workbench/form), 5 kinds | state/slot/element/**collection**/display-rules/expressions, `on:click→set_ui_state` |
| data bind | hardcoded `data.leads[]` | `slot … from:"path"` + expression tree |
| intent out | a button `action` string | instruction tuples (local JS eval) |
| engine | → Rust kit → **frame STATE facts** | → ViewArtifact → **HTML/Tailwind + JS micro-runtime** |
| status | stable, narrow | richer vocab, **lab-only, no stable syntax** |

Capability vs our screens — **both fail the things we just built**:

| feature | World A | World B |
|---|---|---|
| nested layout | ✗ | ✗ |
| list / repeat | ✗ | ✓ (collections) |
| table | ✗ | ✗ |
| text input | ✓ | ✓ |
| toggle / checkbox | ✓ | ✓ |
| segmented control | ✗ | ✗ |
| scroll | ✗ | ✗ |
| hover / focus | ✗ | ✗ (click only) |
| data binding | ✗ | ✓ |
| intent emission | partial | ✓ |

## The tension the matrix hides

A naive read says "extend World B — it has the richest vocabulary." **But World B's engine is the
legacy stack we are moving away from**: Ruby `instance_eval` → HTML/Tailwind classes → a JS
micro-runtime. That is exactly NOT the frame-ui thesis (machine-free Rust/wasm, deterministic,
content-addressed, no JS computing intent). Adopting World B's *engine* would undo the work. World A is
Rust+deterministic (right engine) but its *vocabulary* is a dead-end (workbench/form only).

So neither world is the target as-is:
- World B has the right **vocabulary** (state, slot/binding, element, **collection/repeat**,
  display-rule, `on:event → intent`) but the wrong **engine**.
- World A has the right **engine** (Rust, deterministic, frame facts) but the wrong **vocabulary**.
- We already built the missing middle: the **layout DSL** (P4) and the **canonical widget vocabulary**
  (P8) — over the right engine (frame-ui).

## Recommendation — "World C": a `.igv` over the frame-ui runtime

Author a NEW `.igv` dialect that **compiles to a frame-ui projector**, borrowing World B's proven
view vocabulary, expressed with our P4 layout DSL + P8 widget vocab, on the machine-free engine:

```
.igv  (view)  = layout (P4 DSL)  +  widgets (P8 canon)  +  data bindings  +  intent emission
.ig   (logic) = state facts (type/variant)  +  reducer contract (intent,state)->deltas  +  injected effects
                                   └──────────────→ frame-ui runtime (projector → frame → render) ←┘
```

- Reuse the **ideas** of World B (slots/collections/display-rules/on-event), NOT its Ruby/HTML engine.
- Keep **ViewArtifact** as a compatible IR if useful (both A and B already target it), but the live
  target is our `Projector`/`Frame`.
- The logic half is `.ig` **as it already is** — the `(state,event)->state` contract is the reducer;
  state is `type`/`variant`. The one missing seam is binding view intents ↔ `.ig` reducer.
- This is a **lab precedent** that pressures canon toward a real view+logic story, instead of cementing
  either legacy dialect.

## Proposed first build step

Prototype `.igv` for ONE screen (the **list**): author `~20` lines of `.igv` (layout + a `row` repeat
bound to `item:*` facts + `select`/`add`/`toggle` intents) and a compiler `.igv → ListProjector`,
proving the **~300 lines Rust → ~20 lines view** reduction, live in frame-ui. Same rhythm:
code + tests + runnable demo. (Logic reducer stays Rust for the prototype; wiring a `.ig` reducer is a
follow-on once the view seam is proven.)

## Anchors

- `.ig` reducer idiom: `apps/igniter-apps/arch_patterns/event_sourcing.ig:12-53`
- `.ig`→view seam today: `server/igniter-web/examples/todo_view_app/todo_views.ig:8-62`
- World A compiler: `frame-ui/igniter-ui-kit/src/view_artifact.rs:62-76`
- World B compiler + fixtures: `frame-ui/igniter-view-engine/lib/igv_compiler.rb`,
  `frame-ui/igniter-view-engine/fixtures/{tabs,results_panel}.igv`
- Our halves: `frame-ui/igniter-frame/src/layout.rs` (DSL `parse`), `…/widget_host.rs` (canon vocab)
