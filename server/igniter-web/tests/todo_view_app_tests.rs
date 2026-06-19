// igniter-web/tests/todo_view_app_tests.rs — LAB-TODOAPP-VIEW-MANIFEST-P2
// Proves the JSON-first TodoApp view path end-to-end: authored `.igweb` view routes + `.ig` handlers
// build a typed `View` descriptor returned via `RespondView`, and the loopback response body root IS
// that clean view JSON object — NOT a `{"body": "<escaped-json>"}` double-wrap. Fake data, no DB, no Rust.

use igniter_web::runner::check_app_dir;
use igniter_web::testkit::roundtrip;
use igniter_web::{build_igweb_app, IgWebBuildInput};
use igniter_server::protocol::ServerApp;
use serde_json::json;
use std::path::PathBuf;
use std::sync::Arc;

fn dir() -> PathBuf {
    PathBuf::from(format!("{}/examples/todo_view_app", env!("CARGO_MANIFEST_DIR")))
}

fn sources() -> Vec<PathBuf> {
    ["todo_views.ig", "routes.igweb"]
        .iter()
        .map(|f| dir().join(f))
        .collect()
}

fn build() -> Arc<dyn ServerApp + Send + Sync> {
    build_igweb_app(IgWebBuildInput {
        sources: sources(),
        entry: "Serve".into(),
    })
    .expect("build todo_view_app from authored files")
}

#[test]
fn builds_from_manifest_with_no_authored_rust() {
    // The runner builds the app from igweb.toml alone (no per-app Rust) — same path `igweb-serve` uses.
    let report = check_app_dir(&dir()).expect("check_app_dir must build the view app");
    assert_eq!(report.entry, "Serve");
}

#[test]
fn index_view_body_root_is_the_clean_view_object() {
    let app = build();
    let (status, body) = roundtrip(&*app, "GET", "/", &[], "");
    assert_eq!(status, 200);

    // The body ROOT is the View descriptor — recognizable structured fields, nested items array.
    assert_eq!(body["kind"], json!("todo_index"));
    assert_eq!(body["title"], json!("Todos"));
    assert_eq!(body["items"][0]["key"], json!("1"));
    assert_eq!(body["items"][0]["label"], json!("Buy milk"));
    assert_eq!(body["items"][1]["key"], json!("2"));
    assert_eq!(body["items"][1]["label"], json!("Write the spec"));

    // NOT double-wrapped (`{"body": "..."}`) and NOT a stringified JSON document.
    assert!(body.get("body").is_none(), "must not be {{\"body\": ...}}: {body}");
    assert!(body.is_object(), "root must be a JSON object, not a string: {body}");
    // Plain records serialize clean — no VM variant discriminants leak into the view root.
    assert!(body.get("__arm").is_none(), "no __arm in view root: {body}");
    assert!(body.get("__variant").is_none(), "no __variant in view root: {body}");
}

#[test]
fn detail_view_uses_path_param() {
    let app = build();
    let (status, body) = roundtrip(&*app, "GET", "/todos/42", &[], "");
    assert_eq!(status, 200);
    assert_eq!(body["kind"], json!("todo_detail"));
    assert_eq!(body["items"][0]["key"], json!("42")); // captured todo_id reached the view
}

#[test]
fn alias_route_serves_same_index_view() {
    let app = build();
    let (status, body) = roundtrip(&*app, "GET", "/todos", &[], "");
    assert_eq!(status, 200);
    assert_eq!(body["kind"], json!("todo_index"));
}

#[test]
fn api_data_route_keeps_old_respond_shape() {
    // Contrast: a plain `Respond { body: String }` route still wraps as `{"body": ...}` — the view
    // seam is additive, it does not change the existing data-response shape.
    let app = build();
    let (status, body) = roundtrip(&*app, "GET", "/api/health", &[], "");
    assert_eq!(status, 200);
    assert_eq!(body["body"], json!("ok"));
}

#[test]
fn unknown_and_method_refusals_unchanged() {
    let app = build();
    assert_eq!(roundtrip(&*app, "GET", "/missing", &[], "").0, 404);
    assert_eq!(roundtrip(&*app, "POST", "/", &[], "").0, 405);
}
