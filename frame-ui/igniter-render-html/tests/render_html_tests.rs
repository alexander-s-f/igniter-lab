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

// ── LAB-IGNITER-WEB-VIEWARTIFACT-LINK-NODE: the first URL-bearing node (`text` = label, `action` = href) ──

#[test]
fn link_renders_relative_and_http_s_anchors() {
    for href in [
        "/todos/42",
        "/todos?after=todo_2",
        "http://example.com/x",
        "https://example.com/y",
        "./detail",
    ] {
        let artifact = format!(
            r#"{{ "artifact":"view", "layout":"form", "title":"Nav", "body":[ {{ "kind":"link", "text":"Next", "action":"{href}" }} ] }}"#
        );
        let html = render_html(&artifact).expect("link renders");
        assert!(
            html.contains(&format!("<a class=\"ig-link\" href=\"{href}\">Next</a>")),
            "href {href} → {html}"
        );
    }
}

#[test]
fn link_rejects_dangerous_schemes_without_emitting_anchor() {
    for href in [
        "javascript:alert(1)",
        "data:text/html;base64,xxx",
        "mailto:x@y.z",
    ] {
        let artifact = format!(
            r#"{{ "artifact":"view", "layout":"form", "title":"Nav", "body":[ {{ "kind":"link", "text":"Click", "action":"{href}" }} ] }}"#
        );
        let r = render_html(&artifact);
        assert!(
            matches!(r, Err(RenderHtmlError::UnsafeUrl(_))),
            "scheme {href} must fail closed, got {r:?}"
        );
        // and certainly no anchor leaks out
        if let Ok(html) = r {
            assert!(!html.contains("<a "), "no anchor for {href}: {html}");
        }
    }
}

#[test]
fn link_rejects_control_character_scheme_bypasses_and_protocol_relative_urls() {
    for href in [
        "java\\nscript:alert(1)",
        "java\\tscript:alert(1)",
        "\\u0001javascript:alert(1)",
        "//evil.example/x",
    ] {
        let artifact = format!(
            r#"{{ "artifact":"view", "layout":"form", "title":"Nav", "body":[ {{ "kind":"link", "text":"Click", "action":"{href}" }} ] }}"#
        );
        let r = render_html(&artifact);
        assert!(
            matches!(r, Err(RenderHtmlError::UnsafeUrl(_))),
            "href {href:?} must fail closed, got {r:?}"
        );
    }
}

#[test]
fn link_text_and_href_are_escaped() {
    // malicious label + an href carrying an HTML-significant `&` are both escaped on the way to bytes.
    let artifact = r#"{ "artifact":"view", "layout":"form", "title":"X",
        "body":[ { "kind":"link", "text":"<script>x</script>", "action":"/q?a=1&b=2" } ] }"#;
    let html = render_html(artifact).unwrap();
    assert!(
        html.contains("&lt;script&gt;x&lt;/script&gt;"),
        "link text escaped: {html}"
    );
    assert!(
        !html.contains("<script>"),
        "raw script must not appear: {html}"
    );
    assert!(
        html.contains("href=\"/q?a=1&amp;b=2\""),
        "href escaped: {html}"
    );
}

#[test]
fn link_href_attribute_escapes_double_and_single_quotes() {
    let artifact = r#"{ "artifact":"view", "layout":"form", "title":"X",
        "body":[ { "kind":"link", "text":"Quotes", "action":"/q?double=\"&single='" } ] }"#;
    let html = render_html(artifact).unwrap();
    assert!(
        html.contains("href=\"/q?double=&quot;&amp;single=&#x27;\""),
        "href attribute quotes escaped: {html}"
    );
    assert!(
        !html.contains("href=\"/q?double=\"&single='\""),
        "raw attribute quotes must not leak: {html}"
    );
}

#[test]
fn link_missing_text_or_action_fails_closed() {
    let no_action = r#"{ "artifact":"view", "layout":"form", "title":"X",
        "body":[ { "kind":"link", "text":"Next" } ] }"#;
    assert!(matches!(
        render_html(no_action),
        Err(RenderHtmlError::InvalidArtifact(_))
    ));
    let no_text = r#"{ "artifact":"view", "layout":"form", "title":"X",
        "body":[ { "kind":"link", "action":"/todos" } ] }"#;
    assert!(matches!(
        render_html(no_text),
        Err(RenderHtmlError::InvalidArtifact(_))
    ));
}
