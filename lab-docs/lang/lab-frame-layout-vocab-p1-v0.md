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
