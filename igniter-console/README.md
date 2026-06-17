# igniter-console — an operator-console / IDE-shell over the kit

> **Stack map:** this is the app/consumer layer of the Igniter UI authoring stack. For the whole
> architecture (kernel → frame → kit → console), the build guide, and the gates, read
> `../lab-docs/lang/lab-frame-app-authoring-checkpoint-p14-v0.md`.

`igniter-console` (LAB-FRAME-APP-CONSOLE-P13) is the **first app built FROM the kit**. It takes a
ViewArtifact-authored screen (an `igniter-ui-kit` workbench compiled from JSON) and wraps it with
developer tooling:

```text
┌ replay strip ───────────────────────────────────────────────┐  f0 f1 f2 … (click = time-travel)
├ frame viewer ───────────────┬ lineage ─────────────────────┤  the SELECTED frame, rendered
│  (the target app, embedded) │  step / input → effect → frame│  (the target's own SVG)
│                             ├ frame diff vs prev ───────────┤  node-level: added/removed/moved/changed
└─────────────────────────────┴───────────────────────────────┘
```

It invents no layout primitives: it reuses `igniter-frame`'s `Frame` / `ProjectedNode` / `hit_test`
for its own chrome and **embeds the target's rendered SVG** in the viewer. No `igniter-machine` in
the path.

## What it does

- **Runs** a ViewArtifact app: `Console::from_artifact(json)` builds a `WorkbenchRuntime` and records
  the initial frame.
- **Records** every frame: each viewer interaction (`click`, `key`) forwards to the target and
  snapshots `{frame_index, input/effect receipts, render_digest, world_digest, svg, nodes}` into a
  frame history (a frame-as-fact log).
- **Time-travels**: `select_step(i)` (or clicking a replay chip) scrubs to any recorded frame —
  read-only, the target is not mutated.
- **Inspects lineage**: the `input → effect → frame` chain + digests for the selected step.
- **Diffs frames**: `diff()` reports node-level changes (`added` / `removed` / `moved` / `changed`)
  between the selected frame and its predecessor.

Routing: a console click hit-tests the chrome — a replay chip scrubs; a viewer click is translated
into the target's frame coordinates and forwarded to the app (which records a new frame). Keystrokes
forward to the focused field. The host owns nothing; Rust owns the target runtime, recording,
time-travel, and diff.

## Run

```bash
web/build.sh   # build wasm + glue + serve 127.0.0.1:8735
# open http://127.0.0.1:8735/console.html — click the frame viewer to drive the app, click a chip to scrub
```

`cargo test` runs 7 native tests (shell, viewer-forward, scrub, diff, lineage, typing, initial).

## Boundary / status

Lab-only. No window, no GPU, no network beyond localhost, no UI framework, no machine dependency.
Not Igniter Lang canon. It is the consumer that proves the authoring stack (ViewArtifact → kit →
`FrameRuntime`) is enough to build a real developer tool — without inventing new primitives.
