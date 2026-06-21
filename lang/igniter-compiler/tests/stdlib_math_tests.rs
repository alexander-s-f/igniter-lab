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

/// LAB-STDLIB-MATH-DET-TIER1-P5: the deterministic `det_*` surface typechecks identically to the fast
/// surface — `(Float)->Float`, compiles clean, wrong arity/type rejected (OOF-MATH1/OOF-MATH2). Flat spelling
/// (`det_sin`); the dotted `det.sin` is a parse error (OOF-P0), so flat is the live-grammar surface.
#[test]
fn deterministic_surface_compiles_and_typechecks() {
    let (status, errors) = compile(
        "det_valid",
        "module M.Det\n\npure contract C {\n  input x : Float\n  compute a : Float = det_sin(x)\n  compute b : Float = det_cos(x)\n  compute c : Float = det_sqrt(x)\n  output a : Float\n}\n",
    );
    assert_eq!(status, "ok", "det_* must compile; errors: {errors:?}");
    assert!(errors.is_empty(), "no error diagnostics: {errors:?}");

    let (_s, e_arity) = compile(
        "det_arity",
        "module M.DA\n\npure contract C {\n  input x : Float\n  compute s : Float = det_sin(x, x)\n  output s : Float\n}\n",
    );
    assert!(has_rule(&e_arity, "OOF-MATH1"), "det_sin/2 → OOF-MATH1: {e_arity:?}");

    let (_s, e_type) = compile(
        "det_type",
        "module M.DT\n\npure contract C {\n  input n : Integer\n  compute r : Float = det_sqrt(n)\n  output r : Float\n}\n",
    );
    assert!(has_rule(&e_type, "OOF-MATH2"), "det_sqrt(Integer) → OOF-MATH2: {e_type:?}");
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

/// LAB-STDLIB-MATH-NUMERIC-BASICS-P7: N0 basics typecheck — polymorphic Integer/Float, same-type-in/out,
/// `sign`→Integer; OOF-MATH1 arity, OOF-MATH2 non-numeric, OOF-MATH3 mixed numeric types.
#[test]
fn numeric_basics_typecheck() {
    let (status, errors) = compile(
        "n0_valid",
        "module M.N0\n\npure contract C {\n  input x : Float\n  input n : Integer\n  compute a : Float = abs(x)\n  compute mn : Integer = min(n, n)\n  compute mx : Float = max(x, x)\n  compute c : Float = clamp(x, x, x)\n  compute s : Integer = sign(x)\n  output c : Float\n}\n",
    );
    assert_eq!(status, "ok", "N0 basics must compile; errors: {errors:?}");
    assert!(errors.is_empty(), "no error diagnostics: {errors:?}");

    let (_s, e_arity) = compile(
        "n0_arity",
        "module M.NA\n\npure contract C {\n  input x : Float\n  compute m : Float = min(x)\n  output m : Float\n}\n",
    );
    assert!(has_rule(&e_arity, "OOF-MATH1"), "min/1 → OOF-MATH1: {e_arity:?}");

    let (_s, e_num) = compile(
        "n0_nonnum",
        "module M.NN\n\npure contract C {\n  input s : String\n  compute a : String = abs(s)\n  output a : String\n}\n",
    );
    assert!(has_rule(&e_num, "OOF-MATH2"), "abs(String) → OOF-MATH2: {e_num:?}");

    let (_s, e_mixed) = compile(
        "n0_mixed",
        "module M.NM\n\npure contract C {\n  input x : Float\n  input n : Integer\n  compute m : Float = min(x, n)\n  output m : Float\n}\n",
    );
    assert!(has_rule(&e_mixed, "OOF-MATH3"), "min(Float, Integer) → OOF-MATH3: {e_mixed:?}");
}
