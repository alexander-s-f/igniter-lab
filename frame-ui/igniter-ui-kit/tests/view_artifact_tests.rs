//! LAB-FRAME-VIEWARTIFACT-P12 — a portable ViewArtifact JSON compiles to the kit tree and runs on
//! FrameRuntime with byte-identical behavior to the hand-written constructor. The canonical JSON
//! files are the SAME ones the browser loads (single source of truth). Machine-free.

use igniter_ui_kit::composition::WorkbenchRuntime;
use igniter_ui_kit::view_artifact::{compile, compile_workbench, Screen, ViewError};
use igniter_ui_kit::FormRuntime;

const WORKBENCH_JSON: &str = include_str!("../web/lead_review.view.json");
const FORM_JSON: &str = include_str!("../web/lead_intake.view.json");

// ── byte-identical: JSON-compiled runtime ≡ hand-written constructor ─────────────────────────────

fn drive_workbench(rt: &mut WorkbenchRuntime) -> Vec<String> {
    // a multi-panel script (centres in the 720×440 canvas)
    let log: &[(&str, f64, f64)] = &[
        ("c", 344.0, 70.0),  // focus Ada priority
        ("k", 0.0, 0.0),     // type 'h'
        ("k", 1.0, 0.0),     // type 'i'
        ("c", 344.0, 126.0), // cycle stage
        ("c", 344.0, 178.0), // toggle hot
        ("c", 106.0, 105.0), // select Grace
        ("c", 344.0, 224.0), // submit Grace
        ("c", 106.0, 65.0),  // back to Ada
    ];
    let mut digests = vec![rt.render_digest()];
    for (kind, a, b) in log {
        match *kind {
            "c" => {
                rt.click(*a, *b);
            }
            _ => {
                rt.key(if *a == 0.0 { "h" } else { "i" });
            }
        }
        digests.push(rt.render_digest());
    }
    digests
}

#[test]
fn workbench_json_compiles_to_byte_identical_runtime() {
    let mut from_json = WorkbenchRuntime::from_artifact(WORKBENCH_JSON).expect("artifact compiles");
    let mut hand = WorkbenchRuntime::lead_review();

    assert_eq!(
        from_json.render_digest(),
        hand.render_digest(),
        "initial frame identical"
    );
    assert_eq!(
        drive_workbench(&mut from_json),
        drive_workbench(&mut hand),
        "JSON-built workbench is byte-identical to the hand-written one over a full event log"
    );
}

#[test]
fn workbench_json_renders_the_authored_screen() {
    let rt = WorkbenchRuntime::from_artifact(WORKBENCH_JSON).unwrap();
    let svg = rt.render_svg();
    for needle in [
        "Leads",
        "Ada",
        "Grace",
        "Linus",
        "Priority",
        "Stage",
        "Hot lead",
        "Submit",
        "lead: Ada",
    ] {
        assert!(svg.contains(needle), "compiled screen missing: {needle}");
    }
}

fn drive_form(rt: &mut FormRuntime) -> Vec<String> {
    let mut d = vec![rt.render_digest()];
    rt.click(200.0, 81.0); // focus name
    for ch in "Ada".chars() {
        rt.key(&ch.to_string());
    }
    rt.click(200.0, 197.0); // cycle source
    rt.click(200.0, 250.0); // toggle qualified
    rt.click(200.0, 300.0); // submit
    d.push(rt.render_digest());
    d
}

#[test]
fn form_json_compiles_to_byte_identical_runtime() {
    let mut from_json = FormRuntime::from_artifact(FORM_JSON).expect("form artifact compiles");
    let mut hand = FormRuntime::lead_intake();
    assert_eq!(
        from_json.render_digest(),
        hand.render_digest(),
        "initial form identical"
    );
    assert_eq!(
        drive_form(&mut from_json),
        drive_form(&mut hand),
        "JSON-built form is byte-identical to lead_intake()"
    );
}

// ── the compile is a real lowering with diagnostics ─────────────────────────────────────────────

#[test]
fn malformed_json_is_a_parse_error() {
    assert!(matches!(compile("{ not json"), Err(ViewError::Parse(_))));
}

#[test]
fn not_a_view_artifact_is_rejected() {
    let r = compile(r#"{ "artifact": "frame", "layout": "workbench" }"#);
    assert!(matches!(r, Err(ViewError::Schema(_))));
}

#[test]
fn unknown_layout_is_a_schema_error() {
    let r = compile(r#"{ "artifact": "view", "layout": "grid" }"#);
    match r {
        Err(ViewError::Schema(m)) => assert!(m.contains("unknown layout")),
        other => panic!("expected schema error, got {other:?}"),
    }
}

#[test]
fn select_without_options_is_a_schema_error() {
    let json = r#"{ "artifact":"view","layout":"workbench","data":{"leads":["A"]},
      "regions":{"main":{"fields":[{"id":"s","kind":"select","label":"S"}]}} }"#;
    match compile_workbench(json) {
        Err(ViewError::Schema(m)) => assert!(m.contains("options")),
        other => panic!("expected options error, got {other:?}"),
    }
}

#[test]
fn unknown_field_kind_is_a_schema_error() {
    let json = r#"{ "artifact":"view","layout":"workbench","data":{"leads":["A"]},
      "regions":{"main":{"fields":[{"id":"x","kind":"slider","label":"X"}]}} }"#;
    match compile_workbench(json) {
        Err(ViewError::Schema(m)) => assert!(m.contains("unknown field kind")),
        other => panic!("expected kind error, got {other:?}"),
    }
}

#[test]
fn compile_dispatches_on_layout() {
    assert!(matches!(compile(WORKBENCH_JSON), Ok(Screen::Workbench(_))));
    assert!(matches!(compile(FORM_JSON), Ok(Screen::Form(_))));
}
