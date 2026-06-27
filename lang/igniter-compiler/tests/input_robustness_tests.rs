// LAB-IGNITER-COMPILER-INPUT-ROBUSTNESS-P1
// Parser-local crash safety: adversarial nesting and non-finite Float literals
// become parse diagnostics instead of process panics/SIGABRT.

use igniter_compiler::lexer::Lexer;
use igniter_compiler::parser::Parser;

fn parse_errors(src: &str) -> Vec<String> {
    Parser::new(Lexer::new(src).tokenize())
        .parse()
        .parse_errors
        .into_iter()
        .map(|e| e.rule)
        .collect()
}

fn huge_float_literal() -> String {
    format!("{}.0", "9".repeat(5000))
}

#[test]
fn deeply_parenthesized_expression_is_diagnostic_not_stack_overflow() {
    let depth = 600;
    let expr = format!("{}1{}", "(".repeat(depth), ")".repeat(depth));
    let src = format!(
        "pure contract Deep {{ input x : Integer compute y : Integer = {expr} output y : Integer }}"
    );

    let rules = parse_errors(&src);

    assert!(
        rules.iter().any(|rule| rule == "OOF-PDEPTH"),
        "deep parenthesized expression must report OOF-PDEPTH, got {rules:?}"
    );
}

#[test]
fn deeply_nested_array_expression_is_diagnostic_not_stack_overflow() {
    let depth = 600;
    let expr = format!("{}1{}", "[".repeat(depth), "]".repeat(depth));
    let src = format!(
        "pure contract DeepArray {{ input x : Integer compute y : Collection[Integer] = {expr} output y : Collection[Integer] }}"
    );

    let rules = parse_errors(&src);

    assert!(
        rules.iter().any(|rule| rule == "OOF-PDEPTH"),
        "deep array expression must report OOF-PDEPTH, got {rules:?}"
    );
}

#[test]
fn huge_float_expression_literal_is_diagnostic_not_panic() {
    let literal = huge_float_literal();
    let src = format!(
        "pure contract HugeFloat {{ input x : Float compute y : Float = {literal} output y : Float }}"
    );

    let rules = parse_errors(&src);

    assert!(
        rules.iter().any(|rule| rule == "OOF-PFLOAT"),
        "huge FloatLit must report OOF-PFLOAT, got {rules:?}"
    );
}

#[test]
fn huge_assumption_strength_literal_is_diagnostic_not_panic() {
    let literal = huge_float_literal();
    let src = format!(
        r#"assumptions {{
  assumption AuditClaim {{
    kind: :evidence
    statement: "oversized strength"
    source: "audit"
    strength: {literal}
  }}
}}"#
    );

    let rules = parse_errors(&src);

    assert!(
        rules.iter().any(|rule| rule == "OOF-PFLOAT"),
        "huge assumption strength must report OOF-PFLOAT, got {rules:?}"
    );
}
