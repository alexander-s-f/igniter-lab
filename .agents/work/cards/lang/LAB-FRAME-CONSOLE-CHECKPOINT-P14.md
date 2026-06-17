# Card: LAB-FRAME-CONSOLE-CHECKPOINT-P14 — crystallize the UI authoring stack

> Consolidation checkpoint over the P2–P13 UI work (`igniter-frame` / `igniter-ui-kit` /
> `igniter-console` + ViewArtifact). NO new feature, NO code. Builds on
> `LAB-FRAME-APP-CONSOLE-P13`.

**Status: CLOSED 2026-06-16 — checkpoint written.** Front-door map:
`lab-docs/lang/lab-frame-app-authoring-checkpoint-p14-v0.md`.

## Why

We built many layers fast. Without one crystallized map, the next agents risk drift: re-inventing
layout in an app, or starting `.igv` / `.ig` binding without an explicit gate. This card fixes the
map and the gates.

## Result

- **P12 ViewArtifact closure confirmed** (CLOSED; byte-identical native + live browser) and **P13
  IDE-shell accepted** (CLOSED) — both verified against live code, all five crates green
  (frame 22 / 3d 6 / gui 8 / ui-kit 26 / console 7), no machine symbols in the UI wasm.
- **Architecture map crystallized**: kernel → `igniter-frame` (runtime/ports) → domains
  (3d/gui) + `igniter-ui-kit` (components + ViewArtifact compiler) → `igniter-console` (IDE-shell
  consumer). The runtime is `igniter-frame`; everything above is a domain or an app.
- **"How to build an Igniter UI app" mini-guide** (3 ways: ViewArtifact JSON / compose components /
  extend platform) + the canonical example path `view.json → console.html → replay/diff/lineage`.
- **Gates fixed**: `.igv` and `.ig` binding each require an explicit named card; no machine in the
  UI path; nothing here is canon. The IDE-shell CONSUMES the kit, never invents layout.

## Deliverables

- `lab-docs/lang/lab-frame-app-authoring-checkpoint-p14-v0.md` (the map + guide + gates).
- README pointer lines added to `igniter-frame`, `igniter-ui-kit`, `igniter-console` (each points to
  this checkpoint as the stack front door).
- Memory + index updated.

## Next (gated — pick one)

- `LAB-FRAME-IGV-SYNTAX-P*` (`.igv` DSL over the stable ViewArtifact JSON);
- `.ig` binding bridge (separate explicit card: UI `bind`/`action` → real `.ig` data/effects);
- console depth (smallest impl step): frame-diff highlighting inside the embedded SVG.
