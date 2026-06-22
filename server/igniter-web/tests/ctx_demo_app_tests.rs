// igniter-web/tests/ctx_demo_app_tests.rs — LAB-IGNITER-WEB-CONTEXT-COMPOSITION-P26
// Runtime proof: an IgWeb app using an app-level `let` + a scope-level `guard` (inherited by nested
// resource routes, explicit handler args) runs through the generic runner with ZERO authored Rust, and
// the hoisted context + guard value reach the handlers. Loopback only.

use igniter_server::protocol::ServerApp;
use igniter_web::runner::build_app_from_dir;
use igniter_web::testkit::roundtrip;
use serde_json::json;
use std::path::PathBuf;
use std::sync::Arc;

fn dir() -> PathBuf {
    PathBuf::from(format!(
        "{}/examples/ctx_demo_app",
        env!("CARGO_MANIFEST_DIR")
    ))
}

fn build() -> Arc<dyn ServerApp + Send + Sync> {
    build_app_from_dir(&dir())
        .expect("build examples/ctx_demo_app (let/guard, zero authored Rust)")
        .0
}

#[test]
fn ctx_demo_loopback_behaviors() {
    let app = build();

    // index: the scope `guard account` (built from capture 1) threaded into TodoIndex, whose body echoes
    // the account — proving the inherited guard value reached the handler via explicit args.
    let (s, b) = roundtrip(&*app, "GET", "/accounts/7/todos", &[], "");
    assert_eq!(s, 200);
    assert_eq!(
        b["body"],
        json!("7"),
        "guard account context reached TodoIndex"
    );

    // show: same guard + the unconsumed `todo_id` capture reach TodoShow.
    let (s, b) = roundtrip(&*app, "GET", "/accounts/7/todos/42", &[], "");
    assert_eq!(s, 200);
    assert_eq!(b["body"], json!("42"), "todo_id capture reached TodoShow");

    // create without key → keyless 400 outermost (before the guard runs).
    assert_eq!(
        roundtrip(&*app, "POST", "/accounts/7/todos", &[], "{}").0,
        400
    );

    // create with key → 202 InvokeEffect; the effect input echoes the guard account.
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

    // unknown sub-path → 404; wrong method on a known path → 405.
    assert_eq!(
        roundtrip(&*app, "GET", "/accounts/7/missing", &[], "").0,
        404
    );
    assert_eq!(
        roundtrip(&*app, "DELETE", "/accounts/7/todos", &[], "").0,
        405
    );
}
