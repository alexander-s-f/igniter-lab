# LAB-FRAME-VIEW-EQ-WORKAROUND-REMOVAL-P7

Status: TODO
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

- [ ] Workaround location is named in the proof packet.
- [ ] Workaround removed or replaced by authored `.ig` equality.
- [ ] Runtime/generated fixture, if present, is command-produced and the command is documented.
- [ ] Frame-ui test proves selected row changes through reducer interaction.
- [ ] Test output includes enough evidence to distinguish selected vs unselected rows.
- [ ] No host-side equality or row-ID special casing remains in frame-ui.
- [ ] `LAB-VM-PRIMITIVE-EQ-PARITY-P1` verification remains green.
- [ ] `cargo test` for `frame-ui/igniter-frame` relevant tests is green.
- [ ] Do not stage `frame-ui/igniter-frame/Cargo.lock` unless live investigation proves it belongs to this
      card and the proof packet says why.
- [ ] `git diff --check` is clean.

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

