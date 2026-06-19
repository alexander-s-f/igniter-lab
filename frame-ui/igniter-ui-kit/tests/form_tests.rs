//! LAB-FRAME-UI-KIT-FORMS-P9 — a component vocabulary projects to frame nodes; input routes to
//! component intents; field state changes through the reducer (not the host); validation comes from
//! state; deterministic replay. Imports only `igniter_ui_kit` (+ `igniter_frame`, machine-free).

use igniter_ui_kit::FormRuntime;

// Lead Intake layout (vertical stack), box centres:
//   lbl(20..48) · name(56..106)→81 · phone(114..164)→139 · source(172..222)→197
//   qualified(230..270)→250 · submit(278..322)→300
const NAME: (f64, f64) = (200.0, 81.0);
const PHONE: (f64, f64) = (200.0, 139.0);
const SOURCE: (f64, f64) = (200.0, 197.0);
const QUALIFIED: (f64, f64) = (200.0, 250.0);
const SUBMIT: (f64, f64) = (200.0, 300.0);

fn typed(rt: &mut FormRuntime, s: &str) {
    for ch in s.chars() {
        rt.key(&ch.to_string());
    }
}

#[test]
fn component_tree_projects_to_frame_nodes() {
    let rt = FormRuntime::lead_intake();
    let svg = rt.render_svg();
    for needle in [
        "New Lead",
        "Name",
        "Phone",
        "Source",
        "Qualified",
        "Submit",
        "select",
    ] {
        assert!(svg.contains(needle), "missing component: {needle}");
    }
}

#[test]
fn focus_then_type_updates_value_through_reducer() {
    let mut rt = FormRuntime::lead_intake();
    assert!(rt.click(NAME.0, NAME.1), "clicking the field focuses it");
    typed(&mut rt, "Ada");
    assert!(
        rt.render_svg().contains("Ada"),
        "value updated via the reducer, not the host"
    );
    assert_eq!(rt.frame_index(), 4, "focus + 3 keystrokes = 4 effects");
}

#[test]
fn typing_without_focus_is_a_noop() {
    let mut rt = FormRuntime::lead_intake();
    assert!(!rt.key("X"), "no focused field → no state change");
    assert_eq!(rt.frame_index(), 0);
}

#[test]
fn checkbox_toggles_and_select_cycles() {
    let mut rt = FormRuntime::lead_intake();
    assert!(rt.click(QUALIFIED.0, QUALIFIED.1));
    assert!(rt.render_svg().contains("[x] Qualified"));
    assert!(rt.click(SOURCE.0, SOURCE.1));
    assert!(
        rt.render_svg().contains("web"),
        "select cycles to the first option"
    );
    rt.click(SOURCE.0, SOURCE.1);
    assert!(rt.render_svg().contains("referral"), "and to the next");
}

#[test]
fn submit_empty_shows_validation_from_state() {
    let mut rt = FormRuntime::lead_intake();
    assert!(rt.click(SUBMIT.0, SUBMIT.1));
    let svg = rt.render_svg();
    assert!(
        svg.contains("required"),
        "empty required text fields flagged"
    );
    assert!(
        svg.contains("select one"),
        "unselected required select flagged"
    );
    assert!(!svg.contains("lead submitted"), "not submitted");
}

#[test]
fn submit_valid_shows_banner() {
    let mut rt = FormRuntime::lead_intake();
    rt.click(NAME.0, NAME.1);
    typed(&mut rt, "Ada");
    rt.click(PHONE.0, PHONE.1);
    typed(&mut rt, "5551234");
    rt.click(SOURCE.0, SOURCE.1); // select "web"
    assert!(rt.click(SUBMIT.0, SUBMIT.1));
    let svg = rt.render_svg();
    assert!(svg.contains("lead submitted"), "valid form submits");
    assert!(!svg.contains("! required"), "no validation errors");
}

#[test]
fn deterministic_replay_of_form_event_log() {
    let script = |rt: &mut FormRuntime| {
        let mut digests = vec![rt.render_digest()];
        rt.click(NAME.0, NAME.1);
        for ch in "Ada".chars() {
            rt.key(&ch.to_string());
        }
        rt.click(QUALIFIED.0, QUALIFIED.1);
        rt.click(SOURCE.0, SOURCE.1);
        rt.click(SUBMIT.0, SUBMIT.1);
        digests.push(rt.render_digest());
        digests
    };
    let mut a = FormRuntime::lead_intake();
    let mut b = FormRuntime::lead_intake();
    assert_eq!(
        script(&mut a),
        script(&mut b),
        "same form event log → identical frames"
    );
}

#[test]
fn lineage_records_keystroke_events() {
    let mut rt = FormRuntime::lead_intake();
    rt.click(NAME.0, NAME.1); // input:0 → effect:0 → frame:1
    rt.key("A"); // type:1 → effect:1 → frame:2
    let lineage: serde_json::Value = serde_json::from_str(&rt.lineage_json()).unwrap();
    assert_eq!(lineage["input_receipt_id"], "type:1");
    assert_eq!(lineage["effect_receipt_id"], "effect:1");
    assert_eq!(lineage["frame_index"], 2);
}

#[test]
fn reset_returns_to_blank_form() {
    let mut rt = FormRuntime::lead_intake();
    let initial = rt.render_digest();
    rt.click(NAME.0, NAME.1);
    typed(&mut rt, "Ada");
    assert_ne!(rt.render_digest(), initial);
    rt.reset();
    assert_eq!(rt.render_digest(), initial);
    assert_eq!(rt.frame_index(), 0);
}
