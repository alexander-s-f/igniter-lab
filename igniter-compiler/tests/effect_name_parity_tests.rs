// tests/effect_name_parity_tests.rs
// LANG-EFFECT-NAME-PARITY-P2: effect names are LABELS/verbs, not authority selectors. The Rust
// classifier no longer enforces a read/write allowlist (E-IO-EFFECT-UNKNOWN removed) — ANY
// well-formed effect name is accepted (parity with Ruby canon). Capability-binding validation
// (E-IO-CAP-UNKNOWN, E-IO-EFFECT-UNDECLARED) is intact; authority lives in the capability type +
// host passport, never in the effect verb.

use igniter_compiler::classifier::Classifier;
use igniter_compiler::lexer::Lexer;
use igniter_compiler::parser::Parser;

fn oof_codes(src: &str) -> Vec<String> {
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

fn contract_with_effect(name: &str) -> String {
    format!("module M\neffect contract A {{\n  capability c : IO.Capability\n  effect {name} using c\n}}")
}

// ── non-read/write effect labels are now dual-clean (no E-IO-EFFECT-UNKNOWN) ────

#[test]
fn arbitrary_effect_labels_are_accepted() {
    for name in ["read_file", "connect", "charge_vendor", "sync_customer", "notify_slack"] {
        let codes = oof_codes(&contract_with_effect(name));
        assert!(
            !codes.contains(&"E-IO-EFFECT-UNKNOWN".to_string()),
            "effect label '{name}' must NOT be rejected by name; got {codes:?}"
        );
        // a well-formed declared-effect contract with a bound capability is fully clean
        assert!(
            codes.is_empty(),
            "effect '{name}' with a bound capability should be clean; got {codes:?}"
        );
    }
}

// ── capability-binding validation is INTACT ────────────────────────────────────

#[test]
fn undeclared_capability_still_fails() {
    let src = "module M\neffect contract A {\n  capability c : IO.Capability\n  effect connect using missing\n}";
    let codes = oof_codes(src);
    assert!(
        codes.contains(&"E-IO-CAP-UNKNOWN".to_string()),
        "an effect using an undeclared capability must still fail; got {codes:?}"
    );
}

#[test]
fn unbound_capability_still_fails() {
    // `d` is declared but no effect uses it
    let src = "module M\neffect contract A {\n  capability c : IO.Capability\n  capability d : IO.Capability\n  effect connect using c\n}";
    let codes = oof_codes(src);
    assert!(
        codes.contains(&"E-IO-EFFECT-UNDECLARED".to_string()),
        "a capability with no effect binding must still fail; got {codes:?}"
    );
}

// ── the effect label is preserved in the SIR ───────────────────────────────────

#[test]
fn effect_label_preserved_in_ir() {
    use igniter_compiler::emitter::Emitter;
    use igniter_compiler::typechecker::TypeChecker;
    let src = contract_with_effect("charge_vendor");
    let mut lexer = Lexer::new(&src);
    let tokens = lexer.tokenize();
    let mut parser = Parser::new(tokens);
    let parsed = parser.parse();
    let classified = Classifier::new().classify(&parsed, &serde_json::Value::Null);
    let typed = TypeChecker::new().typecheck(&classified, &parsed.functions);
    let emit = Emitter::new().emit_typed(&typed);
    let sir = emit.semantic_ir.expect("contract should compile to SIR");
    assert!(
        sir.to_string().contains("charge_vendor"),
        "the effect label must survive into the SIR"
    );
}
