# Card: LAB-FRAME-CONSOLE-DIFF-HIGHLIGHT-P15 — highlight frame diffs in the console viewer

Status: CLOSED 2026-06-16 — implemented + proven (native + live browser).
Lane: lang / frame-console implementation
Owner: Opus

## Result

The console frame viewer now draws a deterministic visual diff overlay on top of the embedded target
frame: `added` (green) / `removed` (red dashed, prev geometry) / `moved` (blue + displacement line) /
`changed` (amber), derived from the existing `Console::diff()` / `diff_frames` model — Rust still owns
diff truth. Implemented as a pure `diff_overlay_svg(prev, cur)` (`pub`) + `bounds`/`viewer_rect`
helpers mapping TARGET-frame boxes into the embedded viewer via the existing `VX/VY/VW/VH` +
`TARGET_W/TARGET_H`; `render_svg` appends it after the embedded SVG (only when `selected > 0`);
`Console::diff_overlay()` exposes it. Stable classes `diff-added/removed/moved/changed`; point nodes
(no `sw`/`sh`) are OMITTED (no invented geometry), textual entry preserved.

Verification: `cd igniter-console && cargo test` → 7 (P13) + 7 (new `console_diff_highlight_tests.rs`)
= 14 passed. WASM rebuilt, no machine symbols; `web/console.html` unchanged (overlay is in
`render_svg`). Live (127.0.0.1:8735): step 0 no markers; selecting Grace renders 10 markers
(added/removed/changed) on the embedded frame with the textual diff panel intact. All 8 acceptance
met. Proof doc: `lab-docs/lang/lab-frame-console-diff-highlight-p15-v0.md`. No surface authority file
exists for the console, so none was created (per card).

## Why this card exists

P13 built `igniter-console` as a replayable SVG workbench over `ViewArtifact` frames:
replay strip, embedded frame viewer, lineage inspector, and textual frame diff.
The remaining high-value console-depth gap is visual: the frame diff is correct,
but changed regions are not highlighted inside the embedded target view.

This card adds that visual layer.

## Verify-first inputs

Before editing, read the live surface:

- `igniter-console/src/lib.rs`
- `igniter-console/tests/console_tests.rs`
- `igniter-console/web/console.html`
- `lab-docs/lang/lab-frame-app-console-p13-v0.md`
- `lab-docs/lang/lab-frame-app-authoring-checkpoint-p14-v0.md`
- `.agents/work/cards/lang/LAB-FRAME-APP-CONSOLE-P13.md`
- `.agents/work/cards/lang/LAB-FRAME-CONSOLE-CHECKPOINT-P14.md`

Do not infer console behavior from older frame/UI notes if live code disagrees.

## Goal

Add deterministic visual diff highlights to the console frame viewer:

- `added` nodes are highlighted in the current frame.
- `removed` nodes are highlighted using previous-frame geometry.
- `moved` nodes show position change without hiding the current frame.
- `changed` nodes show a visible changed-region marker.

The highlight must be derived from the existing frame diff model
(`Console::diff()` / `NodeChange`) and current/previous frame geometry.

## Expected implementation shape

Keep the slice narrow:

- Extend `Console::render_svg()` or small helper functions under `igniter-console`
  to render a diff overlay inside the existing embedded target viewer.
- Reuse existing constants/geometry for the viewer (`VX`, `VY`, `VW`, `VH`,
  `TARGET_W`, `TARGET_H`) so node bounds are mapped into viewer coordinates.
- Prefer deterministic SVG markers/classes, for example:
  - `diff-added`
  - `diff-removed`
  - `diff-moved`
  - `diff-changed`
- Preserve the existing textual frame diff panel; the overlay complements it.
- Keep `Console::diff()` as the semantic source of truth.

Removed-node highlights may use previous-frame bounds. If exact bounds are not
available for a node, omit the overlay for that node and keep the textual diff
entry; do not invent geometry.

## Acceptance

1. Step 0 / no-previous-frame renders no visual diff overlay.
2. Scrubbing to a changed frame renders overlay markers for changed nodes.
3. Overlay coordinates are mapped into the embedded target viewer, not the
   console shell coordinate space.
4. Added, removed, moved, and changed states are distinguishable in SVG output.
5. Scrubbing changes the overlay deterministically with the selected frame.
6. Live interactions that create a new frame update both textual diff and visual
   overlay.
7. Existing console shell, replay strip, lineage inspector, and textual diff
   behavior remain intact.
8. Tests assert stable SVG markers/classes rather than brittle full-SVG strings.

## Verification

Required:

```bash
cd igniter-console
cargo test
```

Recommended if any shared frame/UI crate is touched:

```bash
cd igniter-frame && cargo test
cd igniter-ui-kit && cargo test
```

If `web/console.html` changes, run a small manual/browser smoke or document why
the static file did not need a separate smoke.

## Deliverables

- Implementation in `igniter-console`.
- Focused tests in `igniter-console/tests/console_tests.rs` or a new adjacent
  console test file.
- Proof doc:
  `lab-docs/lang/lab-frame-console-diff-highlight-p15-v0.md`
- Close this card with a short summary and verification output.
- Update `igniter-frame/IMPLEMENTED_SURFACE.md` or the nearest frame/console
  surface only if this repository already tracks console surface there. Do not
  create a new authority file just for this slice.

## Closed surfaces

Do not do these in this card:

- No `.igv` format work.
- No `.ig` frame binding work.
- No new `ViewArtifact` schema authority unless a live-code bug makes it
  unavoidable; if so, stop and route to a readiness card first.
- No `igniter-machine` integration.
- No JS-owned diff semantics; JS may display, but Rust console owns diff truth.
- No canvas/GPU renderer.
- No product IDE work.
- No broad UI restyle.

## Notes for closure

This is a visual debugger/console slice, not a new frame authoring layer.
The intended user value is immediate: when a replay step changes, a developer
can see what changed in the target frame without reading the textual diff first.
