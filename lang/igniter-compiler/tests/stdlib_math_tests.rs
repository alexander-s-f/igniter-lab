// LAB-STDLIB-MATH-TRANSCENDENTALS-P2
//
// Compiler-side proof: `sin/cos/sqrt/pi` typecheck as `(Float)->Float` / `()->Float`, valid calls compile
// clean, and wrong arity / non-Float arguments are rejected deterministically (OOF-MATH1 / OOF-MATH2).
// Each test writes a tiny `.ig` to a tempdir and runs the real `igniter_compiler` binary.

use serde_json::Value;
use std::process::Command;

fn bin() -> &'static str {
    env!("CARGO_BIN_EXE_igniter_compiler")
}

/// Compile `src`; return (top-level status, error-severity diagnostics).
fn compile(tag: &str, src: &str) -> (String, Vec<Value>) {
    let dir = std::env::temp_dir().join(format!("igc_math_{}_{}", tag, std::process::id()));
    let _ = std::fs::create_dir_all(&dir);
    let ig = dir.join("m.ig");
    std::fs::write(&ig, src).unwrap();
    let out = dir.join("m.igapp");
    let output = Command::new(bin())
        .args(["compile", ig.to_str().unwrap(), "--out", out.to_str().unwrap()])
        .output()
        .expect("run igniter_compiler");
    let stdout = String::from_utf8_lossy(&output.stdout);
    let v: Value = serde_json::from_str(&stdout).unwrap_or(Value::Null);
    let status = v.get("status").and_then(|s| s.as_str()).unwrap_or("?").to_string();
    let errors: Vec<Value> = v
        .get("diagnostics")
        .and_then(|d| d.as_array())
        .map(|a| {
            a.iter()
                .filter(|d| d.get("severity").and_then(|s| s.as_str()) == Some("error"))
                .cloned()
                .collect()
        })
        .unwrap_or_default();
    (status, errors)
}

fn has_rule(errors: &[Value], rule: &str) -> bool {
    errors.iter().any(|d| d.get("rule").and_then(|r| r.as_str()) == Some(rule))
}

#[test]
fn valid_transcendental_calls_compile_clean() {
    let (status, errors) = compile(
        "valid",
        "module M.Valid\n\npure contract C {\n  input x : Float\n  compute s : Float = sin(x)\n  compute c : Float = cos(x)\n  compute r : Float = sqrt(x)\n  compute p : Float = pi()\n  compute half : Float = p / 2.0\n  compute one : Float = sin(half)\n  output one : Float\n}\n",
    );
    assert_eq!(status, "ok", "valid math program must compile; errors: {errors:?}");
    assert!(errors.is_empty(), "no error diagnostics: {errors:?}");
}

#[test]
fn wrong_arity_is_oof_math1() {
    let (_status, errors) = compile(
        "arity",
        "module M.Arity\n\npure contract C {\n  input x : Float\n  compute s : Float = sin(x, x)\n  output s : Float\n}\n",
    );
    assert!(has_rule(&errors, "OOF-MATH1"), "sin/2 → OOF-MATH1: {errors:?}");
}

#[test]
fn non_float_argument_is_oof_math2() {
    let (_status, errors) = compile(
        "argtype",
        "module M.Type\n\npure contract C {\n  input n : Integer\n  compute r : Float = sqrt(n)\n  output r : Float\n}\n",
    );
    assert!(has_rule(&errors, "OOF-MATH2"), "sqrt(Integer) → OOF-MATH2: {errors:?}");
}

/// LAB-STDLIB-MATH-KURAMOTO-PROOF-P4: the N=2 Kuramoto order-parameter slice
/// `r = (1/2)·sqrt((cos ti + cos tj)² + (sin ti + sin tj)²)` compiles clean on the P2 Tier-1 surface —
/// native `cos`/`sin`/`sqrt`, all-Float, no collections, NO hand-rolled Taylor. Numeric behavior
/// (r=1.0 synchronized, r≈0 anti-phase) is asserted live via `igniter-vm run --json` (see proof doc); this
/// locks the compile path against stdlib.Math regressions. Mirrors the home-lab kuramoto_proof.ig fixture.
#[test]
fn kuramoto_order_parameter_slice_compiles_clean() {
    let src = "module Emergence.KuramotoProof\n\npure contract KuramotoR2 {\n  input ti : Float\n  input tj : Float\n  compute ci : Float = cos(ti)\n  compute cj : Float = cos(tj)\n  compute si : Float = sin(ti)\n  compute sj : Float = sin(tj)\n  compute cx : Float = ci + cj\n  compute sy : Float = si + sj\n  compute cx2 : Float = cx * cx\n  compute sy2 : Float = sy * sy\n  compute mag2 : Float = cx2 + sy2\n  compute mag : Float = sqrt(mag2)\n  compute r : Float = mag / 2.0\n  output r : Float\n}\n";
    let (status, errors) = compile("kuramoto", src);
    assert_eq!(status, "ok", "Kuramoto slice must compile on Tier-1 math; errors: {errors:?}");
    assert!(errors.is_empty(), "no error diagnostics: {errors:?}");
    assert!(!src.contains("5040"), "fixture must NOT contain a hand-rolled Taylor series");
}
