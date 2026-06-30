# LAB-FRAME-VIEW-EQ-WORKAROUND-REMOVAL-P7

Date: 2026-06-28
Status: DONE
Route: standard / igniter-lab / frame-ui / igniter-frame / interaction / payoff
Depends-On: `LAB-VM-PRIMITIVE-EQ-PARITY-P1`

Lab evidence. frame-ui scope. No new view syntax, no `.igv`/`.ig.html`, no parser/form-vocabulary
change, no host-render redesign. The equality runtime is NOT re-implemented here (P1 owns it);
this card consumes it. `frame-ui/igniter-frame/Cargo.lock` not staged (no dependency change).

## Dependency evidence from P1

`LAB-VM-PRIMITIVE-EQ-PARITY-P1` proved the VM executes `==` (`stdlib.primitive.eq`) for
String/Text, Integer, and Bool through compile → VM run, with mismatched scalars rejected at
compile time. That removed the only blocker the frame-ui workarounds cited. Verified still green
this card: `primitive_eq_parity_tests` 6/6; machine fleet sweep 13/13.

## Exact workaround removed (Q1)

The selected-state workaround lived in **two** places, both because `==` was assumed unavailable
in the VM:

1. **Authored `.ig` specimen** `lab-docs/lang/specimens/dx-view-d/vm_loop_app.ig` — carried an
   explicit NOTE: *"igniter-vm does NOT implement `stdlib.primitive.eq` … So this app avoids
   equality: the re-projected view reflects new state by echoing `state.sel` into a status leaf's
   TEXT … Once `eq` lands, the view can mark the selected row directly."* I.e. a **status-text echo
   stand-in** instead of per-row selection.
2. **Rust test projector** `frame-ui/igniter-frame/tests/ig_reducer_interaction_tests.rs` — the
   `IgViewProjector` decided selection in **host code**:
   ```rust
   let sel = world.iter().find(|(k,_)| k == "__sel__")…;
   for n in &mut f.nodes { if n.id == sel { n.data["selected"] = json!(true); } }  // host-side eq
   ```

Both are removed.

## Authored equality (Q2) — selection computed in `.ig`

`vm_loop_app.ig` now authors per-row selection with real equality over stable domain keys. The
`Element` type gained a `selected : Bool` field; the `View` computes it via `==`:

```ig
type State { sel : String }
type Element { tag : String  attrs : Attrs  text : String  intent : String  key : String  selected : Bool  children : Collection[Element] }

contract Leaf {
  input attrs : Attrs  input text : String  input intent : String  input key : String  input selected : Bool
  compute el = { tag: "leaf", attrs: attrs, text: text, intent: intent, key: key, selected: selected, children: [] }
  output el : Element
}

contract View {
  input state : State
  compute sel0 = "lead:0" == state.sel
  compute sel1 = "lead:1" == state.sel
  compute sel2 = "lead:2" == state.sel
  compute n0 = call_contract("Leaf", a_row, "Review Ada's lead",   "select", "lead:0", sel0)
  compute n1 = call_contract("Leaf", a_row, "Call Grace back",     "select", "lead:1", sel1)
  compute n2 = call_contract("Leaf", a_row, "Send Linus the quote","select", "lead:2", sel2)
  compute screen = call_contract("Col", a_side, [n0, n1, n2])
  output screen : Element
}
```

The bridge change is **structural rendering only** (`ig_bridge.rs`): `ElInfo` gained `selected`
(read from the Element JSON, default `false`), and `node_for`'s interactive-leaf arm renders
`"selected": i.selected` instead of a hardcoded `false`. The bridge **renders** the authored flag;
it never decides selection (Q4). `widget_host` already styles a selected row distinctly, so the
authored flag is visible in the rendered SVG.

## Runtime / render evidence (Q3)

VM-executed authored equality (real `igniter-vm` run of the updated specimen):

| View input | per-row `selected` (lead:0, lead:1, lead:2) |
| --- | --- |
| `state.sel = ""` | `false, false, false` |
| `state.sel = "lead:1"` | `false, true, false` |

The runtime-produced `Element` JSON preserves selected state through click → reducer → rerender:
the `ig_vm_loop_tests` loop proves a click on "Call Grace back" carries the authored domain key
`"lead:1"`, the `.ig` `Reduce` (on the VM) sets `sel = "lead:1"`, and the `.ig` `View` re-run on the
new state marks exactly that row `selected` (others stay `false`) — projected through the bridge.

## Remaining host-side special casing (Q4)

None in the `.ig` view path. `ig_reducer_interaction_tests` no longer marks selection in Rust; its
projector only re-projects, and the test now proves the input → effect → next-frame loop mechanics
(intent survives, `derive_intent`, lineage, frame advance), pointing to `ig_vm_loop_tests` for the
authored-selection proof. The only `… == sel` left in frame-ui is in the **hand-written Rust demo
screens** (`table_screen.rs`, `form_screen.rs`) — those are not `.ig`-authored views and were never
the VM-eq workaround; out of scope here.

## Fixtures (command-produced)

`tests/fixtures/vm_loop_{view0,view1,reduce}.runtime.json` regenerated from the updated specimen.
Documented command (also in the `ig_vm_loop_tests` header):

```text
igc compile lab-docs/lang/specimens/dx-view-d/vm_loop_app.ig --out /tmp/vmloop.igapp
igniter-vm run --contract /tmp/vmloop.igapp --entry View   --inputs '{"state":{"sel":""}}'                  --json  # view0
igniter-vm run --contract /tmp/vmloop.igapp --entry View   --inputs '{"state":{"sel":"lead:1"}}'            --json  # view1
igniter-vm run --contract /tmp/vmloop.igapp --entry Reduce --inputs '{"state":{"sel":""},"key":"lead:1"}'   --json  # reduce
```

`latency_us` is normalized to `0` in the checked-in envelopes so the command reproduces them
byte-for-byte. The live orchestration `examples/vm_loop.rs` self-checks the same transition and now
asserts authored per-row selection instead of the status-text echo.

## Verification commands and results

```text
cargo test --manifest-path lang/igniter-vm/Cargo.toml --test primitive_eq_parity_tests        # 6/6 (P1 green)
cargo test --manifest-path frame-ui/igniter-frame/Cargo.toml --test ig_vm_loop_tests          # 1/1 (authored selection)
cargo test --manifest-path frame-ui/igniter-frame/Cargo.toml --test ig_reducer_interaction_tests # 4/4 (no host eq)
cargo test --manifest-path frame-ui/igniter-frame/Cargo.toml --test ig_runtime_bridge_tests   # 5/5
cargo test --manifest-path frame-ui/igniter-frame/Cargo.toml                                   # 79/0 (full suite)
cargo test --manifest-path runtime/igniter-machine/Cargo.toml --test machine_tests test_machine_fleet_sweep  # 13/13
git diff --check                                                                               # PASS
```

## Remaining frame-ui blockers

- None for authored selected-state. The `.ig` view+logic loop now uses real equality end-to-end.
- The live per-frame VM-in-the-loop projector remains an `examples/vm_loop.rs` (subprocess
  `igniter-vm`) + command-produced fixtures shape, keeping the frame-ui **library** machine-free; a
  first-class in-process VM-loop projector behind the optional `machine` feature is a possible future
  DX slice (not required for this payoff).
