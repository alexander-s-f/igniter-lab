// tests/array_literal_element_typing_tests.rs
// LAB-IGNITER-COMPILER-ARRAY-LITERAL-ELEMENT-TYPING-P9 / audit-control-board A19.
//
// Array-literal element validation now uses the P5 IgType structural boundary for
// simple non-record elements. This locks the old name-only tail in
// check_array_literal_shape while preserving v0's Unknown-compatible skips for
// complex expressions the compiler does not infer at this shape-check boundary.

use std::process::Command;

fn bin() -> &'static str {
    env!("CARGO_BIN_EXE_igniter_compiler")
}

fn compile(src: &str, tag: &str) -> String {
    let dir = std::env::temp_dir().join(format!("arr_elem_{}_{}", tag, std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let f = dir.join("m.ig");
    std::fs::write(&f, src).unwrap();
    let out = dir.join("out");
    let output = Command::new(bin())
        .args([
            "compile",
            f.to_str().unwrap(),
            "--out",
            out.to_str().unwrap(),
        ])
        .output()
        .expect("run igniter_compiler");
    String::from_utf8_lossy(&output.stdout).to_string()
}

fn is_ok(stdout: &str) -> bool {
    stdout.contains("\"status\": \"ok\"")
}

#[test]
fn collection_integer_array_literal_compiles() {
    let src =
        "contract C { compute xs : Collection[Integer] = [1, 2]  output xs : Collection[Integer] }";
    let out = compile(src, "ints_ok");
    assert!(
        is_ok(&out),
        "Collection[Integer] literal with Integer elements must compile: {out}"
    );
}

#[test]
fn mixed_scalar_array_literal_fails_closed() {
    let src = "contract C { compute xs : Collection[Integer] = [1, \"x\"]  output xs : Collection[Integer] }";
    let out = compile(src, "mixed_scalar");
    assert!(
        !is_ok(&out),
        "Collection[Integer] literal with a String element must fail: {out}"
    );
    assert!(out.contains("OOF-TY0"), "fault is OOF-TY0: {out}");
    assert!(
        out.contains("expected Integer, got String"),
        "diagnostic names expected and actual scalar types: {out}"
    );
}

#[test]
fn string_literals_are_assignable_to_collection_text() {
    let src =
        "contract C { compute xs : Collection[Text] = [\"a\", \"b\"]  output xs : Collection[Text] }";
    let out = compile(src, "text_alias");
    assert!(
        is_ok(&out),
        "String literal tags must be assignable to Text through IgType: {out}"
    );
}

#[test]
fn record_element_array_literal_compiles() {
    let src = "type Row { id : Text  n : Integer }\n\
        contract C { compute rows : Collection[Row] = [{ id: \"a\", n: 1 }]  output rows : Collection[Row] }";
    let out = compile(src, "record_ok");
    assert!(
        is_ok(&out),
        "Collection[Row] literal with matching record element must compile: {out}"
    );
}

#[test]
fn wrong_record_field_type_inside_array_literal_fails_closed() {
    let src = "type Row { id : Text  n : Integer }\n\
        contract C { compute rows : Collection[Row] = [{ id: \"a\", n: \"x\" }]  output rows : Collection[Row] }";
    let out = compile(src, "record_bad_field");
    assert!(
        !is_ok(&out),
        "wrong record field type inside array literal must fail: {out}"
    );
    assert!(out.contains("OOF-TY0"), "fault is OOF-TY0: {out}");
    assert!(
        out.contains("field 'n' expects Integer, got String"),
        "diagnostic points at the record field mismatch: {out}"
    );
}

#[test]
fn complex_element_expression_remains_deferred() {
    let src = "contract C { input a : Integer  input b : Integer  compute xs : Collection[Integer] = [a + b]  output xs : Collection[Integer] }";
    let out = compile(src, "complex_deferred");
    assert!(
        is_ok(&out),
        "complex element expressions remain Unknown-compatible in the array shape check: {out}"
    );
}
