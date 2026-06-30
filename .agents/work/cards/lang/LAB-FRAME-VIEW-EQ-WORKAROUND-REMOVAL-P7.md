# LAB-FRAME-VIEW-EQ-WORKAROUND-REMOVAL-P7

Status: CLOSED (2026-06-28)
Route: standard / igniter-lab / frame-ui / igniter-frame / interaction / payoff
Skill: idd-agent-protocol

Depends-On: `LAB-VM-PRIMITIVE-EQ-PARITY-P1`

## Goal

Remove the frame-ui selected-state equality workaround and prove the authored `.ig` view/reducer path can use
real equality:

```ig
result.sel == row_id
```

This is the payoff card after VM equality parity. It should make frame-ui stop carrying a host-side or
hand-authored workaround for selected rows.

## Current Authority

Live source wins over this card if it moved.

Read first:

- `frame-ui/igniter-frame/tests/ig_reducer_interaction_tests.rs`
- `frame-ui/igniter-frame/tests/ig_runtime_bridge_tests.rs`
- `frame-ui/igniter-frame/tests/fixtures/`
- `frame-ui/igniter-frame/src/ig_bridge.rs`
- `lab-docs/lang/lab-frame-view-ig-reducer-interaction-p5-v0.md`
- `lab-docs/lang/lab-vm-primitive-eq-parity-p1-v0.md`

Known context:

- P5 proved reducer interaction, but selected-state was not fully authored through equality because VM `eq`
  parity was still open.
- P1 should make equality usable in the VM. This card consumes that fact; do not re-implement equality here.

## Questions To Answer

1. Where exactly is the workaround today: authored `.ig`, generated fixture, Rust bridge, or test-only JSON?
2. Can the selected row be expressed in the authored `.ig` source using row ID equality only?
3. Does the runtime-produced `Element` JSON preserve selected/checked/active state after click → reducer →
   rerender?
4. Is any remaining host-side special casing still present after the change?

## Implementation Guidance

1. Verify P1 is committed or present in the working tree.
2. Locate the selected-state workaround and remove the smallest amount of code/fixture drift.
3. Update the authored `.ig` specimen so selection is computed by equality over stable row IDs.
4. Regenerate any command-produced runtime fixture if the frame tests use checked-in JSON.
5. Add/adjust tests so the proof is interaction-shaped:
   - initial render has no selected row or the documented default,
   - click/select row A,
   - rerun/reduce,
   - row A is visibly selected and row B is not.
6. Keep `ig_bridge` structural: it may render selected state, but it must not decide selection by itself.

## Acceptance

- [x] Workaround location named in the packet: (1) `vm_loop_app.ig` status-text-echo stand-in (NOTE
      avoiding `==`); (2) Rust `IgViewProjector` `n.id == sel` in `ig_reducer_interaction_tests`.
- [x] Workaround removed + replaced by authored `.ig` equality (`row_key == state.sel` in `View`).
- [x] Fixtures command-produced; the regen command is documented (packet + `ig_vm_loop_tests` header),
      with `latency_us` normalized to 0 for byte-reproducibility.
- [x] Frame-ui test proves the selected row changes through reducer interaction (`ig_vm_loop_tests`).
- [x] Evidence distinguishes selected vs unselected: `sel=""`→(f,f,f); `sel="lead:1"`→(f,**t**,f).
- [x] No host-side equality / row-ID special casing remains in the `.ig` view path (only hand-written
      Rust demo screens keep their own `== sel` — not the view path; noted in packet).
- [x] P1 verification remains green (`primitive_eq_parity_tests` 6/6, fleet 13/13).
- [x] `frame-ui/igniter-frame` tests green (full suite 79/0).
- [x] `Cargo.lock` not staged (no dependency change).
- [x] `git diff --check` is clean.

## Report (2026-06-28)

The payoff after P1. The selected-state workaround existed in two spots because `==` was assumed
VM-unavailable: (1) `vm_loop_app.ig` carried a NOTE and used a status-text echo instead of per-row
selection; (2) the P5 Rust test projector marked `n.id == sel` in host code. Both removed.

`vm_loop_app.ig` now authors selection with real equality: `Element` gained `selected : Bool`, and
`View` computes each row `selected = "lead:i" == state.sel` via `==` (run on the VM). The bridge
(`ig_bridge.rs`) was extended to RENDER the authored `selected` (read from the Element, default
false) — structural only, never deciding selection. `widget_host` already styles selected rows, so
it shows in the SVG. Fixtures regenerated from the specimen; `ig_vm_loop_tests` now asserts per-row
authored selection (click "Call Grace back" → `Reduce` sets `sel="lead:1"` → re-run `View` marks
exactly that row); `ig_reducer_interaction_tests` lost its host-eq marking and now proves loop
mechanics only; `examples/vm_loop.rs` self-check updated to assert authored selection.

Files: `frame-ui/igniter-frame/src/ig_bridge.rs`, `…/examples/vm_loop.rs`,
`…/tests/ig_vm_loop_tests.rs`, `…/tests/ig_reducer_interaction_tests.rs`,
`…/tests/fixtures/vm_loop_{view0,view1,reduce}.runtime.json`,
`lab-docs/lang/specimens/dx-view-d/vm_loop_app.ig`, packet
`lab-docs/lang/lab-frame-view-eq-workaround-removal-p7-v0.md`.

Remaining: none for authored selected-state. A first-class in-process VM-loop projector behind the
optional `machine` feature is a possible future DX slice (library stays machine-free today via the
subprocess-`igniter-vm` + command-produced-fixtures shape).

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab

cargo test --manifest-path lang/igniter-vm/Cargo.toml <eq_test_name>
cargo test --manifest-path frame-ui/igniter-frame/Cargo.toml --test ig_reducer_interaction_tests
cargo test --manifest-path frame-ui/igniter-frame/Cargo.toml --test ig_runtime_bridge_tests
git diff --check
```

## Required Packet

Create:

```text
lab-docs/lang/lab-frame-view-eq-workaround-removal-p7-v0.md
```

Packet must include:

- dependency evidence from P1,
- exact workaround removed,
- authored equality snippet,
- runtime/render evidence,
- verification commands and results,
- remaining frame-ui blockers, if any.

