//! igniter-web/tests/todo_postgres_api_write_tests.rs — LAB-TODOAPP-API-WRITE-P4
//!
//! Tightens the product WRITE shape: the mutating route handlers now build a structured `WriteIntent` via
//! the app's command contracts (`BuildCreateTodoIntent` / `BuildMarkTodoDoneIntent`) — the product source
//! of write meaning — and (LAB-IGNITER-WEB-STRUCTURED-EFFECT-INPUT-P7) carry the WHOLE structured `intent`
//! across the seam as `InvokeEffect.input` (`intent.key` is still the separate idempotency field). The host
//! execution seam is UNCHANGED: keyed routes still execute through `MachineEffectHost` (proven by
//! `todo_postgres_effect_host_tests`).
//!
//! This file proves the command contracts themselves dispatch and produce the expected `WriteIntent`
//! records, that the handlers call them, and (P7) that the structured intent maps cleanly to
//! `PostgresWriteIntent.values` via `from_args`. Gated `--features machine`. NO live Postgres, NO new
//! syntax, NO capability identity in the app.
#![cfg(feature = "machine")]

use igniter_machine::machine::IgniterMachine;
use igniter_machine::postgres_write::PostgresWriteIntent;
use serde_json::json;
use std::path::PathBuf;

fn app_dir() -> PathBuf {
    PathBuf::from(format!(
        "{}/examples/todo_postgres_app",
        env!("CARGO_MANIFEST_DIR")
    ))
}

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}

/// Load the prelude + the PRODUCT app's `todo_handlers.ig` (its own authored contracts).
fn load_app_contracts() -> IgniterMachine {
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let dir = std::env::temp_dir().join(format!(
        "igweb_api_write_p4_{}_{}",
        std::process::id(),
        stamp
    ));
    std::fs::create_dir_all(&dir).unwrap();
    let pl = dir.join("prelude.ig");
    std::fs::write(&pl, igniter_compiler::igweb::PRELUDE_SOURCE).unwrap();
    let handlers = app_dir().join("todo_handlers.ig");
    let m = IgniterMachine::new(None, "in_memory").unwrap();
    m.load_program(
        &[
            pl.to_string_lossy().to_string(),
            handlers.to_string_lossy().to_string(),
        ],
        "BuildCreateTodoIntent",
    )
    .expect("load todo_postgres_app/todo_handlers.ig contracts");
    m
}

// ── 1: the product command contracts dispatch and produce structured WriteIntent records ─────────

#[test]
fn command_contracts_produce_write_intents() {
    rt().block_on(async {
        let m = load_app_contracts();

        // P36: create takes a host-minted `surrogate_id` (NOT the idempotency key) and the business
        // `key` is the product-prefixed surrogate — decoupled from the idempotency key.
        let create = m
            .dispatch(
                "BuildCreateTodoIntent",
                json!({"account_id": "acct-7", "surrogate_id": "abc123", "title": "Buy milk"}),
            )
            .await
            .unwrap();
        assert_eq!(create["operation"], json!("insert"));
        assert_eq!(create["target"], json!("todos"));
        assert_eq!(
            create["key"],
            json!("todo_abc123"),
            "intent key = product-prefixed host surrogate, NOT the idempotency key"
        );
        // P16: the create title is the supplied body string.
        assert_eq!(create["values"]["title"], json!("Buy milk"));

        let done = m
            .dispatch(
                "BuildMarkTodoDoneIntent",
                json!({"account_id": "acct-7", "todo_id": "todo-42", "idempotency_key": "evt-2"}),
            )
            .await
            .unwrap();
        // P15: done targets the route todo_id as the business key (NOT the idempotency key), and uses
        // "upsert" (the host adapter is an INSERT … ON CONFLICT DO UPDATE; "update" is not in the op
        // allowlist). account_id is carried so the on-conflict update stays FK-valid.
        assert_eq!(done["operation"], json!("upsert"));
        assert_eq!(done["target"], json!("todos"));
        assert_eq!(
            done["key"],
            json!("todo-42"),
            "business key = route todo_id"
        );
        assert_eq!(done["values"]["account_id"], json!("acct-7"));
        assert_eq!(done["values"]["done"], json!("true"));

        // no capability identity smuggled into the structured intent.
        for k in [
            "capability_id",
            "operation_scope",
            "scope",
            "passport",
            "dsn",
        ] {
            assert!(create.get(k).is_none(), "WriteIntent must not carry `{k}`");
        }
    });
}

// ── 1b (P36): Done can TARGET the host-minted surrogate id ────────────────────────────────────────
//
// The decouple is only useful if a client can act on the minted id afterwards. A create mints
// `todo_<surrogate>` as the business key; a subsequent Done whose route `todo_id` IS that minted id
// produces a WriteIntent keyed to the same business row — so update routes target the minted resource,
// not the idempotency key.

#[test]
fn done_targets_the_minted_surrogate_id() {
    rt().block_on(async {
        let m = load_app_contracts();
        // The host mints `todo_<surrogate>`; here the surrogate input stands in for the host digest.
        let create = m
            .dispatch(
                "BuildCreateTodoIntent",
                json!({"account_id": "acct-7", "surrogate_id": "abc123", "title": "Buy milk"}),
            )
            .await
            .unwrap();
        let minted = create["key"].as_str().unwrap().to_string();
        assert_eq!(minted, "todo_abc123");

        // A client now marks THAT todo done by passing the minted id as the route `todo_id`.
        let done = m
            .dispatch(
                "BuildMarkTodoDoneIntent",
                json!({"account_id": "acct-7", "todo_id": minted, "idempotency_key": "evt-done-9"}),
            )
            .await
            .unwrap();
        assert_eq!(
            done["key"],
            create["key"],
            "Done targets the minted business id (same row), NOT the idempotency key"
        );
        // The Done effect still carries the request idempotency key separately (correlation/receipts).
        assert_eq!(done["correlation_id"], json!("evt-done-9"));
    });
}

// ── 2: the mutating handlers are wired to the command contracts, no capability identity in the app ─

#[test]
fn handlers_wire_command_contracts_with_no_identity() {
    let handlers = std::fs::read_to_string(app_dir().join("todo_handlers.ig")).unwrap();

    // the handlers now build the intent via the command contract and derive the effect from it.
    assert!(handlers.contains("call_contract(\"BuildCreateTodoIntent\""));
    assert!(handlers.contains("call_contract(\"BuildMarkTodoDoneIntent\""));
    // P36: create's business key is a host-minted surrogate (`todo_` + req.surrogate_id), DECOUPLED
    // from the idempotency key; BOTH effects set their idempotency key from the request's. The literal
    // `idempotency_key: intent.key` coupling is gone.
    assert!(handlers.contains("req.surrogate_id"));
    assert!(handlers.contains("concat(\"todo_\", surrogate_id)"));
    assert!(handlers.contains("idempotency_key: req.idempotency_key"));
    assert!(
        !handlers.contains("idempotency_key: intent.key"),
        "the idempotency-key-as-business-id coupling must be removed (P36)"
    );
    assert!(handlers.contains("target: \"todo-create\""));
    assert!(handlers.contains("target: \"todo-done\""));

    // the app names no capability identity / DB authority (code only; comments discuss the boundary).
    let code = handlers
        .lines()
        .map(|l| l.split("--").next().unwrap_or(""))
        .collect::<Vec<_>>()
        .join("\n")
        .to_lowercase();
    for forbidden in [
        "capability_id",
        "io.postgres",
        "passport",
        "dsn",
        "select ",
        "raw_sql",
    ] {
        assert!(
            !code.contains(forbidden),
            "authored app must not contain `{forbidden}`"
        );
    }
}

// ── 3 (P7): the structured WriteIntent (the value carried by `InvokeEffect.input`) maps to a
//            `PostgresWriteIntent` with TYPED, tag-free `values` — no string parsing at the host ─────

#[test]
fn structured_intent_maps_to_postgres_write_values() {
    rt().block_on(async {
        let m = load_app_contracts();
        // the command contract emits exactly the structured value the handler now puts in `input: intent`.
        let intent = m
            .dispatch(
                "BuildCreateTodoIntent",
                json!({"account_id": "acct-7", "surrogate_id": "abc123", "title": "Buy milk"}),
            )
            .await
            .unwrap();

        // the VM-serialized intent is a CLEAN JSON object — no string wrapper, no variant discriminants.
        assert!(
            intent.is_object(),
            "intent crosses as an object, not a string"
        );
        let s = intent.to_string();
        assert!(
            !s.contains("__arm") && !s.contains("__variant"),
            "plain record is tag-free: {s}"
        );

        // the host builds a PostgresWriteIntent straight from that object — no SQL, no parsing.
        let pg =
            PostgresWriteIntent::from_args(&intent).expect("from_args on the structured intent");
        assert_eq!(pg.operation, "insert");
        assert_eq!(pg.target, "todos");
        assert_eq!(pg.key, "todo_abc123", "P36: business key = host surrogate, not the idem key");
        // the TYPED values survive nested + structured (the whole point of P7).
        assert_eq!(pg.values["account_id"], json!("acct-7"));
        assert_eq!(pg.values["title"], json!("Buy milk"));
        assert_eq!(pg.values["done"], json!("false"));
        assert!(
            pg.values.is_object(),
            "values is a structured object, not a string"
        );
    });
}

// ── 4 (P7): raw SQL smuggled into the structured input is refused by the host gate ────────────────

#[test]
fn raw_sql_in_structured_input_is_refused() {
    let malicious = json!({
        "operation": "insert", "target": "todos", "key": "k1",
        "values": { "title": "x" }, "raw_sql": "DROP TABLE todos"
    });
    let err = PostgresWriteIntent::from_args(&malicious).unwrap_err();
    assert!(
        err.contains("raw SQL refused"),
        "host must refuse raw SQL: {err}"
    );
}
