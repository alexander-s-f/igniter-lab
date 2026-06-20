// tests/signature_contract_surface_tests.rs — LAB-LANG-SIGNATURE-BOUND-CONTRACT-SURFACE-P2
// The compact `(in: T) -> (out: U) { name = expr }` surface DESUGARS to canonical
// `input`/`compute`/`output` body decls. Parity is proven at the AST level: the signature form's
// parsed `body` is byte-identical (as serde value) to the explicit form's — identical AST ⟹ identical
// SemanticIR by construction. Only `=` bindings; no `<-`/`?`/comprehensions/`let` here.

use igniter_compiler::lexer::Lexer;
use igniter_compiler::parser::Parser;
use serde_json::Value;

fn parse(src: &str) -> igniter_compiler::parser::SourceFile {
    let mut lexer = Lexer::new(src);
    let tokens = lexer.tokenize();
    Parser::new(tokens).parse()
}

fn body_json(src: &str) -> Value {
    let sf = parse(src);
    serde_json::to_value(&sf.contracts[0].body).unwrap()
}

// ── 1: single input/output desugar parity ────────────────────────────────────────────────────────

#[test]
fn single_signature_desugars_identically_to_explicit() {
    let sig = "module M
pure contract RenderPage(req: Request) -> (d: Decision) {
  d = Render { status: 200, artifact_json: req }
}";
    let explicit = "module M
pure contract RenderPage {
  input req : Request
  compute d : Decision = Render { status: 200, artifact_json: req }
  output d : Decision
}";
    assert_eq!(
        body_json(sig),
        body_json(explicit),
        "signature-form body must desugar byte-identically to the explicit body"
    );
}

// ── 2: intermediate node + multi-output parity ───────────────────────────────────────────────────

#[test]
fn intermediate_and_multi_output_desugar_identically() {
    let sig = "module M
pure contract Build(req: Request) -> (status: Integer, body: String) {
  prepared : String = Prepare { req: req }
  status = 200
  body = prepared
}";
    let explicit = "module M
pure contract Build {
  input req : Request
  compute prepared : String = Prepare { req: req }
  compute status : Integer = 200
  compute body : String = prepared
  output status : Integer
  output body : String
}";
    // Note: in the signature form the output computes (`status`, `body`) inherit their type from the
    // signature; the intermediate (`prepared`) carries its explicit type. Both → the same AST.
    assert_eq!(body_json(sig), body_json(explicit));
}

// ── 3: missing output binding is a clear diagnostic ──────────────────────────────────────────────

#[test]
fn missing_output_binding_is_rejected() {
    let sig = "module M
pure contract Bad(x: Integer) -> (y: Integer, z: Integer) {
  y = x
}";
    let sf = parse(sig);
    assert!(
        sf.parse_errors
            .iter()
            .any(|e| e.message.contains("output `z` is not defined")),
        "missing output must be diagnosed, got: {:?}",
        sf.parse_errors
    );
}

// ── 4: duplicate body binding is a clear diagnostic ──────────────────────────────────────────────

#[test]
fn duplicate_body_binding_is_rejected() {
    let sig = "module M
pure contract Dup(x: Integer) -> (y: Integer) {
  t : Integer = x
  t : Integer = x
  y = t
}";
    let sf = parse(sig);
    assert!(
        sf.parse_errors
            .iter()
            .any(|e| e.message.contains("duplicate body binding")),
        "duplicate body binding must be diagnosed, got: {:?}",
        sf.parse_errors
    );
}

// ── 5: explicit (signature-less) contracts are unchanged ─────────────────────────────────────────

#[test]
fn signatureless_contract_still_parses() {
    let explicit = "module M
pure contract Plain {
  input x : Integer
  compute y : Integer = x
  output y : Integer
}";
    let sf = parse(explicit);
    assert_eq!(sf.contracts.len(), 1);
    assert!(sf.parse_errors.is_empty(), "explicit form unaffected: {:?}", sf.parse_errors);
    // 1 input + 1 compute + 1 output
    assert_eq!(sf.contracts[0].body.len(), 3);
}
