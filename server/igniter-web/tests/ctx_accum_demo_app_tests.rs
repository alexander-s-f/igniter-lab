// igniter-web/tests/ctx_accum_demo_app_tests.rs — LAB-IGNITER-WEB-CONTEXT-ACCUMULATION-P27
// Runtime proof: depth-2 same-name `guard ctx` accumulation runs through the generic runner with ZERO
// authored Rust. The app guard builds a Ctx; the scope guard enriches it with the account; the enriched
// context reaches the handlers (proven via response bodies / effect input). Loopback only.

use igniter_server::protocol::ServerApp;
use igniter_web::runner::build_app_from_dir;
use igniter_web::testkit::roundtrip;
use serde_json::json;
use std::path::PathBuf;
use std::sync::Arc;

fn dir() -> PathBuf {
    PathBuf::from(format!(
        "{}/examples/ctx_accum_demo_app",
        env!("CARGO_MANIFEST_DIR")
    ))
}

fn build() -> Arc<dyn ServerApp + Send + Sync> {
    build_app_from_dir(&dir())
        .expect("build examples/ctx_accum_demo_app (depth-2 accumulation, zero authored Rust)")
        .0
}

#[test]
fn ctx_accum_demo_loopback_behaviors() {
    let app = build();

    // index: the scope guard enriched `ctx.account_id` from capture 1; TodoIndex echoes it — proving the
    // accumulated context (app guard → scope guard → handler) reached the handler with the latest value.
    let (s, b) = roundtrip(&*app, "GET", "/accounts/7/todos", &[], "");
    assert_eq!(s, 200);
    assert_eq!(b["body"], json!("7"), "accumulated account context reached TodoIndex");

    // show: same accumulated ctx + the unconsumed todo_id capture reach TodoShow.
    let (s, b) = roundtrip(&*app, "GET", "/accounts/7/todos/42", &[], "");
    assert_eq!(s, 200);
    assert_eq!(b["body"], json!("42"), "todo_id capture reached TodoShow");

    // create without key → keyless 400 outermost (before the whole accumulation chain).
    assert_eq!(
        roundtrip(&*app, "POST", "/accounts/7/todos", &[], "{}").0,
        400
    );

    // create with key → 202 InvokeEffect; the effect input echoes the accumulated account.
    let (s, b) = roundtrip(
        &*app,
        "POST",
        "/accounts/7/todos",
        &[("idempotency-key", "evt-1")],
        "{}",
    );
    assert_eq!(s, 202);
    assert_eq!(b["target"], json!("todo-create"));
    assert_eq!(b["idempotency_key"], json!("evt-1"));

    // 404 / 405 preserved.
    assert_eq!(roundtrip(&*app, "GET", "/accounts/7/missing", &[], "").0, 404);
    assert_eq!(roundtrip(&*app, "DELETE", "/accounts/7/todos", &[], "").0, 405);
}
