// LAB-STDLIB-LINALG-VEC3-PACKAGE-P2
//
// End-to-end value proof for the Float `Vec3` LOCAL PACKAGE: compile the consumer workspace through the
// REAL package/workspace resolver (`igc compile --project-root`, which folds the `linalg` dependency), then
// run each operation contract through the VM (`igniter-vm run --contract … --entry … --inputs`) and assert
// exact Float values. Pure `.ig` package, no VM builtins. Fixture:
// `igniter-compiler/tests/fixtures/project_mode/linalg_vec3/{linalg,app}`.

use std::path::{Path, PathBuf};
use std::process::Command;

fn vm_bin() -> &'static str {
    env!("CARGO_BIN_EXE_igniter-vm")
}

/// Locate the `igniter_compiler` binary built alongside this crate (non-workspace lab: per-crate target).
fn igc_bin() -> String {
    for p in [
        "../igniter-compiler/target/debug/igniter_compiler",
        "../igniter-compiler/target/release/igniter_compiler",
    ] {
        if Path::new(p).exists() {
            return p.to_string();
        }
    }
    panic!("igniter_compiler binary not found — build `igniter-compiler` before running this test");
}

const APP: &str = "../igniter-compiler/tests/fixtures/project_mode/linalg_vec3/app";

/// Compile the consumer app through the real workspace resolver; return the `.igapp` path.
fn compile_app() -> PathBuf {
    let out = std::env::temp_dir().join(format!("linalg_vm_{}.igapp", std::process::id()));
    let o = Command::new(igc_bin())
        .args([
            "compile",
            "--project-root",
            APP,
            "--entry",
            "App.Main",
            "--out",
            out.to_str().unwrap(),
        ])
        .output()
        .expect("run igc");
    let stdout = String::from_utf8_lossy(&o.stdout);
    assert!(
        stdout.contains("\"status\": \"ok\""),
        "package project must compile clean through the resolver: {stdout}"
    );
    out
}

/// Run one contract through the VM with JSON inputs; return stdout (contains `Resulting Output: …`).
fn run(app: &Path, entry: &str, inputs: &str) -> String {
    let inf = std::env::temp_dir().join(format!("linalg_in_{}_{}.json", entry, std::process::id()));
    std::fs::write(&inf, inputs).unwrap();
    let o = Command::new(vm_bin())
        .args([
            "run",
            "--contract",
            app.to_str().unwrap(),
            "--entry",
            entry,
            "--inputs",
            inf.to_str().unwrap(),
        ])
        .output()
        .expect("run igniter-vm");
    String::from_utf8_lossy(&o.stdout).to_string()
}

#[test]
fn vec3_ops_exact_values_through_package_and_vm() {
    let app = compile_app();
    let ab = r#"{"a":{"x":1.0,"y":2.0,"z":3.0},"b":{"x":4.0,"y":5.0,"z":6.0}}"#;

    // add (1,2,3)+(4,5,6) = (5,7,9)
    let r = run(&app, "AddProof", ab);
    assert!(
        r.contains(r#""x": Float(5.0)"#)
            && r.contains(r#""y": Float(7.0)"#)
            && r.contains(r#""z": Float(9.0)"#),
        "add = (5,7,9): {r}"
    );
    // sub = (-3,-3,-3)
    let r = run(&app, "SubProof", ab);
    assert!(
        r.contains(r#""x": Float(-3.0)"#) && r.contains(r#""z": Float(-3.0)"#),
        "sub = (-3,-3,-3): {r}"
    );
    // scale (1,2,3)*2 = (2,4,6)
    let r = run(
        &app,
        "ScaleProof",
        r#"{"v":{"x":1.0,"y":2.0,"z":3.0},"k":2.0}"#,
    );
    assert!(
        r.contains(r#""x": Float(2.0)"#)
            && r.contains(r#""y": Float(4.0)"#)
            && r.contains(r#""z": Float(6.0)"#),
        "scale = (2,4,6): {r}"
    );
    // dot (1,2,3)·(4,5,6) = 32
    assert!(
        run(&app, "DotProof", ab).contains("Float(32.0)"),
        "dot = 32"
    );
    // cross (1,0,0)×(0,1,0) = (0,0,1) — right-handed
    let c = run(
        &app,
        "CrossProof",
        r#"{"a":{"x":1.0,"y":0.0,"z":0.0},"b":{"x":0.0,"y":1.0,"z":0.0}}"#,
    );
    assert!(
        c.contains(r#""x": Float(0.0)"#)
            && c.contains(r#""y": Float(0.0)"#)
            && c.contains(r#""z": Float(1.0)"#),
        "cross = (0,0,1): {c}"
    );
    // norm((3,4,0)) = 5.0 via fast sqrt
    assert!(
        run(&app, "NormProof", r#"{"v":{"x":3.0,"y":4.0,"z":0.0}}"#).contains("Float(5.0)"),
        "norm = 5.0"
    );
    // det_norm((3,4,0)) = 5.0 via det_sqrt
    assert!(
        run(&app, "DetNormProof", r#"{"v":{"x":3.0,"y":4.0,"z":0.0}}"#).contains("Float(5.0)"),
        "det_norm = 5.0"
    );
    // distance((0,0,0),(3,4,0)) = 5.0
    assert!(
        run(
            &app,
            "DistanceProof",
            r#"{"a":{"x":0.0,"y":0.0,"z":0.0},"b":{"x":3.0,"y":4.0,"z":0.0}}"#
        )
        .contains("Float(5.0)"),
        "distance = 5.0"
    );
}
