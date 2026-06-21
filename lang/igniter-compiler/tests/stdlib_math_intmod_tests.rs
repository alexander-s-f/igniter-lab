// LAB-STDLIB-MATH-INTEGER-ROOTS-AND-MOD-P8
//
// Compiler-side proof: `isqrt/ipow/mod` typecheck as Integer-only with an Integer result; valid calls
// compile clean, wrong arity → OOF-MATH1, non-Integer arguments → OOF-MATH2. Each test writes a tiny `.ig`
// to a tempdir and runs the real `igniter_compiler` binary.

use serde_json::Value;
use std::process::Command;

fn bin() -> &'static str {
    env!("CARGO_BIN_EXE_igniter_compiler")
}

fn compile(tag: &str, src: &str) -> (String, Vec<Value>) {
    let dir = std::env::temp_dir().join(format!("igc_intmod_{}_{}", tag, std::process::id()));
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
fn valid_integer_calls_compile_clean() {
    let (status, errors) = compile(
        "valid",
        "module M.Valid\n\npure contract C {\n  input n : Integer\n  compute root : Integer = isqrt(n)\n  compute pow : Integer = ipow(n, 3)\n  compute rem : Integer = mod(n, 7)\n  compute combined : Integer = mod(ipow(root, 2), 100)\n  output combined : Integer\n}\n",
    );
    assert_eq!(status, "ok", "valid integer-math program must compile; errors: {errors:?}");
    assert!(errors.is_empty(), "no error diagnostics: {errors:?}");
}

#[test]
fn wrong_arity_is_oof_math1() {
    let (_status, errors) = compile(
        "arity",
        "module M.Arity\n\npure contract C {\n  input n : Integer\n  compute s : Integer = isqrt(n, n)\n  output s : Integer\n}\n",
    );
    assert!(has_rule(&errors, "OOF-MATH1"), "isqrt/2 → OOF-MATH1: {errors:?}");
}

#[test]
fn non_integer_argument_is_oof_math2() {
    let (_status, errors) = compile(
        "nonint",
        "module M.NonInt\n\npure contract C {\n  input f : Float\n  compute s : Integer = isqrt(f)\n  output s : Integer\n}\n",
    );
    assert!(has_rule(&errors, "OOF-MATH2"), "isqrt(Float) → OOF-MATH2: {errors:?}");
}

#[test]
fn ipow_and_mod_reject_non_integer() {
    let (_s1, e1) = compile(
        "ipowf",
        "module M.IpowF\n\npure contract C {\n  input f : Float\n  compute s : Integer = ipow(f, 2)\n  output s : Integer\n}\n",
    );
    assert!(has_rule(&e1, "OOF-MATH2"), "ipow(Float,_) → OOF-MATH2: {e1:?}");
    let (_s2, e2) = compile(
        "modf",
        "module M.ModF\n\npure contract C {\n  input f : Float\n  compute s : Integer = mod(f, 2)\n  output s : Integer\n}\n",
    );
    assert!(has_rule(&e2, "OOF-MATH2"), "mod(Float,_) → OOF-MATH2: {e2:?}");
}
