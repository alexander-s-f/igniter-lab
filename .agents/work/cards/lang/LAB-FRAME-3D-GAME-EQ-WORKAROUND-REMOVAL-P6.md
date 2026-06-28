# LAB-FRAME-3D-GAME-EQ-WORKAROUND-REMOVAL-P6

Status: CLOSED (2026-06-27)

## Closing Report

- **Result:** GREEN. Workaround removed — `KickBody` uses direct `if target == b.id { … }`. But live
  re-verify found a REGRESSION contradicting P1: `==` lowered to the OP_CALL path failed everywhere with
  `OP_CALL: Unknown/unimplemented function 'stdlib.primitive.eq'` — including `vm_loop_app.ig`'s `View`
  (P7's "real `==`" case). The card sanctions a VM edit on a regression contradicting P1; made the
  minimal one: added `stdlib.primitive.{eq,ne}` to the VM OP_CALL dispatch (`vm.rs`, after the
  `stdlib.integer.{lt,gt}` arm), reusing the existing `value_eq_exact` — same pattern as the arithmetic
  fix. Packet: `lab-docs/lang/lab-frame-3d-game-eq-workaround-removal-p6-v0.md`.
- **Q1** direct `==` runs? YES (after the fix). **Q2** behavior unchanged? YES — byte-identical kick
  result, tests/harness green. **Q3** stale or real gap? REAL (`stdlib.primitive.eq` absent on OP_CALL
  path) — contradicts P1, now fixed. **Q4** next card → `LAB-VM-OPCALL-BUILTIN-NAME-AUDIT-P1`.
- **Files:** `lang/igniter-vm/src/vm.rs` (+ eq/ne OP_CALL arms — VM owners, reconcile w/ P1),
  `specimens/dx-view-d/vm_game_app.ig` (KickBody direct `==`, comment corrected),
  `lab-docs/lang/lab-frame-3d-game-eq-workaround-removal-p6-v0.md` (packet).
- **Verify:** probe `ViaMap`→`[false,true,false]`; vm_loop `View(lead:1)`→success selected=lead:1; game
  `Reduce(target=1)`→b1 vy 1400, others 0; kick == committed fixture (no fixture change); `cargo test`
  99/0; `git diff --check` clean. No Cargo.lock change; GPU-host assets untouched.
- **Next:** `LAB-VM-OPCALL-BUILTIN-NAME-AUDIT-P1` — sweep OP_CALL builtin names vs igc emission so no
  `stdlib.*` op is unimplemented at runtime while the binary-op/OP_* paths support it.
Route: standard / igniter-lab / frame-ui / 3D game / language-pressure cleanup
Skill: idd-agent-protocol
Depends-On:
- `LAB-VM-PRIMITIVE-EQ-PARITY-P1`
- `LAB-FRAME-3D-GAME-IG-P4`
- `LAB-FRAME-3D-GAME-IG-INTERACTION-P5`
- `frame-ui GPU host P1 / Ceiling B` (`25e5f97`)

## Goal

Remove the stale `<`/`>` equality workaround from the Igniter-authored 3D game
reducer and replace it with normal authored equality.

This is a cleanup/realignment card, **not** a VM feature card. `P1` already
proved that `==` is emitted as `binary_op "=="` / `OP_EQ` and is supported by
the VM for the relevant scalar domains. The current game specimen still carries
an older comment claiming `stdlib.primitive.eq` / `OP_CALL` is missing, and it
implements `id == target` as `(not id<target) * (not id>target)`.

## Current Authority

Live source wins. Read first:

- `.agents/work/cards/lang/LAB-VM-PRIMITIVE-EQ-PARITY-P1.md`
- `lab-docs/lang/lab-vm-primitive-eq-parity-p1-v0.md`
- `lab-docs/lang/specimens/dx-view-d/vm_game_app.ig`
- `frame-ui/igniter-frame/src/game_loop.rs`
- `frame-ui/igniter-frame/tests/ig_vm_game_tests.rs`
- `lab-docs/lang/lab-frame-3d-game-ig-p4-v0.md`
- latest GPU-host proof packet / commit context.

Known live facts to re-verify:

- `vm_loop_app.ig` already uses real equality (`"lead:0" == state.sel`).
- `LAB-VM-PRIMITIVE-EQ-PARITY-P1` says no VM code change was needed.
- `vm_game_app.ig` still has a stale comment and workaround in `KickBody`.

## Scope

Allowed:

- Replace the `ge`/`le`/`hit` workaround in `KickBody` with direct authored
  equality (`b.id == target`) or the smallest equivalent expression that uses
  `==` plainly.
- Remove or correct stale comments that mention `stdlib.primitive.eq` / OP_CALL
  as missing.
- Update tests/fixtures/golden outputs only if the behavior is byte-identical
  except for expected source/projection metadata.
- Add one focused assertion if useful: clicking/kicking the target body still
  changes only that body.
- Add a short proof packet if this changes more than the specimen/test fixture.

Closed:

- Do not edit VM equality implementation unless live verification finds a new
  regression that contradicts `P1`.
- Do not introduce new syntax, `.igv`, `.ig.html`, host-side selection logic, or
  GPU changes.
- Do not broaden into mesh generation, physics features, collision detection,
  or WebGL rendering.
- Do not touch unrelated frame-ui demos.

## Questions To Answer

1. Does direct `b.id == target` compile and run through the current game VM
   harness?
2. Is the rendered/interaction behavior unchanged after removing the workaround?
3. Was the old OP_CALL comment simply stale, or is there a narrower remaining
   equality gap?
4. What should the next 3D/language-pressure card be after the cleanup?

## Acceptance

- [ ] Live equality proof (`LAB-VM-PRIMITIVE-EQ-PARITY-P1`) and game specimen are
      re-verified before editing.
- [ ] `vm_game_app.ig` uses direct authored equality for target selection.
- [ ] Stale `stdlib.primitive.eq` / OP_CALL workaround comments are removed or
      replaced with current truth.
- [ ] Frame-ui 3D/game VM tests pass.
- [ ] GPU-host demo assets are not changed unless behavior requires it.
- [ ] No VM/compiler code changes unless a fresh regression is documented.
- [ ] `git diff --check` passes.
- [ ] Card closed with concise report and next-card recommendation.

## Suggested Verification

Adapt after live discovery, but start with:

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
cargo test --manifest-path frame-ui/igniter-frame/Cargo.toml ig_vm_game
cargo test --manifest-path frame-ui/igniter-frame/Cargo.toml
git diff --check
```

If the card discovers that `b.id == target` still fails, stop and write the exact
failure shape. Do not silently reintroduce the workaround.

## Optional Packet

Create only if useful:

```text
lab-docs/lang/lab-frame-3d-game-eq-workaround-removal-p6-v0.md
```

Packet should be short: stale premise, direct equality proof, test results, and
the next pressure card.
