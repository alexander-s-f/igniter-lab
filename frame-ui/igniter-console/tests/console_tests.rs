//! LAB-FRAME-APP-CONSOLE-P13 — the console wraps a ViewArtifact-authored workbench with a replay
//! strip, frame viewer, lineage inspector, and frame diff over the recorded history. Imports only
//! `igniter_console` (+ `igniter_ui_kit`/`igniter_frame`, machine-free).

use igniter_console::Console;

const JSON: &str = include_str!("../web/lead_review.view.json");

// viewer box in console coords is (28,120,576,352) over a 720×440 target → map target→console.
fn viewer_click(c: &mut Console, tx: f64, ty: f64) -> bool {
    c.click(28.0 + tx / 720.0 * 576.0, 120.0 + ty / 440.0 * 352.0)
}
// strip chip i centre (chip_rect: x=24+i*64, y=22, w=56, h=38)
fn chip_click(c: &mut Console, i: usize) -> bool {
    c.click((24 + i as i64 * 64 + 28) as f64, 41.0)
}

#[test]
fn console_builds_the_ide_shell_around_the_artifact() {
    let c = Console::from_artifact(JSON).expect("artifact compiles");
    assert_eq!(c.len(), 1, "initial frame recorded");
    assert_eq!(c.selected(), 0);
    let svg = c.render_svg();
    for needle in ["replay", "frame viewer", "lineage", "frame diff", "Lead \u{b7} Ada"] {
        assert!(svg.contains(needle), "console shell missing: {needle}");
    }
}

#[test]
fn viewer_click_forwards_to_target_and_records_a_frame() {
    let mut c = Console::from_artifact(JSON).unwrap();
    assert!(viewer_click(&mut c, 106.0, 105.0), "click in viewer forwards (select Grace)");
    assert_eq!(c.len(), 2, "a new frame was recorded");
    assert_eq!(c.selected(), 1, "selection follows the live frame");
    assert!(c.is_live());
    assert!(c.render_svg().contains("Lead \u{b7} Grace"), "the embedded target frame followed selection");
}

#[test]
fn replay_strip_scrubs_history_without_mutating_target() {
    let mut c = Console::from_artifact(JSON).unwrap();
    viewer_click(&mut c, 106.0, 105.0); // select Grace (step 1)
    assert_eq!(c.len(), 2);
    assert!(chip_click(&mut c, 0), "clicking the first chip scrubs back");
    assert_eq!(c.selected(), 0, "time-travelled to the initial frame");
    assert!(!c.is_live());
    assert_eq!(c.len(), 2, "scrubbing did not record or mutate");
    assert!(c.render_svg().contains("Lead \u{b7} Ada"), "viewer shows the historical frame");
}

#[test]
fn frame_diff_reports_node_level_changes() {
    let mut c = Console::from_artifact(JSON).unwrap();
    viewer_click(&mut c, 106.0, 105.0); // Ada → Grace : main fields swap, panels/list/inspector change
    let diff = c.diff_json();
    assert!(diff.contains("fld:Grace:priority") && diff.contains("\"added\""), "Grace's fields appear");
    assert!(diff.contains("fld:Ada:priority") && diff.contains("\"removed\""), "Ada's fields leave");
    assert!(diff.contains("panel:main") && diff.contains("\"changed\""), "the main panel title changed");
}

#[test]
fn lineage_inspector_reflects_the_selected_step() {
    let mut c = Console::from_artifact(JSON).unwrap();
    viewer_click(&mut c, 106.0, 105.0); // select Grace → an effect
    let live: serde_json::Value = serde_json::from_str(&c.lineage_json()).unwrap();
    assert_eq!(live["effect_receipt_id"], "effect:0");
    assert_eq!(live["frame_index"], 1);

    c.select_step(0); // scrub to the initial frame
    let init: serde_json::Value = serde_json::from_str(&c.lineage_json()).unwrap();
    assert!(init["effect_receipt_id"].is_null(), "the initial frame has no effect");
    assert_eq!(init["step"], 0);
}

#[test]
fn typing_forwards_through_the_console_to_the_reducer() {
    let mut c = Console::from_artifact(JSON).unwrap();
    viewer_click(&mut c, 344.0, 70.0); // focus Ada priority
    c.key("h");
    c.key("i");
    assert!(c.is_live());
    assert!(c.render_svg().contains("hi"), "keystrokes routed to the target field (reducer owns it)");
    // a frame was recorded per accepted keystroke (focus + 2 keys → 3 events past init)
    assert!(c.len() >= 3);
}

#[test]
fn initial_frame_has_no_diff() {
    let c = Console::from_artifact(JSON).unwrap();
    assert_eq!(c.diff_json(), "[]");
    assert!(c.render_svg().contains("(initial frame)"));
}
