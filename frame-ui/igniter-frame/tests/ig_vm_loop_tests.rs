//! LAB-FRAME-VIEW-IG-VM-IN-THE-LOOP-P6 — deterministic proof over command-produced fixtures.
//!
//! The fixtures are real `igniter-vm` runtime envelopes of the `vm_loop_app.ig` contracts:
//! `vm_loop_view0` = View(sel=""), `vm_loop_reduce` = Reduce(state, key="lead:1"), `vm_loop_view1` =
//! View(sel="lead:1"). They reconstruct the full loop: a click on the VIEW's lead carries the authored
//! domain `key`, the `.ig` REDUCER (run on the VM) consumes it, and the `.ig` VIEW re-run on the new
//! state reflects it. (The live orchestration is `examples/vm_loop.rs`.)

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

fn status_text(element: &Value) -> String {
    element["children"].as_array().and_then(|a| a.last()).and_then(|n| n["text"].as_str()).unwrap_or("").to_string()
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
        &InputEvent { kind: "click".into(), x: lead.sx + 6, y: lead.sy + 6, payload: Value::Null },
    )
    .expect("click derives an intent");
    assert_eq!(intent.action, "select");
    assert_eq!(intent.params.get("key").and_then(|v| v.as_str()), Some("lead:1"), "the authored domain key reached the host");

    // 2) the `.ig` REDUCER (run on the VM) consumed that key → new state -----------------------------
    assert_eq!(result(REDUCE)["sel"], "lead:1", ".ig reducer set sel = clicked key");

    // 3) the `.ig` VIEW re-run on the new state reflects it (re-projection, not mutation) ------------
    let v1 = result(VIEW1);
    assert_eq!(status_text(&v0), "", "frame 0 had no selection");
    assert_eq!(status_text(&v1), "lead:1", "re-projected frame echoes the VM-reduced state");

    // 4) both frames render through the bridge; the new selection is visible -------------------------
    assert!(render_ig_view(&v0.to_string(), 720, 440).starts_with("<svg"));
    let svg1 = render_ig_view(&v1.to_string(), 720, 440);
    assert!(svg1.contains("lead:1"), "re-projected view shows the new selection");
    for needle in ["Review Ada's lead", "Call Grace back", "Send Linus the quote"] {
        assert!(svg1.contains(needle), "lead {needle:?} renders");
    }
}
