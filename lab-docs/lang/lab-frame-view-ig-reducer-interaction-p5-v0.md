# LAB-FRAME-VIEW-IG-REDUCER-INTERACTION-P5 — proof packet

Status: CLOSED — the view+logic loop is proven: a click on an Igniter-authored view derives the
authored intent and drives a reducer through the existing frame input loop.
Card: `.agents/work/cards/lang/LAB-FRAME-VIEW-IG-REDUCER-INTERACTION-P5.md`
Lane: igniter-lab / frame-ui / Igniter-authored view + reducer interaction
Date: 2026-06-27

## Result

P2–P4/P1 proved an Igniter-authored `Element` tree renders through the bridge. This closes the next
loop: the SAME semantic nodes drive interaction. A click hit-tests a node, `derive_intent` lifts the
AUTHORED intent (with the node id as target), a reducer updates state, and the NEXT frame is a
re-projection from the new state — **input → effect → next frame, never a frame mutation**. Machine-free,
no SVG scraping.

## Source fixtures (command-produced, not hand mirrors)

- `tests/fixtures/list_view_dynamic.runtime.json` — P4, the `map`-built specimen run on `igniter-vm`.
- `tests/fixtures/list_view_form.runtime.json` — P1, the desugared `col { row { leaf } }` form run on
  `igniter-vm`.
The proof runs over BOTH (Q5).

## Host path / helper added

`ig_bridge.rs` now exposes **`project_ig_element(element_json, w, h) -> Frame`** — the bridge's semantic
nodes (layout → solve → canonical widgets, each `Element.intent` preserved on `ProjectedNode.intent`),
total + fail-closed (malformed JSON → empty frame). `render_ig_view` was refactored to share the same
`frame_from_element` path, so **interaction uses exactly the nodes rendering uses** (no SVG re-parse).

## The loop (test `ig_reducer_interaction_tests.rs`)

A `FrameRuntime` is built over: world `[("__sel__","")]`, an `IgViewProjector` holding the fixed `.ig`
Element tree (it projects the bridge nodes and marks the `__sel__` node), the app-local reducer, and a
no-op render host (semantics, not SVG).

- **Q1 — intent survives:** a node carries the authored `select` intent (`ProjectedNode.intent`), and is
  initially not selected.
- **Q2 — authored intent, not host-invented:** `derive_intent` on a click over that node →
  `Intent{ action:"select", target: Some(node_id) }` — the action is the authored one, the target is the
  hit node's id.
- **Q3 — reducer updates state deterministically:** `select` → `[("__sel__", node_id)]` (pure
  `(intent, state) -> deltas`, machine-free).
- **Q4 — lineage input → effect → next frame:** `rt.click(...)` advances the step `0 → 1`; lineage =
  `input:0 → effect:0 → frame:1`; and the re-projected next frame marks that node `selected: true` — the
  view changed because STATE changed and was re-projected, not because the frame was mutated.
- **Miss path:** a click outside any node → `false`, no step advance, `effect_receipt_id: null`.
- **Determinism:** the same click log → the same frame index + render digest.

`cargo test` (frame-ui): **78 passed / 0 failed** (4 interaction tests added; the `project_ig_element`
refactor kept all render tests green). `git diff --check`: clean. No canon/VM/compiler changes, no
Cargo.lock change.

## Remaining gap (honest)

The **VIEW** is Igniter-authored (real runtime output); the **REDUCER** here is a small frame-ui (Rust)
closure, and the next frame re-projects the FIXED `.ig` tree (marking selection) rather than re-running
the `.ig` view with new state. To make the LOGIC also Igniter-authored, the next step runs an `.ig`
reducer contract `(intent, state) -> deltas` on `igniter-vm` per click (the same run path P4 used for the
projector), and re-projects by re-running the `.ig` view on the new state — i.e. VM-in-the-loop. That is
a separate card; this one proves the authored intents flow through the real input loop + reducer
substrate, which was the open question.

## Files

- `frame-ui/igniter-frame/src/ig_bridge.rs` — `project_ig_element` + `frame_from_element` (refactor).
- `frame-ui/igniter-frame/tests/ig_reducer_interaction_tests.rs` — the loop proof (4 tests, both fixtures).
