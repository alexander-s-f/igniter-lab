// tests/effect_summary_interprocedural_tests.rs
// NW-T2-4 / audit-control-board A20 (compiler §B-U5): interprocedural effect summary.
//
// Before this slice, purity was decided by an inline `stdlib.IO.` prefix scan over contract
// bodies only (classifier::expr_has_io_call). A helper `def` that performed I/O presented as a
// plain call, so a `pure` contract could launder effects through it and OOF-M1 never fired.
//
// This slice computes a transitive per-`def` `ambient_io` summary over the same call graph used
// for the OOF-L4 recursion gate, and has the typechecker flag any `pure` contract that reaches an
// effectful def. Diagnostic code is OOF-M1 (the pure-modifier violation family), matching the
// classifier's direct-I/O purity check; the message distinguishes the transitive helper path.

use igniter_compiler::classifier::Classifier;
use igniter_compiler::lexer::Lexer;
use igniter_compiler::parser::Parser;
use igniter_compiler::typechecker::TypeChecker;

/// Typechecker diagnostic rule codes (the effect summary lives in the typechecker pass).
fn typecheck_codes(src: &str) -> Vec<String> {
    let mut lexer = Lexer::new(src);
    let tokens = lexer.tokenize();
    let mut parser = Parser::new(tokens);
    let parsed = parser.parse();
    let classified = Classifier::new().classify(&parsed, &serde_json::Value::Null);
    let typed = TypeChecker::new().typecheck(&classified, &parsed.functions);
    typed.type_errors.iter().map(|d| d.rule.clone()).collect()
}

/// Classifier diagnostic rule codes (direct, intra-contract I/O checks).
fn classifier_codes(src: &str) -> Vec<String> {
    let mut lexer = Lexer::new(src);
    let tokens = lexer.tokenize();
    let mut parser = Parser::new(tokens);
    let parsed = parser.parse();
    let classified = Classifier::new().classify(&parsed, &serde_json::Value::Null);
    classified
        .contracts
        .iter()
        .flat_map(|c| c.oof_log.iter().map(|d| d.rule.clone()))
        .collect()
}

fn count(codes: &[String], rule: &str) -> usize {
    codes.iter().filter(|c| c.as_str() == rule).count()
}

// ── the core gap: pure contract laundering I/O through a def ─────────────────────

#[test]
fn pure_contract_launders_io_through_def_is_oof_m1() {
    let src = "module Lab.EffectSummary
def leak(cap: Text, p: Text) -> Text {
  stdlib.IO.read_text(p, cap)
}
pure contract Launder {
  input cap : Text
  input path : Text
  compute result = leak(cap, path)
}";
    let codes = typecheck_codes(src);
    assert!(
        codes.contains(&"OOF-M1".to_string()),
        "a pure contract that calls a def performing stdlib.IO.* must fail with OOF-M1; got {codes:?}"
    );
}

// ── negative: a pure contract calling a pure helper stays clean ──────────────────

#[test]
fn pure_contract_calling_pure_def_is_clean_of_oof_m1() {
    let src = "module Lab.EffectSummary
def safe(n: Float) -> Float {
  n
}
pure contract Clean {
  input n : Float
  compute result = safe(n)
}";
    let codes = typecheck_codes(src);
    assert!(
        !codes.contains(&"OOF-M1".to_string()),
        "a pure contract calling a side-effect-free def must NOT raise OOF-M1; got {codes:?}"
    );
}

// ── transitivity: I/O two hops down the call graph is still caught ───────────────

#[test]
fn transitive_two_hop_laundering_is_oof_m1() {
    let src = "module Lab.EffectSummary
def sink(p: Text) -> Text {
  stdlib.IO.read_text(p, p)
}
def outer(p: Text) -> Text {
  sink(p)
}
pure contract Launder2 {
  input path : Text
  compute result = outer(path)
}";
    let codes = typecheck_codes(src);
    assert!(
        codes.contains(&"OOF-M1".to_string()),
        "I/O reached two def-hops deep must still raise OOF-M1; got {codes:?}"
    );
}

// ── `?`-wrapped call edges are real edges (Try traversal) ────────────────────────

#[test]
fn try_wrapped_laundering_is_detected() {
    let src = "module Lab.EffectSummary
def leak(p: Text) -> Text {
  stdlib.IO.read_text(p, p)
}
pure contract LaunderTry {
  input path : Text
  compute result = leak(path)?
}";
    let codes = typecheck_codes(src);
    assert!(
        codes.contains(&"OOF-M1".to_string()),
        "laundering through a `?`-wrapped call must be detected; got {codes:?}"
    );
}

// ── cycles are handled deterministically (no panic, stable single diagnostic) ────

#[test]
fn cyclic_helper_graph_with_io_is_deterministic_oof_m1() {
    let src = "module Lab.EffectSummary
def ping(n: Float) -> Float decreases fuel {
  let x = stdlib.IO.read_text(\"f\", \"f\")
  pong(n)
}
def pong(n: Float) -> Float decreases fuel {
  ping(n)
}
pure contract Cyclic {
  input n : Float
  compute result = ping(n)
}";
    // Run twice: the SCC fixpoint must be order-independent / deterministic.
    let first = typecheck_codes(src);
    let second = typecheck_codes(src);
    assert_eq!(
        first, second,
        "effect summary must be deterministic across runs"
    );
    assert!(
        first.contains(&"OOF-M1".to_string()),
        "a pure contract reaching a cyclic I/O helper group must raise OOF-M1; got {first:?}"
    );
    // The contract reaches the cycle through a single named def (`ping`); exactly one OOF-M1.
    assert_eq!(
        count(&first, "OOF-M1"),
        1,
        "exactly one transitive OOF-M1 expected for the single reached def; got {first:?}"
    );
}

// ── scope guard: only `pure` is restricted; `observed` may read through a def ─────

#[test]
fn observed_contract_calling_io_def_is_not_oof_m1() {
    let src = "module Lab.EffectSummary
def leak(p: Text) -> Text {
  stdlib.IO.read_text(p, p)
}
observed contract Reader {
  input path : Text
  compute result = leak(path)
}";
    let codes = typecheck_codes(src);
    assert!(
        !codes.contains(&"OOF-M1".to_string()),
        "an observed contract may read through a def — the effect summary must not raise OOF-M1; got {codes:?}"
    );
}

// ── regression guard: direct I/O in a pure contract is still flagged ─────────────
// The classifier owns the direct, intra-contract check (E-IO-AMBIENT-BLOCKED). The new
// interprocedural slice must not disturb it.

#[test]
fn direct_io_in_pure_contract_still_flagged() {
    let src = "module Lab.EffectSummary
pure contract DirectIo {
  input path : Text
  compute result = stdlib.IO.read_text(path, path)
}";
    let codes = classifier_codes(src);
    assert!(
        codes.contains(&"E-IO-AMBIENT-BLOCKED".to_string()),
        "direct stdlib.IO.* in a pure contract must still be flagged by the classifier; got {codes:?}"
    );
}
