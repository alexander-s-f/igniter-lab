//! todo_postgres_smoke_guard_tests.rs — LAB-TODOAPP-API-OPERATOR-SMOKE-P21
//!
//! Bounded, DB-FREE proof of the operator smoke's PREFLIGHT REFUSALS. Each case invokes the real
//! `scripts/todo_postgres_smoke.sh` with controlled env and asserts it refuses (exit 2) with a clear,
//! NON-SECRET message BEFORE it ever builds the binary or connects to Postgres. No `IGNITER_TODO_PG_DSN`
//! that resolves, no live DB, no network — the refusals all fire in the script's preflight.

use std::path::PathBuf;
use std::process::Command;

fn script() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("scripts/todo_postgres_smoke.sh")
}

fn examples_doc() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("examples/todo_postgres_app/EXAMPLES.md")
}

/// Run the smoke script with an explicit env (PATH inherited so the shebang resolves), the two smoke
/// vars removed first, then `vars` applied. Returns (exit_code, combined stdout+stderr).
fn run(vars: &[(&str, &str)]) -> (i32, String) {
    let mut cmd = Command::new(script());
    cmd.env_remove("IGNITER_TODO_PG_DSN")
        .env_remove("IGNITER_TODO_EFFECT_TOKEN")
        .env_remove("IGNITER_TODO_SMOKE_ALLOW_NONLOCAL");
    for (k, v) in vars {
        cmd.env(k, v);
    }
    let out = cmd.output().expect("spawn todo_postgres_smoke.sh");
    let mut s = String::from_utf8_lossy(&out.stdout).to_string();
    s.push_str(&String::from_utf8_lossy(&out.stderr));
    (out.status.code().unwrap_or(-1), s)
}

#[test]
fn refuses_missing_dsn() {
    let (code, out) = run(&[]);
    assert_eq!(code, 2, "missing DSN must exit 2; out={out}");
    assert!(
        out.contains("IGNITER_TODO_PG_DSN"),
        "names the missing var; out={out}"
    );
}

#[test]
fn refuses_missing_token() {
    let (code, out) = run(&[(
        "IGNITER_TODO_PG_DSN",
        "host=localhost dbname=igniter_todo_test",
    )]);
    assert_eq!(code, 2, "missing token must exit 2; out={out}");
    assert!(
        out.contains("IGNITER_TODO_EFFECT_TOKEN"),
        "names the missing var; out={out}"
    );
}

#[test]
fn refuses_sparkish_dbname() {
    let (code, out) = run(&[
        ("IGNITER_TODO_PG_DSN", "host=localhost dbname=spark_prod"),
        ("IGNITER_TODO_EFFECT_TOKEN", "t"),
    ]);
    assert_eq!(code, 2, "spark/prod dbname must exit 2; out={out}");
    assert!(
        out.to_lowercase().contains("production") || out.contains("spark"),
        "explains the refusal; out={out}"
    );
}

#[test]
fn refuses_non_local_host() {
    let (code, out) = run(&[
        (
            "IGNITER_TODO_PG_DSN",
            "host=db.example.com dbname=todo_test",
        ),
        ("IGNITER_TODO_EFFECT_TOKEN", "t"),
    ]);
    assert_eq!(code, 2, "non-local host must exit 2; out={out}");
    assert!(out.contains("not local"), "explains the refusal; out={out}");
}

#[test]
fn refuses_missing_dbname() {
    let (code, out) = run(&[
        ("IGNITER_TODO_PG_DSN", "host=localhost user=alex"),
        ("IGNITER_TODO_EFFECT_TOKEN", "t"),
    ]);
    assert_eq!(code, 2, "no dbname must exit 2; out={out}");
    assert!(out.contains("dbname"), "explains the refusal; out={out}");
}

#[test]
fn does_not_echo_token_or_full_dsn_on_refusal() {
    // A refusal that prints the dbname must NOT leak the token or the full DSN string.
    let (code, out) = run(&[
        (
            "IGNITER_TODO_PG_DSN",
            "host=db.example.com password=topsecret dbname=todo_test",
        ),
        ("IGNITER_TODO_EFFECT_TOKEN", "supersecrettoken"),
    ]);
    assert_eq!(code, 2);
    assert!(
        !out.contains("supersecrettoken"),
        "token must never appear; out={out}"
    );
    assert!(
        !out.contains("password=topsecret"),
        "full DSN must never appear; out={out}"
    );
}

#[test]
fn examples_doc_pins_current_api_contract_without_inline_secrets() {
    let path = examples_doc();
    let text = std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("read {}: {e}", path.display()));

    for marker in [
        "{\"title\":\"Buy milk\"}",
        "bare JSON string body is removed and rejected",
        "todo_<digest>",
        "?after=$TODO_ID",
        "RespondError { status, error }",
        "last returned `id` as `after`",
        "{items,next}",
        "Authorization: Bearer $IGNITER_TODO_EFFECT_TOKEN",
    ] {
        assert!(
            text.contains(marker),
            "EXAMPLES.md must contain contract marker {marker:?}"
        );
    }

    for forbidden in [
        "Authorization: Bearer dev-token",
        "Authorization: Bearer local",
        "password=",
        "postgres://",
        "host=localhost",
        "some-local-bearer-token",
        "supersecrettoken",
    ] {
        assert!(
            !text.contains(forbidden),
            "EXAMPLES.md must not inline secret-like value {forbidden:?}"
        );
    }
}
