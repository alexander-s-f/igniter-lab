// LAB-IGNITER-RENDER-HTML-P3 — ViewArtifact JSON → escaped HTML, proven deterministic + injection-safe.
// The two real fixtures are the canonical kit artifacts (igniter-ui-kit/web), pulled in at compile time
// only (no runtime/dev dependency on ui-kit), so the renderer is proven against the SAME schema the
// frame runtime consumes.

use igniter_render_html::{render_html, render_html_fragment, RenderHtmlError};

const LEAD_INTAKE: &str = include_str!("../../igniter-ui-kit/web/lead_intake.view.json"); // form
const LEAD_REVIEW: &str = include_str!("../../igniter-ui-kit/web/lead_review.view.json"); // workbench

#[test]
fn renders_canonical_form_fixture_deterministically() {
    let a = render_html(LEAD_INTAKE).expect("render form");
    let b = render_html(LEAD_INTAKE).expect("render form again");
    assert_eq!(a, b, "same artifact must render byte-identically");
    // document shape + escaped content from the real fixture.
    assert!(a.starts_with("<!DOCTYPE html>"));
    assert!(a.contains("<title>Lead Intake</title>"));
    assert!(a.contains("<input type=\"text\" name=\"name\" required>"));
    assert!(a.contains("<option value=\"referral\">referral</option>"));
    assert!(
        a.contains("<button type=\"submit\" id=\"submit\" data-action=\"submit\">Submit</button>")
    );
}

#[test]
fn renders_canonical_workbench_fixture() {
    let html = render_html(LEAD_REVIEW).expect("render workbench");
    assert_eq!(html, render_html(LEAD_REVIEW).unwrap(), "deterministic");
    assert!(html.contains("<title>lead_review</title>"));
    // data.leads → list
    assert!(html.contains("<li>Ada</li>"));
    assert!(html.contains("<li>Grace</li>"));
    assert!(html.contains("<li>Linus</li>"));
    // regions.main.fields → form inputs
    assert!(html.contains("<input type=\"text\" name=\"priority\" required>"));
    assert!(html.contains("<option value=\"qualified\">qualified</option>"));
    assert!(html.contains("type=\"checkbox\" name=\"hot\""));
}

#[test]
fn fragment_has_no_document_wrapper() {
    let frag = render_html_fragment(LEAD_INTAKE).expect("fragment");
    assert!(!frag.contains("<!DOCTYPE"));
    assert!(!frag.contains("<html"));
    assert!(frag.starts_with("<form class=\"ig-form\">"));
}

#[test]
fn text_content_is_escaped_never_a_raw_script() {
    let artifact = r#"{ "artifact":"view", "layout":"form", "title":"X",
        "body":[ { "kind":"label", "text":"<script>alert(1)</script>" } ] }"#;
    let html = render_html(artifact).unwrap();
    assert!(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"));
    assert!(!html.contains("<script>"), "raw script must never appear");
}

#[test]
fn attribute_values_are_escaped() {
    // a malicious id tries to break out of the name="" attribute.
    let artifact = r#"{ "artifact":"view", "layout":"form", "title":"X",
        "body":[ { "kind":"text", "id":"x\" onload=\"evil", "label":"L" } ] }"#;
    let html = render_html(artifact).unwrap();
    assert!(html.contains("name=\"x&quot; onload=&quot;evil\""));
    assert!(
        !html.contains("onload=\"evil\""),
        "must not break out of the attribute"
    );
}

#[test]
fn unknown_component_kind_fails_closed() {
    let artifact = r#"{ "artifact":"view", "layout":"form", "title":"X",
        "body":[ { "kind":"marquee", "text":"hi" } ] }"#;
    assert!(matches!(
        render_html(artifact),
        Err(RenderHtmlError::UnsupportedNode(_))
    ));
}

#[test]
fn non_view_artifact_is_rejected() {
    assert!(matches!(
        render_html(r#"{ "artifact":"frame", "layout":"form", "body":[] }"#),
        Err(RenderHtmlError::InvalidArtifact(_))
    ));
    assert!(matches!(
        render_html("not json at all"),
        Err(RenderHtmlError::InvalidArtifact(_))
    ));
    assert!(matches!(
        render_html(r#"{ "artifact":"view", "layout":"galaxy" }"#),
        Err(RenderHtmlError::InvalidArtifact(_))
    ));
}

#[test]
fn empty_form_body_is_rejected() {
    assert!(matches!(
        render_html(r#"{ "artifact":"view", "layout":"form", "body":[] }"#),
        Err(RenderHtmlError::InvalidArtifact(_))
    ));
}
