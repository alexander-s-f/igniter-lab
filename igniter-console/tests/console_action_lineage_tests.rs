//! LAB-FRAME-CONSOLE-ACTION-LINEAGE-P19 — the console displays host action/receipt lineage next to
//! frames, as plain data, time-traveled per frame. Imports only `igniter_console` (+ ui-kit/frame,
//! machine-free). No machine handle.

use igniter_console::{Console, HostActionRecord};
use serde_json::Value;

const JSON: &str = include_str!("../web/lead_review.view.json");

fn rec() -> HostActionRecord {
    HostActionRecord {
        action_id: "act-1".into(),
        action_name: "submit_lead".into(),
        contract: "SubmitLeadReview".into(),
        pool_id: Some("svc".into()),
        invoke_digest: Some("sha256:deadbeefcafef00d".into()),
        effect_receipt_id: Some("IO.FrameFixture:idem-1".into()),
        effect_state: Some("committed".into()),
        idempotency_key: Some("idem-1".into()),
        correlation_id: Some("corr-1".into()),
    }
}

// viewer box (28,120,576,352) over a 720×440 target → map target→console for an interaction.
fn viewer(c: &mut Console, tx: f64, ty: f64) {
    c.click(28.0 + tx / 720.0 * 576.0, 120.0 + ty / 440.0 * 352.0);
}

#[test]
fn frame_carries_host_action_in_lineage_json() {
    let mut c = Console::from_artifact(JSON).unwrap();
    viewer(&mut c, 106.0, 105.0); // record a frame (select Grace)
    assert!(c.attach_action(rec()));
    let lin: Value = serde_json::from_str(&c.lineage_json()).unwrap();
    assert_eq!(lin["host_action"]["action_name"], "submit_lead");
    assert_eq!(lin["host_action"]["contract"], "SubmitLeadReview");
    assert_eq!(lin["host_action"]["effect_receipt_id"], "IO.FrameFixture:idem-1");
    assert_eq!(lin["host_action"]["effect_state"], "committed");
}

#[test]
fn render_panel_shows_action_and_receipt_line() {
    let mut c = Console::from_artifact(JSON).unwrap();
    viewer(&mut c, 106.0, 105.0);
    c.attach_action(rec());
    let svg = c.render_svg();
    assert!(svg.contains("action: submit_lead"), "action name shown");
    assert!(svg.contains("receipt: committed"), "receipt state shown");
}

#[test]
fn time_travel_shows_selected_frames_own_action() {
    let mut c = Console::from_artifact(JSON).unwrap();
    viewer(&mut c, 106.0, 105.0); // step 1 (Grace)
    c.attach_action(rec());
    let action_step = c.selected();

    c.select_step(0); // scrub to the initial frame (no action)
    let lin0: Value = serde_json::from_str(&c.lineage_json()).unwrap();
    assert!(lin0.get("host_action").is_none(), "initial frame has no host action");
    assert!(!c.render_svg().contains("action: submit_lead"));

    c.select_step(action_step); // back to the action frame
    let lin1: Value = serde_json::from_str(&c.lineage_json()).unwrap();
    assert_eq!(lin1["host_action"]["action_name"], "submit_lead");
}

#[test]
fn frames_without_action_preserve_existing_lineage() {
    let c = Console::from_artifact(JSON).unwrap(); // init frame, no action
    let lin: Value = serde_json::from_str(&c.lineage_json()).unwrap();
    assert!(lin.get("host_action").is_none());
    assert_eq!(lin["step"], 0);
    assert!(c.render_svg().contains("frame viewer"));
}

#[test]
fn long_ids_are_shortened_in_the_svg_but_full_in_json() {
    let mut c = Console::from_artifact(JSON).unwrap();
    viewer(&mut c, 106.0, 105.0);
    let mut r = rec();
    r.effect_receipt_id = Some("IO.FrameFixture:idem-very-long-correlation-key-1234567890".into());
    c.attach_action(r);
    let svg = c.render_svg();
    assert!(svg.contains("…"), "long id shortened in the SVG");
    assert!(!svg.contains("1234567890"), "the full long id is not rendered raw");
    assert!(c.lineage_json().contains("1234567890"), "raw JSON keeps the full id");
}

#[test]
fn from_json_attaches_action() {
    let mut c = Console::from_artifact(JSON).unwrap();
    viewer(&mut c, 106.0, 105.0);
    assert!(c.attach_action_json(r#"{"action_name":"submit_lead","contract":"SubmitLeadReview","effect_state":"committed","effect_receipt_id":"IO.FrameFixture:idem-9"}"#));
    assert!(c.render_svg().contains("action: submit_lead"));
}

#[test]
fn existing_console_surfaces_intact() {
    let mut c = Console::from_artifact(JSON).unwrap();
    viewer(&mut c, 106.0, 105.0);
    c.attach_action(rec());
    let svg = c.render_svg();
    for needle in ["replay", "frame viewer", "lineage", "frame diff", "Lead \u{b7} Grace"] {
        assert!(svg.contains(needle), "missing: {needle}");
    }
    // the visual diff overlay still works (selected > 0)
    assert!(!c.diff_overlay().is_empty());
}
