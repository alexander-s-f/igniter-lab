// tests/user_fn_signature_check_tests.rs
// LAB-IGNITER-COMPILER-USER-FN-SIGNATURE-CHECK-P6 / audit-control-board A19 (§B-U1).
//
// Before this slice, an `Expr::Call` to an app-local user `def` was resolved by NAME ALONE
// (typechecker.rs `infer_expr`): the checker looked the function up, trusted its
// `return_type`, and never compared the call's argument arity or argument types against the
// declared parameters. A def could therefore be called with the wrong number of arguments, or
// with arguments of the wrong type, and the program still typechecked clean.
//
// This slice validates the call signature at the resolution site, reusing the P5 `IgType`
// structural-assignability boundary so generic parameters (`Collection[Integer]` vs
// `Collection[Text]`) are distinguished. Faults are emitted as OOF-TY0, the established
// type-soundness code used by the binding/output boundaries.

use igniter_compiler::classifier::Classifier;
use igniter_compiler::lexer::Lexer;
use igniter_compiler::parser::Parser;
use igniter_compiler::typechecker::TypeChecker;

/// Typechecker diagnostic rule codes (signature checking lives in the typechecker pass).
fn typecheck_codes(src: &str) -> Vec<String> {
    let mut lexer = Lexer::new(src);
    let tokens = lexer.tokenize();
    let mut parser = Parser::new(tokens);
    let parsed = parser.parse();
    let classified = Classifier::new().classify(&parsed, &serde_json::Value::Null);
    let typed = TypeChecker::new().typecheck(&classified, &parsed.functions);
    typed.type_errors.iter().map(|d| d.rule.clone()).collect()
}

/// Typechecker diagnostic messages (for asserting the arity vs param-type distinction).
fn typecheck_messages(src: &str) -> Vec<String> {
    let mut lexer = Lexer::new(src);
    let tokens = lexer.tokenize();
    let mut parser = Parser::new(tokens);
    let parsed = parser.parse();
    let classified = Classifier::new().classify(&parsed, &serde_json::Value::Null);
    let typed = TypeChecker::new().typecheck(&classified, &parsed.functions);
    typed
        .type_errors
        .iter()
        .map(|d| d.message.clone())
        .collect()
}

fn count(codes: &[String], rule: &str) -> usize {
    codes.iter().filter(|c| c.as_str() == rule).count()
}

// ── the core gap: wrong arity ────────────────────────────────────────────────────

#[test]
fn wrong_arity_too_many_args_is_oof_ty0() {
    let src = "module Lab.Sig
def ident(a: Float) -> Float {
  a
}
pure contract C {
  input n : Float
  compute result = ident(n, n)
}";
    let codes = typecheck_codes(src);
    assert!(
        codes.contains(&"OOF-TY0".to_string()),
        "calling a 1-param def with 2 args must fail OOF-TY0; got {codes:?}"
    );
    let msgs = typecheck_messages(src);
    assert!(
        msgs.iter()
            .any(|m| m.contains("expected 1 argument") && m.contains("got 2")),
        "arity message names expected/got counts; got {msgs:?}"
    );
}

#[test]
fn wrong_arity_too_few_args_is_oof_ty0() {
    let src = "module Lab.Sig
def add(a: Float, b: Float) -> Float {
  a
}
pure contract C {
  input n : Float
  compute result = add(n)
}";
    let codes = typecheck_codes(src);
    assert!(
        codes.contains(&"OOF-TY0".to_string()),
        "calling a 2-param def with 1 arg must fail OOF-TY0; got {codes:?}"
    );
}

// ── wrong parameter type (concrete named) ────────────────────────────────────────

#[test]
fn wrong_named_param_type_is_oof_ty0() {
    let src = "module Lab.Sig
def need_float(a: Float) -> Float {
  a
}
pure contract C {
  input t : Text
  compute result = need_float(t)
}";
    let codes = typecheck_codes(src);
    assert!(
        codes.contains(&"OOF-TY0".to_string()),
        "passing Text where a Float param is declared must fail OOF-TY0; got {codes:?}"
    );
    let msgs = typecheck_messages(src);
    assert!(
        msgs.iter()
            .any(|m| m.contains("parameter 'a'") && m.contains("Float") && m.contains("Text")),
        "param-type message names the parameter and both types; got {msgs:?}"
    );
}

// ── wrong parameter type (generic): the P5 structural boundary at the call site ───

#[test]
fn wrong_generic_param_type_is_oof_ty0() {
    let src = "module Lab.Sig
def take_text_col(xs: Collection[Text], fallback: Float) -> Float {
  fallback
}
pure contract C {
  input ints : Collection[Integer]
  input n : Float
  compute result = take_text_col(ints, n)
}";
    let codes = typecheck_codes(src);
    assert!(
        codes.contains(&"OOF-TY0".to_string()),
        "Collection[Integer] into a Collection[Text] param must fail OOF-TY0 (structural); got {codes:?}"
    );
    // The arity is correct (2 = 2), so this is a parameter-type fault, not arity.
    let msgs = typecheck_messages(src);
    assert!(
        msgs.iter().any(|m| m.contains("parameter 'xs'")),
        "the generic fault names the offending parameter; got {msgs:?}"
    );
}

// ── valid calls still compile (no over-tightening) ───────────────────────────────

#[test]
fn valid_named_call_is_clean() {
    let src = "module Lab.Sig
def ident(a: Float) -> Float {
  a
}
pure contract C {
  input n : Float
  compute result = ident(n)
}";
    let codes = typecheck_codes(src);
    assert_eq!(
        count(&codes, "OOF-TY0"),
        0,
        "a correctly-typed, correct-arity call must not raise OOF-TY0; got {codes:?}"
    );
}

#[test]
fn valid_generic_call_is_clean() {
    // Same shape as `wrong_generic_param_type_is_oof_ty0` but with a matching element type:
    // proves the structural check does not over-tighten on generics.
    let src = "module Lab.Sig
def take_text_col(xs: Collection[Text], fallback: Float) -> Float {
  fallback
}
pure contract C {
  input texts : Collection[Text]
  input n : Float
  compute result = take_text_col(texts, n)
}";
    let codes = typecheck_codes(src);
    assert_eq!(
        count(&codes, "OOF-TY0"),
        0,
        "a matching Collection[Text] argument must not raise OOF-TY0; got {codes:?}"
    );
}
