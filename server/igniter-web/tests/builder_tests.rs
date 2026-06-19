// igniter-web/tests/builder_tests.rs — LAB-IGNITER-WEB-CRATE-P8
// Direct tests for the IgWeb builder in its new lab home.

use igniter_web::testkit::{build_todo_app, roundtrip, HANDLERS};
use igniter_web::{build_igweb_app, IgWebBuildError, IgWebBuildInput};
use serde_json::json;
use std::path::PathBuf;

fn write_dir(tag: &str, files: &[(&str, &str)]) -> Vec<PathBuf> {
    let dir = std::env::temp_dir().join(format!("igweb_ct_{}_{}", std::process::id(), tag));
    std::fs::create_dir_all(&dir).unwrap();
    files
        .iter()
        .map(|(name, content)| {
            let p = dir.join(name);
            std::fs::write(&p, content).unwrap();
            p
        })
        .collect()
}

#[test]
fn builds_health_app() {
    let app = build_todo_app("c_health");
    assert_eq!(roundtrip(&*app, "GET", "/health", &[], "").0, 200);
}

#[test]
fn preserves_route_param_id() {
    let app = build_todo_app("c_param");
    let (status, body) = roundtrip(&*app, "GET", "/todos/42", &[], "");
    assert_eq!(status, 200);
    assert_eq!(
        body["body"],
        json!("42"),
        "id flows via generated regexp/capture"
    );
}

#[test]
fn emits_logical_invoke_effect_without_identity() {
    let app = build_todo_app("c_effect");
    let (status, body) = roundtrip(
        &*app,
        "POST",
        "/todos/42/done",
        &[("idempotency-key", "k-8")],
        "{}",
    );
    assert_eq!(status, 202);
    assert_eq!(body["target"], json!("todo-done"));
    assert_eq!(body["idempotency_key"], json!("k-8"));
    assert!(body.get("capability_id").is_none());
    assert!(body.get("scope").is_none());
}

#[test]
fn lowering_error_is_structured() {
    // malformed route on line 2 → parse error fires during the loop, before the handlers check.
    let bad = "app X entry Serve {\n  route GET /todos -> Health\n}\n";
    let paths = write_dir(
        "c_lowerr",
        &[("handlers.ig", HANDLERS), ("routes.igweb", bad)],
    );
    match build_igweb_app(IgWebBuildInput {
        sources: paths,
        entry: "Serve".into(),
    }) {
        Err(IgWebBuildError::Lower { line, .. }) => assert_eq!(line, 2),
        Err(e) => panic!("expected Lower error, got {e:?}"),
        Ok(_) => panic!("expected Lower error, got Ok"),
    }
}

#[test]
fn compile_error_is_structured() {
    let broken = format!("{HANDLERS}\npure contract {{ input req : Request }}\n");
    let valid =
        "app X entry Serve {\n  handlers TodoHandlers\n  route GET \"/health\" -> Health\n}\n";
    let paths = write_dir(
        "c_comperr",
        &[("handlers.ig", &broken), ("routes.igweb", valid)],
    );
    match build_igweb_app(IgWebBuildInput {
        sources: paths,
        entry: "Serve".into(),
    }) {
        Err(IgWebBuildError::Load(msg)) => assert!(!msg.is_empty()),
        Err(e) => panic!("expected Load error, got {e:?}"),
        Ok(_) => panic!("expected Load error, got Ok"),
    }
}
