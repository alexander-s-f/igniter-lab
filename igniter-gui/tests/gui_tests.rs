//! LAB-FRAME-GUI-ENGINE-REHOME-P8 — the GUI reactive loop over igniter-frame: layout → box
//! hit-test → intent → update reducer → re-layout, deterministic + replayable. Imports only
//! `igniter_gui` (+ `igniter_frame`, machine-free) → no machine.

use igniter_gui::GuiRuntime;

// Layout: box i at sx=20, sy=20+i*52, w=360, h=44 → centre (200, 42+i*52).
// order: ctrl_add(0), task_1(1), task_2(2), counter(3).
const ADD: (f64, f64) = (200.0, 42.0);
const TASK_1: (f64, f64) = (200.0, 94.0);
const TASK_2: (f64, f64) = (200.0, 146.0);
const COUNTER: (f64, f64) = (200.0, 198.0);

#[test]
fn layout_renders_widgets_as_boxes() {
    let rt = GuiRuntime::new();
    let svg = rt.render_svg();
    assert_eq!(svg.matches("<rect").count(), 5, "background + 4 widget boxes");
    assert!(svg.contains("+ add task"));
    assert!(svg.contains("[ ] task 1"));
    assert!(svg.contains("0 / 2 done"));
}

#[test]
fn click_toggle_marks_done_and_updates_counter() {
    let mut rt = GuiRuntime::new();
    assert!(rt.click(TASK_1.0, TASK_1.1), "clicking a row fires its toggle intent");
    assert_eq!(rt.frame_index(), 1);
    let svg = rt.render_svg();
    assert!(svg.contains("[x] task 1"), "row is now done");
    assert!(svg.contains("[ ] task 2"), "the other row is untouched");
    assert!(svg.contains("1 / 2 done"), "counter recomputed by the reducer");
}

#[test]
fn click_add_appends_row_and_relayouts() {
    let mut rt = GuiRuntime::new();
    assert!(rt.click(ADD.0, ADD.1), "the add button fires");
    let svg = rt.render_svg();
    assert_eq!(svg.matches("<rect").count(), 6, "a new widget box appeared (re-layout)");
    assert!(svg.contains("[ ] task 3"), "a new row was appended");
    assert!(svg.contains("0 / 3 done"), "counter reflects the new total");
}

#[test]
fn display_widget_has_no_intent() {
    let mut rt = GuiRuntime::new();
    let before = rt.render_digest();
    assert!(!rt.click(COUNTER.0, COUNTER.1), "the counter display is hit but has no on_click");
    assert_eq!(rt.frame_index(), 0, "no effect, no advance");
    assert_eq!(rt.render_digest(), before);
}

#[test]
fn hit_test_uses_box_not_radius() {
    // A point inside the add-button rect (20..380 × 20..64) but ~160px from its centre: a radius
    // hit-test would MISS; the box hit-test hits. Proves the box-aware path.
    let mut rt = GuiRuntime::new();
    assert!(rt.click(40.0, 30.0), "a click in the box corner still hits the widget");
    assert!(rt.render_svg().contains("[ ] task 3"), "the add intent fired");
}

#[test]
fn deterministic_replay_of_ui_event_log() {
    let log = [TASK_1, ADD, TASK_2, ADD, TASK_1];
    let run = || {
        let mut rt = GuiRuntime::new();
        let mut svgs = vec![rt.render_svg()];
        for (x, y) in log {
            rt.click(x, y);
            svgs.push(rt.render_svg());
        }
        svgs
    };
    let a = run();
    let b = run();
    assert_eq!(a, b, "same start + same UI event log → identical rendered frames");
    assert_eq!(a.len(), log.len() + 1);
    // the log genuinely changed the UI
    assert_ne!(a.first().unwrap(), a.last().unwrap());
}

#[test]
fn lineage_uses_the_same_runtime_discipline() {
    let mut rt = GuiRuntime::new();
    rt.click(TASK_1.0, TASK_1.1);
    let lineage: serde_json::Value = serde_json::from_str(&rt.lineage_json()).unwrap();
    assert_eq!(lineage["input_receipt_id"], "input:0");
    assert_eq!(lineage["effect_receipt_id"], "effect:0");
    assert_eq!(lineage["frame_index"], 1);
}

#[test]
fn reset_returns_to_initial_ui() {
    let mut rt = GuiRuntime::new();
    let initial = rt.render_digest();
    rt.click(TASK_1.0, TASK_1.1);
    rt.click(ADD.0, ADD.1);
    assert_ne!(rt.render_digest(), initial);
    rt.reset();
    assert_eq!(rt.render_digest(), initial);
    assert_eq!(rt.frame_index(), 0);
}
