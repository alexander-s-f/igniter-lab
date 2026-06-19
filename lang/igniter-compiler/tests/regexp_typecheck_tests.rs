// tests/regexp_typecheck_tests.rs — LAB-STDLIB-REGEXP-P3
// Typechecker registration of stdlib.regexp.{matches,capture}: arity/type diagnostics + literal
// invalid-pattern diagnostic (OOF-RE1). In-process pipeline (no subprocess, no VM).

use igniter_compiler::classifier::Classifier;
use igniter_compiler::lexer::Lexer;
use igniter_compiler::parser::Parser;
use igniter_compiler::typechecker::TypeChecker;

/// Compile `src` through lex→parse→classify→typecheck and return all typechecker diagnostic rule codes.
fn type_rules(src: &str) -> Vec<String> {
    let tokens = Lexer::new(src).tokenize();
    let parsed = Parser::new(tokens).parse();
    let classified = Classifier::new().classify(&parsed, &serde_json::Value::Null);
    let typed = TypeChecker::new().typecheck(&classified, &parsed.functions);
    typed.type_errors.iter().map(|d| d.rule.clone()).collect()
}

fn contract(body: &str) -> String {
    format!(
        "module RegexpTest\ncontract R {{\n  input path : String\n  input pat : String\n{}\n}}",
        body
    )
}

#[test]
fn valid_matches_and_capture_compile_clean() {
    let rules = type_rules(&contract(
        "  compute ok : Bool = matches(path, pat)\n  compute id : Option[String] = capture(path, pat, 1)\n  output ok : Bool\n  output id : Option[String]",
    ));
    assert!(
        !rules.iter().any(|r| r == "OOF-TY0"),
        "no arity/type error, got {rules:?}"
    );
    assert!(
        !rules.iter().any(|r| r == "OOF-RE1"),
        "dynamic pattern is not a literal error, got {rules:?}"
    );
}

#[test]
fn matches_wrong_arity_is_oof_ty0() {
    let rules = type_rules(&contract(
        "  compute ok : Bool = matches(path)\n  output ok : Bool",
    ));
    assert!(
        rules.iter().any(|r| r == "OOF-TY0"),
        "1-arg matches must error, got {rules:?}"
    );
}

#[test]
fn capture_wrong_arity_is_oof_ty0() {
    let rules = type_rules(&contract(
        "  compute id : Option[String] = capture(path, pat)\n  output id : Option[String]",
    ));
    assert!(
        rules.iter().any(|r| r == "OOF-TY0"),
        "2-arg capture must error, got {rules:?}"
    );
}

#[test]
fn capture_wrong_index_type_is_oof_ty0() {
    // arg 3 should be Integer; passing a String must error.
    let rules = type_rules(&contract(
        "  compute id : Option[String] = capture(path, pat, path)\n  output id : Option[String]",
    ));
    assert!(
        rules.iter().any(|r| r == "OOF-TY0"),
        "non-Integer index must error, got {rules:?}"
    );
}

#[test]
fn literal_invalid_pattern_is_oof_re1() {
    let rules = type_rules(&contract(
        "  compute ok : Bool = matches(path, \"(\")\n  output ok : Bool",
    ));
    assert!(
        rules.iter().any(|r| r == "OOF-RE1"),
        "literal bad pattern must be OOF-RE1, got {rules:?}"
    );
}

#[test]
fn literal_lookaround_is_oof_re1() {
    let rules = type_rules(&contract(
        "  compute ok : Bool = matches(path, \"foo(?=bar)\")\n  output ok : Bool",
    ));
    assert!(
        rules.iter().any(|r| r == "OOF-RE1"),
        "literal lookaround must be OOF-RE1, got {rules:?}"
    );
}

#[test]
fn dynamic_pattern_has_no_literal_diagnostic() {
    // a dynamic (non-literal) pattern is valid at compile time; runtime validates it.
    let rules = type_rules(&contract(
        "  compute ok : Bool = matches(path, pat)\n  output ok : Bool",
    ));
    assert!(
        !rules.iter().any(|r| r == "OOF-RE1"),
        "dynamic pattern must not be OOF-RE1, got {rules:?}"
    );
}

#[test]
fn literal_valid_pattern_compiles() {
    let rules = type_rules(&contract(
        "  compute ok : Bool = matches(path, \"^/todos/([0-9]+)$\")\n  output ok : Bool",
    ));
    assert!(
        !rules.iter().any(|r| r == "OOF-RE1"),
        "valid literal pattern must not error, got {rules:?}"
    );
}
