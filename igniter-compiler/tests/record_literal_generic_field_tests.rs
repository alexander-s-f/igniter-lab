// tests/record_literal_generic_field_tests.rs
// LAB-IGNITER-COMPILER-RECORD-LITERAL-NONINLINE-FIELD-TYPING-P7 / audit-control-board A19 (§B-U3).
//
// Closes the last A19/IgType tail: a NON-INLINE record-literal field value (a `Ref` or `Literal`,
// not an inline nested record) was compared to the declared field type by OUTER NAME ONLY in
// `check_record_literal_shape`. So `Collection[Integer]` assigned into a `Collection[Text]` record
// field passed silently (both names are "Collection"). This slice routes that comparison through the
// P5 `IgType` structural boundary (the same one P5 used for variant fields and P6 for user-fn args),
// so the element parameter is checked. Scalars are unaffected; faults remain OOF-TY0.
//
// Proven end-to-end through the real compiler binary, mirroring the sibling record tests.

use std::process::Command;

fn bin() -> &'static str {
    env!("CARGO_BIN_EXE_igniter_compiler")
}

/// Compile one `.ig` source; return its compiler-result stdout (JSON).
fn compile(src: &str, tag: &str) -> String {
    let dir = std::env::temp_dir().join(format!("rec_gen_{}_{}", tag, std::process::id()));
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

// ── the bug: generic element mismatch in a non-inline record field now fails closed ──

#[test]
fn collection_integer_into_collection_text_field_fails_closed() {
    // `tags` is declared Collection[Text]; the field value `ints` is a Ref to a Collection[Integer]
    // input — a non-inline value. Name-only comparison accepted this; structural must reject it.
    let src = "type Tagged { tags : Collection[Text] }\n\
        contract C { input ints : Collection[Integer]  compute r : Tagged = { tags: ints }  output r : Tagged }";
    let out = compile(src, "gen_mismatch");
    assert!(
        !is_ok(&out),
        "Collection[Integer] into Collection[Text] must fail: {out}"
    );
    assert!(out.contains("OOF-TY0"), "fault is OOF-TY0: {out}");
    assert!(
        out.contains("Collection[Text]") && out.contains("Collection[Integer]"),
        "message names both generic types with their element params: {out}"
    );
}

// ── matching generic field still compiles (no over-tightening) ──────────────────────

#[test]
fn collection_text_into_collection_text_field_compiles() {
    let src = "type Tagged { tags : Collection[Text] }\n\
        contract C { input texts : Collection[Text]  compute r : Tagged = { tags: texts }  output r : Tagged }";
    let out = compile(src, "gen_match");
    assert!(
        is_ok(&out),
        "Collection[Text] into Collection[Text] must compile: {out}"
    );
}

// ── ordinary scalar record literal still compiles ───────────────────────────────────

#[test]
fn ordinary_scalar_record_literal_compiles() {
    let src = "type P { n : Integer  name : Text }\n\
        contract C { input n : Integer  input name : Text  compute r : P = { n: n, name: name }  output r : P }";
    let out = compile(src, "scalar_ok");
    assert!(
        is_ok(&out),
        "an ordinary record literal must still compile: {out}"
    );
}

// ── scalar mismatch still fails (the name-only check this preserves) ─────────────────

#[test]
fn scalar_field_mismatch_still_fails_closed() {
    // Text into an Integer field — caught by name-only before, must remain caught structurally.
    let src = "type P { n : Integer }\n\
        contract C { input t : Text  compute r : P = { n: t }  output r : P }";
    let out = compile(src, "scalar_mismatch");
    assert!(
        !is_ok(&out),
        "Text into an Integer field must still fail: {out}"
    );
    assert!(out.contains("OOF-TY0"), "fault is OOF-TY0: {out}");
}
