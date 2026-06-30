// tests/collection_flat_map_tests.rs
// LANG-STDLIB-COLLECTION-FLATMAP-P4 - lab Rust `igniter-compiler` parity with the canon Ruby P3
// flat_map surface (LANG-STDLIB-COLLECTION-FLATMAP-P3):
//
//   flat_map(Collection[A], A -> Collection[B]) -> Collection[B]
//   SIR: stdlib.collection.flat_map
//   diagnostics: OOF-COL1 (arity/non-lambda) - OOF-COL2 (non-collection first arg) -
//                OOF-COL9 (lambda body not a collection)
//
// The crucial rule is ONE-LEVEL unwrap (the result is the body's collection type, never
// Collection[Collection[B]]) and that the lambda param binds to the input element type A - replacing
// the old Integer placeholder that rode the monadic `and_then` path. `and_then` stays Result/Option.
//
// PARITY CAVEAT (documented, pre-existing): an array-literal lambda body like `x -> [x, x]` infers
// `Collection[Unknown]` in the lab Rust TC, because Rust array-literal element inference is
// context-driven and a lambda body has no expected-type hint (the horizon-research section4 gap; NOT a
// flat_map bug - Ruby infers it from contents). So the one-level-unwrap proofs here use
// collection-VALUED lambda bodies (a Ref or a record field that is itself a `Collection[B]`), which
// carry a concrete element type and exercise the exact flat_map contract without that gap. The
// array-literal body is still covered as an Unknown-permissive case (no false OOF-COL9).

use igniter_compiler::classifier::Classifier;
use igniter_compiler::lexer::Lexer;
use igniter_compiler::parser::Parser;
use igniter_compiler::typechecker::TypeChecker;
use std::process::Command;

/// In-process typecheck -> OOF rule codes (fast; for the flat_map-owned COL1/COL2/COL9 diagnostics).
fn tc_codes(src: &str) -> Vec<String> {
    let mut lexer = Lexer::new(src);
    let tokens = lexer.tokenize();
    let mut parser = Parser::new(tokens);
    let parsed = parser.parse();
    let classified = Classifier::new().classify(&parsed, &serde_json::Value::Null);
    let typed = TypeChecker::new().typecheck(&classified, &parsed.functions);
    typed.type_errors.iter().map(|d| d.rule.clone()).collect()
}

/// Full `igc compile` -> `(status_ok, sir_fn_names)`. The emitter qualifies HOF names and the
/// orchestrator runs the output-type check (OOF-TY1), so the binary is authoritative for both.
fn binary_compile(src: &str, tag: &str) -> (bool, Vec<String>) {
    let dir = std::env::temp_dir().join(format!("fm_p4_{}_{}", tag, std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let f = dir.join("m.ig");
    std::fs::write(&f, src).unwrap();
    let igapp = dir.join("out.igapp");
    let out = Command::new(env!("CARGO_BIN_EXE_igniter_compiler"))
        .args([
            "compile",
            f.to_str().unwrap(),
            "--out",
            igapp.to_str().unwrap(),
        ])
        .output()
        .expect("run igniter_compiler");
    let ok = String::from_utf8_lossy(&out.stdout).contains("\"status\": \"ok\"");
    let mut fns = Vec::new();
    if let Ok(s) = std::fs::read_to_string(igapp.join("semantic_ir_program.json")) {
        if let Ok(sir) = serde_json::from_str::<serde_json::Value>(&s) {
            collect_fns(&sir, &mut fns);
        }
    }
    (ok, fns)
}

fn collect_fns(v: &serde_json::Value, out: &mut Vec<String>) {
    match v {
        serde_json::Value::Object(m) => {
            if m.get("kind").and_then(|k| k.as_str()) == Some("call") {
                if let Some(f) = m.get("fn").and_then(|f| f.as_str()) {
                    out.push(f.to_string());
                }
            }
            for (_, vv) in m {
                collect_fns(vv, out);
            }
        }
        serde_json::Value::Array(a) => a.iter().for_each(|vv| collect_fns(vv, out)),
        _ => {}
    }
}

// -- 1. happy path: clean, qualified SIR, ONE-LEVEL unwrap (Collection[Collection[Integer]] -> Collection[Integer]) --
#[test]
fn happy_flat_map_one_level_unwrap_clean_and_qualified() {
    // identity-flatten: each element is itself a Collection[Integer]; flat_map flattens one level.
    let src = "module FM\npure contract C {\n  input xss : Collection[Collection[Integer]]\n\
        compute ys = flat_map(xss, inner -> inner)\n  output ys : Collection[Integer]\n}\n";
    let (ok, fns) = binary_compile(src, "happy");
    assert!(
        ok,
        "one-level-unwrap flat_map must compile clean (result Collection[Integer])"
    );
    assert!(
        fns.iter().any(|f| f == "stdlib.collection.flat_map"),
        "SIR must emit qualified flat_map: {fns:?}"
    );
    assert!(
        !fns.iter().any(|f| f == "flat_map"),
        "SIR must never carry bare flat_map: {fns:?}"
    );
}

#[test]
fn one_level_unwrap_not_double_wrapped() {
    // The SAME flat_map result is Collection[Integer]; a declared Collection[Collection[Integer]]
    // output MUST mismatch (proving the result is NOT double-wrapped).
    let src = "module FM\npure contract C {\n  input xss : Collection[Collection[Integer]]\n\
        compute ys = flat_map(xss, inner -> inner)\n  output ys : Collection[Collection[Integer]]\n}\n";
    let (ok, _) = binary_compile(src, "nested");
    assert!(
        !ok,
        "Collection[Collection[Integer]] output must mismatch (result is Collection[Integer])"
    );
}

// -- 2. record/descriptor pressure: param is the record element type (field access), not Integer --
#[test]
fn record_pressure_param_is_record_type_not_integer_placeholder() {
    // `bd -> bd.items` only typechecks if the lambda param `bd` is bound to `Body` (has `.items`),
    // NOT the old Integer placeholder. The body `bd.items : Collection[Integer]` flattens one level.
    let src = "module FM\ntype Body { items : Collection[Integer] }\npure contract C {\n\
        input bodies : Collection[Body]\n\
        compute ys = flat_map(bodies, bd -> bd.items)\n  output ys : Collection[Integer]\n}\n";
    let (ok, fns) = binary_compile(src, "rec");
    assert!(
        ok,
        "record flat_map (param=Body, field access, one-level unwrap) must compile clean"
    );
    assert!(fns.iter().any(|f| f == "stdlib.collection.flat_map"));
}

// -- 3. OOF-COL9: lambda body not a collection ----------------------------------------------------
#[test]
fn scalar_lambda_body_emits_oof_col9() {
    let src = "module FM\npure contract C {\n  input xs : Collection[Integer]\n\
        compute ys = flat_map(xs, x -> x)\n  output ys : Collection[Integer]\n}\n";
    assert!(
        tc_codes(src).contains(&"OOF-COL9".to_string()),
        "scalar body must emit OOF-COL9: {:?}",
        tc_codes(src)
    );
}

// -- 4. OOF-COL1 / OOF-COL2 ------------------------------------------------------------------------
#[test]
fn arity_nonlambda_and_noncollection_diagnostics() {
    let arity = "module FM\npure contract C {\n  input xs : Collection[Integer]\n\
        compute ys = flat_map(xs)\n  output ys : Collection[Integer]\n}\n";
    assert!(
        tc_codes(arity).contains(&"OOF-COL1".to_string()),
        "wrong arity -> OOF-COL1"
    );

    let nonlambda = "module FM\npure contract C {\n  input xs : Collection[Integer]\n\
        compute ys = flat_map(xs, 5)\n  output ys : Collection[Integer]\n}\n";
    assert!(
        tc_codes(nonlambda).contains(&"OOF-COL1".to_string()),
        "non-lambda 2nd arg -> OOF-COL1"
    );

    let noncol = "module FM\npure contract C {\n  input n : Integer\n\
        compute ys = flat_map(n, x -> [x])\n  output ys : Collection[Integer]\n}\n";
    assert!(
        tc_codes(noncol).contains(&"OOF-COL2".to_string()),
        "non-collection first arg -> OOF-COL2"
    );
}

// -- 5. Unknown permissive: array-literal/empty-list body raises no false OOF-COL9 ----------------
#[test]
fn array_literal_and_empty_body_are_unknown_permissive_no_false_col9() {
    // Both `x -> [x, x]` and `x -> []` infer Collection[Unknown] inside the lambda (array-literal
    // inference gap) - they must be Unknown-permissive at the flat_map gate (no false OOF-COL9).
    for body in ["x -> [x, x]", "x -> []"] {
        let src = format!(
            "module FM\npure contract C {{\n  input xs : Collection[Integer]\n\
             compute ys = flat_map(xs, {body})\n  output ys : Collection[Integer]\n}}\n"
        );
        assert!(
            !tc_codes(&src).contains(&"OOF-COL9".to_string()),
            "`{body}` must not emit OOF-COL9: {:?}",
            tc_codes(&src)
        );
    }
}

// -- 6. regression: map qualifies + and_then stays Result-only ------------------------------------
#[test]
fn map_qualifies_and_and_then_is_result_only() {
    let mapsrc = "module FM\npure contract C {\n  input xs : Collection[Integer]\n\
        compute ys = map(xs, x -> x)\n  output ys : Collection[Integer]\n}\n";
    let (ok, fns) = binary_compile(mapsrc, "map");
    assert!(
        ok && fns.iter().any(|f| f == "stdlib.collection.map"),
        "map still clean + qualified: {fns:?}"
    );

    // and_then over a Result remains a Result-monadic op (NOT a collection flatten / no COL diagnostics).
    let andthen = "module FM\npure contract C {\n  input r : Result[Integer, Text]\n\
        compute out = and_then(r, x -> ok(x))\n  output out : Result[Integer, Text]\n}\n";
    let acodes = tc_codes(andthen);
    assert!(
        !acodes.contains(&"OOF-COL9".to_string()) && !acodes.contains(&"OOF-COL2".to_string()),
        "and_then on Result must not trigger collection flat_map diagnostics: {acodes:?}"
    );
}
