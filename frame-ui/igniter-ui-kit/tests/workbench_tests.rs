//! LAB-FRAME-UI-KIT-COMPOSITION-P10 — a nested Workbench (Sidebar[List] / Main[Form] /
//! Inspector[KeyValuePanel]) over igniter-frame: multi-region layout, nested event routing, stable
//! ids, focus survival across layout changes, scoped validation, selection-driven inspector,
//! deterministic replay. Imports only `igniter_ui_kit` (+ `igniter_frame`, machine-free).

use igniter_ui_kit::composition::WorkbenchRuntime;

// canvas 720×440; box centres (css == frame):
const ADA: (f64, f64) = (106.0, 65.0);
const GRACE: (f64, f64) = (106.0, 105.0);
const PRIORITY: (f64, f64) = (344.0, 70.0);
const STAGE: (f64, f64) = (344.0, 126.0);
const HOT: (f64, f64) = (344.0, 178.0);
const SUBMIT: (f64, f64) = (344.0, 224.0);

fn typed(rt: &mut WorkbenchRuntime, s: &str) {
    for ch in s.chars() {
        rt.key(&ch.to_string());
    }
}

#[test]
fn nested_tree_projects_to_three_regions() {
    let rt = WorkbenchRuntime::lead_review();
    let svg = rt.render_svg();
    for needle in [
        "Leads",
        "Lead \u{b7} Ada",
        "Details",
        "Ada",
        "Grace",
        "Linus",
        "Priority",
        "Stage",
        "Hot lead",
        "Submit",
        "lead: Ada",
    ] {
        assert!(
            svg.contains(needle),
            "missing from composed screen: {needle}"
        );
    }
}

#[test]
fn selection_routes_and_updates_inspector() {
    let mut rt = WorkbenchRuntime::lead_review();
    assert!(svg(&rt).contains("lead: Ada"));
    assert!(
        rt.click(GRACE.0, GRACE.1),
        "clicking a list item selects it"
    );
    let s = svg(&rt);
    assert!(
        s.contains("Lead \u{b7} Grace"),
        "main panel follows selection"
    );
    assert!(s.contains("lead: Grace"), "inspector follows selection");
}

#[test]
fn nested_field_editing_updates_inspector_via_reducer() {
    let mut rt = WorkbenchRuntime::lead_review();
    rt.click(PRIORITY.0, PRIORITY.1); // focus Ada priority
    typed(&mut rt, "P1");
    let s = svg(&rt);
    assert!(s.contains("P1"), "field value updated via the reducer");
    assert!(s.contains("priority: P1"), "inspector reflects the edit");
    // checkbox + select also route through the reducer
    rt.click(HOT.0, HOT.1);
    assert!(svg(&rt).contains("hot: yes"));
    rt.click(STAGE.0, STAGE.1);
    assert!(svg(&rt).contains("stage: new"));
}

#[test]
fn stable_ids_preserve_per_lead_state_across_selection() {
    let mut rt = WorkbenchRuntime::lead_review();
    rt.click(PRIORITY.0, PRIORITY.1);
    typed(&mut rt, "hot");
    rt.click(GRACE.0, GRACE.1); // switch away — Grace's priority is empty
    assert!(
        !svg(&rt).contains("priority: hot"),
        "Grace has its own (empty) state"
    );
    rt.click(ADA.0, ADA.1); // switch back
    assert!(
        svg(&rt).contains("priority: hot"),
        "Ada's value persisted (stable id keying)"
    );
}

#[test]
fn focus_survives_within_lead_but_clears_when_component_leaves() {
    let mut rt = WorkbenchRuntime::lead_review();
    rt.click(PRIORITY.0, PRIORITY.1); // focus Ada priority
    typed(&mut rt, "h");
    assert!(svg(&rt).contains("h"), "typed into focused field");

    // a different selection re-lays-out: the focused component (fld:Ada:priority) is gone → clear
    rt.click(GRACE.0, GRACE.1);
    let frame_after_select = rt.frame_index();
    assert!(
        !rt.key("z"),
        "no focused field after layout change → keystroke is a no-op"
    );
    assert_eq!(rt.frame_index(), frame_after_select, "no frame advanced");

    // re-selecting Ada keeps the value but does NOT auto-restore focus
    rt.click(ADA.0, ADA.1);
    assert!(svg(&rt).contains("priority: hot") == false); // sanity: value is "h" not "hot"
    assert!(svg(&rt).contains("priority: h"));
}

#[test]
fn validation_is_scoped_per_lead_not_global() {
    let mut rt = WorkbenchRuntime::lead_review();
    rt.click(SUBMIT.0, SUBMIT.1); // submit Ada empty → errors
    let s = svg(&rt);
    assert!(s.contains("! required"), "Ada priority flagged");
    assert!(s.contains("! select one"), "Ada stage flagged");
    assert!(s.contains("errors: 2"), "inspector shows Ada's error count");

    rt.click(GRACE.0, GRACE.1); // Grace was never submitted
    let g = svg(&rt);
    assert!(
        !g.contains("! required"),
        "Grace shows no errors (scoped, not global)"
    );
    assert!(g.contains("errors: 0"));
}

#[test]
fn deterministic_replay_of_multi_panel_event_log() {
    let script = |rt: &mut WorkbenchRuntime| {
        let mut d = vec![rt.render_digest()];
        rt.click(PRIORITY.0, PRIORITY.1);
        for ch in "hi".chars() {
            rt.key(&ch.to_string());
        }
        rt.click(STAGE.0, STAGE.1); // cycle
        rt.click(HOT.0, HOT.1); // toggle
        rt.click(GRACE.0, GRACE.1); // select another lead
        rt.click(SUBMIT.0, SUBMIT.1); // submit Grace
        rt.click(ADA.0, ADA.1); // back to Ada
        d.push(rt.render_digest());
        d
    };
    let mut a = WorkbenchRuntime::lead_review();
    let mut b = WorkbenchRuntime::lead_review();
    assert_eq!(
        script(&mut a),
        script(&mut b),
        "same multi-panel event log → identical frames"
    );
}

#[test]
fn empty_panel_area_click_is_a_noop() {
    let mut rt = WorkbenchRuntime::lead_review();
    let before = rt.render_digest();
    assert!(
        !rt.click(344.0, 400.0),
        "clicking empty main-panel space hits the panel (no intent)"
    );
    assert_eq!(rt.render_digest(), before);
}

fn svg(rt: &WorkbenchRuntime) -> String {
    rt.render_svg()
}
