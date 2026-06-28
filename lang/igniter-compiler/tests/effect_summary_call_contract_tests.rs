// tests/effect_summary_call_contract_tests.rs
// LAB-IGNITER-COMPILER-EFFECT-SUMMARY-CALL-CONTRACT-P7 (audit-control-board A20 follow-up).
//
// P6 summarized ambient I/O over the app-local `def` call graph and flagged a `pure` contract
// that launders I/O through a `def` (OOF-M1). It deliberately deferred `call_contract("Name", …)`
// inter-contract edges.
//
// Verify-first finding for P7: the inter-contract laundering vector is ALREADY CLOSED BY
// CONSTRUCTION, so no contract-level effect propagation is needed (it would be dead code today):
//
//   1. `call_contract` v0 accepts ONLY a literal-String callee that is `pure`
//      (typechecker/stdlib_calls.rs ~2536: non-pure callee → OOF-TY0). So a pure surface cannot
//      even *reach* an effectful (`observed`/…) contract through `call_contract`.
//   2. A `pure` callee cannot perform ambient I/O — direct I/O is caught by the classifier
//      (E-IO-AMBIENT-BLOCKED) and transitive-via-`def` I/O by P6 (OOF-M1). So there is no
//      "pure but secretly effectful" contract for a literal `call_contract` to target.
//   3. Non-literal / dynamic callees are not statically resolvable; they resolve to `Unknown`
//      and are VM fail-closed (no constructible `.ig` case — igweb emits literals only, dynamic
//      dispatch DEFERs). Out of scope per the card ("No dynamic contract dispatch").
//
// These tests REGRESSION-LOCK that invariant from both sides. If a future card relaxes the
// `call_contract` pure-only rule (allowing effectful callees), test (1) will break and signal
// that contract-level effect propagation is then genuinely required
// (LAB-IGNITER-COMPILER-EFFECT-SUMMARY-CONTRACT-GRAPH-P8).

use igniter_compiler::classifier::Classifier;
use igniter_compiler::lexer::Lexer;
use igniter_compiler::parser::Parser;
use igniter_compiler::typechecker::TypeChecker;

fn typecheck_codes(src: &str) -> Vec<String> {
    let mut lexer = Lexer::new(src);
    let tokens = lexer.tokenize();
    let mut parser = Parser::new(tokens);
    let parsed = parser.parse();
    let classified = Classifier::new().classify(&parsed, &serde_json::Value::Null);
    let typed = TypeChecker::new().typecheck(&classified, &parsed.functions);
    typed.type_errors.iter().map(|d| d.rule.clone()).collect()
}

// ── (1) the laundering attempt: a pure contract cannot reach an effectful contract ──────────
// `Reader` is `observed` and legally reads I/O through a def. A `pure` contract that tries to
// launder that I/O via `call_contract("Reader", …)` is refused at the call site by the
// pure-only callee gate (OOF-TY0) — it never even reaches the effect. (Note: OOF-M1 does NOT
// fire here, because the pure contract does not call the `def` directly; the purity gate is the
// load-bearing protection.)
#[test]
fn pure_contract_cannot_call_contract_an_effectful_contract() {
    let src = "module Lab.EffectSummaryCallContract
def leak(p: Text) -> Text {
  stdlib.IO.read_text(p, p)
}
observed contract Reader {
  input path : Text
  compute result = leak(path)
}
pure contract LaunderViaContract {
  input path : Text
  compute result = call_contract(\"Reader\", path)
}";
    let codes = typecheck_codes(src);
    assert!(
        codes.contains(&"OOF-TY0".to_string()),
        "a pure contract calling call_contract on a non-pure (observed) contract must be refused \
         by the pure-only callee gate (OOF-TY0); got {codes:?}"
    );
}

// ── (2) no false positive: a pure contract calling a pure, I/O-free contract is clean ───────
#[test]
fn pure_contract_call_contract_to_pure_target_is_clean() {
    let src = "module Lab.EffectSummaryCallContract
pure contract Helper {
  input n : Float
  compute result = n
  output result : Float
}
pure contract Caller {
  input n : Float
  compute result = call_contract(\"Helper\", n)
}";
    let codes = typecheck_codes(src);
    assert!(
        !codes.contains(&"OOF-M1".to_string()) && !codes.contains(&"OOF-TY0".to_string()),
        "a pure contract calling a pure I/O-free contract by literal name must be clean \
         (no OOF-M1, no OOF-TY0); got {codes:?}"
    );
}

// ── (3) the induction base: there is no "pure but secretly effectful" contract to target ────
// A contract declared `pure` that launders I/O through a def is itself rejected (OOF-M1, P6).
// So every legal `call_contract` callee (which must be pure) is provably I/O-free — the
// guarantee that makes (1)+(2) sufficient without contract-level effect propagation.
#[test]
fn a_pure_contract_that_launders_is_rejected_so_no_effectful_pure_target_exists() {
    let src = "module Lab.EffectSummaryCallContract
def leak(p: Text) -> Text {
  stdlib.IO.read_text(p, p)
}
pure contract SecretlyEffectful {
  input path : Text
  compute result = leak(path)
}
pure contract CallsIt {
  input path : Text
  compute result = call_contract(\"SecretlyEffectful\", path)
}";
    let codes = typecheck_codes(src);
    assert!(
        codes.contains(&"OOF-M1".to_string()),
        "a contract declared pure that launders I/O through a def must be rejected (OOF-M1), so it \
         can never be a valid call_contract target; got {codes:?}"
    );
}
