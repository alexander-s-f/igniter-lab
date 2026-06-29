// tests/if_cond_bare_ident_before_brace_tests.rs
// LAB-LANG-PARSE-BARE-IDENT-BEFORE-BRACE-P1
//
// FALSIFICATION + regression-lock. The game/frame specimens (P6/P7) avoided the natural spelling
// `if b.id == target { ... }` / `if ready { ... }`, believing a bare identifier immediately before
// `{` mis-parses as a record/variant construction. Verify-first on the live parser shows this is NOT
// true for VALUE identifiers: the variant-construct trigger (`parser.rs`) fires ONLY for a
// **PascalCase** ident immediately before `{`; a lowercase value identifier before `{` parses as a
// plain `Ref`, so the `{` correctly opens the `if` body. (A PascalCase comparand before `{` - a type
// /variant name - is a genuine construct, which is correct, not a bug.)
//
// These tests lock the natural `if` shapes (no parse error, clean typecheck) and the record-literal
// control, so the surface can't silently regress.

use igniter_compiler::classifier::Classifier;
use igniter_compiler::lexer::Lexer;
use igniter_compiler::parser::Parser;
use igniter_compiler::typechecker::TypeChecker;

/// (parser-error rules, typechecker-error rules) for a source string.
fn compile_errors(src: &str) -> (Vec<String>, Vec<String>) {
    let mut lexer = Lexer::new(src);
    let tokens = lexer.tokenize();
    let mut parser = Parser::new(tokens);
    let parsed = parser.parse();
    let parse_errs: Vec<String> = parsed.parse_errors.iter().map(|e| e.rule.clone()).collect();
    let classified = Classifier::new().classify(&parsed, &serde_json::Value::Null);
    let typed = TypeChecker::new().typecheck(&classified, &parsed.functions);
    let type_errs: Vec<String> = typed.type_errors.iter().map(|d| d.rule.clone()).collect();
    (parse_errs, type_errs)
}

fn assert_clean(label: &str, src: &str) {
    let (pe, te) = compile_errors(src);
    assert!(
        pe.is_empty(),
        "{label}: must have NO parse errors, got {pe:?}"
    );
    assert!(
        te.is_empty(),
        "{label}: must have NO type errors, got {te:?}"
    );
}

const PRELUDE: &str = "module Lab.IfBraceProbe\ntype B { id : Text }\n";

fn contract(body: &str) -> String {
    format!("{PRELUDE}pure contract C {{\n{body}\n}}\n")
}

// -- (1) field/lhs equality before a block: `if b.id == target { ... }` ---------------------------
#[test]
fn field_eq_before_block_parses_as_if_not_construct() {
    assert_clean(
        "field-eq before block",
        &contract(
            "  input b : B\n  input target : Text\n\
             compute r = if b.id == target { 1 } else { 0 }\n  output r : Integer",
        ),
    );
}

// -- (2) bare identifier equality before a block: `if current == target { ... }` ------------------
#[test]
fn bare_ident_eq_before_block_parses_as_if_not_construct() {
    assert_clean(
        "bare-ident-eq before block",
        &contract(
            "  input current : Text\n  input target : Text\n\
             compute r = if current == target { 1 } else { 0 }\n  output r : Integer",
        ),
    );
}

// -- (3) bare Bool condition: `if ready { ... }` --------------------------------------------------
#[test]
fn bare_bool_condition_parses() {
    assert_clean(
        "bare-Bool condition",
        &contract("  input ready : Bool\n  compute r = if ready { 1 } else { 0 }\n  output r : Integer"),
    );
}

// -- (4) control cases (the workaround spellings) still parse -------------------------------------
#[test]
fn control_reversed_and_eq_true_still_parse() {
    assert_clean(
        "reversed comparand (workaround)",
        &contract(
            "  input b : B\n  input target : Text\n\
             compute r = if target == b.id { 1 } else { 0 }\n  output r : Integer",
        ),
    );
    assert_clean(
        "eq-true (workaround)",
        &contract("  input ready : Bool\n  compute r = if ready == true { 1 } else { 0 }\n  output r : Integer"),
    );
}

// -- (5) record literals still parse under typed annotation (no regression) -----------------------
#[test]
fn record_literal_still_parses() {
    let src = "module Lab.IfBraceProbe\ntype R { id : Text  ready : Bool }\n\
        pure contract C {\n  input target : Text\n  input ready : Bool\n\
        compute r = { id: target, ready: ready }\n  output r : R\n}\n";
    assert_clean("record literal", src);
}

// -- game-exact nested shape: natural spelling with a nested `if` body -----------------------------
#[test]
fn game_exact_nested_natural_spelling_parses() {
    let src = "module Lab.IfBraceProbe\ntype B { id : Integer  px : Integer }\n\
        pure contract C {\n  input b : B\n  input target : Integer\n\
        compute kx = if b.id == target { if b.px > 0 { 700 } else { 0 } } else { 0 }\n\
        output kx : Integer\n}\n";
    assert_clean("game-exact nested natural", src);
}

// -- boundary lock: a PascalCase ident before `{` IS still a variant construct (intended) ---------
// This documents WHY the value-ident case is unambiguous: the construct trigger is case-gated. A
// PascalCase comparand before `{` is a genuine construct, so this shape does NOT parse as an `if`
// body - proving the disambiguation is by case, not an accident.
#[test]
fn pascalcase_before_brace_is_still_a_construct_not_an_if_body() {
    // `Foo` is PascalCase -> `Foo { ... }` is parsed as a variant construct, so this `if` has no
    // recognizable boolean condition + block and does NOT compile clean. (Contrast (1)/(2) above.)
    let src = "module Lab.IfBraceProbe\ntype B { id : Text }\n\
        pure contract C {\n  input b : B\n\
        compute r = if b.id == Foo { 1 } else { 0 }\n  output r : Integer\n}\n";
    let (pe, te) = compile_errors(src);
    assert!(
        !pe.is_empty() || !te.is_empty(),
        "a PascalCase comparand before `{{` is a construct, so this must NOT compile clean as an if-body"
    );
}
