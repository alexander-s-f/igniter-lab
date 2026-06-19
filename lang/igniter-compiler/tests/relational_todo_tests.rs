// tests/relational_todo_tests.rs — LAB-IGNITER-RELATIONAL-CONTRACTS-TODO-P2
// Prove the LANGUAGE/APP side of relational contracts: a pure `.ig` Todo module that expresses queries as
// structured `QueryPlan` records and writes as `WriteIntent` records (mirroring the live machine boundary),
// with relations as CONTRACTS not fields — and that it compiles clean through the REAL multifile compiler.
// No DB, no machine, no SQL execution. Anti-ORM / no-SQL surface is asserted over the fixture source.

use std::process::Command;

const FIXTURE: &str = include_str!("fixtures/relational_todo/relational_todo.ig");

fn bin() -> &'static str {
    env!("CARGO_BIN_EXE_igniter_compiler")
}

/// The fixture with `--` line comments stripped — the anti-SQL / anti-ORM checks target the authored
/// CODE surface, not the explanatory prose (comments legitimately mention SQL/capability/lazy concepts).
fn code_only() -> String {
    FIXTURE
        .lines()
        .map(|l| match l.find("--") {
            Some(i) => &l[..i],
            None => l,
        })
        .collect::<Vec<_>>()
        .join("\n")
        .to_lowercase()
}

/// Compile the single relational fixture module through the real compiler; return stdout (result JSON).
fn compile_fixture() -> String {
    let dir = std::env::temp_dir().join(format!("relational_todo_{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let src = dir.join("relational_todo.ig");
    let out = dir.join("out.igapp");
    std::fs::write(&src, FIXTURE).unwrap();
    let output = Command::new(bin())
        .args([
            "compile",
            src.to_str().unwrap(),
            "--out",
            out.to_str().unwrap(),
        ])
        .output()
        .expect("run igniter_compiler");
    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    assert!(
        output.status.success(),
        "relational Todo fixture must compile.\n--- stdout ---\n{}\n--- stderr ---\n{}",
        stdout,
        stderr
    );
    assert!(out.exists(), "compiler should write the .igapp artifact");
    stdout
}

/// Tests 1–6: the fixture compiles clean (no type/regexp errors) through the real compiler. A clean
/// compile is the proof that QueryPlan / QueryFilter-collection / WriteIntent records, the
/// relation-as-contract shape, and the `Option[Todo]` not-found shape all typecheck.
#[test]
fn relational_todo_compiles_clean() {
    let stdout = compile_fixture();
    assert!(
        !stdout.contains("OOF-TY0"),
        "relational records/collections/options must typecheck (no OOF-TY0).\n{stdout}"
    );
    assert!(
        !stdout.contains("\"severity\": \"error\"") && !stdout.contains("\"severity\":\"error\""),
        "no error diagnostics expected.\n{stdout}"
    );

    // sanity: the intended shapes are actually present in the fixture (guards against an empty/no-op proof).
    for needle in [
        "output plan : QueryPlan",          // query contracts return a structured plan
        "output intent : WriteIntent",      // command contracts return a structured write intent
        "Collection[QueryFilter]",          // filters are a typed collection
        "compute r : Option[Todo]",         // not-found is an Option
        "some(todo)",
        "none()",
        "pure contract TodosByAccount",     // relation expressed as a CONTRACT
    ] {
        assert!(FIXTURE.contains(needle), "fixture should contain `{needle}`");
    }
}

/// Test 7 — no raw SQL surface in the authored code (comments stripped).
#[test]
fn fixture_has_no_raw_sql() {
    let hay = code_only();
    for sql in [
        "select ",
        "insert into",
        "update ",
        "delete from",
        "where ",
        " join ",
        "create table",
    ] {
        assert!(!hay.contains(sql), "fixture code must contain no raw SQL: `{sql}`");
    }
}

/// Test 8 — no ORM-ish / active-record surface in the authored code, and the relation is a contract,
/// not a field: no row type declares a `todos` field.
#[test]
fn fixture_has_no_orm_surface() {
    let hay = code_only();
    for orm in [
        ".save", "save(", "find_by_sql", "belongs_to", "has_many", "has_one", "active_record",
        ".all(", "lazy",
    ] {
        assert!(!hay.contains(orm), "fixture code must contain no ORM surface: `{orm}`");
    }
    // "Account has many Todos" is the `TodosByAccount` contract — NOT a nested/lazy `todos` field.
    assert!(
        !hay.contains("todos :") && !hay.contains("todos:"),
        "no row type may carry a `todos` relation field; relation is a contract"
    );
}

/// Test 9 — the fixture is pure `.ig`: self-contained, no import / machine / effect / capability surface
/// in the authored code (comments may discuss the boundary).
#[test]
fn fixture_is_pure_ig() {
    let hay = code_only();
    for forbidden in ["import ", "invokeeffect", "call_capability", "capability", "passport"] {
        assert!(
            !hay.contains(forbidden),
            "relational Todo fixture code must be self-contained pure `.ig` (found `{forbidden}`)"
        );
    }
}
