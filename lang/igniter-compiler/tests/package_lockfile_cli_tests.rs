// LAB-IGNITER-PACKAGE-LOCKFILE-CLI-P4
//
// End-to-end tests for `igc lock` / `igc verify` over the P3 `workspace_lock`/`verify_lock` API. The lock
// is written into the project root (`igniter.lock`), so every test COPIES the `workspace` fixture into a
// fresh tempdir and runs there — the version-controlled fixture tree is never written to.

use serde_json::Value;
use std::path::{Path, PathBuf};
use std::process::Command;

fn bin() -> &'static str {
    env!("CARGO_BIN_EXE_igniter_compiler")
}

/// Recursively copy a directory tree.
fn copy_tree(src: &Path, dst: &Path) {
    std::fs::create_dir_all(dst).unwrap();
    for entry in std::fs::read_dir(src).unwrap() {
        let entry = entry.unwrap();
        let from = entry.path();
        let to = dst.join(entry.file_name());
        if entry.file_type().unwrap().is_dir() {
            copy_tree(&from, &to);
        } else {
            std::fs::copy(&from, &to).unwrap();
        }
    }
}

/// Copy the `workspace` fixture (app + lib) into a unique tempdir; return the app root to run against.
fn temp_workspace(tag: &str) -> PathBuf {
    temp_fixture("workspace", tag)
}

/// Copy an arbitrary `project_mode/<fixture>` tree into a unique tempdir; return its `app` root.
fn temp_fixture(fixture: &str, tag: &str) -> PathBuf {
    let base = std::env::temp_dir().join(format!("igc_lock_{}_{}", tag, std::process::id()));
    let _ = std::fs::remove_dir_all(&base);
    copy_tree(
        Path::new(&format!("tests/fixtures/project_mode/{fixture}")),
        &base,
    );
    base.join("app")
}

/// Run `igc <cmd> --project-root <root>`; return (success, parsed-stdout-json).
fn run(cmd: &str, root: &Path) -> (bool, Value) {
    run_args(&[cmd, "--project-root", root.to_str().unwrap()])
}

/// Run `igc` with explicit args; return (success, parsed-stdout-json).
fn run_args(args: &[&str]) -> (bool, Value) {
    let output = Command::new(bin())
        .args(args)
        .output()
        .expect("run igniter_compiler");
    let stdout = String::from_utf8_lossy(&output.stdout);
    let v: Value = serde_json::from_str(&stdout).unwrap_or(Value::Null);
    (output.status.success(), v)
}

#[test]
fn cli_lock_then_verify_clean() {
    let root = temp_workspace("clean");
    let (ok, v) = run("lock", &root);
    assert!(ok, "lock exits 0");
    assert_eq!(v["written"], Value::Bool(true));
    assert_eq!(v["dependencies"], serde_json::json!(1));
    assert!(root.join("igniter.lock").exists(), "igniter.lock written");

    let (ok, v) = run("verify", &root);
    assert!(ok, "verify exits 0 on a clean workspace");
    assert_eq!(v["ok"], Value::Bool(true));
    assert!(v["drift"].as_array().unwrap().is_empty(), "no drift: {v}");
}

#[test]
fn cli_lock_is_idempotent() {
    let root = temp_workspace("idem");
    run("lock", &root);
    let a = std::fs::read(root.join("igniter.lock")).unwrap();
    run("lock", &root);
    let b = std::fs::read(root.join("igniter.lock")).unwrap();
    assert_eq!(a, b, "re-running `lock` produces a byte-identical igniter.lock");
}

#[test]
fn cli_verify_detects_drift() {
    let root = temp_workspace("drift");
    run("lock", &root);
    // Mutate a dependency source file (the lock was over `../lib`'s content).
    let dep_file = root.join("../lib/src/util.ig");
    let mut content = std::fs::read_to_string(&dep_file).unwrap();
    content.push_str("\n-- drift\n");
    std::fs::write(&dep_file, content).unwrap();

    let (ok, v) = run("verify", &root);
    assert!(!ok, "verify exits non-zero on drift");
    assert_eq!(v["ok"], Value::Bool(false));
    let drift = v["drift"].as_array().unwrap();
    assert_eq!(drift.len(), 1, "one drift: {v}");
    assert_eq!(drift[0]["kind"], serde_json::json!("changed"));
    assert_eq!(drift[0]["name"], serde_json::json!("lib"));
}

#[test]
fn cli_verify_missing_lockfile_fails() {
    let root = temp_workspace("missing");
    // No `igc lock` run → no igniter.lock.
    let output = Command::new(bin())
        .args(["verify", "--project-root", root.to_str().unwrap()])
        .output()
        .expect("run igniter_compiler");
    assert!(!output.status.success(), "verify without a lockfile exits non-zero");
}

/// LAB-IGNITER-PACKAGE-VERSION-PROVENANCE-P5: tampering the lock's pinned compiler version on disk makes
/// `igc verify` report a `toolchain` drift and exit non-zero.
#[test]
fn cli_verify_detects_toolchain_drift() {
    let root = temp_workspace("toolchain");
    run("lock", &root);
    // Rewrite the on-disk lock to pin a bogus compiler version.
    let lock_path = root.join("igniter.lock");
    let mut v: Value = serde_json::from_str(&std::fs::read_to_string(&lock_path).unwrap()).unwrap();
    v["toolchain"]["compiler"] = Value::String("0.0.0-bogus".to_string());
    std::fs::write(&lock_path, serde_json::to_string_pretty(&v).unwrap()).unwrap();

    let (ok, out) = run("verify", &root);
    assert!(!ok, "verify exits non-zero on toolchain drift");
    let drift = out["drift"].as_array().unwrap();
    let tc = drift.iter().find(|d| d["kind"] == serde_json::json!("toolchain"));
    let tc = tc.unwrap_or_else(|| panic!("expected a toolchain drift: {out}"));
    assert_eq!(tc["field"], serde_json::json!("compiler"));
    assert_eq!(tc["locked"], serde_json::json!("0.0.0-bogus"));
}

/// LAB-IGNITER-PACKAGE-STDLIB-VERSION-CONSTANT-P6: `igc lock` writes `toolchain.stdlib`; tampering it on
/// disk makes `igc verify` report a `toolchain` drift with `field:"stdlib"` and exit non-zero.
#[test]
fn cli_lock_writes_stdlib_and_verify_detects_stdlib_drift() {
    let root = temp_workspace("stdlib");
    run("lock", &root);
    let lock_path = root.join("igniter.lock");
    let mut v: Value = serde_json::from_str(&std::fs::read_to_string(&lock_path).unwrap()).unwrap();
    assert!(
        v["toolchain"]["stdlib"].as_str().is_some_and(|s| !s.is_empty()),
        "lock writes a non-empty toolchain.stdlib: {v}"
    );
    v["toolchain"]["stdlib"] = Value::String("0.0.0-bogus-stdlib".to_string());
    std::fs::write(&lock_path, serde_json::to_string_pretty(&v).unwrap()).unwrap();

    let (ok, out) = run("verify", &root);
    assert!(!ok, "verify exits non-zero on stdlib drift");
    let drift = out["drift"].as_array().unwrap();
    let tc = drift
        .iter()
        .find(|d| d["kind"] == serde_json::json!("toolchain") && d["field"] == serde_json::json!("stdlib"))
        .unwrap_or_else(|| panic!("expected a stdlib toolchain drift: {out}"));
    assert_eq!(tc["locked"], serde_json::json!("0.0.0-bogus-stdlib"));
}

// ── LAB-IGNITER-PACKAGE-LOCKFILE-FROZEN-CI-P8 ───────────────────────────────────────────────────────

fn root_arg(root: &Path) -> String {
    root.to_str().unwrap().to_string()
}

/// `igc lock --frozen` passes (exit 0, ok:true) when the committed lock is current, without rewriting it.
#[test]
fn cli_lock_frozen_passes_when_current() {
    let root = temp_workspace("frozen_ok");
    run("lock", &root);
    let before = std::fs::read(root.join("igniter.lock")).unwrap();
    let (ok, v) = run_args(&["lock", "--project-root", &root_arg(&root), "--frozen"]);
    assert!(ok, "frozen passes when current: {v}");
    assert_eq!(v["ok"], Value::Bool(true));
    assert_eq!(v["reason"], serde_json::json!("up-to-date"));
    assert_eq!(v["written"], Value::Bool(false));
    let after = std::fs::read(root.join("igniter.lock")).unwrap();
    assert_eq!(before, after, "frozen must not rewrite the lockfile");
}

/// `igc lock --frozen` fails (exit 1, reason missing) when there is no committed lock, and never writes one.
#[test]
fn cli_lock_frozen_fails_when_missing() {
    let root = temp_workspace("frozen_missing");
    let (ok, v) = run_args(&["lock", "--project-root", &root_arg(&root), "--frozen"]);
    assert!(!ok, "frozen fails when no lockfile");
    assert_eq!(v["reason"], serde_json::json!("missing"));
    assert!(!root.join("igniter.lock").exists(), "frozen must not create a lockfile");
}

/// `igc lock --frozen` fails (reason out-of-date) when the workspace drifted, leaving the lock untouched.
#[test]
fn cli_lock_frozen_fails_when_stale() {
    let root = temp_workspace("frozen_stale");
    run("lock", &root);
    let before = std::fs::read(root.join("igniter.lock")).unwrap();
    // Drift a dependency source file.
    let dep_file = root.join("../lib/src/util.ig");
    let mut c = std::fs::read_to_string(&dep_file).unwrap();
    c.push_str("\n-- drift\n");
    std::fs::write(&dep_file, c).unwrap();

    let (ok, v) = run_args(&["lock", "--project-root", &root_arg(&root), "--frozen"]);
    assert!(!ok, "frozen fails when stale");
    assert_eq!(v["reason"], serde_json::json!("out-of-date"));
    let after = std::fs::read(root.join("igniter.lock")).unwrap();
    assert_eq!(before, after, "frozen must not rewrite a stale lockfile");
}

/// `igc verify --strict` catches a phantom import that plain `verify` (drift-only) does not — the strict
/// gate adds workspace-assembly integrity (OOF-IMP6) on top of lock drift.
#[test]
fn cli_verify_strict_catches_phantom() {
    let root = temp_fixture("workspace_phantom", "strict_phantom");
    run("lock", &root); // lock only digests deps; the phantom does not affect digests, so this succeeds

    // Plain verify: no drift → passes (it does NOT assemble the workspace).
    let (ok_plain, _) = run("verify", &root);
    assert!(ok_plain, "plain verify is drift-only and passes despite the phantom import");

    // Strict verify: integrity fails on OOF-IMP6.
    let (ok_strict, v) = run_args(&["verify", "--project-root", &root_arg(&root), "--strict"]);
    assert!(!ok_strict, "strict verify fails on phantom import: {v}");
    assert_eq!(v["ok"], Value::Bool(false));
    assert_eq!(v["integrity"]["ok"], Value::Bool(false));
    assert_eq!(v["integrity"]["diagnostic"]["rule"], serde_json::json!("OOF-IMP6"));
}

/// `igc verify --strict` passes on a clean, current workspace (drift-clean + integrity-clean).
#[test]
fn cli_verify_strict_passes_clean() {
    let root = temp_workspace("strict_clean");
    run("lock", &root);
    let (ok, v) = run_args(&["verify", "--project-root", &root_arg(&root), "--strict"]);
    assert!(ok, "strict verify passes on a clean workspace: {v}");
    assert_eq!(v["ok"], Value::Bool(true));
    assert_eq!(v["integrity"]["ok"], Value::Bool(true));
}
