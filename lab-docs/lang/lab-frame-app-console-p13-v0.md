# lab-frame-app-console-p13-v0 — an IDE-shell built from the kit

**Card:** `LAB-FRAME-APP-CONSOLE-P13` (new crate `igniter-console`, over `igniter-ui-kit` /
`igniter-frame`)
**Status:** CLOSED — proven (native + live browser). The FIRST app over the mature kit: it consumes
a ViewArtifact-authored workbench and wraps it with a replay strip, frame viewer, lineage inspector,
and frame diff over the recorded frame history. It invents no layout primitives. Machine-free.

## Why this is the right first app

P11/P12 established the authoring stack (ViewArtifact JSON → kit tree → `FrameRuntime`). An IDE was
deferred so it would CONSUME a mature kit rather than invent layout inside the first app. P13 is that
consumer: it builds developer tooling entirely on top of the proven pieces — proving the stack is
enough to write a real tool.

## The shell

`Console` runs a target `WorkbenchRuntime` (compiled from `lead_review.view.json`) and renders one
SVG IDE shell (940×600):

- **replay strip** — a chip per recorded frame (`f0 f1 …`, digest preview); click to time-travel.
- **frame viewer** — the SELECTED frame, rendered as the target's OWN SVG embedded (a nested `<svg>`
  re-scaled into the viewer box). Title shows `step N/M (live|replay)`.
- **lineage inspector** — `step / event / input → effect → frame / render digest` for the selection.
- **frame diff vs prev** — node-level changes between the selected frame and its predecessor.

## How it reuses the kit (no new primitives)

- **chrome interaction** = `igniter-frame`'s `Frame` + `ProjectedNode` + `hit_test`: the console
  builds a tiny chrome `Frame` (strip chips + the viewer box) and hit-tests clicks against it
  (innermost-box, the P10 generalization). No bespoke geometry.
- **the app** = an unmodified `WorkbenchRuntime::from_artifact` (P12). The console never reaches into
  it — it forwards events and reads `frame()` / `render_svg()` / `lineage_json()` (one new read-only
  accessor `FrameRuntime::frame()` exposes the projected frame for inspection/diff).
- **the viewer** = the target's render host output, embedded verbatim. The console adds no renderer.
- **the frame history** = a `Vec<FrameRecord>` (frame-as-fact: digest + lineage + nodes) — the
  `__frames__` analog, in-memory.

Routing: a console click hit-tests the chrome → a `step:N` chip scrubs (`select_step`, read-only); a
`viewer` hit is translated into target frame coordinates and forwarded to the app (`click` → record
a new frame). Keystrokes forward to the focused field. The host computes nothing.

## Proof

**Native** (7 tests, `igniter-console/tests/console_tests.rs`, machine-free):

| acceptance | test |
|---|---|
| the console builds the IDE shell around the artifact | `console_builds_the_ide_shell_around_the_artifact` |
| a viewer click forwards to the target + records a frame | `viewer_click_forwards_to_target_and_records_a_frame` |
| a replay chip scrubs history without mutating the target | `replay_strip_scrubs_history_without_mutating_target` |
| the frame diff reports node-level changes (added/removed/changed) | `frame_diff_reports_node_level_changes` |
| the lineage inspector reflects the selected step (live + scrubbed) | `lineage_inspector_reflects_the_selected_step` |
| typing forwards through the console to the reducer | `typing_forwards_through_the_console_to_the_reducer` |
| the initial frame has no diff | `initial_frame_has_no_diff` |

**WASM build**: `cargo build --release --target wasm32-unknown-unknown --features wasm` → a 283 KB
`.wasm` exposing `WasmConsole.from_artifact`; no `igniter-machine`/`TBackend`/`rocksdb` symbols.

**Live browser** (`igniter-console/web/console.html`, headless-verified): the page fetches the
ViewArtifact JSON and `WasmConsole.from_artifact`s it; real `pointerdown` on the frame viewer drives
the embedded app (focus a field, type "hi", select Grace) — each interaction adds a replay chip;
real `keydown` types into the focused field; clicking the first chip time-travels to the initial
frame (read-only, `len` unchanged); the lineage shows `type:2 → effect:2 → frame:3` and the frame
diff lists `changed panel:main`, `added fld:Grace:priority/stage/hot`, `removed fld:Ada:priority`.
The host only maps DOM events.

## Acceptance

replay strip ✅ · frame viewer (embedded target SVG) ✅ · lineage inspector ✅ · frame diff over the
recorded history ✅ · built FROM the kit, no new layout primitives ✅ · consumes a ViewArtifact app ✅ ·
machine-free wasm ✅ · live browser ✅ · all prior kit tests stay green ✅.

## Decisions

- **the console is an app, not a kit change**: one read-only accessor (`FrameRuntime::frame()`) was
  added; everything else is consumption.
- **the viewer embeds the target's own SVG** — the console renders no app widgets itself, so it can
  inspect ANY kit app, not just this workbench.
- **time-travel is read-only**: scrubbing selects a recorded frame; only viewer interaction advances
  the live target. Frames are facts; the log is the `__frames__` history.
- **diff is node-level over frames** (`added/removed/moved/changed` by id), the substrate for a
  visual debugger.

## Next

- **`LAB-FRAME-IGV-SYNTAX-P14`** — an `.igv` ergonomic DSL over the (now stable) ViewArtifact JSON.
- **`.ig` binding bridge** (separate, explicit) — resolve `bind`/`action` to real `.ig`
  data-sources/effects, so the console can inspect an app wired to live contracts.
- console depth (optional): multi-app tabs, frame export/import, a diff that highlights changed
  regions in the embedded SVG.
