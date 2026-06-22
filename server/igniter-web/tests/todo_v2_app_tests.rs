// igniter-web/tests/todo_v2_app_tests.rs — LAB-IGNITER-WEB-TODO-V2-APP-P23
// App-pressure proof: a second, account-scoped Todo app exercising the whole proven IgWeb stack
// (scope + resource + route-level `via` + composite guard + idempotent mutating routes) runs through the
// generic runner (`build_app_from_dir` → ServerApp) with ZERO authored Rust runner. Loopback only.

use igniter_server::protocol::ServerApp;
use igniter_web::runner::build_app_from_dir;
use igniter_web::testkit::roundtrip;
use serde_json::json;
use std::path::PathBuf;
use std::sync::Arc;

fn v2_dir() -> PathBuf {
    PathBuf::from(format!(
        "{}/examples/todo_v2_app",
        env!("CARGO_MANIFEST_DIR")
    ))
}

fn build() -> Arc<dyn ServerApp + Send + Sync> {
    build_app_from_dir(&v2_dir())
        .expect("build examples/todo_v2_app from igweb.toml (zero authored Rust)")
        .0
}

#[test]
fn todo_v2_loopback_behaviors() {
    let app = build();

    // 1. health
    let (s, b) = roundtrip(&*app, "GET", "/health", &[], "");
    assert_eq!(s, 200);
    assert_eq!(b["body"], json!("ok"));

    // 2. index — the account context (capture 1) threaded through the composite guard into the handler.
    let (s, b) = roundtrip(&*app, "GET", "/accounts/7/todos", &[], "");
    assert_eq!(s, 200);
    assert_eq!(
        b["body"],
        json!("7"),
        "account context reached AccountTodoIndex"
    );

    // 3. show — the todo context (capture 2) threaded through the two-capture composite guard. The
    //    account is co-carried in the same TodoCtx (compile-enforced; independently proven by #2/#5).
    let (s, b) = roundtrip(&*app, "GET", "/accounts/7/todos/42", &[], "");
    assert_eq!(s, 200);
    assert_eq!(
        b["body"],
        json!("42"),
        "todo context reached AccountTodoShow"
    );

    // 4. create without idempotency-key → keyless 400 (guard outermost, before the via match).
    assert_eq!(
        roundtrip(&*app, "POST", "/accounts/7/todos", &[], "{}").0,
        400
    );

    // 5. create with key → 202 InvokeEffect target `todo-create`, key preserved.
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
    assert!(
        b.get("capability_id").is_none(),
        "no effect identity smuggled"
    );
    assert!(b.get("scope").is_none());

    // 6. done without key → 400.
    assert_eq!(
        roundtrip(&*app, "POST", "/accounts/7/todos/42/done", &[], "{}").0,
        400
    );

    // 7. done with key → 202 InvokeEffect target `todo-done`, key preserved.
    let (s, b) = roundtrip(
        &*app,
        "POST",
        "/accounts/7/todos/42/done",
        &[("idempotency-key", "evt-2")],
        "{}",
    );
    assert_eq!(s, 202);
    assert_eq!(b["target"], json!("todo-done"));
    assert_eq!(b["idempotency_key"], json!("evt-2"));

    // 8. unknown sub-path under the account scope → 404.
    assert_eq!(
        roundtrip(&*app, "GET", "/accounts/7/missing", &[], "").0,
        404
    );

    // 9. wrong method on a known path → 405 (DELETE on the /todos collection, which only has GET+POST).
    assert_eq!(
        roundtrip(&*app, "DELETE", "/accounts/7/todos", &[], "").0,
        405
    );
}
