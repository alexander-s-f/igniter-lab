// tests/string_escapes_tests.rs — LAB-LANG-STRING-ESCAPES-P1
//
// `.ig` string literals now decode a minimal conventional escape set (`\"` `\\` `\n` `\t` `\r`). Invalid
// escapes and unterminated strings become an `Illegal` token the parser surfaces as `OOF-LEX1`. Ordinary
// (escape-free) strings are unchanged. Lexer-level proves the decoded value; parser-level proves the error
// path. The `.ig` sources are written as Rust raw strings so the backslashes are exactly what the lexer sees.

use igniter_compiler::lexer::{Lexer, Token, TokenType};
use igniter_compiler::parser::Parser;

fn lex_first(src: &str) -> Token {
    Lexer::new(src).tokenize().into_iter().next().unwrap()
}

/// Decoded value of the first token, asserting it lexed as a `StringLit`.
fn str_value(src: &str) -> String {
    let t = lex_first(src);
    assert_eq!(
        t.token_type,
        TokenType::StringLit,
        "expected StringLit for {src:?}, got {:?} ({})",
        t.token_type,
        t.value
    );
    t.value
}

fn has_lex_error(src: &str) -> bool {
    Parser::new(Lexer::new(src).tokenize())
        .parse()
        .parse_errors
        .iter()
        .any(|e| e.rule == "OOF-LEX1")
}

// ── decode valid escapes ─────────────────────────────────────────────────────────────────────────

#[test]
fn decodes_escaped_quote() {
    // .ig source: "say \"hi\""  →  say "hi"
    assert_eq!(str_value(r#""say \"hi\"""#), "say \"hi\"");
}

#[test]
fn decodes_escaped_backslash() {
    // .ig source: "a\\b"  →  a\b
    assert_eq!(str_value(r#""a\\b""#), "a\\b");
}

#[test]
fn decodes_newline_tab_cr() {
    assert_eq!(str_value(r#""x\ny""#), "x\ny");
    assert_eq!(str_value(r#""x\ty""#), "x\ty");
    assert_eq!(str_value(r#""x\ry""#), "x\ry");
}

#[test]
fn decodes_json_shaped_string() {
    // the exact case the IgWeb render proofs had to route around.
    assert_eq!(str_value(r#""{\"body\":\"ok\"}""#), "{\"body\":\"ok\"}");
}

#[test]
fn ordinary_string_is_unchanged() {
    assert_eq!(str_value(r#""hello world""#), "hello world");
    assert_eq!(str_value(r#""^/todos/([^/]+)$""#), "^/todos/([^/]+)$"); // a regex literal (no backslash)
}

// ── invalid escapes / unterminated → Illegal token + OOF-LEX1 ────────────────────────────────────

#[test]
fn invalid_escape_is_illegal_token() {
    let t = lex_first(r#""\q""#);
    assert_eq!(t.token_type, TokenType::Illegal);
    assert!(t.value.contains("invalid string escape"), "got: {}", t.value);
}

#[test]
fn unterminated_string_is_illegal_token() {
    let t = lex_first(r#""abc"#); // no closing quote
    assert_eq!(t.token_type, TokenType::Illegal);
    assert!(t.value.contains("unterminated"), "got: {}", t.value);
}

#[test]
fn trailing_backslash_is_illegal_token() {
    let t = lex_first("\"abc\\"); // .ig source: "abc\  (backslash then EOF)
    assert_eq!(t.token_type, TokenType::Illegal);
    assert!(t.value.contains("unterminated"), "got: {}", t.value);
}

// ── compile-level: the lexer error surfaces as a parse diagnostic; valid escapes don't ────────────

#[test]
fn valid_escape_contract_has_no_lex_error() {
    let src = r#"contract Esc { input x : String compute s : String = "{\"body\":\"ok\"}" output s : String }"#;
    assert!(!has_lex_error(src), "valid-escape contract must not raise OOF-LEX1");
}

#[test]
fn invalid_escape_contract_reports_oof_lex1() {
    let src = r#"contract Esc { input x : String compute s : String = "bad \q here" output s : String }"#;
    assert!(has_lex_error(src), "invalid escape must surface OOF-LEX1");
}
