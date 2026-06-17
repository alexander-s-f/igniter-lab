# lab-frame-app-authoring-checkpoint-p14-v0 — the Igniter UI authoring stack (crystallized map)

**Card:** `LAB-FRAME-CONSOLE-CHECKPOINT-P14` (consolidation — NO new feature, NO code)
**Status:** CLOSED — this is the single front-door map for the UI authoring stack (P2–P13). Read it
before extending any layer. Everything here is **lab-only implementation evidence, not Igniter Lang
canon.**

We built many layers quickly. This checkpoint crystallizes them into one map so future agents
EXTEND the stack instead of drifting (re-inventing layout, or starting `.igv` / `.ig` binding
without an explicit gate).

## Verify-first (ground truth)

Live code + `cargo test` outrank any older roadmap. As of 2026-06-16, five machine-free crates, all
green:

| crate | role | tests | wasm |
|---|---|---|---|
| `igniter-frame` | the runtime + projection ports | 22 | yes |
| `igniter-3d` | 3D sim domain (proof of generality) | 6 | yes |
| `igniter-gui` | GUI domain (proof of generality) | 8 | yes |
| `igniter-ui-kit` | component vocabulary + ViewArtifact compiler | 26 | yes |
| `igniter-console` | IDE-shell app (consumer) | 7 | yes |

All depend on `igniter_frame` with `default-features = false` → **no `igniter-machine` in the
UI/browser path** (verified: the `.wasm` artifacts contain no machine/TBackend/rocksdb symbols).

## The architecture map

```text
igniter-machine        state kernel — facts/receipts/capsules/capability-IO. KNOWS NOTHING about UI.
   │  (TBackend adapter, optional `machine` feature on igniter-frame; OFF in the UI path)
   ▼
igniter-frame          THE RUNTIME. state → frame → input → intent → state. Ports:
   │                     • Projector   (world facts → Frame; CameraProjector / layout projectors)
   │                     • RenderHost  (Frame → artifact; Svg / wireframe / GUI rects)
   │                     • IntentReducer (intent → state deltas)
   │                     • FrameRuntime (click / send / dispatch; render_svg / frame / lineage; replay)
   │                     • hit_test (points by radius; boxes by innermost-area), Viewport, Camera
   ├──────────────┬───────────────┬──────────────────────────────┐
   ▼              ▼               ▼                              ▼
igniter-3d     igniter-gui     igniter-ui-kit                  (2D demo)
 (tick=reducer, (widgets=facts,  Component vocab (Label/Text/Select/Checkbox/Button),
  wireframe)     box layout)     Form + Workbench, FormProjector/WorkbenchProjector,
                                 reducers, render hosts, + ViewArtifact JSON compiler
                                     │
                                     ▼
                                igniter-console   IDE-shell: replay strip · frame viewer ·
                                                  lineage inspector · frame diff (CONSUMES the kit)
```

Rule of thumb: **the runtime is `igniter-frame`; everything above it is a domain or an app.** New UI
capability is a new Projector / RenderHost / Component (kit), never a change to the kernel and rarely
a change to the runtime (only domain-neutral generalizations: the `Projector` port, box hit-test,
`send`, innermost hit-test, `frame()` were each justified by a phase).

## The authoring pipeline

```text
.ig contracts/state/effects            (FUTURE binding — gated, see below)
        ▲ bind / action
ViewArtifact JSON   ──or──  .igv (FUTURE DSL — gated)      ← app authoring (data, portable)
        │ compile  (igniter-ui-kit::view_artifact)
        ▼
igniter-ui-kit component tree (Form / Workbench)           ← app authoring (Rust)
        │ project · reduce · render
        ▼
igniter-frame FrameRuntime                                  ← platform authoring (Rust)
        │ render_svg / click / key ; records frames
        ▼
thin browser/WASM host   ──inspected by──►  igniter-console (replay / diff / lineage)
```

## How to build an Igniter UI app

Three honest ways, smallest first:

1. **Author a screen as data (recommended).** Write a ViewArtifact JSON (`{"artifact":"view",
   "layout":"workbench"|"form", …}`), then:
   ```rust
   let rt = WorkbenchRuntime::from_artifact(json)?;   // or FormRuntime::from_artifact(json)?
   ```
   The JSON compiles to the kit tree and runs on `FrameRuntime` — byte-identical to the hand-written
   constructor.
2. **Compose existing components in Rust** (app authoring): build a `Form { title, body: vec![…] }`
   or a `Workbench { leads, fields }` from the vocabulary; wrap in its `*Runtime`.
3. **Extend the platform in Rust** (platform authoring): a new `Component`, a `Projector` (layout),
   a `RenderHost` (output), or an `IntentReducer` (update) — then compose with (1)/(2).

Serve it: a thin host (no framework) loads the `.wasm`, calls `render_svg()` → DOM, and forwards
`pointerdown`/`keydown` → `rt.click()`/`rt.key()`. The host computes no intent. Inspect it: open the
console (`igniter-console`) over the same app for replay / lineage / diff.

## Canonical example path

```text
igniter-ui-kit/web/lead_review.view.json     ← the authored screen (data)
        │  WorkbenchRuntime::from_artifact (igniter-ui-kit::view_artifact::compile_workbench)
        ▼
igniter-console/web/console.html             ← fetch json → WasmConsole.from_artifact → run
        │  click the frame viewer (drive the app) ; click a replay chip (time-travel)
        ▼
replay strip · frame viewer · lineage (input→effect→frame) · frame diff (node-level)
```

Live: `igniter-console/web/build.sh` → `http://127.0.0.1:8735/console.html`. The same
`lead_review.view.json` is the single source of truth — loaded by the kit tests (`include_str!`),
the ui-kit browser demo (`/viewartifact.html`, port 8734), and the console.

## Authority / boundaries — and the GATES

- **Lab-only, not canon.** No stable public UI API. `igniter-machine` stays a boring kernel with no
  UI knowledge; it must not gain `Frame`/`Camera`/projection again (the P1 leftovers were removed).
- **The IDE-shell CONSUMES the kit; it does not invent layout/components.** `igniter-console` reuses
  `igniter-frame`'s `hit_test` for its chrome and embeds the target's own SVG. Any new app must do
  the same — if you find yourself writing layout math in an app, lift it into a kit Projector.
- **Explicit gates — do NOT start these without a named card:**
  - `.igv` text DSL → requires `LAB-FRAME-IGV-SYNTAX-P*`. The JSON shape must be stable first; `.igv`
    is sugar over it, lab-only, never canon.
  - `.ig` binding bridge (resolve `bind`/`action` to real `.ig` data-sources/effects) → requires a
    separate explicit card. `.ig` is the business-logic/state/effect authority; it must NOT silently
    become a UI markup language.
  - any `igniter-machine` dependency in the UI/browser path → forbidden without re-opening the P2
    extraction decision.

## What's proven vs. proposed

- **Proven (implemented + tested, native + live browser):** the runtime, three domains (2D/3D/GUI),
  the component kit, the ViewArtifact JSON compiler (byte-identical), and the IDE-shell.
- **Proposed (design only, gated):** `.igv` DSL, `.ig` binding bridge, console depth (multi-app
  tabs, frame export/import, in-SVG diff highlight).

## Next (pick one, each gated by its own card)

1. `.igv` syntax over the stable ViewArtifact JSON.
2. `.ig` binding bridge (UI actions → real contracts/effects).
3. console depth — e.g. frame-diff highlighting inside the embedded SVG (the smallest implementation
   step; everything else above is consolidation).
