// igniter_env_smoke_tests.rs — LAB-DISTRIBUTION-IGNITER-ENV-IMPL-P33
//
// Smoke for `igniter env doctor|template <app_or_bundle>`: it reports the machine-mode env-NAME catalogue
// (from the commit-safe host.example.toml / bundle host.toml.example) and the set/unset/empty status of each
// var in the process — NEVER the value. `.env` is not read. The catalogue/bundle path is exercised through
// the real `bin/igniter`; the bundle step pins IGNITER_IGWEB_SERVE_BIN so nothing nested-builds.

use std::fs;
use std::path::PathBuf;
use std::process::Command;

fn wrapper() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../bin/igniter")
        .canonicalize()
        .expect("repo-local bin/igniter wrapper must exist")
}

fn todo_app() -> String {
    format!("{}/examples/todo_app", env!("CARGO_MANIFEST_DIR"))
}

fn todo_postgres_app() -> String {
    format!("{}/examples/todo_postgres_app", env!("CARGO_MANIFEST_DIR"))
}

fn tmp(tag: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!("envsmoke_{}_{}", tag, std::process::id()));
    fs::create_dir_all(&d).unwrap();
    d
}

/// Run `bin/igniter env <args...>` with a clean inherited env plus any extra (name,value) pairs.
fn run_env(args: &[&str], extra: &[(&str, &str)]) -> (String, String, i32) {
    let mut cmd = Command::new(wrapper());
    cmd.arg("env").args(args);
    for (k, v) in extra {
        cmd.env(k, v);
    }
    let out = cmd.output().expect("run igniter env");
    (
        String::from_utf8_lossy(&out.stdout).to_string(),
        String::from_utf8_lossy(&out.stderr).to_string(),
        out.status.code().unwrap_or(-1),
    )
}

#[test]
fn igniter_env_doctor_reports_required_names_without_values() {
    // unset case: both names present, marked unset, exit 0 (a report)
    let (so, _se, code) = run_env(&["doctor", &todo_postgres_app()], &[]);
    assert_eq!(code, 0, "env doctor is a report (exit 0): {so}");
    assert!(
        so.contains("IGNITER_TODO_PG_DSN"),
        "names the DSN env var: {so}"
    );
    assert!(
        so.contains("IGNITER_TODO_EFFECT_TOKEN"),
        "names the effect token env var: {so}"
    );

    // set case with a FAKE value: status flips to set, but the value never appears in output
    let (so2, se2, code2) = run_env(
        &["doctor", &todo_postgres_app()],
        &[("IGNITER_TODO_PG_DSN", "host=LEAKED_SECRET_XYZ")],
    );
    assert_eq!(code2, 0);
    assert!(so2.contains("[set"), "a set var is reported as set: {so2}");
    assert!(
        !so2.contains("LEAKED_SECRET_XYZ") && !se2.contains("LEAKED_SECRET_XYZ"),
        "the env VALUE must never be printed:\nSTDOUT:{so2}\nSTDERR:{se2}"
    );
}

#[test]
fn igniter_env_template_emits_blank_exports() {
    // even with a value set in the environment, the template stays blank
    let (so, _se, code) = run_env(
        &["template", &todo_postgres_app()],
        &[("IGNITER_TODO_PG_DSN", "host=LEAKED_SECRET_XYZ")],
    );
    assert_eq!(code, 0, "template exits 0: {so}");
    assert!(
        so.contains("export IGNITER_TODO_PG_DSN="),
        "blank DSN export: {so}"
    );
    assert!(
        so.contains("export IGNITER_TODO_EFFECT_TOKEN="),
        "blank token export: {so}"
    );
    // the line must be a BLANK assignment, not carry the current value
    assert!(
        !so.contains("LEAKED_SECRET_XYZ"),
        "template must not print current values: {so}"
    );
    for line in so.lines().filter(|l| l.starts_with("export ")) {
        let rhs = line.split('=').nth(1).unwrap_or("");
        let rhs_val = rhs.split('#').next().unwrap_or("").trim();
        assert!(rhs_val.is_empty(), "export RHS must be blank: `{line}`");
    }
}

#[test]
fn igniter_env_pure_app_reports_no_machine_env() {
    let (so, _se, code) = run_env(&["doctor", &todo_app()], &[]);
    assert_eq!(code, 0, "pure app env doctor exits 0: {so}");
    assert!(
        so.contains("no machine-mode env required"),
        "states no env needed: {so}"
    );
}

#[test]
fn igniter_env_reads_bundle_host_toml_example() {
    // bundle todo_postgres_app, then `env doctor <bundle>` must read the bundle's host.toml.example
    let out = tmp("bundle_out");
    let bundle_parent = out.to_str().unwrap().to_string();
    let bundle_out = Command::new(wrapper())
        .args([
            "app",
            "bundle",
            &todo_postgres_app(),
            "--out",
            &bundle_parent,
            "--version",
            "V1",
        ])
        .env("IGNITER_IGWEB_SERVE_BIN", env!("CARGO_BIN_EXE_igweb-serve"))
        .output()
        .expect("run igniter app bundle");
    assert!(
        bundle_out.status.success(),
        "bundling todo_postgres_app must succeed: {}{}",
        String::from_utf8_lossy(&bundle_out.stdout),
        String::from_utf8_lossy(&bundle_out.stderr)
    );

    let bundle_dir = out.join("todo_postgres_app-V1");
    assert!(
        bundle_dir.join("host.toml.example").exists(),
        "bundle ships host.toml.example"
    );

    let (so, _se, code) = run_env(&["doctor", bundle_dir.to_str().unwrap()], &[]);
    assert_eq!(code, 0, "env doctor on a bundle exits 0: {so}");
    assert!(
        so.contains("host.toml.example"),
        "reads the bundle catalogue file: {so}"
    );
    assert!(
        so.contains("IGNITER_TODO_PG_DSN"),
        "names env vars from the bundle catalogue: {so}"
    );
}

#[test]
fn igniter_env_usage_errors_are_clean() {
    // unknown verb, no verb, missing path → non-zero usage errors (not silent success)
    for args in [vec!["frobnicate"], vec![], vec!["doctor"]] {
        let (_so, _se, code) = run_env(&args.iter().map(|s| *s).collect::<Vec<_>>(), &[]);
        assert_ne!(code, 0, "`env {args:?}` must be a non-zero usage error");
    }
    // `.env` is explicitly not read — help says so
    let (so, _se, code) = run_env(&["--help"], &[]);
    assert_eq!(code, 0);
    assert!(
        so.contains(".env") && so.contains("NOT read"),
        "help states .env is not read: {so}"
    );
}

// ── env check (P34): the failing gate ───────────────────────────────────────────────────────────────────

#[test]
fn igniter_env_check_gates_on_unset_and_passes_when_set() {
    // unset → non-zero gate failure
    let (_so, _se, code) = run_env(&["check", &todo_postgres_app()], &[]);
    assert_ne!(
        code, 0,
        "env check must FAIL (non-zero) when required vars are unset"
    );

    // set to fake non-empty values → exit 0, and the values never appear
    let (so2, se2, code2) = run_env(
        &["check", &todo_postgres_app()],
        &[
            ("IGNITER_TODO_PG_DSN", "host=LEAKED_SECRET_XYZ"),
            ("IGNITER_TODO_EFFECT_TOKEN", "tok"),
        ],
    );
    assert_eq!(
        code2, 0,
        "env check passes when all required vars are set: {so2}{se2}"
    );
    assert!(
        !so2.contains("LEAKED_SECRET_XYZ") && !se2.contains("LEAKED_SECRET_XYZ"),
        "env check must never print values:\nSTDOUT:{so2}\nSTDERR:{se2}"
    );

    // empty value → still a failure
    let (_so3, _se3, code3) = run_env(
        &["check", &todo_postgres_app()],
        &[
            ("IGNITER_TODO_PG_DSN", "x"),
            ("IGNITER_TODO_EFFECT_TOKEN", ""),
        ],
    );
    assert_ne!(code3, 0, "env check must FAIL on an empty required var");
}

#[test]
fn igniter_env_check_pure_app_passes() {
    let (so, _se, code) = run_env(&["check", &todo_app()], &[]);
    assert_eq!(code, 0, "pure app (no env catalogue) passes the gate: {so}");
}
