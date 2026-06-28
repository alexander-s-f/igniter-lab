# LAB-FRAME-VIEW-INPROCESS-VM-LOOP-READINESS-P8

Status: TODO
Route: standard / igniter-lab / frame-ui / igniter-frame / VM-loop / readiness
Skill: idd-agent-protocol

## Goal

Design the next DX slice after authored equality selection: a first-class in-process VM-loop projector for
frame-ui, without breaking the current machine-free frame core.

Today the proof is honest but clunky:

```text
authored .ig View/Reduce
  -> external igniter-vm subprocess
  -> command-produced JSON fixtures
  -> frame-ui bridge/runtime tests
```

We want to know whether the next step should be an optional in-process adapter, a reusable test harness, or
whether subprocess remains the right boundary for now.

## Current Authority

Live source wins over this card if it has moved.

Read first:

- `frame-ui/igniter-frame/Cargo.toml`
- `frame-ui/igniter-frame/src/lib.rs`
- `frame-ui/igniter-frame/examples/vm_loop.rs`
- `frame-ui/igniter-frame/tests/ig_vm_loop_tests.rs`
- `lab-docs/lang/specimens/dx-view-d/vm_loop_app.ig`
- `lab-docs/lang/lab-frame-view-eq-workaround-removal-p7-v0.md`
- `lang/igniter-vm/src/lib.rs`
- `runtime/igniter-machine/src/lib.rs`

Known live facts:

- `igniter-frame` core is intended to build with `--no-default-features` and stay machine-free.
- `igniter-frame` already has an optional `machine` feature for TBackend/frame facts.
- P7 proved authored selected-state via real `.ig` equality using command-produced fixtures.
- The remaining DX pain is orchestration, not view semantics.

## Questions To Answer

1. Should in-process execution depend on `igniter_vm`, `igniter_machine`, both, or a smaller shared crate?
2. Should it be a new feature (`vm-loop`) separate from existing `machine`, or live under `machine`?
3. Can the adapter expose a pure-ish API like:

   ```rust
   ViewReduceLoop::load(igapp, view_entry, reduce_entry)
     .render(state_json) -> Element JSON
     .reduce(state_json, key_json) -> State JSON
   ```

4. How does the adapter preserve frame-ui’s current dependency boundaries:
   - `--no-default-features` stays machine-free,
   - wasm stays machine-free,
   - no server/host IO sneaks into frame core?
5. Does the adapter need real `igc run`/passport flow, or can it use the existing VM library load/dispatch path?
6. What are the failure envelopes: compile/load error, malformed input, VM runtime error, unsupported entry?
7. What is the smallest implementation card after this readiness packet?

## Constraints

- Readiness/design only. Do not implement the adapter in this card.
- Do not change `.ig` syntax, form vocabulary, `.igv`, `.ig.html`, or bridge semantics.
- Do not collapse command-produced fixture tests; they remain useful even if an in-process adapter is added.
- Do not add dependencies or touch `Cargo.lock`.
- Keep public claims scoped: this is frame-ui DX, not a canonical app runner.

## Acceptance

- [ ] Packet identifies the exact current subprocess/fixture boundary and what it buys us.
- [ ] Packet compares at least three options:
      `subprocess stays`, `optional igniter_vm adapter`, `optional igniter_machine adapter`.
- [ ] Packet names the recommended feature boundary (`machine`, `vm-loop`, or other) with dependency proof.
- [ ] Packet lists a minimal API shape and failure taxonomy.
- [ ] Packet states whether wasm/no-default builds remain unchanged.
- [ ] Packet gives one named implementation card if proceeding.
- [ ] No production code changes.
- [ ] `git diff --check` is clean.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab

cargo test --manifest-path frame-ui/igniter-frame/Cargo.toml --no-default-features
cargo test --manifest-path frame-ui/igniter-frame/Cargo.toml --no-default-features --features wasm
cargo test --manifest-path frame-ui/igniter-frame/Cargo.toml
git diff --check
```

If a command does not apply to live Cargo features, document the real command and why.

## Required Packet

Create:

```text
lab-docs/lang/lab-frame-view-inprocess-vm-loop-readiness-p8-v0.md
```

Packet must include:

- live dependency map,
- option comparison,
- recommended next slice,
- acceptance matrix for the implementation card,
- explicit “do not break machine-free core” statement.

