// LAB-STDLIB-LINALG-MAT3-P3
//
// End-to-end value proof for the Float `Mat3` LOCAL PACKAGE (three Float `Vec3` rows, built on the P2 Vec3
// package). Compile the consumer workspace through the REAL package/workspace resolver
// (`igc compile --project-root`, which folds the `linalg` dependency carrying BOTH Vec3 and Mat3), then run
// each Mat3 proof contract through the VM and assert exact Float values. Pure `.ig`, no VM builtins, no
// generic matrix. Fixture: `igniter-compiler/tests/fixtures/project_mode/linalg_mat3/{linalg,app}`.

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

const APP: &str = "../igniter-compiler/tests/fixtures/project_mode/linalg_mat3/app";

/// Compile the consumer app through the real workspace resolver; return the `.igapp` path.
fn compile_app() -> PathBuf {
    let out = std::env::temp_dir().join(format!("linalg_mat3_vm_{}.igapp", std::process::id()));
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
        "mat3 package project must compile clean through the resolver: {stdout}"
    );
    out
}

/// Run one contract through the VM with JSON inputs; return stdout (contains `Resulting Output: …`).
fn run(app: &Path, entry: &str, inputs: &str) -> String {
    let inf = std::env::temp_dir().join(format!("linalg_mat3_in_{}_{}.json", entry, std::process::id()));
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

// m = [[1,2,3],[4,5,6],[7,8,9]]
const M: &str = r#"{"r0":{"x":1.0,"y":2.0,"z":3.0},"r1":{"x":4.0,"y":5.0,"z":6.0},"r2":{"x":7.0,"y":8.0,"z":9.0}}"#;

#[test]
fn mat3_ops_exact_values_through_package_and_vm() {
    let app = compile_app();

    // identity = diag(1,1,1)
    let r = run(&app, "IdentityProof", "{}");
    assert!(
        r.contains(r#""r0": Record({"x": Float(1.0), "y": Float(0.0), "z": Float(0.0)})"#)
            && r.contains(r#""r1": Record({"x": Float(0.0), "y": Float(1.0), "z": Float(0.0)})"#)
            && r.contains(r#""r2": Record({"x": Float(0.0), "y": Float(0.0), "z": Float(1.0)})"#),
        "identity = diag(1,1,1): {r}"
    );

    // identity * v = v
    let r = run(&app, "IdentityMulVecProof", r#"{"v":{"x":1.0,"y":2.0,"z":3.0}}"#);
    assert!(
        r.contains(r#""x": Float(1.0), "y": Float(2.0), "z": Float(3.0)"#),
        "identity * (1,2,3) = (1,2,3): {r}"
    );

    // transpose([[1,2,3],[4,5,6],[7,8,9]]) = [[1,4,7],[2,5,8],[3,6,9]]
    let r = run(&app, "TransposeProof", &format!(r#"{{"m":{M}}}"#));
    assert!(
        r.contains(r#""r0": Record({"x": Float(1.0), "y": Float(4.0), "z": Float(7.0)})"#)
            && r.contains(r#""r1": Record({"x": Float(2.0), "y": Float(5.0), "z": Float(8.0)})"#)
            && r.contains(r#""r2": Record({"x": Float(3.0), "y": Float(6.0), "z": Float(9.0)})"#),
        "transpose: {r}"
    );

    // transpose(transpose(m)) = m
    let r = run(&app, "TransposeTwiceProof", &format!(r#"{{"m":{M}}}"#));
    assert!(
        r.contains(r#""r0": Record({"x": Float(1.0), "y": Float(2.0), "z": Float(3.0)})"#)
            && r.contains(r#""r1": Record({"x": Float(4.0), "y": Float(5.0), "z": Float(6.0)})"#)
            && r.contains(r#""r2": Record({"x": Float(7.0), "y": Float(8.0), "z": Float(9.0)})"#),
        "transpose(transpose(m)) = m: {r}"
    );

    // add: m + ones = [[2,3,4],[5,6,7],[8,9,10]]
    let ones = r#"{"r0":{"x":1.0,"y":1.0,"z":1.0},"r1":{"x":1.0,"y":1.0,"z":1.0},"r2":{"x":1.0,"y":1.0,"z":1.0}}"#;
    let r = run(&app, "AddProof", &format!(r#"{{"a":{M},"b":{ones}}}"#));
    assert!(
        r.contains(r#""r0": Record({"x": Float(2.0), "y": Float(3.0), "z": Float(4.0)})"#)
            && r.contains(r#""r2": Record({"x": Float(8.0), "y": Float(9.0), "z": Float(10.0)})"#),
        "add: {r}"
    );

    // scale: m * 2 = [[2,4,6],[8,10,12],[14,16,18]]
    let r = run(&app, "ScaleProof", &format!(r#"{{"m":{M},"k":2.0}}"#));
    assert!(
        r.contains(r#""r0": Record({"x": Float(2.0), "y": Float(4.0), "z": Float(6.0)})"#)
            && r.contains(r#""r1": Record({"x": Float(8.0), "y": Float(10.0), "z": Float(12.0)})"#)
            && r.contains(r#""r2": Record({"x": Float(14.0), "y": Float(16.0), "z": Float(18.0)})"#),
        "scale: {r}"
    );

    // known matrix-vector: m * (1,0,0) = (1,4,7)
    let r = run(&app, "MatVecProof", &format!(r#"{{"m":{M},"v":{{"x":1.0,"y":0.0,"z":0.0}}}}"#));
    assert!(
        r.contains(r#""x": Float(1.0), "y": Float(4.0), "z": Float(7.0)"#),
        "mat-vec m*(1,0,0) = (1,4,7): {r}"
    );

    // known matrix-matrix: shear A * shear B = [[7,2,0],[3,1,0],[0,0,1]]
    let sa = r#"{"r0":{"x":1.0,"y":2.0,"z":0.0},"r1":{"x":0.0,"y":1.0,"z":0.0},"r2":{"x":0.0,"y":0.0,"z":1.0}}"#;
    let sb = r#"{"r0":{"x":1.0,"y":0.0,"z":0.0},"r1":{"x":3.0,"y":1.0,"z":0.0},"r2":{"x":0.0,"y":0.0,"z":1.0}}"#;
    let r = run(&app, "MatMulProof", &format!(r#"{{"a":{sa},"b":{sb}}}"#));
    assert!(
        r.contains(r#""r0": Record({"x": Float(7.0), "y": Float(2.0), "z": Float(0.0)})"#)
            && r.contains(r#""r1": Record({"x": Float(3.0), "y": Float(1.0), "z": Float(0.0)})"#)
            && r.contains(r#""r2": Record({"x": Float(0.0), "y": Float(0.0), "z": Float(1.0)})"#),
        "mat-mul: {r}"
    );

    // rotation: rotZ(90°: cos=0,sin=1) applied to (1,0,0) = (0,1,0)
    let r = run(
        &app,
        "RotationApplyProof",
        r#"{"cos_t":0.0,"sin_t":1.0,"v":{"x":1.0,"y":0.0,"z":0.0}}"#,
    );
    assert!(
        r.contains(r#""x": Float(0.0), "y": Float(1.0), "z": Float(0.0)"#),
        "rotZ(90) * (1,0,0) = (0,1,0): {r}"
    );
}
