//! LAB-FRAME-VIEW-IGC-RUN-ELEMENT-EXTRACTION-P3 — the mirror is removed.
//!
//! This test consumes the REAL runtime output of `list_view_inline.ig` (produced by `igniter-vm run`,
//! NOT a hand-written mirror) and feeds it through the frame-ui bridge. The fixture is the full runtime
//! envelope `{ latency_us, observations, result, status }`; the extraction rule is `.result` (the
//! Element tree). See `lab-docs/lang/lab-frame-view-igc-run-element-extraction-p3-v0.md` for how the
//! fixture was generated (igc compile → igniter-vm run, since `igc run` is passport-gated).

use igniter_frame::ig_bridge::render_ig_view;
use serde_json::Value;

/// The exact igniter-vm run envelope, captured to a checked-in fixture (not authored by hand).
const RUNTIME_ENVELOPE: &str = include_str!("fixtures/list_view_inline.runtime.json");

#[test]
fn runtime_produced_element_tree_renders_through_the_bridge() {
    let env: Value = serde_json::from_str(RUNTIME_ENVELOPE).expect("fixture is valid JSON");
    // the runtime succeeded and wraps the Element tree under `.result`
    assert_eq!(env["status"], "success", "runtime envelope status");
    let element = env.get("result").expect("runtime envelope carries `.result`");
    assert_eq!(element["tag"], "row", "top-level Element is the screen row");

    // feed the RUNTIME-produced Element tree (not a mirror) through the bridge
    let svg = render_ig_view(&element.to_string(), 720, 440);
    assert!(svg.starts_with("<svg"));

    // every authored lead label + the action buttons survive runtime → bridge → SVG
    for needle in ["Review Ada's lead", "Call Grace back", "Send Linus the quote", "+ add item", "mark done"] {
        assert!(svg.contains(needle), "rendered SVG missing {needle:?}");
    }
    // the buttons routed through the canonical button widget (rounded rect)
    assert!(svg.contains("rx=\"8\""), "expected a button rect in the rendered output");
}

#[test]
fn runtime_result_matches_the_demo_fixture() {
    // the live demo fixture (web/list_view.element.json) IS the extracted runtime `.result` — no mirror
    let env: Value = serde_json::from_str(RUNTIME_ENVELOPE).unwrap();
    let demo: Value = serde_json::from_str(include_str!("../web/list_view.element.json")).unwrap();
    assert_eq!(env["result"], demo, "demo fixture must equal the runtime .result (mirror removed)");
}
