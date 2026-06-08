// tests/loop_conformance_tests.rs
// Rust integration tests for PROP-039 lab conformance:
//   G3a: OOF-R2 (recursive/decreases) and OOF-R4 (fuel_bounded/max_steps)
//   G3b: FiniteLoop `for Name item in source { body }` parse + IR
//   G3c: SemanticIR shape — kind="loop_node", loop_class, termination, source_ref

use igniter_compiler::lexer::Lexer;
use igniter_compiler::parser::Parser;
use igniter_compiler::classifier::Classifier;
use igniter_compiler::typechecker::TypeChecker;
use igniter_compiler::emitter::Emitter;

// ─── helpers ────────────────────────────────────────────────────────────────

fn run_pipeline(src: &str) -> (
    igniter_compiler::classifier::ClassifiedProgram,
    igniter_compiler::typechecker::TypedProgram,
    igniter_compiler::emitter::EmitResult,
) {
    let mut lexer = Lexer::new(src);
    let tokens = lexer.tokenize();
    let mut parser = Parser::new(tokens);
    let parsed = parser.parse();
    let classifier = Classifier::new();
    let classified = classifier.classify(&parsed, &serde_json::Value::Null);
    let typechecker = TypeChecker::new();
    let typed = typechecker.typecheck(&classified, &parsed.functions);
    let emitter = Emitter::new();
    let emit_res = emitter.emit_typed(&typed);
    (classified, typed, emit_res)
}

fn oof_codes(classified: &igniter_compiler::classifier::ClassifiedProgram) -> Vec<String> {
    classified.contracts.iter()
        .flat_map(|c| c.oof_log.iter().map(|d| d.rule.clone()))
        .collect()
}

fn loop_nodes_from_emit(emit_res: &igniter_compiler::emitter::EmitResult) -> Vec<serde_json::Value> {
    let sir_opt = emit_res.semantic_ir.as_ref();
    let contracts = sir_opt
        .and_then(|s| s.get("contracts"))
        .and_then(|c| c.as_array())
        .cloned()
        .unwrap_or_default();
    contracts.iter()
        .flat_map(|c| {
            c.get("nodes").and_then(|n| n.as_array()).cloned().unwrap_or_default()
        })
        .filter(|n| {
            let kind = n.get("kind").and_then(|k| k.as_str()).unwrap_or("");
            kind == "loop_node" || kind == "loop"
        })
        .collect()
}

// ─── G3a: OOF-R2 diagnostic ─────────────────────────────────────────────────

#[test]
fn test_oof_r2_fires_for_recursive_without_decreases() {
    let src = r#"
module M1
recursive contract Factorial {
  input n: Integer
  output result: Integer
  compute result = n
}
"#;
    let (classified, _, _) = run_pipeline(src);
    let codes = oof_codes(&classified);
    assert!(
        codes.iter().any(|c| c == "OOF-R2"),
        "Expected OOF-R2, got: {:?}",
        codes
    );
}

#[test]
fn test_oof_r2_suppressed_for_recursive_with_decreases() {
    let src = r#"
module M1
recursive contract Factorial {
  input n: Integer
  output result: Integer
  decreases n
  compute result = n
}
"#;
    let (classified, _, _) = run_pipeline(src);
    let codes = oof_codes(&classified);
    assert!(
        !codes.iter().any(|c| c == "OOF-R2"),
        "OOF-R2 should be suppressed when decreases is present, got: {:?}",
        codes
    );
}

// ─── G3a: OOF-R4 diagnostic ─────────────────────────────────────────────────

#[test]
fn test_oof_r4_fires_for_fuel_bounded_without_max_steps() {
    let src = r#"
module M1
fuel_bounded contract Bounded {
  input n: Integer
  output result: Integer
  compute result = n
}
"#;
    let (classified, _, _) = run_pipeline(src);
    let codes = oof_codes(&classified);
    assert!(
        codes.iter().any(|c| c == "OOF-R4"),
        "Expected OOF-R4, got: {:?}",
        codes
    );
}

#[test]
fn test_oof_r4_suppressed_for_fuel_bounded_with_max_steps() {
    let src = r#"
module M1
fuel_bounded contract Bounded {
  input n: Integer
  output result: Integer
  max_steps 50
  compute result = n
}
"#;
    let (classified, _, _) = run_pipeline(src);
    let codes = oof_codes(&classified);
    assert!(
        !codes.iter().any(|c| c == "OOF-R4"),
        "OOF-R4 should be suppressed when max_steps is present, got: {:?}",
        codes
    );
}

#[test]
fn test_oof_r4_fires_for_recursive_decreases_fuel_without_max_steps() {
    let src = r#"
module M1
recursive contract FuelNoSteps {
  input n: Integer
  output result: Integer
  decreases fuel
  compute result = n
}
"#;
    let (classified, _, _) = run_pipeline(src);
    let codes = oof_codes(&classified);
    assert!(
        codes.iter().any(|c| c == "OOF-R4"),
        "Expected OOF-R4 for recursive+decreases fuel without max_steps, got: {:?}",
        codes
    );
}

#[test]
fn test_oof_r2_and_r4_independent() {
    // recursive WITHOUT decreases → OOF-R2, NOT OOF-R4 (no decreases fuel either)
    let src = r#"
module M1
recursive contract NoDecreases {
  input n: Integer
  output result: Integer
  compute result = n
}
"#;
    let (classified, _, _) = run_pipeline(src);
    let codes = oof_codes(&classified);
    assert!(codes.iter().any(|c| c == "OOF-R2"), "Expected OOF-R2");
    assert!(!codes.iter().any(|c| c == "OOF-R4"), "OOF-R4 should not fire without decreases fuel");
}

// ─── G3b: FiniteLoop parser ──────────────────────────────────────────────────

#[test]
fn test_finite_loop_parses_successfully() {
    let src = r#"
module W1
contract SumAll {
  input items: Collection[Integer]
  compute total = 0
  for ProcessAll item in items {
    compute total = total + item
  }
  output total: Integer
}
"#;
    let (classified, _, emit_res) = run_pipeline(src);
    // Must not produce parse-level OOF-P0 for unknown "for" keyword
    let all_oof: Vec<_> = classified.oof_log.iter()
        .chain(classified.contracts.iter().flat_map(|c| c.oof_log.iter()))
        .filter(|d| d.rule == "OOF-P0")
        .collect();
    assert!(
        all_oof.is_empty(),
        "FiniteLoop `for` should parse without OOF-P0; got: {:?}",
        all_oof
    );

    // Should produce a loop_node in SemanticIR
    let nodes = loop_nodes_from_emit(&emit_res);
    assert!(!nodes.is_empty(), "Expected at least one loop_node in SemanticIR");
}

#[test]
fn test_finite_loop_does_not_trigger_unbounded_oof_l1() {
    // FiniteLoop (`for`) must NOT trigger the parser-level OOF-L1 "unbounded loop"
    // which is reserved for `loop` without max_steps.
    let src = r#"
module W1
contract Check {
  input items: Collection[Integer]
  compute total = 0
  for Process item in items {
    compute total = total + item
  }
  output total: Integer
}
"#;
    let mut lexer = Lexer::new(src);
    let tokens = lexer.tokenize();
    let mut parser = Parser::new(tokens);
    let parsed = parser.parse();

    let unbounded_oof_l1: Vec<_> = parsed.parse_errors.iter()
        .filter(|e| e.rule == "OOF-L1" && e.message.contains("unbounded"))
        .collect();
    assert!(
        unbounded_oof_l1.is_empty(),
        "`for` loop must not trigger unbounded OOF-L1, got: {:?}",
        unbounded_oof_l1
    );
}

// ─── G3c: SemanticIR shape ───────────────────────────────────────────────────

#[test]
fn test_finite_loop_ir_shape() {
    let src = r#"
module W1
contract ShapeCheck {
  input items: Collection[Integer]
  compute total = 0
  for Scan item in items {
    compute total = total + item
  }
  output total: Integer
}
"#;
    let (_, _, emit_res) = run_pipeline(src);
    let nodes = loop_nodes_from_emit(&emit_res);
    assert!(!nodes.is_empty(), "Expected loop_node in SemanticIR");

    let finite: Vec<_> = nodes.iter()
        .filter(|n| n.get("loop_class").and_then(|v| v.as_str()) == Some("finite"))
        .collect();
    assert!(!finite.is_empty(), "Expected loop_class='finite' for `for` loop");

    let node = &finite[0];
    assert_eq!(
        node.get("kind").and_then(|v| v.as_str()),
        Some("loop_node"),
        "kind must be 'loop_node' (G3c)"
    );
    assert_eq!(
        node.get("termination").and_then(|v| v.as_str()),
        Some("collection_exhaustion"),
        "FiniteLoop termination must be 'collection_exhaustion'"
    );
    assert!(
        node.get("source_ref").is_some(),
        "source_ref must be present in FiniteLoop loop_node"
    );
    assert!(
        node.get("max_steps").is_none(),
        "FiniteLoop must not have max_steps in IR"
    );
}

#[test]
fn test_budgeted_loop_ir_shape() {
    let src = r#"
module W1
contract BudgetShape {
  input nums: Collection[Integer]
  compute total = 0
  loop Process n in nums max_steps: 50 {
    compute total = total + n
  }
  output total: Integer
}
"#;
    let (_, _, emit_res) = run_pipeline(src);
    let nodes = loop_nodes_from_emit(&emit_res);
    assert!(!nodes.is_empty(), "Expected loop_node in SemanticIR");

    let budgeted: Vec<_> = nodes.iter()
        .filter(|n| n.get("loop_class").and_then(|v| v.as_str()) == Some("budgeted"))
        .collect();
    assert!(!budgeted.is_empty(), "Expected loop_class='budgeted' for `loop` with max_steps");

    let node = &budgeted[0];
    assert_eq!(node.get("kind").and_then(|v| v.as_str()), Some("loop_node"));
    assert_eq!(
        node.get("termination").and_then(|v| v.as_str()),
        Some("budget_exhaustion"),
        "BudgetedLocalLoop termination must be 'budget_exhaustion'"
    );
    assert!(
        node.get("source_ref").is_some(),
        "source_ref must be present in BudgetedLocalLoop loop_node"
    );
    assert_eq!(
        node.get("max_steps").and_then(|v| v.as_i64()),
        Some(50),
        "max_steps=50 must be present at top level in BudgetedLocalLoop"
    );
}

// ─── G6: OOF-L1 canon alignment ─────────────────────────────────────────────

#[test]
fn test_oof_l1_fires_for_finite_loop_non_collection_source() {
    // Canon OOF-L1: FiniteLoop (`for`) source must be Collection[T].
    // BudgetedLocalLoop (`loop`) does not trigger canon OOF-L1.
    let src = r#"
module W1
contract Check {
  input x: Integer
  compute total = 0
  for Process item in x {
    compute total = total + item
  }
  output total: Integer
}
"#;
    let (_, typed, _) = run_pipeline(src);
    let codes: Vec<_> = typed.contracts.iter()
        .flat_map(|c| c.type_errors.iter().map(|e| e.rule.clone()))
        .collect();
    assert!(
        codes.iter().any(|c| c == "OOF-L1"),
        "Canon OOF-L1 must fire for FiniteLoop with non-Collection source, got: {:?}",
        codes
    );
}

#[test]
fn test_oof_l1_suppressed_for_finite_loop_collection_source() {
    let src = r#"
module W1
contract Check {
  input items: Collection[Integer]
  compute total = 0
  for Process item in items {
    compute total = total + item
  }
  output total: Integer
}
"#;
    let (_, typed, _) = run_pipeline(src);
    let codes: Vec<_> = typed.contracts.iter()
        .flat_map(|c| c.type_errors.iter().map(|e| e.rule.clone()))
        .collect();
    assert!(
        !codes.iter().any(|c| c == "OOF-L1"),
        "OOF-L1 must NOT fire for FiniteLoop with Collection[T] source, got: {:?}",
        codes
    );
}

#[test]
fn test_oof_l1_not_fired_for_budgeted_loop_non_collection_source() {
    // Canon OOF-L1 is ONLY for FiniteLoop (for). BudgetedLocalLoop (loop) with a non-Collection
    // source does NOT trigger canon OOF-L1 — that's a separate concern.
    let src = r#"
module W1
contract Check {
  input x: Integer
  compute total = 0
  loop Process n in x max_steps: 10 {
    compute total = total + n
  }
  output total: Integer
}
"#;
    let (_, typed, _) = run_pipeline(src);
    // BudgetedLocalLoop should NOT emit canon OOF-L1 for non-Collection source
    let canon_oof_l1: Vec<_> = typed.contracts.iter()
        .flat_map(|c| c.type_errors.iter())
        .filter(|e| e.rule == "OOF-L1" && e.message.contains("canon OOF-L1"))
        .collect();
    assert!(
        canon_oof_l1.is_empty(),
        "Canon OOF-L1 must NOT fire for BudgetedLocalLoop, got: {:?}",
        canon_oof_l1
    );
}

#[test]
fn test_ir_kind_is_loop_node_not_loop() {
    // Regression: kind must be "loop_node", never the old "loop" value
    let src = r#"
module W1
contract KindCheck {
  input xs: Collection[Integer]
  compute acc = 0
  loop DoLoop x in xs max_steps: 10 {
    compute acc = acc + x
  }
  output acc: Integer
}
"#;
    let (_, _, emit_res) = run_pipeline(src);
    let sir = emit_res.semantic_ir.as_ref().expect("semantic_ir must be present");
    let all_nodes_json = serde_json::to_string(sir).unwrap();

    assert!(
        !all_nodes_json.contains("\"kind\":\"loop\"") && !all_nodes_json.contains("\"kind\": \"loop\""),
        "SemanticIR must not contain kind='loop'; found in: {}",
        &all_nodes_json[..all_nodes_json.len().min(500)]
    );
    assert!(
        all_nodes_json.contains("\"kind\":\"loop_node\"") || all_nodes_json.contains("\"kind\": \"loop_node\""),
        "SemanticIR must contain kind='loop_node'"
    );
}
