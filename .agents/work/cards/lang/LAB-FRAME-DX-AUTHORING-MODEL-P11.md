# Card: LAB-FRAME-DX-AUTHORING-MODEL-P11 — answer "what does a developer write?"

> Readiness/design card for the `igniter-frame` / `igniter-ui-kit` authoring
> layer. Builds on `LAB-FRAME-UI-KIT-FORMS-P9` and
> `LAB-FRAME-UI-KIT-COMPOSITION-P10`.

**Status:** CLOSED 2026-06-16 — design/readiness doc written, no code changed.
**Skill:** `idd-agent-protocol` (smallest artifact, authority boundary, verify-first).

## Result

Authoring model formalized in `lab-docs/lang/lab-frame-dx-authoring-model-p11-v0.md`. Answer in one
line: **today a developer writes Rust** — *platform authoring* (new `Component`/`Projector`/
`RenderHost`/`IntentReducer`/runtime ports) vs. *app authoring* (composing existing components into a
`Form`/`Workbench`). The next portable app-authoring layer is a **ViewArtifact JSON** that compiles
to the kit tree (inspectable/diffable, before any text DSL); **`.igv`** is a future sugar over it;
**`.ig`** stays the business-logic/state/effect authority that views *bind to* (data source, action→
effect, validation contract) — explicitly NOT a UI markup language. All lab-only, not canon; no
machine in the UI/browser path. Pipeline: `.ig` contracts ← bindings ← ViewArtifact/.igv → ui-kit
tree → FrameRuntime → thin host. Verified against live code (P9 `Form`, P10 `Workbench`), not stale
roadmap. Next implementation card named (not started): **`LAB-FRAME-VIEWARTIFACT-P12`** (JSON →
kit tree → runtime, ideally byte-identical to the hand-written workbench), then an app/console card,
then `.igv` only after the JSON shape stabilizes.

## Why this card exists

P2-P10 proved the mechanics:

```text
state -> frame -> input -> intent -> state
component tree -> frame nodes
host maps DOM events only
Rust runtime owns hit-test / intent / reducer / projection
```

But the developer DX is still unclear. Today the proven authoring layer is Rust:
`Form`, `Workbench`, `Projector`, `RenderHost`, `IntentReducer`. The open product
question is:

```text
When a developer wants to build a UI, what do they write?

Rust?
Igniter .ig?
A lab-only .igv / ViewArtifact?
Some generated JSON shape?
```

This card must formalize that model BEFORE building `igniter-ide` or more UI
surface, so future agents do not invent the authoring layer inside the first app.

## Verify-first inputs

Read these before writing:

- `igniter-frame/README.md`
- `igniter-ui-kit/README.md`
- `igniter-ui-kit/src/lib.rs`
- `igniter-ui-kit/src/composition.rs`
- `lab-docs/lang/lab-frame-ui-kit-forms-p9-v0.md`
- `lab-docs/lang/lab-frame-ui-kit-composition-p10-v0.md`
- `.agents/work/cards/lang/LAB-FRAME-UI-KIT-FORMS-P9.md`
- `.agents/work/cards/lang/LAB-FRAME-UI-KIT-COMPOSITION-P10.md`

Live code and current `IMPLEMENTED_SURFACE.md` outrank stale roadmap language.

## Core question

Produce a crisp answer to:

```text
What are the authoring layers?
Who writes which layer?
What is current/proven vs proposed?
What compiles/translates into what?
What remains lab-only vs canon?
```

## Recommended starting thesis

Use this as the initial hypothesis, but verify and adjust if the code disagrees:

```text
Rust             = platform/widget authoring
                   New components, projectors, render hosts, reducers, runtime ports.

ViewArtifact JSON = first portable lab artifact
                   A structured, testable screen description generated from or compiled to Rust kit
                   primitives. Good before a text DSL because it is inspectable and easy to diff.

.igv             = possible future ergonomic view DSL
                   Lab-only candidate syntax over ViewArtifact, not canon yet.

.ig              = business logic / state / effects / contracts
                   Not a UI markup language by default. It may provide data sources, validation,
                   actions, intents, and effect contracts that a view binds to.
```

The expected direction is:

```text
.ig contracts/state/effects
        ^
        | bindings/actions
ViewArtifact / .igv screen
        |
        v
igniter-ui-kit component tree
        |
        v
igniter-frame FrameRuntime
```

## Deliverable

Create one design/readiness doc:

```text
lab-docs/lang/lab-frame-dx-authoring-model-p11-v0.md
```

Then close/update this card with a short result summary.

Optional only if it prevents drift: add a one-line pointer from the P10 card or
README. Do not update canon docs.

## Required sections in the doc

1. **Current proven DX**
   - What a developer writes today in Rust.
   - Show the smallest current Rust examples (`Form::lead_intake`,
     `Workbench::lead_review`, reducer/projector/render-host roles).

2. **Layer taxonomy**
   - Rust kit API
   - ViewArtifact JSON or equivalent structured artifact
   - `.igv` candidate DSL
   - `.ig` contracts/state/effects
   - browser/host glue

3. **Authority boundaries**
   - What is lab-only.
   - What is implementation evidence.
   - What is NOT Igniter Lang canon.
   - Why `.ig` should not silently become a UI markup language.

4. **Authoring pipeline**
   - Draw the compile/translation path from developer-authored screen to frame runtime.
   - Include where bindings to `.ig` contracts happen.
   - Include where state facts live and where reducer/effect ownership lives.

5. **Minimal example**
   - Take one screen, preferably the existing lead-review workbench.
   - Show it in:
     - current Rust API;
     - proposed ViewArtifact JSON shape;
     - optional `.igv` sketch.
   - The JSON / `.igv` sketches are design artifacts only, not implemented syntax.

6. **State and binding model**
   - How component ids stay stable.
   - How field values, focus, validation, selection, and inspector data map to state facts.
   - How a UI action becomes an intent, reducer action, or `.ig` contract/effect call.

7. **What not to build yet**
   - No `.igv` parser.
   - No `igniter-lang` canon changes.
   - No IDE product UX.
   - No JS framework.
   - No machine dependency in UI-kit core/browser path.

8. **Next-card recommendations**
   - One implementation card for a portable ViewArtifact JSON proof.
   - One app card for operator-console or IDE-shell consuming the authoring model.
   - One later card for `.igv` syntax only after the JSON artifact shape is stable.

## Acceptance

- Answers "what does a developer write?" directly, not only by describing runtime internals.
- Separates platform-authoring Rust from app-authoring artifacts.
- Keeps `.ig` as business logic/effect/state authority unless explicitly bridged.
- Treats `.igv` as a lab candidate, not canon.
- Provides at least one concrete screen in current Rust plus proposed artifact form.
- Maps developer-authored structure to existing `igniter-frame`/`igniter-ui-kit` mechanisms.
- Names the next implementation card without starting it.
- No source code changes required.
- No parser/compiler changes.
- No `igniter-machine` dependency added to UI-kit or browser path.

## Closed surfaces

- Do not implement `.igv`.
- Do not build `igniter-ide`.
- Do not edit `igniter-lang` canon.
- Do not introduce a stable public UI API claim.
- Do not turn old lab docs into authority if live code says otherwise.

## Suggested next route if closed

If the answer is coherent, open:

```text
LAB-FRAME-VIEWARTIFACT-P12
```

Goal: proof-local structured ViewArtifact JSON -> `igniter-ui-kit` component tree ->
`igniter-frame` runtime, using the P11 model. This should come before `.igv`
syntax.
