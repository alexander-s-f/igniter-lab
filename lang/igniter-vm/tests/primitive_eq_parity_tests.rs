// LAB-VM-PRIMITIVE-EQ-PARITY-P1
//
// Frame-view reducer interaction wanted to author selected-state logic as `result.sel == row_id`
// instead of doing the comparison in Rust host code. The card asked whether the VM executes the
// compiler-emitted equality operator for that shape.
//
// VERIFY-FIRST FINDING: the equality runtime ALREADY exists. The compiler emits `a == b` as a SIR
// `{ kind: "binary_op", op: "==" }` node (NOT a `stdlib.primitive.eq` call — that name is only the
// typechecker's internal type-resolution). Both VM paths handle it: the bytecode compiler lowers
// `op == "=="` → `OP_EQ` (`compiler.rs`), and `eval_ast` handles `"=="` in lambda/HOF bodies
// (`vm.rs`); both delegate to `value_eq_exact`, which compares String/Text, Integer, Bool, and
// (scale-normalized) Decimal. So this card is a CHARACTERIZATION + REGRESSION-LOCK, not a new
// implementation — no VM code changed.
//
// These tests guard the equality runtime through the REAL compiler → VM run path for the domains the
// frame-ui workaround removal (P7) depends on: String/Text, Integer, Bool, the exact record-field
// shape `rec.sel == rid`, and the `eval_ast` lambda path. Mismatched scalar types are rejected at
// COMPILE time (`OOF-TY0`), matching live typechecker policy — proven here too.

use std::path::PathBuf;
use std::process::Command;

fn igc() -> Option<PathBuf> {
    let p = PathBuf::from("../igniter-compiler/target/debug/igniter_compiler");
    if p.exists() {
        Some(p)
    } else {
        None
    }
}

fn vm_bin() -> &'static str {
    env!("CARGO_BIN_EXE_igniter-vm")
}

/// Compile `src` and return the compiler's stdout (so a test can assert ok vs `oof`).
fn compile(src: &str, tag: &str) -> Option<(PathBuf, String)> {
    let igc = igc()?;
    let dir = std::env::temp_dir().join(format!("prim_eq_{}_{}", tag, std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let f = dir.join("e.ig");
    std::fs::write(&f, src).unwrap();
    let igapp = dir.join("out.igapp");
    let c = Command::new(&igc)
        .args([
            "compile",
            f.to_str().unwrap(),
            "--out",
            igapp.to_str().unwrap(),
        ])
        .output()
        .expect("run igniter_compiler");
    Some((igapp, String::from_utf8_lossy(&c.stdout).to_string()))
}

/// Compile (asserting ok) + run `entry` with `inputs`, returning the VM's `--json` stdout.
fn compile_and_run(src: &str, entry: &str, inputs: &str, tag: &str) -> Option<String> {
    let (igapp, cout) = compile(src, tag)?;
    assert!(
        cout.contains("\"status\": \"ok\""),
        "compile must be ok: {cout}"
    );
    let dir = igapp.parent().unwrap();
    let inf = dir.join("in.json");
    std::fs::write(&inf, inputs).unwrap();
    let r = Command::new(vm_bin())
        .args([
            "run",
            "--contract",
            igapp.to_str().unwrap(),
            "--entry",
            entry,
            "--inputs",
            inf.to_str().unwrap(),
            "--json",
        ])
        .output()
        .expect("run igniter-vm");
    Some(String::from_utf8_lossy(&r.stdout).to_string())
}

const SCALARS: &str = r#"
module Lab.PrimEq
pure contract StrEq {
  input a : Text
  input b : Text
  compute result = a == b
  output result : Bool
}
pure contract IntEq {
  input a : Integer
  input b : Integer
  compute result = a == b
  output result : Bool
}
pure contract BoolEq {
  input a : Bool
  input b : Bool
  compute result = a == b
  output result : Bool
}
"#;

fn assert_result(out: &str, expected_true: bool) {
    assert!(
        out.contains("\"status\":\"success\""),
        "run must succeed: {out}"
    );
    let needle = if expected_true {
        "\"result\":true"
    } else {
        "\"result\":false"
    };
    assert!(out.contains(needle), "expected {needle} in: {out}");
}

#[test]
fn string_equality_true_and_false_through_compile_and_vm() {
    let Some(t) = compile_and_run(SCALARS, "StrEq", r#"{"a":"lead:1","b":"lead:1"}"#, "str_t")
    else {
        eprintln!("SKIP: igniter_compiler not built");
        return;
    };
    assert_result(&t, true);
    let f = compile_and_run(SCALARS, "StrEq", r#"{"a":"lead:1","b":"lead:2"}"#, "str_f").unwrap();
    assert_result(&f, false);
}

#[test]
fn integer_equality_true_and_false_through_compile_and_vm() {
    let Some(t) = compile_and_run(SCALARS, "IntEq", r#"{"a":1,"b":1}"#, "int_t") else {
        eprintln!("SKIP: igniter_compiler not built");
        return;
    };
    assert_result(&t, true);
    let f = compile_and_run(SCALARS, "IntEq", r#"{"a":1,"b":2}"#, "int_f").unwrap();
    assert_result(&f, false);
}

#[test]
fn bool_equality_true_and_false_through_compile_and_vm() {
    // Bool == Bool IS a compiler-supported equality shape (typechecker `==` compatible pairs),
    // so it is covered rather than documented out-of-scope.
    let Some(t) = compile_and_run(SCALARS, "BoolEq", r#"{"a":true,"b":true}"#, "bool_t") else {
        eprintln!("SKIP: igniter_compiler not built");
        return;
    };
    assert_result(&t, true);
    let f = compile_and_run(SCALARS, "BoolEq", r#"{"a":true,"b":false}"#, "bool_f").unwrap();
    assert_result(&f, false);
}

#[test]
fn record_field_equality_matches_frame_selected_state_shape() {
    // The exact shape the frame-ui reducer wanted to author: `result.sel == row_id`.
    let src = r#"
module Lab.PrimEqField
type Sel { sel : Text }
pure contract FieldEq {
  input rec : Sel
  input rid : Text
  compute result = rec.sel == rid
  output result : Bool
}
"#;
    let Some(t) = compile_and_run(
        src,
        "FieldEq",
        r#"{"rec":{"sel":"lead:2"},"rid":"lead:2"}"#,
        "fe_t",
    ) else {
        eprintln!("SKIP: igniter_compiler not built");
        return;
    };
    assert_result(&t, true);
    let f = compile_and_run(
        src,
        "FieldEq",
        r#"{"rec":{"sel":"lead:2"},"rid":"lead:9"}"#,
        "fe_f",
    )
    .unwrap();
    assert_result(&f, false);
}

#[test]
fn equality_inside_lambda_runs_through_eval_ast() {
    // The reducer-ish path: `==` inside a `filter` lambda body goes through `eval_ast`, not bytecode.
    let src = r#"
module Lab.PrimEqLambda
pure contract SelectedRows {
  input ids : Collection[Text]
  input sel : Text
  compute result = filter(ids, x -> x == sel)
  output result : Collection[Text]
}
"#;
    let Some(out) = compile_and_run(
        src,
        "SelectedRows",
        r#"{"ids":["lead:1","lead:2","lead:3"],"sel":"lead:2"}"#,
        "lam",
    ) else {
        eprintln!("SKIP: igniter_compiler not built");
        return;
    };
    assert!(
        out.contains("\"status\":\"success\""),
        "run must succeed: {out}"
    );
    assert!(
        out.contains("lead:2") && !out.contains("lead:1") && !out.contains("lead:3"),
        "filter x==sel must keep only the matching id: {out}"
    );
}

#[test]
fn mismatched_scalar_equality_is_rejected_at_compile_time() {
    // Q5 policy (live typechecker): mismatched non-Unknown scalar `==` is a COMPILE error
    // (`OOF-TY0`, "cannot compare …"), NOT a runtime false/error. Lock that boundary.
    let src = r#"
module Lab.PrimEqBad
pure contract BadEq {
  input i : Integer
  input t : Text
  compute result = i == t
  output result : Bool
}
"#;
    let Some((_igapp, cout)) = compile(src, "bad") else {
        eprintln!("SKIP: igniter_compiler not built");
        return;
    };
    assert!(
        cout.contains("OOF-TY0") && cout.contains("cannot compare"),
        "mismatched scalar == must be rejected at compile time with OOF-TY0: {cout}"
    );
}
