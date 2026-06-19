//! LAB-FRAME-IGV-BINDING-SYNTAX-P1 — a tiny `.igv` text syntax lowers deterministically to the
//! proven ViewArtifact JSON, accepted by the existing binding host. Imports only `igniter_ui_kit`
//! (+ igniter_frame, machine-free). No machine.

use igniter_ui_kit::binding::{BoundViewHost, FixtureContractRegistry};
use igniter_ui_kit::igv::{lower_igv, IgvError};
use serde_json::Value;

const IGV: &str = include_str!("../web/lead_review.igv");

#[test]
fn parse_minimal_workbench_igv() {
    let v = lower_igv(IGV).expect("lowers");
    assert_eq!(v["artifact"], "view");
    assert_eq!(v["layout"], "workbench");
    assert_eq!(v["screen"], "lead_review");
}

#[test]
fn igv_lowers_to_existing_viewartifact_shape() {
    let v = lower_igv(IGV).unwrap();
    // sources → P16 source manifest shape
    assert_eq!(v["sources"]["leads"]["contract"], "ListLeads");
    assert_eq!(v["sources"]["leads"]["mode"], "read");
    // regions
    assert_eq!(v["regions"]["sidebar"]["component"], "List");
    assert_eq!(v["regions"]["sidebar"]["bind"], "leads");
    assert_eq!(v["regions"]["sidebar"]["on_select"], "select");
    assert_eq!(v["regions"]["inspector"]["component"], "KeyValuePanel");
    assert_eq!(v["regions"]["inspector"]["bind"], "selected");
    assert_eq!(v["regions"]["main"]["component"], "Form");
    assert_eq!(v["regions"]["main"]["submit"]["action"], "submit_lead");
    // fields (order preserved; select carries options)
    let fields = v["regions"]["main"]["fields"].as_array().unwrap();
    assert_eq!(fields.len(), 3);
    assert_eq!(fields[0]["id"], "priority");
    assert_eq!(fields[0]["kind"], "text");
    assert_eq!(fields[0]["required"], true);
    assert_eq!(fields[1]["id"], "stage");
    assert_eq!(
        fields[1]["options"],
        serde_json::json!(["new", "qualified", "won"])
    );
    assert_eq!(fields[2]["id"], "hot");
    assert_eq!(fields[2]["required"], false);
}

#[test]
fn igv_action_manifest_matches_p18_bridge_expectations() {
    let v = lower_igv(IGV).unwrap();
    let a = &v["actions"]["submit_lead"];
    assert_eq!(a["contract"], "SubmitLeadReview");
    assert_eq!(a["input"]["lead"], "$selection.lead");
    assert_eq!(a["input"]["fields"], "$form.values");
    assert_eq!(a["validate"], "ValidateLeadReview");
    // the P17/P18 effect block shape: { capability_id, operation, scope }
    assert_eq!(a["effect"]["capability_id"], "IO.FrameFixture");
    assert_eq!(a["effect"]["operation"], "record");
    assert_eq!(a["effect"]["scope"], "write");
}

#[test]
fn lowering_is_deterministic_byte_stable() {
    let a = lower_igv(IGV).unwrap().to_string();
    let b = lower_igv(IGV).unwrap().to_string();
    assert_eq!(a, b, "same .igv → byte-identical JSON");
}

#[test]
fn igv_bound_source_runs_through_the_fixture_host() {
    // acceptance 2/4: the lowered JSON is accepted by the existing binding host, and the source runs
    let json = lower_igv(IGV).unwrap().to_string();
    let mut host = BoundViewHost::from_artifact(&json, FixtureContractRegistry::lead_review())
        .expect("binding host accepts the lowered artifact");
    assert_eq!(
        host.leads(),
        vec!["Ada", "Grace", "Linus"],
        "leads came from ListLeads via the lowered source"
    );
    assert_eq!(host.calls("ListLeads"), 1);

    // submit (empty Ada) → scoped validation through the lowered action's validate contract
    host.click(344.0, 224.0); // submit button
    assert!(
        host.errors_for("Ada").is_some(),
        "the lowered action's validate ran"
    );
    assert!(host.last_receipt().is_none());
}

#[test]
fn invalid_igv_reports_stable_error() {
    // missing layout + brace
    match lower_igv("view oops") {
        Err(IgvError { line, msg }) => {
            assert_eq!(line, 1);
            assert!(msg.contains("expected: view"), "stable message: {msg}");
        }
        Ok(_) => panic!("expected an error"),
    }
    // a select field without options
    let bad = "view x workbench {\n  field s select \"S\"\n  submit a\n}";
    assert!(matches!(lower_igv(bad), Err(IgvError { line: 2, .. })));
    // unknown statement
    assert!(matches!(
        lower_igv("view x workbench {\n  wat\n}"),
        Err(IgvError { line: 2, .. })
    ));
}

#[test]
fn igv_lowers_equivalently_to_the_handwritten_bound_artifact() {
    // the lowered JSON drives the same workbench as the hand-written bound artifact (same leads+fields)
    let from_igv = BoundViewHost::from_artifact(
        &lower_igv(IGV).unwrap().to_string(),
        FixtureContractRegistry::lead_review(),
    )
    .unwrap();
    const BOUND: &str = include_str!("../web/lead_review_bound.view.json");
    let from_json =
        BoundViewHost::from_artifact(BOUND, FixtureContractRegistry::lead_review()).unwrap();
    assert_eq!(
        from_igv.workbench_render_digest(),
        from_json.workbench_render_digest(),
        ".igv ≡ hand-written bound artifact"
    );
}

#[test]
fn parse_error_implements_display() {
    let e: Value = match lower_igv("nope") {
        Err(err) => serde_json::json!(err.to_string()),
        Ok(_) => panic!(),
    };
    assert!(e.as_str().unwrap().contains(".igv error (line 1)"));
}
