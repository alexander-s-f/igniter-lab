# lab-frame-console-diff-highlight-p15-v0 — visual frame-diff overlay in the console viewer

**Card:** `LAB-FRAME-CONSOLE-DIFF-HIGHLIGHT-P15` (implementation, in `igniter-console`)
**Status:** CLOSED — proven (native + live browser). The console frame viewer now draws a
deterministic visual diff overlay (added / removed / moved / changed) on top of the embedded target
frame, derived from the existing `Console::diff()` model + frame geometry. Machine-free; no new
authoring layer.

## What it adds

P13 gave the console a correct but TEXTUAL frame diff. The remaining console-depth gap was visual:
when a replay step changes, a developer had to read the textual diff to see what moved. P15 paints
the change directly onto the embedded frame:

- **added** → green outline at the node's current-frame box;
- **removed** → red dashed outline at the node's PREVIOUS-frame box;
- **moved** → blue outline at the current box + a dashed line from the previous box (shows the
  displacement without hiding the current frame);
- **changed** → amber outline at the current box.

The overlay COMPLEMENTS the textual diff panel (still present); it does not replace it.

## How (narrow slice)

- `diff_overlay_svg(prev, cur) -> String` (pure, `pub` for testing) walks `diff_frames(prev, cur)`
  — the existing semantic source of truth — and emits one SVG marker per change.
- `bounds(frame, id)` returns a node's box (`sx,sy,sw,sh`) or `None` for a point node; `viewer_rect`
  maps a TARGET-frame box into the embedded viewer's console coordinates using the existing
  `VX/VY/VW/VH` + `TARGET_W/TARGET_H` constants (no new geometry).
- `Console::render_svg()` appends the overlay AFTER the embedded target SVG (so it draws on top),
  only when `selected > 0`. `Console::diff_overlay()` exposes the overlay for the selected step.
- Markers carry stable classes — `diff-added` / `diff-removed` / `diff-moved` / `diff-changed` — so
  tests assert classes, not brittle full-SVG strings.
- **Geometry honesty:** a node without `sw`/`sh` (a point) gets NO overlay rect — the textual diff
  entry stays, but we never invent bounds.

`Console::diff()` / `NodeChange` are unchanged: Rust owns diff truth; the overlay only displays it.

## Proof

**Native** (7 new tests, `igniter-console/tests/console_diff_highlight_tests.rs`; the 7 P13 tests
stay green → 14 total):

| acceptance | test |
|---|---|
| step 0 / no-previous renders no overlay | `step_zero_renders_no_overlay` |
| a changed frame renders overlay markers | `selecting_a_lead_overlays_added_removed_changed` |
| overlay coords are in the embedded-viewer space, not the shell | `overlay_is_mapped_into_the_viewer_coordinate_space` (fld:Grace:priority → `x="204" y="158"`; no shell `y="22"`) |
| added/removed/moved/changed are distinguishable in SVG | `all_four_change_kinds_are_distinguishable` (+ a `<line class="diff-moved">`) |
| scrubbing changes the overlay deterministically | `scrubbing_updates_the_overlay_deterministically` |
| existing shell/strip/lineage/textual diff intact | `existing_console_behaviour_is_intact` |
| don't invent geometry for point nodes | `point_node_change_keeps_textual_diff_but_no_overlay_geometry` |

```text
cd igniter-console && cargo test
  → console_tests:                7 passed
  → console_diff_highlight_tests: 7 passed
```

**WASM build**: `cargo build --release --target wasm32-unknown-unknown --features wasm` →
`igniter_console_bg.wasm`, no `igniter-machine`/`TBackend`/`rocksdb` symbols. `web/console.html` was
NOT changed (the overlay lives in `render_svg`, which the page already calls).

**Live browser** (`http://127.0.0.1:8735/console.html`, headless-verified): at step 0 the rendered
SVG contains no `diff-` markers; a real `pointerdown` selecting Grace renders 10 overlay markers —
`class="diff-added"` (Grace's three fields, green), `class="diff-removed"` (Ada's fields, red
dashed), `class="diff-changed"` (`panel:main`, `lead:Ada`, `lead:Grace`, `kv:lead`, amber) — drawn on
top of the embedded frame, with the textual `frame diff vs prev` panel still present.

## Acceptance vs. card (all 8)

1. step 0 / no-previous → no overlay ✅
2. scrubbing to a changed frame → overlay markers ✅
3. overlay mapped into the embedded viewer space (not shell) ✅
4. added/removed/moved/changed distinguishable in SVG ✅
5. scrubbing changes the overlay deterministically ✅
6. live interaction updates both textual diff and visual overlay ✅
7. shell / replay strip / lineage / textual diff intact ✅
8. tests assert stable classes, not full strings ✅

## Decisions

- the overlay is DISPLAY only; `Console::diff()`/`diff_frames` stay the diff truth (no JS-owned diff).
- `removed` uses previous-frame geometry; everything else uses current; point nodes are omitted (no
  invented geometry).
- stable classes (`diff-added/removed/moved/changed`) are the test + styling contract.
- no `igniter-machine`, no `.ig`/`.igv`, no ViewArtifact schema change, no canvas/GPU, no IDE product
  work — a pure visual-debugger slice over the existing frame model.

## Next

Unchanged from the stack roadmap (each gated): `LAB-FRAME-IG-BINDING-P16` (fixture host bind), `.igv`
syntax, or further console depth (e.g. multi-app tabs, frame export/import).
