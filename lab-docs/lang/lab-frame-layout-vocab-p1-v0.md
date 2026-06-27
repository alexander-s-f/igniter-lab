# LAB-FRAME-LAYOUT-VOCAB-P1 — deterministic integer box layout (the authoring-DX keystone)

Status: CLOSED — implemented + proven (native tests, machine-free + wasm32 builds)
Lane: igniter-lab / frame-ui / unpause (Ceiling A from the frame-ui foundation audit)
Date: 2026-06-26
Skill: idd-agent-protocol

## Why

The frame-ui audit (`lab-docs/igniter-frame-ui-foundation-audit-p1.md`, Ceiling A) named the #1
DX tax: the node tree is FLAT and every screen's `(x, y, w, h)` is hand-computed with screen-
specific integer constants (e.g. `WorkbenchProjector`'s `SIDEBAR`/`MAIN`/`INSPECTOR` column tuples
+ per-field `my += 56`). Every new screen needs a fresh Rust projector with hand-tuned math. This
slice lifts that ceiling with a composable, recursive, pure-integer layout pass — the prerequisite
that makes lists/tables/nesting and a generalized `.igv` possible.

## What landed

New module `igniter-frame/src/layout.rs` — a deterministic integer box-layout engine:

- `Dir::{Col, Row}`, `Size::{Fixed(i64), Flex(i64)}`, `LayoutBox { id, dir, main, pad, gap, children }`
  with ergonomic constructors (`leaf`/`col`/`row`/`.pad()`/`.gap()`).
- `solve(root, x, y, w, h) -> Vec<Rect>` — a flexbox-lite: fixed children take their size; flex
  children share the remaining main-axis space by weight, with the integer-division remainder
  distributed one-px-each to the earliest flex siblings (so flex **fills the content box exactly**
  and is order-deterministic); cross axis = stretch; padding insets, gap separates; rects are
  emitted parent-before-children (matches the projectors' panel-first order + the innermost-area
  hit-test). Total + saturating (over-padding clamps to 0, no panic/overflow).
- `layout_digest(&[Rect])` — canonical dependency-light content digest (the layout analogue of
  `render_digest`).
- Bridge in `lib.rs`: `ProjectedNode::from_rect(rect, intent, data)` — the seam a projector uses to
  turn solved rects into box nodes, instead of hand-computing `(sx, sy, sw, sh)`.

Pure integer math, no `f64`, no clock/RNG, no kernel — **machine-free by construction**.

## Evidence

```text
cargo test                         # 8 layout unit + 3 layout-screen integration, all green; no regressions
                                   #   (existing frame 5/6/6/5 suites unchanged)
cargo build --no-default-features  # layout compiles with ZERO igniter-machine dependency
cargo build --no-default-features --features wasm --target wasm32-unknown-unknown  # WASM-clean (stack property held)
```

`tests/layout_screen_tests.rs` proves the **payoff** end-to-end: a 2-column screen authored by
COMPOSING boxes (no screen constants) →

- `composed_screen_feeds_real_hit_test`: a click inside `lead:Grace` routes to the lead (innermost
  child wins over enclosing panels) and carries its declared `select` intent; the flex `main` column
  resolves to 540 px and its fields sit inside the padded content. The composed layout drives the
  real `hit_test`/interaction model.
- `adding_an_item_auto_flows_no_constant_edits`: 3 leads → ys `[8, 48, 88]`; a 4th lead → the first
  three positions are **identical** and the 4th flows in at `128` — zero constant edits. (This is the
  Ceiling-A fix in one assertion: compose N items, the layout flows.)
- `deterministic_layout_digest`: two solves are byte-identical.

## Boundary

Lab-only; `igniter-frame` addition only — NO core (language/compiler/VM/machine) change, so no
language-pressure doc needed. The existing tested `WorkbenchProjector` (byte-identical-to-browser)
is untouched; this adds the reusable primitive beside it. Cross-axis is stretch-only and alignment
is start-only in v0 (per-child cross alignment + intrinsic cross sizing are later slices).

## Next (the layout vocab opens these)

- **P2 — declarative screen → layout runtime:** a `LayoutScreen` projector (or a `Screen` vocabulary)
  that takes a `LayoutBox` tree + per-leaf data/intent + a render host → an interactive frame, so an
  app author composes a screen instead of writing a projector. Then re-target `.igv` to emit it
  (generalize beyond the one workbench template).
- **P3 — data-bound `list`/`table` node** over the layout (`Col` of rows / `Col` of `Row`s) — the
  vocabulary ceiling the audit named for real apps.
- Optionally refactor `WorkbenchProjector` onto `solve` (prove byte-identical, retire its constants).

---

## P2 — declarative list/detail screen + live browser demo (CLOSED)

`igniter-frame/src/list_screen.rs` — a data-driven list/detail screen built ENTIRELY on the layout
engine (no screen coordinate constants), proving the authoring payoff end-to-end and runnable live:

- Items are world FACTS (`item:<n>` → `{label, done}`); `ListProjector` COMPOSES the screen each
  frame (`Row[sidebar(Col of item rows + an "add" row) , detail(Col flex)]`) and `solve`s it; a
  reducer handles `select` / `toggle` / `add`. The `add` action appends an item fact and the list
  **auto-flows** — the projector never hand-computes a position.
- WASM binding `WasmListScreen` (in `wasm.rs`) + `web/list.html` + `web/run-list-demo.sh` (one
  command: build wasm → wasm-bindgen glue → serve `http://127.0.0.1:8736/list.html`).

Evidence:

```text
cargo test                         # 37 pass / 0 fail across all suites (8 layout unit + 4 list_screen
                                   #   + 3 layout_screen integration + existing 22); no regressions
cargo build --no-default-features  # clean ;  + wasm32 release --features wasm  → clean
wasm: WasmListScreen exported in the glue; ZERO kernel symbols (rocksdb/TBackend/igniter_machine) in
      the 179 KB binary — machine-free at the binary level.
```

`list_screen.rs` tests: `rows_are_laid_out_by_composition_and_select_routes` (rows at solved offsets;
a click hits the innermost row), `add_auto_flows_the_list_no_constant_edits` (a 4th item flows in at
the old "add" position; add shifts down — zero constant edits; the new row auto-selects),
`select_then_toggle_marks_the_selected_item`, `deterministic_replay_of_a_click_log` (same start +
same click log → byte-identical frame).

**Proven LIVE in the browser** (preview harness over the served page): the wasm loads and renders
(9 rects / 10 texts; the `＋ add item` row present), no console errors; synthetic clicks advance the
frame (0 → 2), flow a new "New item 4" into the list, and chain lineage `input:1 → effect:1 →
frame:2` with a changing content-addressed `render_digest`. Run: `./web/run-list-demo.sh`.

`.claude/launch.json` gained a `frame-list-demo` entry (port 8736) — NB the pre-existing frame-ui
demo entries there have STALE `--directory` paths (`igniter-lab/igniter-frame/web` vs the real
`igniter-lab/frame-ui/igniter-frame/web`); the new entry uses the correct path.

Next: P3 data-bound `table` node (a `Col` of `Row`s over the layout) + retarget `.igv` to emit the
composed layout; optionally refactor `WorkbenchProjector` onto `solve` (prove byte-identical).

---

## P3 — data-bound table node + live demo (CLOSED)

The vocabulary ceiling the audit named for real apps. `layout::table(id, header_ids, col_weights,
header_h, row_h, rows)` composes a `Col` of a header `Row` + one data `Row` per entry, all sharing
`col_weights` — so the engine resolves IDENTICAL column x-positions for the header and every data row
(columns ALIGN for free, no per-cell coordinate math). A table is "just" a `Col` of `Row`s.

`igniter-frame/src/table_screen.rs` — an interactive leads table (`lead:<n>` facts → `{name, stage,
hot}`): clicking any cell selects its row (cells carry the row's `select` intent; the row container
sits behind them as the selection background), and bottom controls `cycle`/`toggle`/`add` edit the
selected lead (and `add` flows a new row into the table). `WasmTableScreen` + `web/table.html`
(served by the same `run-list-demo.sh`; opens `/table.html`).

Evidence:

```text
cargo test     # 41 pass / 0 fail (adds layout::table_columns_align_across_rows + 3 table_screen tests)
cargo build --no-default-features  +  wasm32 release --features wasm   → clean
wasm: WasmTableScreen exported; ZERO kernel symbols.
```

`table_columns_align_across_rows` asserts the header and every data row share each column's x AND
width (weights 3:2:1 over 600 → 300/200/100 at x 0/300/500). `table_screen` tests:
`columns_align_and_cell_click_selects_the_row`, `select_cycle_toggle_add_drive_state` (cycle 1→won,
toggle hot, add → a 4th "New lead 4" flows in), `deterministic_replay`.

**Proven LIVE in the browser**: the table renders with aligned `Name | Stage | Hot` columns, rows
data-bound from facts (`Ada/new/○`, `Grace/won/✓`, `Linus/qualified/○`); synthetic select → cycle →
toggle → add advance the frame 0→4, flow "New lead 4" into the grid, and update the title to
`Leads · 4 rows · 2 hot` with chained lineage `input:3 → effect:3 → frame:4` and a changing digest;
no console errors.

Remaining of the "three moves": retarget `.igv` to emit the composed layout (beyond the one
workbench template); optionally refactor `WorkbenchProjector` onto `solve` (prove byte-identical,
retire its constants).

---

## P4 — author a layout as TEXT + live playground (CLOSED)

The authoring-DX surface the vocab opens (the "retarget authoring" move, realized self-contained in
`igniter-frame` rather than churning ui-kit's workbench-shaped `.igv`). A compact, total text DSL →
the same `LayoutBox` tree → `solve` → an inspection render, driven live from a browser text field.

- `layout::parse(text) -> Result<LayoutBox, ParseError>` — indentation-based: each line is
  `<kind> <id> [fixed N | flex N] [pad N] [gap N]` (`kind` = `col`/`row`/`leaf`), two spaces nest a
  child; `#` / `--` comments and blanks ignored. **Total** — any malformed line returns a
  `ParseError{line, msg}` with a 1-based number, never a panic (safe to call on every keystroke).
- `layout::preview_svg(tree, w, h)` — solved boxes as depth-colored labeled rects; ids HTML-escaped
  (arbitrary author text can't inject markup). `layout::error_svg(err, w, h)` — a parse-error card.
- `wasm: layout_preview(src, w, h) -> String` (free fn) + `web/playground.html` — a textarea + a live
  SVG pane that re-parses/re-solves on input, with `app shell` / `3-pane` / `form` / `holy grail`
  examples. The Rust parse+solve runs in the browser; no JS computes layout.

Evidence:

```text
cargo test     # 45 pass / 0 fail (adds parse_builds_the_same_tree_as_the_builder,
               #   parse_ignores_comments_and_blank_lines, parse_reports_errors_*, preview_svg_*)
cargo build --no-default-features  +  wasm32 release --features wasm   → clean
wasm: layout_preview exported; ZERO kernel symbols.
```

Tests: parse round-trips to the builder tree (and solves); comments/blanks ignored; **errors carry
1-based line numbers and never panic** (unknown kind/attr, odd indent, indent jump, non-integer,
indented root, empty); preview is deterministic and **escapes author markup** (`<script>` →
`&lt;script&gt;`), and a parse error renders a card.

**Proven LIVE in the browser**: the default app-shell spec renders 14 nested depth-colored boxes
(screen→header/body→sidebar(nav-a/b/c)+main(toolbar/cards→card-1/2/3)→footer); editing the text
reflows instantly (a 3-pane spec → split/left/middle/right); a malformed spec shows
`parse error · line 2 · indentation must be a multiple of 2 spaces`; an `<img onerror=…>` author
string does not inject (no raw `<img>`); no console errors. Run: `./web/run-list-demo.sh` →
`/playground.html` (also `/list.html`, `/table.html`).

The layout vocabulary now spans: engine (P1) → composed list (P2) → data-bound table (P3) → text
authoring + live playground (P4). Still open: a true `.igv` retarget in ui-kit (this DSL is the
target shape it would lower to); optional `WorkbenchProjector`-onto-`solve` byte-identical refactor.

---

## P5 — breadth: cross-axis alignment + a settings-form widget vocabulary (CLOSED)

Broadens 2D DX toward "pleasant DX across forms" — the layout half (alignment) + the render half
(widgets), the gaps the P1 boundary flagged (cross-axis was stretch-only / start-only).

**Layout engine (`layout.rs`):** `CrossSize::{Stretch, Fixed(n)}` (a child's cross-axis size; default
stretch) and `Align::{Start, Center, End}` (a container positions its non-stretched children on the
cross axis — the analogue of `align-items`), with builders `.cross(n)` / `.align(a)` and DSL
attributes `cross N` / `align start|center|end`. Defaults (`Stretch`/`Start`) preserve every prior
layout byte-for-byte (no regressions). True size-to-content is deferred (needs text metrics — out of
scope for the machine-free engine; cross size is authored explicitly).

**Widget vocabulary (`form_screen.rs`):** a settings form — each field a row of `label (flex) +
control (fixed cross-size, cross-aligned center)` — exercising **toggle**, **checkbox**, **segmented
control**, **stepper** (− value +, clamped 1..99), and **action buttons** (Reset / Save). All
click-driven; state is world facts; `Save` summarizes the state into a status line. `WasmFormScreen`
+ `web/form.html`. (Keyboard text entry is the next slice — every control here is click-only.)

Evidence:

```text
cargo test     # 51 pass / 0 fail (adds cross_align_positions_fixed_cross_children, dsl_parses_cross_and_align,
               #   + 4 form_screen tests); existing list/table/layout suites unchanged (defaults preserved)
cargo build --no-default-features  +  wasm32 release --features wasm   → clean
wasm: WasmFormScreen exported; ZERO kernel symbols.
```

Layout tests: a `Fixed` cross child is centered/end-positioned by the parent `align` (row → vertical,
col → horizontal) while a stretched sibling still fills; the DSL round-trips `cross`/`align` and
rejects a bad align word. Form tests: controls sit right of their label and are vertically centered
by `align` (toggle `sy == row.sy + (42-28)/2`); segmented cells are equal-width; toggle/checkbox/
segmented/stepper drive state and `Save` produces the summary; the stepper clamps and `Reset`
restores defaults; replay is byte-identical.

**Proven LIVE in the browser**: the form renders the full control set (two toggles — one on/green, one
off; an empty checkbox; a Free|**Pro**|Team segmented control; a − **3** + stepper; Reset / green Save
buttons), all cross-aligned without coordinate math; clicking toggle-dark → Team → +,+ → Save yields
`Saved ✓ — notifications on, dark on, newsletter off, plan Team, 5 seats` (frame 0→5, lineage
`input:4 → effect:4 → frame:5`, changing digest); no console errors. The playground gains `cross` /
`align` in its grammar + an `aligned` example (a right-aligned, vertically-centered toolbar). Run:
`./web/run-list-demo.sh` → `/form.html` (also `/list.html`, `/table.html`, `/playground.html`).

Next breadth slices: keyboard/text-entry input path (type into a focused field — a runtime+wasm
`key`/`text` method + a `__focus__` fact); a reusable generic widget render host shared across
screens; then the 3D/gamedev frontier (Ceiling B).

---

## P6 — keyboard text entry (CLOSED)

Completes the form story: fields you click to focus and then TYPE into. Notably this needed **no
runtime change** — the existing `FrameRuntime::send(action, params)` system-intent path (already
documented for `send("type", {"char":"a"})`) carries keystrokes, and `__focus__` is just another
world fact. A pointer derives a `focus` intent (hit-test); a keystroke is a system intent (no
hit-test); the reducer edits whichever field `__focus__` names.

`igniter-frame/src/text_form_screen.rs` — a contact form (`field:{name,email,msg}` facts):
`TextFormRuntime::key(k)` maps a browser key — printable char → `send("type", {char})`, `Backspace`
→ delete, `Enter` → submit, modifier/nav keys ignored. Input is length-capped (40) and the focused
input shows an accent border + caret. `WasmTextForm` (with a `key` method) + `web/text.html` (forwards
`keydown` → `key`, pointer → `click`).

Evidence:

```text
cargo test     # 55 pass / 0 fail (adds 4 text_form tests: focus-then-type, backspace/clear/submit,
               #   length-cap + modifier-key ignore, deterministic replay of a focus+typing log)
cargo build --no-default-features  +  wasm32 release --features wasm   → clean
wasm: WasmTextForm exported (with key); ZERO kernel symbols.
```

Tests: typing with nothing focused is a no-op; click focuses and subsequent keys land only in that
field; refocusing routes to another field; backspace pops; `Enter` submits a summary; `Clear` wipes
all fields; input caps at 40 chars and ignores `Shift`/`ArrowLeft`/`Tab`; replaying a focus+typing
log is byte-identical.

**Proven LIVE in the browser** (stepping per event-loop tick, as a real user does): click Name → type
`Ada`, click Email → type `ada@x.io`, `Enter` → `Sent ✓ — name "Ada", email "ada@x.io", 0 chars of
message`, focused field shows the blue border + caret, lineage `submit:13 → effect:13 → frame:14`, no
console errors. (Note: dispatching a synthetic pointer click in the *same synchronous JS batch*
immediately after synthetic `keydown`s — which call `draw()`/`innerHTML` — does not register the
click; this is a test-harness batching artifact only, not reachable by a real user, and the Rust unit
tests + multi-tick browser flow confirm the logic.) Run: `./web/run-list-demo.sh` → `/text.html`.

The 2D DX surface now covers: layout engine + alignment, text authoring/playground, list, table,
click-controls form, and keyboard text entry. Next breadth options: a reusable generic widget render
host shared across the screens (retire the per-screen hosts); scroll/overflow; then the 3D/gamedev
frontier (Ceiling B).

---

## P7 — scroll/overflow + keyboard nav + hover (CLOSED)

Three interaction-breadth features on one scrollable list, and a **two-tier state model** the stack
was missing: ephemeral PRESENTATION state vs. semantic DOMAIN effects.

**Runtime (`runtime.rs`, generic + reusable):** `view_send(action, params)` runs the reducer and
applies deltas (so view facts update and the next render reflects them) but does NOT advance the step
counter or lineage. `hover(css_x, css_y)` hit-tests and routes the hovered id as a view-only `hover`
intent; `scroll(css_x, css_y, dy)` routes the wheel delta as a view-only `scroll` intent (the reducer
owns clamping). So hover/scroll re-render without inflating the frame index; nav/select stay semantic.

**Screen (`scroll_list_screen.rs`):** a 24-row list in a fixed 10-row viewport (row-snapped — the
window is `items[off..off+10]`, so no partial-row clipping and hit-test stays exact). Wheel scrolls
(`__scroll__`, clamped); pointer-move highlights the hovered row (`__hover__`); Tab / Shift-Tab /
Arrows move a focus ring (`__focus__`) and AUTO-SCROLL to keep it visible; Enter/Space/click select.
A proportional scrollbar thumb shows the window position. `WasmScrollList` (click/hover/scroll/key)
+ `web/scroll.html` (forwards `wheel`/`pointermove`/`keydown`).

Evidence:

```text
cargo test     # 60 pass / 0 fail (adds 5: wheel-scroll+clamp+view-only, hover+view-only+no-op-dedup,
               #   tab-focus+autoscroll+enter-select, click-select, deterministic replay)
cargo build --no-default-features  +  wasm32 release --features wasm   → clean
wasm: WasmScrollList exported; ZERO kernel symbols.
```

Tests assert the **view-only property explicitly**: scrolling 5 notches and hovering a row leave
`frame_index` unchanged, yet the window/highlight update; scroll clamps at both ends; re-hovering the
same row returns no redraw; 12 Tabs move focus 0→12 and the list auto-scrolls so item:12 stays
visible while item:0 leaves; Enter selects the focused row; replaying a scroll+hover+nav log is
byte-identical.

**Proven LIVE in the browser**: wheel scrolls the window (`showing 1–10` → `6–15 of 24`) with
`frame_index` staying 0 (view-only); pointer-move highlights the row under the cursor (also frame 0);
12 Tabs advance the frame 0→12 and auto-scroll to `showing 4–13` with the focus ring on the focused
row; Enter → `Selected 13 Esme`, lineage `activate:12 → effect:12 → frame:13`; no console errors. The
screenshot shows all three at once (focus ring on row 1, hover on row 5, scrollbar thumb). Run:
`./web/run-list-demo.sh` → `/scroll.html`.

The 2D DX surface now spans layout+alignment, text authoring/playground, list, table, click-controls
form, keyboard text entry, and scroll+nav+hover — with a clean view/domain state split. Next: a
reusable generic widget render host (retire the per-screen hosts); then the 3D/gamedev frontier
(Ceiling B).

---

## P8 — one generic widget render host (CLOSED)

Every screen shipped its own `RenderHost` with an ad-hoc `kind` vocabulary (5 hosts, ~50 match arms,
divergent names — two `item`s, two `toggle`s). This collapses them into a single
`widget_host::WidgetRenderHost { width, height }` that renders a frame by dispatching on each node's
**canonical** `data.kind` + a documented data contract. A new screen no longer writes a render host —
it emits canonical widget nodes and gets a consistent look for free. **This canonical vocabulary is
the surface a developer authors against — the seam toward `.igv`.**

Canonical kinds: `title` · `label` · `note` (hint/status/footer, tone+align) · `panel`
(surface/bar/group) · `row` (selected/hovered/focused/done/lead — the unified list & table row) ·
`cell` · `header_cell` · `button` (go/warn/neutral/add) · `toggle` · `checkbox` · `segment` ·
`stepper_btn` / `stepper_val` · `input` · `scrollbar` (track/thumb).

Migration: all 5 projectors now emit canonical kinds (e.g. table `hbar`→`panel{variant:bar}`,
`th`→`header_cell`, `rowbg`→`row`; form `seg`→`segment`, `seggroup`→`panel{variant:group}`,
`stepbtn`→`stepper_btn`; list `item`→`row`, the detail `toggle` and `add` row →`button`; scroll
`item`→`row{lead:dot}`, `sbthumb`→`scrollbar{variant:thumb}`). The 5 `*RenderHost` structs and their
duplicated `esc` helpers are deleted; each runtime now constructs `WidgetRenderHost::new(W, H)`.

Evidence:

```text
cargo test     # 60 pass / 0 fail — unchanged (tests assert node DATA + determinism, not golden bytes,
               #   so unifying the host is behaviour-preserving). Only one test touched: scroll's
               #   `visible()` filter item→row.
cargo build --no-default-features  +  wasm32 release --features wasm   → clean (no unused warnings)
```

**Proven LIVE**: all five demos (`/list /table /form /text /scroll`) render correctly under the single
host with a consistent, normalized look (list rows + add/done as canonical buttons; table header as a
`panel{bar}`; form controls; text inputs; scroll rows with `lead:dot` markers) — no console errors.
Net: −5 render hosts, +1 shared host + a named widget vocabulary.

Next: the DX investigation — what do we hand a developer? The canonical widget vocabulary + the layout
DSL are the two halves of an authoring surface (`.ig` / `.igv`); then the 3D/gamedev frontier
(Ceiling B).
