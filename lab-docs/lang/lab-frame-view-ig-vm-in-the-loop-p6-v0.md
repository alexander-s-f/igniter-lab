# LAB-FRAME-VIEW-IG-VM-IN-THE-LOOP-P6 — proof packet

Status: CLOSED — the FULL Igniter view+logic loop runs end-to-end: both the VIEW and the REDUCER are
`.ig` contracts on `igniter-vm`; frame-ui only hit-tests the click and threads JSON. One VM parity gap
(`==`/`eq`) found and worked around; routed to the VM owners.
Lane: igniter-lab / frame-ui / Igniter view+logic on the VM
Date: 2026-06-27
Builds on: P5 (frame-ui-reducer loop) — this closes its "remaining gap" (VM-in-the-loop).

## Result

```text
View(state)  --igniter-vm-->  Element  --frame-ui hit_test/derive_intent-->  (action, key)
  --igniter-vm Reduce(state,key)-->  state'  --igniter-vm View(state')-->  Element'   (re-projection)
```

A click on an Igniter-authored view is hit-tested by frame-ui; the authored intent carries a DOMAIN
`key`; the `.ig` REDUCER `(State, key) -> State` runs on the VM to produce new state; the `.ig` VIEW
`(State) -> Element` RE-RUNS on the VM; the re-projection reflects the VM-reduced state. The logic and
the view are both `.ig`; the host does no domain logic.

## The app — `specimens/dx-view-d/vm_loop_app.ig` (compiles `ok`)

- `type State { sel: String }`
- `contract View(state) -> Element` — three clickable lead leaves (each carries `intent:"select"` +
  `key:"lead:N"`) plus a STATUS leaf whose text echoes `state.sel`.
- `contract Reduce(state, key) -> State` — `next = { sel: key }`.

## Live orchestration — `examples/vm_loop.rs` (frame-ui is the host)

```bash
cargo build --release --manifest-path lang/igniter-vm/Cargo.toml          # the lab VM
ruby -I …/igniter-lang/lib …/bin/igc compile …/vm_loop_app.ig --out /tmp/vm_loop_app.igapp   # ok
cargo run --no-default-features --example vm_loop -- /tmp/vm_loop_app.igapp \
  lang/igniter-vm/target/release/igniter-vm
```

Output (self-checked — the example panics on any mismatch):

```text
frame 0  ·  View(sel="")  ·  status leaf text = ""
click (18,66)  ·  derive_intent -> action="select" key="lead:1"
Reduce(state, key)  ·  VM  ·  state' = {"sel":"lead:1"}
frame 1  ·  View(sel="lead:1")  ·  status leaf text = "lead:1"
OK — full .ig view+logic loop: click -> .ig Reduce (VM) -> .ig View (VM) -> re-projection.
```

## Bridge change (frame-ui)

`ig_bridge.rs`: `Element.key` now flows onto the node's intent (`{action, key}`), so a click on a
`.ig`-authored node carries the DOMAIN key the `.ig` reducer needs — `ElInfo.key`, read in
`element_to_layout`, emitted by `node_for`. Backward-compatible (fixtures without `key` → `""`); the
P2–P5 tests stay green.

## Deterministic proof — `tests/ig_vm_loop_tests.rs` (over command-produced fixtures)

`tests/fixtures/vm_loop_{view0,reduce,view1}.runtime.json` are real `igniter-vm` envelopes
(`View(sel="")`, `Reduce(state, key="lead:1")`, `View(sel="lead:1")`). The test reconstructs the loop:
the click on `Call Grace back` derives `{action:"select", key:"lead:1"}`; the reducer envelope's
`.result.sel == "lead:1"`; the re-run view's status leaf goes `"" → "lead:1"`; both frames render and
the new selection is visible. **`cargo test` (frame-ui): 79 passed / 0 failed.** `git diff --check`
clean. No canon/compiler/VM source change; no Cargo.lock change.

## VM parity gap found (routed to VM owners)

`igniter-vm` does NOT implement `stdlib.primitive.eq` (`==` on Integer OR String) — the compiler
accepts `==` and `<` runs, but `==` errors at runtime:

```text
VM evaluation failed: OP_CALL: Unknown/unimplemented function 'stdlib.primitive.eq' with 2 arguments
```

(Probe: `IntLt` = success; `IntEq` / `StrEq` = the error above.) This is a compiler↔VM parity gap, like
the `map` gap fixed earlier. WORKAROUND used here so P6 still closes: the view echoes `state.sel` into a
status leaf's TEXT (state-dependent render with no `==`) instead of marking the selected row, and the
reducer assigns `sel = key` (action routing stays in the host). Once `eq` lands, the view can mark the
selected row directly and the reducer can branch on `action`.

**Suggested next card:** `LAB-VM-PRIMITIVE-EQ-PARITY-Pn` — implement `stdlib.primitive.eq` in
`igniter-vm` (Integer + String), mirroring the `map`-parity fix, so `.ig` views/reducers can use `==`.

## Files

- `lab-docs/lang/specimens/dx-view-d/vm_loop_app.ig`
- `frame-ui/igniter-frame/src/ig_bridge.rs` (Element `key` support)
- `frame-ui/igniter-frame/examples/vm_loop.rs` (live host orchestrator)
- `frame-ui/igniter-frame/tests/fixtures/vm_loop_{view0,view1,reduce}.runtime.json`
- `frame-ui/igniter-frame/tests/ig_vm_loop_tests.rs`
