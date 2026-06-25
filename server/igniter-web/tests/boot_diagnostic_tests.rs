//! boot_diagnostic_tests.rs — LAB-IGNITER-DATA-PROJECTION-BOOT-DIAGNOSTIC-P8
//!
//! Proves the source-INDEPENDENT subset of typed `ReadThen` reconciliation is caught at build/check time,
//! before any listener bind, with a stable `PROJECTION_SCHEMA_INVALID` diagnostic:
//!
//!   - a malformed crossing shape (both `rows_json` and `rows`; a scalar `rows` element);
//!   - a `Collection[<AppRow>]` whose row type has a field with no v0 projection landing.
//!
//! Three surfaces: the `IgWebLoadedApp::validate_read_continuations` metadata scan, the `check_app_dir`
//! library check path, and the real `igweb-serve check` CLI. Valid P7 fixtures yield zero diagnostics.
//! DB-free, `--features machine`.
#![cfg(feature = "machine")]

use igniter_web::runner::{check_app_dir, RunnerError};
use igniter_web::runner_diag::{classify_runner_error, DiagCode};
use igniter_web::{build_igweb_loaded_app, IgWebBuildInput};
use std::path::PathBuf;
use std::process::Command;

const INVALID_FIXTURE: &str = include_str!("fixtures/invalid_continuation/invalid_continuation.ig");
const VALID_FIXTURE: &str = include_str!("fixtures/typed_readthen/typed_readthen.ig");
const BIN: &str = env!("CARGO_BIN_EXE_igweb-serve");

fn stamp() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos()
}

/// Write a `.ig` source to a fresh temp file; return its path.
fn write_fixture(tag: &str, src: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!(
        "igweb_p8_{}_{}_{}",
        tag,
        std::process::id(),
        stamp()
    ));
    std::fs::create_dir_all(&dir).unwrap();
    let fx = dir.join(format!("{tag}.ig"));
    std::fs::write(&fx, src).unwrap();
    fx
}

/// Write a runnable app dir: `igweb.toml` (entry) + the named `.ig` source. Returns the dir.
fn write_app_dir(tag: &str, entry: &str, ig_name: &str, src: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!(
        "igweb_p8dir_{}_{}_{}",
        tag,
        std::process::id(),
        stamp()
    ));
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(
        dir.join("igweb.toml"),
        format!("[app]\nentry = \"{entry}\"\n"),
    )
    .unwrap();
    std::fs::write(dir.join(format!("{ig_name}.ig")), src).unwrap();
    dir
}

// ── 1: the metadata scan flags exactly the structurally-invalid continuations ──────────────────────

#[test]
fn validate_flags_invalid_typed_continuations() {
    let app = build_igweb_loaded_app(IgWebBuildInput {
        sources: vec![write_fixture("invalid", INVALID_FIXTURE)],
        entry: "Serve".to_string(),
    })
    .expect("invalid fixture still builds (defect is in the contract shape, not syntax)");

    let diags = app.validate_read_continuations();
    let msgs: Vec<String> = diags.iter().map(|d| d.message.clone()).collect();

    assert_eq!(
        diags.len(),
        3,
        "exactly the three bad continuations: {msgs:?}"
    );
    assert!(diags
        .iter()
        .all(|d| d.code == DiagCode::ProjectionSchemaInvalid));

    let joined = msgs.join(" | ");
    assert!(
        joined.contains("BadBothShapes") && joined.contains("BOTH"),
        "{joined}"
    );
    assert!(
        joined.contains("BadScalarRows") && joined.contains("record"),
        "{joined}"
    );
    assert!(
        joined.contains("BadUnprojectableRow") && joined.contains("Float"),
        "{joined}"
    );
    // The valid `Serve` entry is NOT flagged.
    assert!(
        !joined.contains("`Serve`"),
        "valid entry must not be flagged: {joined}"
    );
}

// ── 2: valid P7 typed + legacy fixture yields ZERO boot diagnostics ─────────────────────────────────

#[test]
fn valid_fixture_has_no_boot_diagnostics() {
    let app = build_igweb_loaded_app(IgWebBuildInput {
        sources: vec![write_fixture("valid", VALID_FIXTURE)],
        entry: "FetchTypedTodos".to_string(),
    })
    .expect("valid fixture builds");
    assert!(
        app.validate_read_continuations().is_empty(),
        "the P7 typed + legacy fixture is structurally sound"
    );
}

// ── 3: check_app_dir fails closed with a ProjectionSchemaInvalid-classified RunnerError ─────────────

#[test]
fn check_app_dir_rejects_invalid_continuations() {
    let dir = write_app_dir("invalid", "Serve", "invalid_continuation", INVALID_FIXTURE);
    match check_app_dir(&dir) {
        Err(e @ RunnerError::ReadContinuation(_)) => {
            assert_eq!(
                classify_runner_error(&e).code,
                DiagCode::ProjectionSchemaInvalid
            );
            let msg = e.to_string();
            assert!(
                msg.contains("BadScalarRows"),
                "names the offending continuation: {msg}"
            );
        }
        other => panic!("expected ReadContinuation error, got {other:?}"),
    }
}

#[test]
fn check_app_dir_accepts_valid_app() {
    let dir = write_app_dir("valid", "FetchTypedTodos", "typed_readthen", VALID_FIXTURE);
    let report = check_app_dir(&dir).expect("valid app passes the boot check");
    assert_eq!(report.entry, "FetchTypedTodos");
}

// ── 4: the real `igweb-serve check` CLI surfaces the stable code with a non-generic exit ────────────

#[test]
fn cli_check_reports_projection_schema_invalid() {
    let dir = write_app_dir(
        "invalid_cli",
        "Serve",
        "invalid_continuation",
        INVALID_FIXTURE,
    );
    let out = Command::new(BIN)
        .args(["check", dir.to_str().unwrap()])
        .output()
        .expect("spawn igweb-serve");
    let code = out.status.code().unwrap_or(-1);
    let stderr = String::from_utf8_lossy(&out.stderr);
    let stdout = String::from_utf8_lossy(&out.stdout);

    assert_eq!(
        code, 12,
        "PROJECTION_SCHEMA_INVALID exit code; stderr={stderr}"
    );
    assert!(
        stderr.contains("[PROJECTION_SCHEMA_INVALID]"),
        "stable code on stderr: {stderr}"
    );
    assert!(!stdout.contains("check ok"), "must not report success");
}

#[test]
fn cli_check_accepts_valid_app() {
    let dir = write_app_dir(
        "valid_cli",
        "FetchTypedTodos",
        "typed_readthen",
        VALID_FIXTURE,
    );
    let out = Command::new(BIN)
        .args(["check", dir.to_str().unwrap()])
        .output()
        .expect("spawn igweb-serve");
    assert_eq!(
        out.status.code().unwrap_or(-1),
        0,
        "valid app check exits 0"
    );
    assert!(String::from_utf8_lossy(&out.stdout).contains("check ok"));
}
