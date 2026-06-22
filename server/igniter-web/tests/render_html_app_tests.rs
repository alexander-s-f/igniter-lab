// igniter-web/tests/render_html_app_tests.rs — LAB-IGNITER-WEB-RENDER-DECISION-P16
// Proves the end-to-end HTML render decision: an authored `.igweb` route + `.ig` handler returns a
// `Render` decision carrying a ViewArtifact JSON string (sourced from the request body, since `.ig`
// string literals cannot contain `"`); igniter-web projects it through igniter-render-html (P3) and ships
// verbatim text/html bytes via the P15 raw seam. A bad artifact fails closed to a JSON 500. `Respond`
// JSON behavior is unchanged.

use igniter_server::protocol::ServerApp;
use igniter_web::testkit::roundtrip_raw;
use igniter_web::{build_igweb_app, IgWebBuildInput};
use std::path::PathBuf;
use std::sync::Arc;

// A full ViewArtifact form. The label text carries `<there>` / `<script>` to prove escaping on the way
// to bytes. Built in Rust (where escapes work); sent as the request body.
const ARTIFACT: &str = r#"{"artifact":"view","layout":"form","title":"Hello","body":[{"kind":"label","text":"Hi <there> & <script>"},{"kind":"text","id":"name","label":"Name","required":true},{"kind":"button","id":"go","label":"Go","action":"submit"}]}"#;

fn dir() -> PathBuf {
    PathBuf::from(format!(
        "{}/examples/render_html_app",
        env!("CARGO_MANIFEST_DIR")
    ))
}

fn build() -> Arc<dyn ServerApp + Send + Sync> {
    let sources = ["render_handlers.ig", "routes.igweb"]
        .iter()
        .map(|f| dir().join(f))
        .collect();
    build_igweb_app(IgWebBuildInput {
        sources,
        entry: "Serve".into(),
    })
    .expect("build render_html_app from authored files")
}

/// Split a raw HTTP/1.1 response into (lower-cased head, body).
fn split(wire: &str) -> (String, &str) {
    let pos = wire.find("\r\n\r\n").map(|i| i + 4).unwrap_or(wire.len());
    (wire[..pos].to_lowercase(), &wire[pos..])
}

#[test]
fn render_decision_returns_verbatim_html_bytes() {
    let app = build();
    let (status, wire) = roundtrip_raw(&*app, "POST", "/render", &[], ARTIFACT);
    assert_eq!(status, 200);
    let (head, body) = split(&wire);

    // text/html content-type, NOT json.
    assert!(
        head.contains("content-type: text/html; charset=utf-8"),
        "head: {head}"
    );
    assert!(!head.contains("application/json"));

    // verbatim HTML document — not JSON-quoted, not `{"body": ...}` wrapped.
    assert!(body.starts_with("<!DOCTYPE html>"), "body: {body}");
    assert!(!body.contains("{\"body\""));
    // rendered ViewArtifact content is present and ESCAPED.
    assert!(body.contains("<title>Hello</title>"));
    assert!(body.contains("Hi &lt;there&gt; &amp; &lt;script&gt;"));
    assert!(body.contains("<input type=\"text\" name=\"name\" required>"));
    assert!(body.contains("data-action=\"submit\""));
    // the malicious `<script>` from the artifact never appears as a real script tag.
    assert!(
        !body.contains("<script>"),
        "raw <script> must not appear: {body}"
    );
}

#[test]
fn invalid_artifact_fails_closed_to_json_500() {
    let app = build();
    // valid JSON but not a view artifact → the renderer rejects it.
    let (status, wire) = roundtrip_raw(&*app, "POST", "/render", &[], r#"{"foo":1}"#);
    assert_eq!(status, 500, "bad artifact → 500");
    let (head, body) = split(&wire);
    assert!(
        head.contains("content-type: application/json"),
        "head: {head}"
    );
    assert!(!body.starts_with("<!DOCTYPE"), "must not be HTML");
    assert!(body.contains("\"error\""));
    assert!(body.contains("render failed"));
    assert!(body.contains("invalid_artifact"), "kind surfaced: {body}");
}

#[test]
fn plain_respond_route_stays_json() {
    let app = build();
    let (status, wire) = roundtrip_raw(&*app, "GET", "/data", &[], "");
    assert_eq!(status, 200);
    let (head, body) = split(&wire);
    assert!(
        head.contains("content-type: application/json"),
        "head: {head}"
    );
    // existing `Respond { body: String }` shape: `{"body":"ok"}` — unchanged by the render seam.
    assert!(body.contains("{\"body\":\"ok\"}"), "body: {body}");
}
