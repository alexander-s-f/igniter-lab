//! LAB-FRAME-IG-BINDING-P16 — proof-local fixture binding: one read source + one submit action,
//! the double gate, view-local vs host state, scoped validation, deterministic fixture receipt.
//! Imports only `igniter_ui_kit` (+ `igniter_frame`, machine-free). No real machine/CoordinationHub.

use igniter_ui_kit::binding::{BindingError, BoundViewHost, FixtureContractRegistry};
use igniter_ui_kit::composition::WorkbenchRuntime;

const BOUND: &str = include_str!("../web/lead_review_bound.view.json");
const UNBOUND: &str = include_str!("../web/lead_review.view.json");

// workbench box centres (720×440 canvas, host renders the workbench directly)
const ADA: (f64, f64) = (106.0, 65.0);
const PRIORITY: (f64, f64) = (344.0, 70.0);
const STAGE: (f64, f64) = (344.0, 126.0);
const SUBMIT: (f64, f64) = (344.0, 224.0);

fn host() -> BoundViewHost {
    BoundViewHost::from_artifact(BOUND, FixtureContractRegistry::lead_review())
        .expect("bound artifact compiles")
}

#[test]
fn bound_source_loads_leads_from_fixture() {
    let h = host();
    assert_eq!(
        h.leads(),
        vec!["Ada", "Grace", "Linus"],
        "leads came from ListLeads, not inline data"
    );
    assert_eq!(
        h.calls("ListLeads"),
        1,
        "the source contract was invoked exactly once at load"
    );
    // and the resulting workbench is the SAME as the hand-written one (source produced equal data)
    assert_eq!(
        h.workbench_render_digest(),
        WorkbenchRuntime::lead_review().render_digest()
    );
}

#[test]
fn unbound_artifact_still_byte_identical() {
    // acceptance 2: the P12 path is untouched
    let mut from_json = WorkbenchRuntime::from_artifact(UNBOUND).unwrap();
    let mut hand = WorkbenchRuntime::lead_review();
    assert_eq!(from_json.render_digest(), hand.render_digest());
    from_json.click(ADA.0, ADA.1);
    hand.click(ADA.0, ADA.1);
    assert_eq!(from_json.render_digest(), hand.render_digest());
}

#[test]
fn missing_source_declaration_is_rejected() {
    let no_source = r#"{ "artifact":"view","layout":"workbench","actions":{},
      "regions":{"sidebar":{"bind":"leads"},"main":{"fields":[{"id":"x","kind":"text","label":"X"}]}} }"#;
    match BoundViewHost::from_artifact(no_source, FixtureContractRegistry::lead_review()).err() {
        Some(BindingError::MissingDeclaration(m)) => assert!(m.contains("sources.leads")),
        other => panic!("expected MissingDeclaration, got {other:?}"),
    }
}

#[test]
fn unknown_contract_is_rejected_by_registry_before_any_call() {
    let bad = r#"{ "artifact":"view","layout":"workbench",
      "sources":{"leads":{"contract":"Unknown","mode":"read"}}, "actions":{},
      "regions":{"sidebar":{"bind":"leads"},"main":{"fields":[{"id":"x","kind":"text","label":"X"}]}} }"#;
    let reg = FixtureContractRegistry::lead_review();
    match BoundViewHost::from_artifact(bad, reg).err() {
        Some(BindingError::NotRegistered(c)) => assert_eq!(c, "Unknown"),
        other => panic!("expected NotRegistered, got {other:?}"),
    }
}

#[test]
fn selection_and_typing_stay_local_and_call_no_contracts() {
    let mut h = host();
    h.click(106.0, 105.0); // select Grace
    h.click(PRIORITY.0, PRIORITY.1); // focus
    for ch in "P1".chars() {
        h.key(&ch.to_string());
    }
    assert_eq!(h.selected_lead(), "Grace");
    // ONLY the load-time ListLeads call happened; no validate/submit
    assert_eq!(h.calls("ListLeads"), 1);
    assert_eq!(h.calls("ValidateLeadReview"), 0);
    assert_eq!(h.calls("SubmitLeadReview"), 0);
}

#[test]
fn validation_failure_writes_scoped_errors_and_no_receipt() {
    let mut h = host(); // Ada selected, all fields empty
    h.click(SUBMIT.0, SUBMIT.1); // submit through the host
    let errs = h.errors_for("Ada").expect("Ada has scoped errors");
    assert_eq!(
        errs.get("priority").and_then(|v| v.as_str()),
        Some("required")
    );
    assert_eq!(
        errs.get("stage").and_then(|v| v.as_str()),
        Some("select one")
    );
    assert!(
        h.last_receipt().is_none(),
        "no success receipt on validation failure"
    );
    assert_eq!(h.calls("ValidateLeadReview"), 1);
    assert_eq!(
        h.calls("SubmitLeadReview"),
        0,
        "submit contract NOT called when validation fails"
    );
}

#[test]
fn submit_success_produces_a_deterministic_fixture_receipt() {
    let fill = |h: &mut BoundViewHost| {
        h.click(PRIORITY.0, PRIORITY.1); // focus priority
        for ch in "P1".chars() {
            h.key(&ch.to_string());
        }
        h.click(STAGE.0, STAGE.1); // cycle stage to "new"
        h.click(SUBMIT.0, SUBMIT.1); // submit
    };
    let mut h1 = host();
    fill(&mut h1);
    let r1 = h1.last_receipt().expect("a receipt on success").clone();
    assert!(r1.id.starts_with("fixture-receipt:"));
    assert_eq!(r1.status, "fixture-ok");
    assert!(
        h1.errors_for("Ada").is_none(),
        "success clears scoped errors"
    );
    assert_eq!(h1.calls("SubmitLeadReview"), 1);

    // deterministic: same drafts → same receipt id
    let mut h2 = host();
    fill(&mut h2);
    assert_eq!(
        h2.last_receipt().unwrap().id,
        r1.id,
        "content-addressed fixture receipt is deterministic"
    );
}

#[test]
fn submit_action_double_gate_refuses_when_contract_unregistered() {
    // declared action, but the submit contract is NOT in this registry
    let mut reg = FixtureContractRegistry::new();
    reg.register("ListLeads", |_| {
        igniter_ui_kit::binding::BindingResponse::Data(serde_json::json!(["Ada"]))
    });
    // no SubmitLeadReview / ValidateLeadReview registered
    let mut h = BoundViewHost::from_artifact(BOUND, reg).expect("loads (ListLeads present)");
    h.click(SUBMIT.0, SUBMIT.1);
    assert!(
        h.last_refusal().is_some(),
        "refused: a declared action whose contract is unregistered"
    );
    assert!(h.last_receipt().is_none());
    assert_eq!(h.calls("SubmitLeadReview"), 0);
}
