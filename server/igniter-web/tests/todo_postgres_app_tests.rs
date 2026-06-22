// igniter-web/tests/todo_postgres_app_tests.rs — LAB-TODOAPP-API-SHAPE-P2
// The first "postgres-shaped" Todo API: routes + composite `via` guards + RELATIONAL QueryPlan/WriteIntent
// contracts, authored as `.igweb` + `.ig` with ZERO authored Rust, built through the generic runner
// (`build_app_from_dir` → ServerApp) and served over loopback. Reads are SHAPED (relational contracts
// compile), writes are OBSERVED (`InvokeEffect`, target only) — the runner executes NO Postgres IO.

use igniter_server::protocol::ServerApp;
use igniter_web::runner::{build_app_from_dir, check_app_dir};
use igniter_web::testkit::roundtrip;
use serde_json::json;
use std::path::PathBuf;
use std::sync::Arc;

fn app_dir() -> PathBuf {
    PathBuf::from(format!(
        "{}/examples/todo_postgres_app",
        env!("CARGO_MANIFEST_DIR")
    ))
}

fn build() -> Arc<dyn ServerApp + Send + Sync> {
    build_app_from_dir(&app_dir())
        .expect("build examples/todo_postgres_app from igweb.toml (zero authored Rust)")
        .0
}

// ── 1 + 2: app files exist, build, and `check` succeeds with no socket ─────────────────────────

#[test]
fn app_files_exist_and_check_succeeds() {
    let dir = app_dir();
    for f in ["igweb.toml", "routes.igweb", "todo_handlers.ig"] {
        assert!(dir.join(f).is_file(), "missing app file: {f}");
    }
    // check = dry build, no socket. Proves the combined routing + relational module compiles + loads.
    let report = check_app_dir(&dir).expect("igweb-serve check examples/todo_postgres_app");
    assert_eq!(report.entry, "Serve");
    assert_eq!(report.source_count, 2);
}

// ── 3: loopback behavior table (observed, no DB) ───────────────────────────────────────────────

#[test]
fn loopback_behaviors() {
    let app = build();

    // health
    let (s, b) = roundtrip(&*app, "GET", "/health", &[], "");
    assert_eq!(s, 200);
    assert_eq!(b["body"], json!("ok"));

    // index — AccountTodoIndex now emits ReadThen (requires machine-mode runner); the sync path
    // returns 500 for unhandled decision tags. The machine-mode path is proven in
    // todo_postgres_async_runner_smoke_tests (LAB-TODOAPP-API-ASYNC-RUNNER-SMOKE-P10).
    let (s, _) = roundtrip(&*app, "GET", "/accounts/7/todos", &[], "");
    assert_eq!(s, 500, "index emits ReadThen → sync path returns 500 (machine mode only)");

    // show — todo context (capture 2) threaded through the two-capture guard.
    let (s, b) = roundtrip(&*app, "GET", "/accounts/7/todos/42", &[], "");
    assert_eq!(s, 200);
    assert_eq!(b["body"], json!("42"));

    // create without idempotency-key → keyless 400 (guard outermost, before the via match).
    assert_eq!(
        roundtrip(&*app, "POST", "/accounts/7/todos", &[], "{}").0,
        400
    );

    // create with key → 202 observed InvokeEffect target `todo-create`, key preserved, no identity.
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

    // done without key → 400; with key → 202 observed InvokeEffect target `todo-done`.
    assert_eq!(
        roundtrip(&*app, "POST", "/accounts/7/todos/42/done", &[], "{}").0,
        400
    );
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

    // unmatched path → 404; wrong method on a known pattern → 405.
    assert_eq!(roundtrip(&*app, "GET", "/missing", &[], "").0, 404);
    assert_eq!(
        roundtrip(&*app, "DELETE", "/accounts/7/todos", &[], "").0,
        405
    );
}

// ── 4 + 5: relational contracts are present, and the authored app carries no SQL/identity surface ─

#[test]
fn relational_contracts_present_and_no_forbidden_surface() {
    let handlers = std::fs::read_to_string(app_dir().join("todo_handlers.ig")).unwrap();

    // postgres-shaped: the relational intent contracts are declared (and compiled via test #1's build).
    for needle in [
        "type QueryPlan {",
        "type WriteIntent {",
        "pure contract ListTodosByAccount",
        "pure contract FindTodo",
        "pure contract BuildCreateTodoIntent",
        "pure contract BuildMarkTodoDoneIntent",
        "output plan : QueryPlan",
        "output intent : WriteIntent",
    ] {
        assert!(
            handlers.contains(needle),
            "handlers must declare `{needle}`"
        );
    }

    // boundary: authored app (routes + handlers) carries no raw SQL, capability ids, scopes, DSNs, secrets.
    // Check the CODE only — strip `--`/`#` line comments (prose legitimately discusses the boundary).
    let routes = std::fs::read_to_string(app_dir().join("routes.igweb")).unwrap();
    let toml = std::fs::read_to_string(app_dir().join("igweb.toml")).unwrap();
    let strip = |src: &str| -> String {
        src.lines()
            .map(|l| {
                let l = l.split("--").next().unwrap_or("");
                l.split('#').next().unwrap_or("")
            })
            .collect::<Vec<_>>()
            .join("\n")
    };
    let code = format!("{}\n{}\n{}", strip(&handlers), strip(&routes), strip(&toml)).to_lowercase();
    for forbidden in [
        "select ",
        "insert into",
        "update ",
        "delete from",
        "create table",
        "capability_id",
        "io.postgres",
        "passport",
        "dsn",
        "password",
        "secret",
        "[effects]",
    ] {
        assert!(
            !code.contains(forbidden),
            "authored app must not contain `{forbidden}`"
        );
    }
}
