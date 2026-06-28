# LAB-FRAME-VIEW-SURFACE-REFRESH-P9

Status: DONE
Route: standard / igniter-lab / frame-ui / docs / implemented-surface / hygiene
Skill: idd-agent-protocol

## Goal

Refresh the frame-view/front-door documentation after the P1/P7 equality wave so future agents do not chase
stale blockers.

The important newly proven fact:

```text
.ig View computes selected = row_key == state.sel
  -> igniter-vm executes equality
  -> bridge renders authored selected
  -> frame-ui runtime reprojects after reducer state change
```

This should be discoverable from the local frame docs without reading every proof packet.

## Current Authority

Live source wins over this card if docs disagree.

Read first:

- `frame-ui/igniter-frame/README.md`
- `frame-ui/igniter-frame/Cargo.toml`
- `frame-ui/igniter-frame/tests/ig_vm_loop_tests.rs`
- `frame-ui/igniter-frame/tests/ig_reducer_interaction_tests.rs`
- `frame-ui/igniter-frame/src/ig_bridge.rs`
- `lang/igniter-vm/IMPLEMENTED_SURFACE.md`
- `lab-docs/lang/lab-vm-primitive-eq-parity-p1-v0.md`
- `lab-docs/lang/lab-frame-view-eq-workaround-removal-p7-v0.md`

## Questions To Answer

1. Where is the current front door for frame-ui status: README only, lab docs, or both?
2. Does it still imply selected-state is host-side, static, mirrored, or blocked on equality?
3. Does it clearly distinguish:
   - structural bridge rendering,
   - authored `.ig` view state,
   - runtime click/reducer/reprojection loop,
   - command-produced fixture boundary?
4. Does it document the remaining DX gap: in-process VM-loop projector is future, command/fixture proof is live?
5. Is `Cargo.lock` tracked or ignored in this crate, and is there any stale instruction about it?

## Scope

Allowed:

- Doc-only edits to `frame-ui/igniter-frame/README.md` and/or a small lab front-door doc if one already
  exists.
- Cross-link the two proof packets and the live tests.
- Clarify `Cargo.lock` status if the docs mention it.

Closed:

- No source changes.
- No fixture changes.
- No new feature work.
- No broad audit-board rewrite unless live docs require a one-line pointer.

## Acceptance

- [x] Docs state equality is live in VM and not a current frame-ui blocker.
- [x] Docs state selected-state is authored in `.ig` and rendered structurally by `ig_bridge`.
- [x] Docs state the current VM loop proof still uses subprocess/command-produced fixtures.
- [x] Docs name the remaining DX follow-up: in-process VM-loop projector readiness/implementation.
- [x] Docs do not claim `.igv`, `.ig.html`, cross-module forms, or public frame API stability beyond evidence.
- [x] Relevant tests are not rerun broadly unless the doc change needs proof; at minimum `git diff --check`.
- [x] No production code changes.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab

git diff --check
rg -n "eq|equality|selected|VM loop|fixture|subprocess" frame-ui/igniter-frame/README.md lab-docs/lang
```

## Required Packet

Create:

```text
lab-docs/lang/lab-frame-view-surface-refresh-p9-v0.md
```

Packet must include:

- exact stale claims found or state “none found”,
- files edited,
- current-true surface summary,
- remaining follow-up link to P8/P10 as appropriate.

## Closing Report - 2026-06-28

Result: DONE. Refreshed the frame-view/front-door documentation after the P1/P7 equality wave.

Files edited:

- `frame-ui/igniter-frame/README.md`
- `lab-docs/lang/lab-frame-app-authoring-checkpoint-p14-v0.md`
- `lab-docs/lang/lab-frame-view-surface-refresh-p9-v0.md`
- this card

Current-true summary now discoverable:

- VM equality `==` / `OP_EQ` is live and is not a current frame-ui blocker.
- Selected-state is authored in `.ig` as `selected = row_key == state.sel`.
- `ig_bridge` renders the authored `selected` field; it does not decide selection with host-side equality.
- The VM-loop payoff is proven through command-produced runtime fixtures / subprocess boundary.
- Remaining DX follow-up: `LAB-FRAME-VIEW-VM-LOOP-PROJECTOR-READINESS-P10`.

Cargo.lock status:

- `frame-ui/igniter-frame/Cargo.lock` exists locally but is ignored by
  `frame-ui/igniter-frame/.gitignore`; it is not a tracked deliverable today.

Verification:

```text
git diff --check
```

Result: PASS.

```text
rg -n "eq|equality|selected|VM loop|fixture|subprocess" frame-ui/igniter-frame/README.md lab-docs/lang
```

Result: refreshed front-door wording is present. Historical P6 stale wording is still found as expected
historical evidence, superseded by P1/P7/current README entries.

No source, fixture, or production code changes were made. Broad tests were not rerun because this was a
doc-only hygiene slice.
