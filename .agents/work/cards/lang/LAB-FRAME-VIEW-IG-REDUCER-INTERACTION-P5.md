# LAB-FRAME-VIEW-IG-REDUCER-INTERACTION-P5

Status: CLOSED (2026-06-27)
Route: standard / frame-ui / Igniter-authored view + reducer interaction
Skill: idd-agent-protocol
Depends-On: `LAB-FRAME-VIEW-ELEMENT-TREE-HOST-BRIDGE-P2`, `LAB-FRAME-VIEW-IGC-RUN-ELEMENT-EXTRACTION-P3`, `LAB-FRAME-VIEW-DYNAMIC-RUNTIME-BRIDGE-P4`, `LAB-FRAME-VIEW-FORM-DESUGAR + ASK1/ASK2 canon contribution (P1)`

## Goal

Close the next frame-ui payoff loop: an Igniter-authored view declares intents,
the frame runtime hit-tests a real click, and a reducer updates state
deterministically, proving "view + logic" composition instead of only static
rendering.

P2-P4 proved `.ig`/desugared view output can render through the host bridge.
This card proves that rendered intent nodes can drive the existing frame input
loop and reducer substrate.

## Current Authority

Live frame-ui code and the latest proof packet win.

Read first:

- `lab-docs/lang/lab-frame-view-form-desugar-and-ask-contribution-p1-v0.md`
- `frame-ui/igniter-frame/src/ig_bridge.rs`
- `frame-ui/igniter-frame/src/igv_desugar.rs`
- `frame-ui/igniter-frame/src/machine_source.rs`
- `frame-ui/igniter-frame/src/runtime.rs`
- `frame-ui/igniter-frame/src/list_screen.rs`
- `frame-ui/igniter-frame/tests/ig_runtime_bridge_tests.rs`
- `frame-ui/igniter-frame/tests/frame_input_loop_tests.rs`
- `frame-ui/igniter-frame/tests/renderer_host_tests.rs`

Known live facts to verify:

- `render_ig_view` maps `Element.intent` into `ProjectedNode.intent`;
- frame input loop already has hit-test -> intent -> reducer -> effect lineage;
- P4/P1 fixtures are command-produced runtime envelopes, not hand mirrors;
- `Cargo.lock` must not be touched for this slice.

## Scope

Allowed:

- Add a focused test that extracts an Element tree from a real runtime envelope
  and drives it through hit-test / intent / reducer.
- Add a tiny app-local reducer for the proof if the existing list reducer is not
  directly reusable.
- Add a small helper to convert an Element tree into a `Frame` / nodes only if
  the current bridge cannot expose the nodes without rendering SVG.
- Keep the reducer machine-free unless using the already-proven
  `TBackendIntentSink` gives a smaller proof.
- Write a proof packet.

Closed:

- No canon language changes.
- No VM/compiler changes.
- No `.form` parser in canon.
- No new widget vocabulary unless a test cannot be written otherwise.
- No browser/WASM requirement.
- No Cargo.lock changes.

## Design Constraint

Do not make the SVG renderer parse itself. The interaction proof should use the
same semantic nodes that rendering uses, not scrape rendered SVG text.

If `ig_bridge` only exposes `render_ig_view`, prefer adding a narrow
`element_to_frame_for_test` / `project_ig_element` helper with a total,
fail-closed shape and test coverage.

## Questions To Answer

1. Does `Element.intent` survive into hit-testable `ProjectedNode.intent`?
2. Can a click on a runtime-produced Igniter view produce the expected intent?
3. Can a reducer consume that intent and update state deterministically?
4. Does lineage remain input -> effect -> next frame, not frame mutation?
5. Is the proof still green for dynamic P4 and desugared-form P1 fixtures?

## Acceptance

- [ ] A command-produced `.ig` runtime Element fixture is used as the view source
      (dynamic P4 and/or form-desugared P1).
- [ ] A click on a rendered/solved node derives the authored intent, not a
      host-invented action.
- [ ] Reducer output changes state deterministically.
- [ ] Miss/no-hit path produces no effect and no state change.
- [ ] Lineage or equivalent proof shows intent flows through effect, not direct
      frame mutation.
- [ ] Existing frame-ui tests remain green.
- [ ] No canon/VM/compiler changes and no Cargo.lock changes.
- [ ] `git diff --check` passes.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
cargo test --manifest-path frame-ui/igniter-frame/Cargo.toml --test ig_runtime_bridge_tests
cargo test --manifest-path frame-ui/igniter-frame/Cargo.toml --test frame_input_loop_tests
cargo test --manifest-path frame-ui/igniter-frame/Cargo.toml
git diff --check
```

## Required Packet

Create:

```text
lab-docs/lang/lab-frame-view-ig-reducer-interaction-p5-v0.md
```

Include the source fixture, click/intent target, reducer behavior, lineage
claim, tests, and the remaining gap to real `.ig` reducer authoring if any.

## Closing Report

- **Result:** GREEN. The view+logic loop is proven over BOTH command-produced fixtures (dynamic P4 +
  desugared-form P1). Packet: `lab-docs/lang/lab-frame-view-ig-reducer-interaction-p5-v0.md`.
  - Q1 (intent survives into `ProjectedNode.intent`): YES. Q2 (click derives the authored intent +
    node-id target, not host-invented): YES. Q3 (reducer updates state deterministically): YES. Q4
    (lineage `input:0 → effect:0 → frame:1`, next frame re-projected from state, not mutated): YES.
    Q5 (green for both fixtures): YES.
- **Source fixture:** `tests/fixtures/list_view_dynamic.runtime.json` + `…_form.runtime.json` (real
  `igniter-vm` output; not hand mirrors).
- **Click/intent target:** a `select`-carrying node; `derive_intent` → `{action:"select", target:<node id>}`.
- **Reducer behavior:** app-local, machine-free `(intent, state) -> deltas`; `select` → `__sel__ = target`.
- **Lineage claim:** input → effect → next frame (re-projection), miss → no effect (`effect_receipt_id:null`).
- **Files changed:** `src/ig_bridge.rs` (added `project_ig_element` + `frame_from_element` refactor;
  `render_ig_view` unchanged in behavior), `tests/ig_reducer_interaction_tests.rs` (new, 4 tests).
- **Tests:** `cargo test` → 78 passed / 0 failed; `git diff --check` clean. No canon/VM/compiler change,
  no Cargo.lock change, no WASM/browser requirement.
- **Remaining gap:** the reducer is a frame-ui (Rust) closure and the next frame re-projects the fixed
  `.ig` tree; making the LOGIC Igniter-authored (run an `.ig` reducer + re-run the `.ig` view on
  `igniter-vm` per click — VM-in-the-loop) is a separate card.
- **Next card (suggested):** `LAB-FRAME-VIEW-IG-VM-IN-THE-LOOP-P6` — run an `.ig` reducer contract on
  `igniter-vm` per click and re-project by re-running the `.ig` view, closing the FULL Igniter
  view+logic loop.
