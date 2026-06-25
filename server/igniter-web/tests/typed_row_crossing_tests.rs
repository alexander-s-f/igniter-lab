//! typed_row_crossing_tests.rs — LAB-IGNITER-DATA-PROJECTION-TYPED-ROW-CROSSING-P6
//!
//! The mainline step after the P1–P5 readiness series: prove `rows_json : String` is no longer the only
//! read-continuation boundary. The host runs the fake `PostgresReadExecutor`, then **materializes** the typed
//! rows into a total + typed `Collection[TodoRow]` (records, not a string) plus a `DatasetMeta` sidecar, and
//! the `.ig` continuation does ordinary typed record work over them.
//!
//!   ListTypedTodos -> QueryPlan
//!     -> StagedReadHost::execute_typed (fake PostgresReadExecutor + host materializer/reconciler)
//!     -> continuation receives `rows : Collection[TodoRow]` (+ `meta : DatasetMeta`)
//!     -> typed field access + HOFs (filter on Bool, fold on Integer, map + call_contract)
//!
//! Both ends are REAL: the `.ig` is dispatched via `IgniterMachine::dispatch` (async, direct — no `block_on`
//! nesting), and the host crossing runs through `StagedReadHost::execute_typed`. NO live Postgres, NO new
//! `.igweb` syntax, NO VM/compiler change. The existing `rows_json` path is exercised side-by-side to prove
//! it stays green. Gated behind `--features machine`.
#![cfg(feature = "machine")]

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::CapabilityExecutorRegistry;
use igniter_machine::machine::IgniterMachine;
use igniter_machine::postgres_read::{
    FakePostgresAdapter, PostgresReadExecutor, PostgresReadPolicy, PostgresReadValueKind,
};
use igniter_server::protocol::{ServerRequest, PROTOCOL_VERSION};
use igniter_web::read_dispatch::{StagedReadHost, StagedReadResult, TypedReadResult};
use igniter_web::read_materialize::{reconcile_projection, AppFieldType, ProjectionSpec};
use serde_json::{json, Value};
use std::sync::Arc;

const FIXTURE: &str = include_str!("fixtures/typed_row_crossing/typed_row_crossing.ig");
const READ_CAP: &str = "IO.PostgresRead";

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}

/// Load the prelude + the typed-row fixture into a fresh machine (every contract registered + dispatchable).
fn load_machine() -> IgniterMachine {
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let dir = std::env::temp_dir().join(format!(
        "igweb_typedrow_p6_{}_{}",
        std::process::id(),
        stamp
    ));
    std::fs::create_dir_all(&dir).unwrap();
    let pl = dir.join("prelude.ig");
    let fx = dir.join("typed_row_crossing.ig");
    std::fs::write(&pl, igniter_compiler::igweb::PRELUDE_SOURCE).unwrap();
    std::fs::write(&fx, FIXTURE).unwrap();
    let m = IgniterMachine::new(None, "in_memory").unwrap();
    m.load_program(
        &[
            pl.to_string_lossy().to_string(),
            fx.to_string_lossy().to_string(),
        ],
        "TypedTodoProbe",
    )
    .expect("load typed-row fixture");
    m
}

/// SELECT-only host policy on `todos` with PER-FIELD decode kinds (the schema authority): String columns as
/// `Text`, `done` as `Boolean`, `rank` as `Integer`.
fn typed_policy(cap: i64) -> PostgresReadPolicy {
    use PostgresReadValueKind::*;
    PostgresReadPolicy::new(cap)
        .allow_ops(&["select"])
        .allow_source_typed(
            "todos",
            &[
                ("id", Text),
                ("account_id", Text),
                ("title", Text),
                ("done", Boolean),
                ("rank", Integer),
            ],
        )
}

fn projection() -> Vec<String> {
    ["id", "account_id", "title", "done", "rank"]
        .iter()
        .map(|s| s.to_string())
        .collect()
}

/// The app's declared `TodoRow` shape (in a boot reconciler this is read from the continuation's compiled IR;
/// here the harness supplies it, standing in for that IR-derived shape — verdict: harness-proven).
fn todorow_app_schema() -> Vec<(String, AppFieldType)> {
    vec![
        ("id".into(), AppFieldType::String),
        ("account_id".into(), AppFieldType::String),
        ("title".into(), AppFieldType::String),
        ("done".into(), AppFieldType::Bool),
        ("rank".into(), AppFieldType::Integer),
    ]
}

/// Typed fixture rows — `done` is a real Bool, `rank` a real Integer (the fake adapter preserves JSON types).
fn typed_rows() -> Vec<Value> {
    vec![
        json!({"id": "todo-1", "account_id": "acct-7", "title": "Buy milk",  "done": false, "rank": 10}),
        json!({"id": "todo-2", "account_id": "acct-7", "title": "Write spec", "done": true,  "rank": 20}),
    ]
}

fn make_read_host(adapter: Arc<FakePostgresAdapter>, policy: PostgresReadPolicy) -> StagedReadHost {
    let exec = Arc::new(PostgresReadExecutor::new(READ_CAP, adapter, policy));
    let mut registry = CapabilityExecutorRegistry::new();
    registry.register(exec);
    let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
    StagedReadHost::new(registry, receipts, READ_CAP)
}

fn get_req() -> ServerRequest {
    ServerRequest {
        protocol: PROTOCOL_VERSION.to_string(),
        method: "GET".to_string(),
        path: "/accounts/acct-7/todos".to_string(),
        body: Value::Null,
        correlation_id: Some("typed-row-test".to_string()),
        idempotency_key: None,
        headers: Default::default(),
        query: Default::default(),
    }
}

/// A minimal `Request` JSON for direct `.ig` dispatch (the continuation only field-accesses `rows`/`meta`).
fn min_req() -> Value {
    json!({
        "method": "GET", "path": "/accounts/acct-7/todos", "body": "", "body_kind": "empty",
        "correlation_id": "", "idempotency_key": "", "surrogate_id": "", "body_json": {}, "query": {}
    })
}

/// Author the QueryPlan from the `.ig` query contract, then run it through the host typed read path.
async fn typed_read(
    m: &IgniterMachine,
    host: &StagedReadHost,
    policy: &PostgresReadPolicy,
) -> TypedReadResult {
    let plan = m
        .dispatch("ListTypedTodos", json!({"account_id": "acct-7"}))
        .await
        .unwrap();
    // Sanity: the authored projection names the typed columns the continuation will access.
    assert_eq!(plan["source"], json!("todos"));
    assert_eq!(plan["projection"][4], json!("rank"));
    let spec = ProjectionSpec::from_policy(policy, "todos", &projection());
    host.execute_typed(&plan, &get_req(), &spec).await
}

// ── 1 + 2 + 3 + 4 + 6: the full typed crossing — rows materialize as Collection[TodoRow] + DatasetMeta ──

#[test]
fn typed_rows_cross_as_collection_with_meta() {
    rt().block_on(async {
        let m = load_machine();
        let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", typed_rows()));
        let policy = typed_policy(100);
        let host = make_read_host(adapter.clone(), policy.clone());

        let (rows, meta) = match typed_read(&m, &host, &policy).await {
            TypedReadResult::Rows { rows, meta } => (rows, meta),
            other => panic!(
                "expected typed Rows, got a non-Rows outcome: {}",
                outcome_name(&other)
            ),
        };
        assert_eq!(adapter.query_count(), 1, "exactly one adapter query");

        // DatasetMeta { source, count, truncated } crossed (box 6).
        assert_eq!(meta["source"], json!("todos"));
        assert_eq!(meta["count"], json!(2));
        assert_eq!(
            meta["truncated"],
            json!(false),
            "limit 50 < cap 100 → not truncated"
        );

        // The continuation receives `rows : Collection[TodoRow]` + `meta : DatasetMeta` and does typed work.
        let proof = m
            .dispatch(
                "TypedTodoProbe",
                json!({"req": min_req(), "rows": rows, "meta": meta}),
            )
            .await
            .unwrap();

        assert_eq!(
            proof["total"],
            json!(2),
            "rows crossed as a Collection (box 1)"
        );
        // Bool field access inside filter(rows, r -> r.done == false): only todo-1 is pending (box 3).
        assert_eq!(
            proof["pending"],
            json!(1),
            "Bool filter selected exactly the pending row"
        );
        // Integer field preserved as Integer, not String: fold arithmetic 10 + 20 = 30 (box 4).
        assert_eq!(
            proof["rank_sum"],
            json!(30),
            "rank summed numerically → Integer preserved"
        );
        // String field access via fold/concat over r.title (box 2).
        let titles = proof["titles"].as_str().unwrap();
        assert!(
            titles.contains("Buy milk") && titles.contains("Write spec"),
            "titles: {titles}"
        );
        // DatasetMeta read inside the continuation (box 6).
        assert_eq!(proof["meta_source"], json!("todos"));
        assert_eq!(proof["meta_count"], json!(2));
        assert_eq!(proof["meta_truncated"], json!(false));
    });
}

// ── 5: HOF transform (map + call_contract over a typed row) drives the realistic Decision seam ──────

#[test]
fn typed_continuation_maps_rows_to_view() {
    rt().block_on(async {
        let m = load_machine();
        let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", typed_rows()));
        let policy = typed_policy(100);
        let host = make_read_host(adapter, policy.clone());

        let (rows, meta) = match typed_read(&m, &host, &policy).await {
            TypedReadResult::Rows { rows, meta } => (rows, meta),
            other => panic!("expected typed Rows, got {}", outcome_name(&other)),
        };

        let decision = m
            .dispatch(
                "TypedTodoIndex",
                json!({"req": min_req(), "rows": rows, "meta": meta}),
            )
            .await
            .unwrap();

        // map(pending, r -> call_contract("TodoRowItem", r)) built a typed View from the pending rows.
        assert_eq!(decision["__arm"], json!("RespondView"));
        assert_eq!(decision["status"], json!(200));
        assert_eq!(
            decision["view"]["kind"],
            json!("todos"),
            "view tagged with meta.source"
        );
        let items = decision["view"]["items"].as_array().unwrap();
        assert_eq!(
            items.len(),
            1,
            "only the pending (done==false) row mapped to a ViewItem"
        );
        assert_eq!(
            items[0]["label"],
            json!("Buy milk"),
            "r.title String access through map+call_contract"
        );
        assert_eq!(items[0]["key"], json!("todo-1"));
    });
}

// ── empty result set is the APP's product decision over the typed collection (404, not infra) ──────

#[test]
fn empty_typed_rows_are_app_not_found_404() {
    rt().block_on(async {
        let m = load_machine();
        // allowlisted source with no rows → definite empty (Succeeded, 0 rows) → materializes to `[]`.
        let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", vec![]));
        let policy = typed_policy(100);
        let host = make_read_host(adapter, policy.clone());

        let (rows, meta) = match typed_read(&m, &host, &policy).await {
            TypedReadResult::Rows { rows, meta } => (rows, meta),
            other => panic!("expected typed Rows (empty), got {}", outcome_name(&other)),
        };
        assert_eq!(rows.as_array().unwrap().len(), 0);
        assert_eq!(meta["count"], json!(0));

        let decision = m
            .dispatch(
                "TypedTodoIndex",
                json!({"req": min_req(), "rows": rows, "meta": meta}),
            )
            .await
            .unwrap();
        assert_eq!(decision["__arm"], json!("Respond"));
        assert_eq!(
            decision["status"],
            json!(404),
            "empty typed rows → app-owned 404"
        );
    });
}

// ── truncated read → meta.truncated == true (the actionable provenance signal) ──────────────────────

#[test]
fn clamped_read_crosses_truncated_meta() {
    rt().block_on(async {
        let m = load_machine();
        let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", typed_rows()));
        // cap of 1 clamps the contract's limit:50 → effective 1, row_limit_clamped = true.
        let policy = typed_policy(1);
        let host = make_read_host(adapter, policy.clone());

        let meta = match typed_read(&m, &host, &policy).await {
            TypedReadResult::Rows { meta, .. } => meta,
            other => panic!("expected typed Rows, got {}", outcome_name(&other)),
        };
        assert_eq!(
            meta["truncated"],
            json!(true),
            "clamped read sets meta.truncated"
        );
        assert_eq!(meta["count"], json!(1), "only the capped row count");
    });
}

// ── 7: a row missing a required field is refused BEFORE continuation dispatch (host-owned) ──────────

#[test]
fn missing_field_is_refused_before_dispatch() {
    rt().block_on(async {
        let m = load_machine();
        // The stored row lacks `done`; the fake projects only present fields, so it crosses without `done`.
        let bad =
            vec![json!({"id": "todo-1", "account_id": "acct-7", "title": "Buy milk", "rank": 10})];
        let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", bad));
        let policy = typed_policy(100);
        let host = make_read_host(adapter, policy.clone());

        match typed_read(&m, &host, &policy).await {
            TypedReadResult::SchemaMismatch(e) => {
                assert!(
                    e.contains("missing required field `done`"),
                    "stable host error: {e}"
                );
            }
            other => panic!(
                "expected SchemaMismatch (host-owned), got {}",
                outcome_name(&other)
            ),
        }
        // No partial app response: the continuation is never dispatched (we returned before it).
    });
}

// ── 8: a wrong scalar kind is refused BEFORE continuation dispatch (the P2 silent-wrong hazard) ─────

#[test]
fn wrong_scalar_kind_is_refused_before_dispatch() {
    rt().block_on(async {
        let m = load_machine();
        // `done` declared Boolean but the row carries the STRING "false" — would compare silently-wrong in `.ig`.
        let bad = vec![
            json!({"id": "todo-1", "account_id": "acct-7", "title": "Buy milk", "done": "false", "rank": 10}),
        ];
        let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", bad));
        let policy = typed_policy(100);
        let host = make_read_host(adapter, policy.clone());

        match typed_read(&m, &host, &policy).await {
            TypedReadResult::SchemaMismatch(e) => {
                assert!(e.contains("`done` wrong kind"), "stable host error: {e}");
            }
            other => panic!("expected SchemaMismatch, got {}", outcome_name(&other)),
        }
    });
}

// ── P3 §3: host decode-kind ⇎ TodoRow type drift is caught by reconciliation (not silent-wrong rows) ─

#[test]
fn reconciliation_catches_kind_drift() {
    use PostgresReadValueKind::*;
    // Matched schema reconciles clean.
    let good = ProjectionSpec::from_policy(&typed_policy(100), "todos", &projection());
    assert!(reconcile_projection(&good, &todorow_app_schema()).is_ok());

    // Host decodes `done` as Text, but TodoRow.done : Bool → ProjectionSchemaDrift (deploy-time fault).
    let drift_policy = PostgresReadPolicy::new(100)
        .allow_ops(&["select"])
        .allow_source_typed(
            "todos",
            &[
                ("id", Text),
                ("account_id", Text),
                ("title", Text),
                ("done", Text), // ← drift vs TodoRow.done : Bool
                ("rank", Integer),
            ],
        );
    let drift = ProjectionSpec::from_policy(&drift_policy, "todos", &projection());
    let err = reconcile_projection(&drift, &todorow_app_schema()).unwrap_err();
    assert!(err.starts_with("ProjectionSchemaDrift"), "{err}");
    assert!(err.contains("`done`"), "{err}");
}

// ── 9: the existing `rows_json : String` path stays green side-by-side (explicit compatibility) ─────

#[test]
fn legacy_rows_json_path_still_works() {
    rt().block_on(async {
        let m = load_machine();
        let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", typed_rows()));
        let policy = typed_policy(100);
        let host = make_read_host(adapter, policy);

        let plan = m
            .dispatch("ListTypedTodos", json!({"account_id": "acct-7"}))
            .await
            .unwrap();
        // The original stringly `execute` is untouched — same plan still crosses as a JSON-array string.
        match host.execute(&plan, &get_req()).await {
            StagedReadResult::Rows(s) => {
                assert!(
                    s.starts_with('[') && s.contains("todo-1"),
                    "rows_json string: {s}"
                );
            }
            other => panic!("expected legacy Rows(String), got {}", staged_name(&other)),
        }
    });
}

// ── the authored fixture carries no capability id / scope / DSN / raw SQL ───────────────────────────

#[test]
fn fixture_has_no_forbidden_surface() {
    let code = FIXTURE
        .lines()
        .map(|l| l.split("--").next().unwrap_or(""))
        .collect::<Vec<_>>()
        .join("\n")
        .to_lowercase();
    for forbidden in [
        "select ",
        "insert into",
        "where ",
        "capability_id",
        "io.postgres",
        "passport",
        "dsn",
        "postgres://",
        "scope",
    ] {
        assert!(
            !code.contains(forbidden),
            "authored .ig must not contain `{forbidden}`"
        );
    }
    // The only DB-ish token is the logical `source` field of QueryPlan.
    assert!(FIXTURE.contains("source: \"todos\""));
}

// ── small helpers for readable panic messages ───────────────────────────────────────────────────────

fn outcome_name(r: &TypedReadResult) -> String {
    match r {
        TypedReadResult::Rows { .. } => "Rows".into(),
        TypedReadResult::Denied(m) => format!("Denied({m})"),
        TypedReadResult::HostError(m) => format!("HostError({m})"),
        TypedReadResult::SchemaMismatch(m) => format!("SchemaMismatch({m})"),
    }
}

fn staged_name(r: &StagedReadResult) -> String {
    match r {
        StagedReadResult::Rows(_) => "Rows".into(),
        StagedReadResult::Denied(m) => format!("Denied({m})"),
        StagedReadResult::HostError(m) => format!("HostError({m})"),
    }
}
