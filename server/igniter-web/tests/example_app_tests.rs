// igniter-web/tests/example_app_tests.rs — LAB-IGNITER-WEB-EXAMPLE-APP-P9
// Proves the on-disk example app (examples/todo_app/*) builds via build_igweb_app and serves over
// real loopback. Uses the SAME authored files the `todo_server` example runs — not inline strings.

use igniter_server::middleware::ServerAppExt;
use igniter_server::protocol::ServerApp;
use igniter_web::testkit::roundtrip;
use igniter_web::{build_igweb_app, IgWebBuildInput};
use serde_json::json;
use std::path::PathBuf;
use std::sync::Arc;

fn example_sources() -> Vec<PathBuf> {
    // P10: no `web_types.ig` — the builder injects the shared IgWebPrelude.
    ["todo_handlers.ig", "routes.igweb"]
        .iter()
        .map(|f| {
            PathBuf::from(format!(
                "{}/examples/todo_app/{}",
                env!("CARGO_MANIFEST_DIR"),
                f
            ))
        })
        .collect()
}

fn build() -> Arc<dyn ServerApp + Send + Sync> {
    build_igweb_app(IgWebBuildInput {
        sources: example_sources(),
        entry: "Serve".into(),
    })
    .expect("build example todo app from authored files")
}

#[test]
fn example_files_exist_on_disk() {
    for p in example_sources() {
        assert!(
            p.exists(),
            "authored example file must exist: {}",
            p.display()
        );
    }
}

#[test]
fn example_health_and_index() {
    let app = build();
    assert_eq!(roundtrip(&*app, "GET", "/health", &[], "").0, 200);
    assert_eq!(roundtrip(&*app, "GET", "/todos", &[], "").0, 200);
}

#[test]
fn example_route_param() {
    let app = build();
    let (status, body) = roundtrip(&*app, "GET", "/todos/42", &[], "");
    assert_eq!(status, 200);
    assert_eq!(
        body["body"],
        json!("42"),
        "path param via generated regexp/capture"
    );
}

#[test]
fn example_keyless_mutation_is_400() {
    let app = build();
    assert_eq!(roundtrip(&*app, "POST", "/todos/42/done", &[], "").0, 400);
}

#[test]
fn example_keyed_mutation_is_invoke_effect() {
    let app = build();
    let (status, body) = roundtrip(
        &*app,
        "POST",
        "/todos/42/done",
        &[("idempotency-key", "evt-1")],
        "{}",
    );
    assert_eq!(status, 202);
    assert_eq!(body["target"], json!("todo-done"));
    assert_eq!(body["idempotency_key"], json!("evt-1"));
    assert!(
        body.get("capability_id").is_none(),
        "no privileged effect identity"
    );
    assert!(body.get("scope").is_none());
}

#[test]
fn example_unknown_and_method_refusals() {
    let app = build();
    assert_eq!(roundtrip(&*app, "GET", "/missing", &[], "").0, 404);
    assert_eq!(roundtrip(&*app, "POST", "/health", &[], "").0, 405);
}

#[test]
fn example_composes_with_middleware() {
    // the example app composes under P8 wrappers like any ServerApp.
    let stack = build().with_auth("tok");
    assert_eq!(
        roundtrip(&stack, "GET", "/health", &[], "").0,
        401,
        "auth short-circuits"
    );
    assert_eq!(
        roundtrip(
            &stack,
            "GET",
            "/health",
            &[("authorization", "Bearer tok")],
            ""
        )
        .0,
        200
    );
}
