# LAB-FRAME-VIEW-SURFACE-REFRESH-P9

Date: 2026-06-28
Status: DONE
Route: standard / igniter-lab / frame-ui / docs / implemented-surface / hygiene

## Scope

Doc-only refresh after the P1/P7 equality wave. This is lab evidence, not canon language authority.
No source, fixture, feature, VM, compiler, machine, or public frame API changes were made.

## Front Door

The current local front door for `igniter-frame` status is:

- `frame-ui/igniter-frame/README.md` for crate-local runtime/projection status.
- `lab-docs/lang/lab-frame-app-authoring-checkpoint-p14-v0.md` for the broader UI authoring
  stack map that the README links to.

Both now point at the current frame-view equality surface without requiring an agent to read every
historical proof packet.

## Stale Claims Found

No live README claim said equality was still blocked or that selected-state remained host-side.
The stale-risk was omission: the README stopped at the P7/P8 projection-agnostic runtime section and
did not state the later P1/P7 payoff.

Historical docs still contain time-local evidence:

- `lab-docs/lang/lab-frame-view-ig-vm-in-the-loop-p6-v0.md` says VM equality was a gap and that the
  proof used a status-text echo workaround. That was accurate for P6 and is superseded by P1/P7.
- `lab-docs/lang/lab-frame-view-eq-workaround-removal-p7-v0.md` consumes the P1 equality result and
  closes the workaround. Its dependency summary names `stdlib.primitive.eq`; the current precise
  surface is `binary_op op:"=="` / `OP_EQ`, with `stdlib.primitive.eq` only an internal typechecker
  resolution name. New front-door wording uses the precise current surface.

## Current-True Surface

The selected-state loop is:

```text
.ig View computes selected = row_key == state.sel
  -> igniter-vm executes equality
  -> ig_bridge renders authored selected
  -> frame-ui runtime reprojects after reducer state change
```

Authority anchors:

- `lang/igniter-vm/IMPLEMENTED_SURFACE.md`: equality `==` / `OP_EQ` is implemented and routes through
  `value_eq_exact`; the compiler emits SIR `binary_op op:"=="`.
- `lab-docs/lang/lab-vm-primitive-eq-parity-p1-v0.md`: verify-first characterized equality and added
  regression tests.
- `frame-ui/igniter-frame/src/ig_bridge.rs`: `selected` is read from the authored Element JSON and
  rendered structurally; the bridge does not decide selection.
- `frame-ui/igniter-frame/tests/ig_vm_loop_tests.rs`: command-produced VM fixtures prove click key ->
  `.ig Reduce` -> `.ig View` re-run -> selected row rendered.
- `frame-ui/igniter-frame/tests/ig_reducer_interaction_tests.rs`: proves the runtime mechanics
  around hit-test, authored intent, reducer effect, lineage, and re-projection.

## Edited Files

- `frame-ui/igniter-frame/README.md`
- `lab-docs/lang/lab-frame-app-authoring-checkpoint-p14-v0.md`
- `lab-docs/lang/lab-frame-view-surface-refresh-p9-v0.md`
- `.agents/work/cards/lang/LAB-FRAME-VIEW-SURFACE-REFRESH-P9.md`

## Remaining Follow-Up

The in-process VM-loop projector/runner remains the next DX gap. Today's proof is intentionally at the
subprocess / command-produced fixture boundary so the frame crate remains machine-free.

Good follow-up route:

```text
LAB-FRAME-VIEW-VM-LOOP-PROJECTOR-READINESS-P10
```

That card should decide whether to keep the VM loop as an example/subprocess tool, add an optional
machine-feature projector, or create a separate bridge crate. It should stay separate from `.igv`,
`.ig.html`, cross-module forms, and public API stability.

## Cargo.lock

`frame-ui/igniter-frame/Cargo.lock` exists locally but is ignored by
`frame-ui/igniter-frame/.gitignore`. It is not a tracked deliverable for this crate today.

## Verification

```text
git diff --check
```

Result: PASS.

```text
rg -n "eq|equality|selected|VM loop|fixture|subprocess" frame-ui/igniter-frame/README.md lab-docs/lang
```

Result: PASS for the refreshed front-door wording. The grep still finds historical P6 wording, which is
expected historical evidence and is superseded by the P1/P7/current README entries.
