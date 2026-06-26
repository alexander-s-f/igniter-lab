// LAB-LANG-FLOAT-TO-TEXT-IMPL-P7
//
// Compiler-side proof: `float_to_text(Float, Integer, String) -> String` typechecks; wrong arity / arg types
// and a LITERAL unsupported rounding mode are rejected (OOF-TY0). The negative test pins that NO implicit
// `to_text(Float)` path exists (a Float arg to `to_text` is still rejected).

use serde_json::Value;
use std::process::Command;

fn bin() -> &'static str {
    env!("CARGO_BIN_EXE_igniter_compiler")
}

fn compile(tag: &str, src: &str) -> (String, Vec<Value>) {
    let dir = std::env::temp_dir().join(format!("igc_ftt_{}_{}", tag, std::process::id()));
    let _ = std::fs::create_dir_all(&dir);
    let ig = dir.join("f.ig");
    std::fs::write(&ig, src).unwrap();
    let out = dir.join("f.igapp");
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
fn has_msg(errors: &[Value], substr: &str) -> bool {
    errors
        .iter()
        .any(|d| d.get("message").and_then(|m| m.as_str()).map(|m| m.contains(substr)).unwrap_or(false))
}

#[test]
fn valid_float_to_text_compiles_clean_as_string() {
    let (status, errors) = compile(
        "valid",
        "module M.Valid\n\npure contract C {\n  input r : Float\n  compute s : String = float_to_text(r, 2, \"half_even\")\n  output s : String\n}\n",
    );
    assert_eq!(status, "ok", "valid float_to_text must compile clean; errors={errors:?}");
    assert!(!has_rule(&errors, "OOF-TY0"), "no type error: {errors:?}");
}

#[test]
fn wrong_arity_is_rejected() {
    let (_s, e) = compile(
        "arity",
        "module M.Arity\n\npure contract C {\n  input r : Float\n  compute s : String = float_to_text(r, 2)\n  output s : String\n}\n",
    );
    assert!(has_rule(&e, "OOF-TY0"), "arity != 3 must be OOF-TY0: {e:?}");
}

#[test]
fn wrong_arg_types_are_rejected() {
    // arg1 Float (here Integer), arg2 Integer (here String), arg3 String (here Integer).
    let (_s1, e1) = compile(
        "a1",
        "module M.A1\n\npure contract C {\n  input n : Integer\n  compute s : String = float_to_text(n, 2, \"half_even\")\n  output s : String\n}\n",
    );
    assert!(has_rule(&e1, "OOF-TY0"), "arg1 non-Float → OOF-TY0: {e1:?}");

    let (_s2, e2) = compile(
        "a2",
        "module M.A2\n\npure contract C {\n  input r : Float\n  compute s : String = float_to_text(r, \"2\", \"half_even\")\n  output s : String\n}\n",
    );
    assert!(has_rule(&e2, "OOF-TY0"), "arg2 non-Integer → OOF-TY0: {e2:?}");

    let (_s3, e3) = compile(
        "a3",
        "module M.A3\n\npure contract C {\n  input r : Float\n  compute s : String = float_to_text(r, 2, 0)\n  output s : String\n}\n",
    );
    assert!(has_rule(&e3, "OOF-TY0"), "arg3 non-String → OOF-TY0: {e3:?}");
}

#[test]
fn literal_unsupported_rounding_mode_rejected() {
    let (_s, e) = compile(
        "litmode",
        "module M.LitMode\n\npure contract C {\n  input r : Float\n  compute s : String = float_to_text(r, 2, \"half_up\")\n  output s : String\n}\n",
    );
    assert!(has_rule(&e, "OOF-TY0"), "literal unsupported mode → OOF-TY0: {e:?}");
    assert!(
        has_msg(&e, "unsupported rounding mode \"half_up\""),
        "stable §2 message names the offending literal mode: {e:?}"
    );
}

#[test]
fn no_implicit_to_text_of_float() {
    // The whole point of float_to_text is that `to_text(Float)` stays REJECTED (no implicit Float→String).
    let (_s, e) = compile(
        "noimplicit",
        "module M.NoImplicit\n\npure contract C {\n  input r : Float\n  compute s : String = to_text(r)\n  output s : String\n}\n",
    );
    assert!(has_rule(&e, "OOF-TY0"), "to_text(Float) must remain rejected: {e:?}");
}
