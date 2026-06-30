// tests/call_contract_arg_typing_tests.rs
// LAB-IGNITER-COMPILER-CALL-CONTRACT-ARG-TYPING-P8 (audit-control-board A19 tail).
//
// P7 closed the `call_contract` effect-laundering vector by construction (literal pure callees only).
// This card is the SEPARATE type-soundness question: does a literal `call_contract("Name", a, b, …)`
// validate each supplied ARGUMENT TYPE against the target contract's declared inputs, as strongly as
// app-local `def` calls do after P6 (`check_user_fn_call_signature`)?
//
// Before P8: the `call_contract` special form checked the callee name (literal String), pure-only,
// unknown-callee, self-recursion, and ARITY (`expects N input(s), got M`) — but NOT the per-argument
// type. P8 adds the per-arg structural check through the SAME `IgType` boundary as P6
// (`structurally_assignable`, with Unknown / Unknown-bearing skipped so it never false-rejects).
//
// These tests lock: wrong arg type → rejected; right arg type → clean; Unknown-bearing arg → deferred.

use igniter_compiler::classifier::Classifier;
use igniter_compiler::lexer::Lexer;
use igniter_compiler::parser::Parser;
use igniter_compiler::typechecker::TypeChecker;

struct Diag {
    rule: String,
    message: String,
}

fn typecheck_diags(src: &str) -> Vec<Diag> {
    let mut lexer = Lexer::new(src);
    let tokens = lexer.tokenize();
    let mut parser = Parser::new(tokens);
    let parsed = parser.parse();
    let classified = Classifier::new().classify(&parsed, &serde_json::Value::Null);
    let typed = TypeChecker::new().typecheck(&classified, &parsed.functions);
    typed
        .type_errors
        .iter()
        .map(|d| Diag {
            rule: d.rule.clone(),
            message: d.message.clone(),
        })
        .collect()
}

fn codes(diags: &[Diag]) -> Vec<String> {
    diags.iter().map(|d| d.rule.clone()).collect()
}

// ── (1) wrong argument type → rejected (the soundness gap P8 closes) ─────────────────────────────
// `Helper` declares `input n : Float`. A caller passing a String literal must be rejected with an
// arg-type diagnostic that names the parameter — not silently accepted, and not merely an arity pass.
#[test]
fn wrong_call_contract_arg_type_is_rejected() {
    let src = "module Lab.CallContractArgTyping
pure contract Helper {
  input n : Float
  compute result = n
  output result : Float
}
pure contract Caller {
  input s : Text
  compute result = call_contract(\"Helper\", \"not-a-float\")
  output result : Float
}";
    let diags = typecheck_diags(src);
    assert!(
        codes(&diags).contains(&"OOF-TY0".to_string()),
        "passing a String where the callee input is Float must be rejected (OOF-TY0); got {:?}",
        codes(&diags)
    );
    assert!(
        diags.iter().any(|d| d
            .message
            .contains("call_contract: callee 'Helper' parameter 'n' expects")),
        "the diagnostic must name the call_contract callee + parameter; got {:?}",
        diags.iter().map(|d| &d.message).collect::<Vec<_>>()
    );
}

// ── (2) correct argument type → clean (no false positive) ────────────────────────────────────────
#[test]
fn correct_call_contract_arg_type_compiles_clean() {
    let src = "module Lab.CallContractArgTyping
pure contract Helper {
  input n : Float
  compute result = n
  output result : Float
}
pure contract Caller {
  input n : Float
  compute result = call_contract(\"Helper\", n)
  output result : Float
}";
    let diags = typecheck_diags(src);
    assert!(
        !codes(&diags).contains(&"OOF-TY0".to_string()),
        "a literal pure call with a correctly-typed argument must compile clean; got {:?}",
        diags.iter().map(|d| &d.message).collect::<Vec<_>>()
    );
}

// ── (3) Unknown-bearing argument → deferred (never a false reject) ────────────────────────────────
// `m` is the result of a MULTI-output `call_contract`, which resolves to `Unknown` (deferred). Passing
// it where the callee expects `Float` must be SKIPPED by the arg-type check, exactly as P6 skips
// Unknown / Unknown-bearing arguments — so no OOF-TY0 is raised for the Unknown arg.
#[test]
fn unknown_bearing_call_contract_arg_is_deferred() {
    let src = "module Lab.CallContractArgTyping
pure contract Multi {
  input n : Float
  compute a = n
  compute b = n
  output a : Float
  output b : Float
}
pure contract Wants {
  input x : Float
  compute result = x
  output result : Float
}
pure contract Chain {
  input n : Float
  compute m = call_contract(\"Multi\", n)
  compute result = call_contract(\"Wants\", m)
  output result : Float
}";
    let diags = typecheck_diags(src);
    assert!(
        !diags.iter().any(|d| d
            .message
            .contains("call_contract: callee 'Wants' parameter")),
        "an Unknown-bearing argument must be deferred, never arg-type-rejected; got {:?}",
        diags.iter().map(|d| &d.message).collect::<Vec<_>>()
    );
}

// ── (4) arity is still independently enforced (regression-lock the pre-P8 behavior) ──────────────
#[test]
fn wrong_call_contract_arity_still_rejected() {
    let src = "module Lab.CallContractArgTyping
pure contract Helper {
  input n : Float
  compute result = n
  output result : Float
}
pure contract Caller {
  input n : Float
  compute result = call_contract(\"Helper\", n, n)
  output result : Float
}";
    let diags = typecheck_diags(src);
    assert!(
        diags
            .iter()
            .any(|d| d.rule == "OOF-TY0" && d.message.contains("expects 1 input")),
        "wrong arity must still be rejected with the arity diagnostic; got {:?}",
        diags.iter().map(|d| &d.message).collect::<Vec<_>>()
    );
}
