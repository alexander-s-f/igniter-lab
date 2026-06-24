// LAB-STDLIB-LINALG-MAT3-P3
//
// Package-resolver side of the Float `Mat3` local package proof: the consumer `app` imports the `Vec3` and
// `Mat3` types and calls the Mat3 op contracts (Identity/Transpose/Add/Scale/MulVec3/Mul/MakeRotationZ) via
// `call_contract` through the REAL workspace resolver — it must compile clean, and the package (now carrying
// BOTH Vec3 and Mat3) must be lock/verify-clean (CI-trustable). Value assertions live in the VM crate's
// `linalg_mat3_tests`.

use serde_json::Value;
use std::path::{Path, PathBuf};
use std::process::Command;

fn bin() -> &'static str {
    env!("CARGO_BIN_EXE_igniter_compiler")
}

const FIX: &str = "tests/fixtures/project_mode/linalg_mat3";

/// The consumer app imports both `Vec3` and `Mat3` and calls the Mat3 package contracts across the workspace
/// boundary; the whole thing must compile clean through the real resolver (no error diagnostics).
#[test]
fn mat3_package_compiles_through_resolver() {
    let out = std::env::temp_dir().join(format!("linalg_mat3_c_{}.igapp", std::process::id()));
    let o = Command::new(bin())
        .args([
            "compile",
            "--project-root",
            &format!("{FIX}/app"),
            "--entry",
            "App.Main",
            "--out",
            out.to_str().unwrap(),
        ])
        .output()
        .expect("run igc");
    let stdout = String::from_utf8_lossy(&o.stdout);
    let v: Value = serde_json::from_str(&stdout).unwrap_or(Value::Null);
    assert_eq!(
        v["status"],
        Value::String("ok".into()),
        "mat3 package compiles clean: {stdout}"
    );
    let err_count = v["diagnostics"]
        .as_array()
        .map(|a| a.iter().filter(|d| d["severity"] == "error").count())
        .unwrap_or(0);
    assert_eq!(err_count, 0, "no error diagnostics: {stdout}");
}

fn copy_tree(src: &Path, dst: &Path) {
    std::fs::create_dir_all(dst).unwrap();
    for e in std::fs::read_dir(src).unwrap() {
        let e = e.unwrap();
        let (from, to) = (e.path(), dst.join(e.file_name()));
        if e.file_type().unwrap().is_dir() {
            copy_tree(&from, &to);
        } else {
            std::fs::copy(&from, &to).unwrap();
        }
    }
}

fn run(args: &[&str]) -> (bool, Value) {
    let o = Command::new(bin()).args(args).output().expect("run igc");
    let v: Value = serde_json::from_str(&String::from_utf8_lossy(&o.stdout)).unwrap_or(Value::Null);
    (o.status.success(), v)
}

/// The package workspace (Vec3 + Mat3) is lock/verify-clean: `igc lock` writes a lock, and `igc verify
/// --strict` (drift + assembly integrity) passes — so a linalg-consuming workspace is CI-trustable. Run on a
/// temp copy (lock writes `igniter.lock` into the app root; never touch the versioned fixture).
#[test]
fn mat3_package_locks_and_verifies_strict() {
    let base = std::env::temp_dir().join(format!("linalg_mat3_lock_{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&base);
    copy_tree(Path::new(FIX), &base);
    let app: PathBuf = base.join("app");
    let app_s = app.to_str().unwrap();

    let (ok, v) = run(&["lock", "--project-root", app_s]);
    assert!(ok, "lock succeeds: {v}");
    assert!(app.join("igniter.lock").exists(), "igniter.lock written");

    let (ok, v) = run(&["verify", "--project-root", app_s, "--strict"]);
    assert!(ok, "verify --strict passes on the linalg Vec3+Mat3 workspace: {v}");
    assert_eq!(v["ok"], Value::Bool(true));
    assert_eq!(
        v["integrity"]["ok"],
        Value::Bool(true),
        "assembly integrity clean: {v}"
    );
}
