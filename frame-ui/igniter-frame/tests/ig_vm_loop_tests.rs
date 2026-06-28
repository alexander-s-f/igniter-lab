//! LAB-FRAME-VIEW-IG-VM-IN-THE-LOOP-P6 + LAB-FRAME-VIEW-EQ-WORKAROUND-REMOVAL-P7 — deterministic
//! proof over command-produced fixtures.
//!
//! The fixtures are real `igniter-vm` runtime envelopes of the `vm_loop_app.ig` contracts:
//! `vm_loop_view0` = View(sel=""), `vm_loop_reduce` = Reduce(state, key="lead:1"), `vm_loop_view1` =
//! View(sel="lead:1"). They reconstruct the full loop: a click on the VIEW's lead carries the authored
//! domain `key`, the `.ig` REDUCER (run on the VM) consumes it, and the `.ig` VIEW re-run on the new
//! state reflects it. (The live orchestration is `examples/vm_loop.rs`.)
//!
//! P7: selection is now authored with REAL `.ig` equality. The view computes each row's
//! `selected = (row_key == state.sel)` on the VM (proven by `LAB-VM-PRIMITIVE-EQ-PARITY-P1`), so the
//! re-projected frame marks the SELECTED ROW directly — replacing the P6 status-text echo stand-in.
//! No host-side `n.id == sel`: the bridge only renders the authored `selected`.
//!
//! Regenerate the fixtures (the documented command) after editing the specimen:
//! ```text
//! igc compile lab-docs/lang/specimens/dx-view-d/vm_loop_app.ig --out /tmp/vmloop.igapp
//! igniter-vm run --contract /tmp/vmloop.igapp --entry View   --inputs '{"state":{"sel":""}}'        --json  # view0
//! igniter-vm run --contract /tmp/vmloop.igapp --entry View   --inputs '{"state":{"sel":"lead:1"}}'  --json  # view1
//! igniter-vm run --contract /tmp/vmloop.igapp --entry Reduce --inputs '{"state":{"sel":""},"key":"lead:1"}' --json  # reduce
//! ```
//! (`latency_us` is normalized to 0 in the checked-in envelopes so the command reproduces them.)

use igniter_frame::ig_bridge::{project_ig_element, render_ig_view};
use igniter_frame::{derive_intent, InputEvent};
use serde_json::Value;

const VIEW0: &str = include_str!("fixtures/vm_loop_view0.runtime.json");
const VIEW1: &str = include_str!("fixtures/vm_loop_view1.runtime.json");
const REDUCE: &str = include_str!("fixtures/vm_loop_reduce.runtime.json");

fn result(envelope: &str) -> Value {
    let env: Value = serde_json::from_str(envelope).unwrap();
    assert_eq!(env["status"], "success");
    env["result"].clone()
}

/// The bridge-projected `selected` flag for the row whose label is `label`.
fn row_selected(view: &Value, label: &str) -> bool {
    let frame = project_ig_element(&view.to_string(), 720, 440);
    frame
        .nodes
        .iter()
        .find(|n| n.data.get("label").and_then(|x| x.as_str()) == Some(label))
        .unwrap_or_else(|| panic!("row {label:?} not found"))
        .data
        .get("selected")
        .and_then(|v| v.as_bool())
        .unwrap_or(false)
}

#[test]
fn vm_loop_click_carries_key_reducer_runs_and_view_reprojects() {
    // 1) the `.ig` VIEW's output: a click on the 2nd lead carries the AUTHORED domain key ----------
    let v0 = result(VIEW0);
    let frame = project_ig_element(&v0.to_string(), 720, 440);
    let lead = frame
        .nodes
        .iter()
        .find(|n| n.data.get("label").and_then(|x| x.as_str()) == Some("Call Grace back"))
        .expect("the 2nd lead node");
    let intent = derive_intent(
        &frame,
        &InputEvent {
            kind: "click".into(),
            x: lead.sx + 6,
            y: lead.sy + 6,
            payload: Value::Null,
        },
    )
    .expect("click derives an intent");
    assert_eq!(intent.action, "select");
    assert_eq!(
        intent.params.get("key").and_then(|v| v.as_str()),
        Some("lead:1"),
        "the authored domain key reached the host"
    );

    // 2) the `.ig` REDUCER (run on the VM) consumed that key → new state -----------------------------
    assert_eq!(
        result(REDUCE)["sel"],
        "lead:1",
        ".ig reducer set sel = clicked key"
    );

    // 3) the `.ig` VIEW re-run on the new state reflects it via AUTHORED equality (P7): the clicked
    //    row is now `selected`, the others are not — re-projection, not mutation, and no host eq. -----
    let v1 = result(VIEW1);
    for label in [
        "Review Ada's lead",
        "Call Grace back",
        "Send Linus the quote",
    ] {
        assert!(
            !row_selected(&v0, label),
            "frame 0 has no selected row ({label:?})"
        );
    }
    assert!(
        row_selected(&v1, "Call Grace back"),
        "the clicked row is selected after re-projection"
    );
    assert!(
        !row_selected(&v1, "Review Ada's lead"),
        "an unclicked row stays unselected"
    );
    assert!(
        !row_selected(&v1, "Send Linus the quote"),
        "an unclicked row stays unselected"
    );

    // 4) both frames render through the bridge; the leads survive and the selection is visible -------
    assert!(render_ig_view(&v0.to_string(), 720, 440).starts_with("<svg"));
    let svg1 = render_ig_view(&v1.to_string(), 720, 440);
    for needle in [
        "Review Ada's lead",
        "Call Grace back",
        "Send Linus the quote",
    ] {
        assert!(svg1.contains(needle), "lead {needle:?} renders");
    }
}
