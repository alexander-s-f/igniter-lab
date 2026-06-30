// LAB-STDLIB-RANDOM-DISTRIBUTIONS-P3
//
// Compiler-side proof: deterministic distribution helpers typecheck over explicit Integer PRNG state.

use serde_json::Value;
use std::process::Command;

fn bin() -> &'static str {
    env!("CARGO_BIN_EXE_igniter_compiler")
}

fn compile(tag: &str, src: &str) -> (String, Vec<Value>) {
    let dir = std::env::temp_dir().join(format!("igc_random_{}_{}", tag, std::process::id()));
    let _ = std::fs::create_dir_all(&dir);
    let ig = dir.join("m.ig");
    std::fs::write(&ig, src).unwrap();
    let out = dir.join("m.igapp");
    let output = Command::new(bin())
        .args([
            "compile",
            ig.to_str().unwrap(),
            "--out",
            out.to_str().unwrap(),
        ])
        .output()
        .expect("run igniter_compiler");
    let stdout = String::from_utf8_lossy(&output.stdout);
    let v: Value = serde_json::from_str(&stdout).unwrap_or(Value::Null);
    let status = v
        .get("status")
        .and_then(|s| s.as_str())
        .unwrap_or("?")
        .to_string();
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
    errors
        .iter()
        .any(|d| d.get("rule").and_then(|r| r.as_str()) == Some(rule))
}

#[test]
fn valid_distribution_calls_compile_clean() {
    let (status, errors) = compile(
        "valid",
        "module M.Valid\n\npure contract C {\n  input seed : Integer\n  compute s0 : Integer = rng_seed(seed)\n  compute s1 : Integer = rng_next(s0)\n  compute sample : Integer = rng_uniform_int(10, 19, s1)\n  compute keep : Bool = rng_bernoulli_per_million(500000, s1)\n  output sample : Integer\n}\n",
    );
    assert_eq!(
        status, "ok",
        "valid random distribution program must compile; errors: {errors:?}"
    );
    assert!(errors.is_empty(), "no error diagnostics: {errors:?}");
}

#[test]
fn wrong_arity_is_oof_rand1() {
    let (_status, errors) = compile(
        "arity",
        "module M.Arity\n\npure contract C {\n  input s : Integer\n  compute sample : Integer = rng_uniform_int(10, s)\n  output sample : Integer\n}\n",
    );
    assert!(
        has_rule(&errors, "OOF-RAND1"),
        "rng_uniform_int/2 -> OOF-RAND1: {errors:?}"
    );
}

#[test]
fn non_integer_argument_is_oof_rand2() {
    let (_status, errors) = compile(
        "nonint",
        "module M.NonInt\n\npure contract C {\n  input f : Float\n  input s : Integer\n  compute sample : Integer = rng_uniform_int(10, 19, f)\n  output sample : Integer\n}\n",
    );
    assert!(
        has_rule(&errors, "OOF-RAND2"),
        "rng_uniform_int(_,_,Float) -> OOF-RAND2: {errors:?}"
    );

    let (_status, bernoulli_errors) = compile(
        "bernoulli_nonint",
        "module M.BernoulliNonInt\n\npure contract C {\n  input f : Float\n  input s : Integer\n  compute keep : Bool = rng_bernoulli_per_million(f, s)\n  output keep : Bool\n}\n",
    );
    assert!(
        has_rule(&bernoulli_errors, "OOF-RAND2"),
        "rng_bernoulli_per_million(Float,_) -> OOF-RAND2: {bernoulli_errors:?}"
    );
}
