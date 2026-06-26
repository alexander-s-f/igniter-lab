// LAB-LANG-NUMBER-TO-TEXT-P1 + LAB-LANG-DECIMAL-TO-TEXT-P2
//
// Compiler-side proof: `to_text` typechecks as `(Integer | Decimal)->String`; valid calls compile clean, and
// wrong arity / a Float (or other non-Integer/non-Decimal) argument are rejected deterministically (OOF-TY0).
// Each test writes a tiny `.ig` to a tempdir and runs the real `igniter_compiler` binary. Float stays HELD.

use serde_json::Value;
use std::process::Command;

fn bin() -> &'static str {
    env!("CARGO_BIN_EXE_igniter_compiler")
}

/// Compile `src`; return (top-level status, error-severity diagnostics).
fn compile(tag: &str, src: &str) -> (String, Vec<Value>) {
    let dir = std::env::temp_dir().join(format!("igc_totext_{}_{}", tag, std::process::id()));
    let _ = std::fs::create_dir_all(&dir);
    let ig = dir.join("t.ig");
    std::fs::write(&ig, src).unwrap();
    let out = dir.join("t.igapp");
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
fn valid_to_text_compiles_clean_as_string() {
    // `to_text(Integer) -> String`, assigned to a String compute → clean. Also proves `concat` accepts it.
    let (status, errors) = compile(
        "valid",
        "module M.Valid\n\npure contract C {\n  input n : Integer\n  compute s : String = to_text(n)\n  compute badge : String = concat(\"Count: \", s)\n  output badge : String\n}\n",
    );
    assert_eq!(
        status, "ok",
        "valid to_text must compile clean; errors={errors:?}"
    );
    assert!(!has_rule(&errors, "OOF-TY0"), "no type error: {errors:?}");
}

#[test]
fn wrong_arity_is_rejected() {
    let (_status, errors) = compile(
        "arity",
        "module M.Arity\n\npure contract C {\n  input n : Integer\n  compute s : String = to_text(n, n)\n  output s : String\n}\n",
    );
    assert!(
        has_rule(&errors, "OOF-TY0"),
        "arity != 1 must be OOF-TY0: {errors:?}"
    );
}

#[test]
fn non_integer_argument_is_rejected() {
    // A String argument is rejected — no implicit coercion; the v0 surface is Integer-only.
    let (_status, errors) = compile(
        "nonint",
        "module M.NonInt\n\npure contract C {\n  input t : String\n  compute s : String = to_text(t)\n  output s : String\n}\n",
    );
    assert!(
        has_rule(&errors, "OOF-TY0"),
        "non-Integer arg must be OOF-TY0: {errors:?}"
    );
}

#[test]
fn float_argument_is_held() {
    // Float is explicitly HELD — a Float arg is rejected, not silently formatted (Integer|Decimal only).
    let (_status, errors) = compile(
        "float",
        "module M.Float\n\npure contract C {\n  input f : Float\n  compute s : String = to_text(f)\n  output s : String\n}\n",
    );
    assert!(
        has_rule(&errors, "OOF-TY0"),
        "Float arg must be OOF-TY0 (held): {errors:?}"
    );
}

// ── LAB-LANG-DECIMAL-TO-TEXT-P2: to_text also accepts Decimal → String ──────────────────────────────

#[test]
fn valid_to_text_decimal_compiles_clean_as_string() {
    // `to_text(Decimal) -> String` (money/report). `decimal(12345, 2)` has a literal scale → Decimal[2].
    let (status, errors) = compile(
        "decimal",
        "module M.Dec\n\npure contract C {\n  compute d : Decimal[2] = decimal(12345, 2)\n  compute s : String = to_text(d)\n  output s : String\n}\n",
    );
    assert_eq!(
        status, "ok",
        "to_text(Decimal) must compile clean; errors={errors:?}"
    );
    assert!(!has_rule(&errors, "OOF-TY0"), "no type error: {errors:?}");
}
