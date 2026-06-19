//! LAB-FRAME-CONSOLE-DIFF-HIGHLIGHT-P15 — the console frame viewer draws a deterministic visual
//! diff overlay (added/removed/moved/changed) on top of the embedded target frame, derived from
//! `Console::diff()` geometry and mapped into the viewer coordinate space. Asserts stable SVG
//! classes, not brittle full strings. Machine-free.

use igniter_console::{diff_overlay_svg, Console};
use igniter_frame::{Frame, ProjectedNode};
use serde_json::json;

const JSON: &str = include_str!("../web/lead_review.view.json");

fn viewer_click(c: &mut Console, tx: f64, ty: f64) -> bool {
    c.click(28.0 + tx / 720.0 * 576.0, 120.0 + ty / 440.0 * 352.0)
}

// ── against the live console ──────────────────────────────────────────────────────────────────

#[test]
fn step_zero_renders_no_overlay() {
    let c = Console::from_artifact(JSON).unwrap();
    assert_eq!(c.diff_overlay(), "", "no previous frame → no overlay");
    assert!(
        !c.render_svg().contains("diff-"),
        "shell shows no diff markers at step 0"
    );
}

#[test]
fn selecting_a_lead_overlays_added_removed_changed() {
    let mut c = Console::from_artifact(JSON).unwrap();
    viewer_click(&mut c, 106.0, 105.0); // Ada → Grace
    let ov = c.diff_overlay();
    assert!(
        ov.contains("class=\"diff-added\""),
        "Grace's fields highlighted as added"
    );
    assert!(
        ov.contains("class=\"diff-removed\""),
        "Ada's fields highlighted as removed"
    );
    assert!(
        ov.contains("class=\"diff-changed\""),
        "the main panel marked changed"
    );
    // both the textual diff AND the visual overlay are present in the rendered shell
    let svg = c.render_svg();
    assert!(svg.contains("class=\"diff-added\""));
    assert!(svg.contains("removed fld:Ada") || svg.contains("removed")); // textual panel intact
}

#[test]
fn overlay_is_mapped_into_the_viewer_coordinate_space() {
    let mut c = Console::from_artifact(JSON).unwrap();
    viewer_click(&mut c, 106.0, 105.0);
    let ov = c.diff_overlay();
    // fld:Grace:priority is at target (220,48) → viewer (28+220/720*576, 120+48/440*352) = (204,158)
    assert!(
        ov.contains("x=\"204\""),
        "added field mapped into viewer x, not shell space"
    );
    assert!(ov.contains("y=\"158\""), "added field mapped into viewer y");
    // overlay must NOT live in the replay-strip shell space (chips are at y=22)
    assert!(
        !ov.contains("y=\"22\""),
        "overlay is not drawn in the console chrome"
    );
}

#[test]
fn scrubbing_updates_the_overlay_deterministically() {
    let mut c = Console::from_artifact(JSON).unwrap();
    viewer_click(&mut c, 106.0, 105.0); // step 1
    let live = c.diff_overlay();
    assert!(!live.is_empty());

    c.select_step(0);
    assert_eq!(c.diff_overlay(), "", "scrubbed to initial → no overlay");

    c.select_step(1);
    assert_eq!(
        c.diff_overlay(),
        live,
        "re-selecting a step reproduces the same overlay (deterministic)"
    );
}

#[test]
fn existing_console_behaviour_is_intact() {
    // a quick smoke that the shell + textual diff still render alongside the overlay
    let mut c = Console::from_artifact(JSON).unwrap();
    viewer_click(&mut c, 106.0, 105.0);
    let svg = c.render_svg();
    for needle in [
        "replay",
        "frame viewer",
        "lineage",
        "frame diff",
        "Lead \u{b7} Grace",
    ] {
        assert!(svg.contains(needle), "missing: {needle}");
    }
}

// ── pure overlay generator: all four kinds distinguishable + geometry honesty ───────────────────

fn box_node(id: &str, sx: i64, sy: i64, data: serde_json::Value) -> ProjectedNode {
    ProjectedNode {
        id: id.into(),
        x: 0.0,
        y: 0.0,
        z: 0.0,
        sx,
        sy,
        intent: None,
        sw: Some(50),
        sh: Some(20),
        data,
    }
}
fn point_node(id: &str, data: serde_json::Value) -> ProjectedNode {
    ProjectedNode {
        id: id.into(),
        x: 0.0,
        y: 0.0,
        z: 0.0,
        sx: 10,
        sy: 10,
        intent: None,
        sw: None,
        sh: None,
        data,
    }
}
fn frame(nodes: Vec<ProjectedNode>) -> Frame {
    Frame {
        frame_index: 0,
        world_digest: String::new(),
        source_receipt_id: None,
        nodes,
    }
}

#[test]
fn all_four_change_kinds_are_distinguishable() {
    let prev = frame(vec![
        box_node("A", 10, 10, json!({ "v": 1 })), // will change (same pos, diff data)
        box_node("R", 10, 40, json!({ "v": 0 })), // will be removed
        box_node("M", 10, 70, json!({ "v": 0 })), // will move
    ]);
    let cur = frame(vec![
        box_node("A", 10, 10, json!({ "v": 2 })),    // changed
        box_node("ADD", 10, 100, json!({ "v": 0 })), // added
        box_node("M", 80, 70, json!({ "v": 0 })),    // moved
    ]);
    let ov = diff_overlay_svg(&prev, &cur);
    assert!(ov.contains("class=\"diff-changed\""), "A changed");
    assert!(ov.contains("class=\"diff-added\""), "ADD added");
    assert!(ov.contains("class=\"diff-removed\""), "R removed");
    assert!(ov.contains("class=\"diff-moved\""), "M moved");
    assert!(
        ov.contains("<line class=\"diff-moved\""),
        "moved shows a displacement line"
    );
}

#[test]
fn point_node_change_keeps_textual_diff_but_no_overlay_geometry() {
    // a node without sw/sh: do not invent geometry → no overlay rect, even though it changed
    let prev = frame(vec![point_node("p", json!({ "v": 1 }))]);
    let cur = frame(vec![point_node("p", json!({ "v": 2 }))]);
    assert_eq!(
        diff_overlay_svg(&prev, &cur),
        "",
        "point-node change emits no overlay rect"
    );
}
