// LAB-LANG-STRING-PAD-LEFT-P3
//
// Compiler-side proof: `pad_left` typechecks as `(String, Integer, String)->String`; a valid call compiles
// clean, and wrong arity / wrong arg types are rejected deterministically (OOF-TY0). Each test writes a tiny
// `.ig` to a tempdir and runs the real `igniter_compiler` binary.

use serde_json::Value;
use std::process::Command;

fn bin() -> &'static str {
    env!("CARGO_BIN_EXE_igniter_compiler")
}

fn compile(tag: &str, src: &str) -> (String, Vec<Value>) {
    let dir = std::env::temp_dir().join(format!("igc_padleft_{}_{}", tag, std::process::id()));
    let _ = std::fs::create_dir_all(&dir);
    let ig = dir.join("p.ig");
    std::fs::write(&ig, src).unwrap();
    let out = dir.join("p.igapp");
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
fn valid_pad_left_compiles_clean_as_string() {
    // `pad_left(String, Integer, String) -> String`; also proves composition with `to_text`.
    let (status, errors) = compile(
        "valid",
        "module M.Valid\n\npure contract C {\n  input n : Integer\n  compute cell : String = pad_left(to_text(n), 3, \"0\")\n  output cell : String\n}\n",
    );
    assert_eq!(
        status, "ok",
        "valid pad_left must compile clean; errors={errors:?}"
    );
    assert!(!has_rule(&errors, "OOF-TY0"), "no type error: {errors:?}");
}

#[test]
fn wrong_arity_is_rejected() {
    let (_status, errors) = compile(
        "arity",
        "module M.Arity\n\npure contract C {\n  input t : String\n  compute s : String = pad_left(t, 3)\n  output s : String\n}\n",
    );
    assert!(
        has_rule(&errors, "OOF-TY0"),
        "arity != 3 must be OOF-TY0: {errors:?}"
    );
}

#[test]
fn wrong_arg_types_are_rejected() {
    // arg1 must be String (here Integer), arg2 Integer (here String), arg3 String (here Integer).
    let (_s1, e1) = compile(
        "a1",
        "module M.A1\n\npure contract C {\n  input n : Integer\n  compute s : String = pad_left(n, 3, \"0\")\n  output s : String\n}\n",
    );
    assert!(
        has_rule(&e1, "OOF-TY0"),
        "arg1 non-String must be OOF-TY0: {e1:?}"
    );

    let (_s2, e2) = compile(
        "a2",
        "module M.A2\n\npure contract C {\n  input t : String\n  compute s : String = pad_left(t, \"3\", \"0\")\n  output s : String\n}\n",
    );
    assert!(
        has_rule(&e2, "OOF-TY0"),
        "arg2 non-Integer must be OOF-TY0: {e2:?}"
    );

    let (_s3, e3) = compile(
        "a3",
        "module M.A3\n\npure contract C {\n  input t : String\n  compute s : String = pad_left(t, 3, 0)\n  output s : String\n}\n",
    );
    assert!(
        has_rule(&e3, "OOF-TY0"),
        "arg3 non-String must be OOF-TY0: {e3:?}"
    );
}
