// tests/collection_predicate_ops_tests.rs
// LANG-STDLIB-COLLECTION-PREDICATE-OPS-P3
//
// Lab Rust parity for canon Ruby P2:
//   find(Collection[T], T -> Bool) -> Option[T]
//   any(Collection[T], T -> Bool)  -> Bool
//   all(Collection[T], T -> Bool)  -> Bool
//
// The compiler must emit qualified stdlib.collection.* SIR names and reuse the
// collection diagnostic family: OOF-COL1, OOF-COL2, OOF-COL3.

use igniter_compiler::classifier::Classifier;
use igniter_compiler::lexer::Lexer;
use igniter_compiler::parser::Parser;
use igniter_compiler::typechecker::TypeChecker;
use std::path::PathBuf;
use std::process::Command;

fn tc_codes(src: &str) -> Vec<String> {
    let mut lexer = Lexer::new(src);
    let tokens = lexer.tokenize();
    let mut parser = Parser::new(tokens);
    let parsed = parser.parse();
    let classified = Classifier::new().classify(&parsed, &serde_json::Value::Null);
    let typed = TypeChecker::new().typecheck(&classified, &parsed.functions);
    typed.type_errors.iter().map(|d| d.rule.clone()).collect()
}

fn binary_compile(src: &str, tag: &str) -> (bool, Vec<String>, String, PathBuf) {
    let dir = std::env::temp_dir().join(format!("pred_ops_{}_{}", tag, std::process::id()));
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
    let stdout = String::from_utf8_lossy(&out.stdout).to_string();
    let ok = stdout.contains("\"status\": \"ok\"");
    let mut fns = Vec::new();
    if let Ok(s) = std::fs::read_to_string(igapp.join("semantic_ir_program.json")) {
        if let Ok(sir) = serde_json::from_str::<serde_json::Value>(&s) {
            collect_fns(&sir, &mut fns);
        }
    }
    (ok, fns, stdout, igapp)
}

fn collect_fns(v: &serde_json::Value, out: &mut Vec<String>) {
    match v {
        serde_json::Value::Object(m) => {
            if m.get("kind").and_then(|k| k.as_str()) == Some("call") {
                if let Some(f) = m.get("fn").and_then(|f| f.as_str()) {
                    out.push(f.to_string());
                }
            }
            for vv in m.values() {
                collect_fns(vv, out);
            }
        }
        serde_json::Value::Array(a) => a.iter().for_each(|vv| collect_fns(vv, out)),
        _ => {}
    }
}

#[test]
fn happy_find_any_all_compile_clean_and_qualified() {
    let cases = [
        (
            "find",
            "module P\ncontract C {\n  input xs : Collection[Integer]\n  compute found = find(xs, x -> x > 0)\n  output found : Option[Integer]\n}\n",
            "stdlib.collection.find",
        ),
        (
            "any",
            "module P\ncontract C {\n  input xs : Collection[Integer]\n  compute ok = any(xs, x -> x > 0)\n  output ok : Bool\n}\n",
            "stdlib.collection.any",
        ),
        (
            "all",
            "module P\ncontract C {\n  input xs : Collection[Integer]\n  compute ok = all(xs, x -> x > 0)\n  output ok : Bool\n}\n",
            "stdlib.collection.all",
        ),
    ];

    for (bare, src, qualified) in cases {
        let (ok, fns, stdout, _) = binary_compile(src, bare);
        assert!(ok, "{bare} must compile clean: {stdout}");
        assert!(
            fns.iter().any(|f| f == qualified),
            "{bare} SIR must emit {qualified}: {fns:?}"
        );
        assert!(
            !fns.iter().any(|f| f == bare),
            "{bare} SIR must not emit bare name: {fns:?}"
        );
    }
}

#[test]
fn find_output_is_option_not_collection_or_scalar() {
    let as_collection = "module P\ncontract C {\n  input xs : Collection[Integer]\n  compute found = find(xs, x -> x > 0)\n  output found : Collection[Integer]\n}\n";
    let (ok_collection, _, stdout_collection, _) =
        binary_compile(as_collection, "find_as_collection");
    assert!(
        !ok_collection,
        "find result must not be assignable to Collection[Integer]: {stdout_collection}"
    );

    let as_integer = "module P\ncontract C {\n  input xs : Collection[Integer]\n  compute found = find(xs, x -> x > 0)\n  output found : Integer\n}\n";
    let (ok_integer, _, stdout_integer, _) = binary_compile(as_integer, "find_as_integer");
    assert!(
        !ok_integer,
        "find result must not be assignable to bare Integer: {stdout_integer}"
    );
}

#[test]
fn record_predicate_binds_lambda_param_to_element_type() {
    let src = "module P\ntype Todo { done : Bool  score : Integer }\ncontract C {\n  input todos : Collection[Todo]\n  compute found = find(todos, t -> t.done)\n  output found : Option[Todo]\n}\n";
    let (ok, fns, stdout, _) = binary_compile(src, "record");
    assert!(
        ok,
        "record predicate field access proves lambda param is Todo: {stdout}"
    );
    assert!(fns.iter().any(|f| f == "stdlib.collection.find"));
}

#[test]
fn diagnostics_are_collection_diagnostics() {
    let wrong_arity = "module P\ncontract C {\n  input xs : Collection[Integer]\n  compute found = find(xs)\n  output found : Option[Integer]\n}\n";
    assert!(
        tc_codes(wrong_arity).contains(&"OOF-COL1".to_string()),
        "wrong arity -> OOF-COL1"
    );

    let non_lambda = "module P\ncontract C {\n  input xs : Collection[Integer]\n  compute ok = any(xs, true)\n  output ok : Bool\n}\n";
    assert!(
        tc_codes(non_lambda).contains(&"OOF-COL1".to_string()),
        "non-lambda second arg -> OOF-COL1"
    );

    let non_collection = "module P\ncontract C {\n  input n : Integer\n  compute ok = all(n, x -> x > 0)\n  output ok : Bool\n}\n";
    assert!(
        tc_codes(non_collection).contains(&"OOF-COL2".to_string()),
        "non-Collection first arg -> OOF-COL2"
    );

    let non_bool = "module P\ntype Todo { done : Bool  score : Integer }\ncontract C {\n  input todos : Collection[Todo]\n  compute found = find(todos, t -> t.score)\n  output found : Option[Todo]\n}\n";
    assert!(
        tc_codes(non_bool).contains(&"OOF-COL3".to_string()),
        "concrete non-Bool predicate -> OOF-COL3"
    );

    let all_codes = [
        tc_codes(wrong_arity),
        tc_codes(non_lambda),
        tc_codes(non_collection),
        tc_codes(non_bool),
    ]
    .concat();
    assert!(
        !all_codes.contains(&"OOF-TM1".to_string()),
        "predicate ops must not use old coarse OOF-TM1 diagnostics: {all_codes:?}"
    );
}

#[test]
fn unknown_predicate_body_is_permissive_no_false_col3() {
    let src = "module P\ncontract C {\n  input xs : Collection[Unknown]\n  compute found = find(xs, x -> missing_predicate)\n  output found : Option[Unknown]\n}\n";
    let codes = tc_codes(src);
    assert!(
        !codes.contains(&"OOF-COL3".to_string()),
        "Unknown predicate body must not emit OOF-COL3: {codes:?}"
    );
    assert!(
        !codes.contains(&"OOF-COL2".to_string()),
        "Collection[Unknown] first arg must remain permissive: {codes:?}"
    );
}

#[test]
fn regressions_filter_flat_map_and_map_stay_intact() {
    let filter_non_bool = "module P\ntype Todo { done : Bool  score : Integer }\ncontract C {\n  input todos : Collection[Todo]\n  compute active = filter(todos, t -> t.score)\n  output active : Collection[Todo]\n}\n";
    assert!(
        tc_codes(filter_non_bool).contains(&"OOF-COL3".to_string()),
        "filter must still reject scalar predicates with OOF-COL3"
    );

    let flat_map_scalar = "module P\ncontract C {\n  input xs : Collection[Integer]\n  compute ys = flat_map(xs, x -> x)\n  output ys : Collection[Integer]\n}\n";
    assert!(
        tc_codes(flat_map_scalar).contains(&"OOF-COL9".to_string()),
        "flat_map must still reject scalar lambda bodies with OOF-COL9"
    );

    let map_src = "module P\ncontract C {\n  input xs : Collection[Integer]\n  compute ys = map(xs, x -> x)\n  output ys : Collection[Integer]\n}\n";
    let (ok, fns, stdout, _) = binary_compile(map_src, "map");
    assert!(ok, "map regression fixture must compile: {stdout}");
    assert!(
        fns.iter().any(|f| f == "stdlib.collection.map"),
        "map must remain qualified: {fns:?}"
    );
    assert!(
        !fns.iter().any(|f| f == "zip") && !fns.iter().any(|f| f == "stdlib.collection.zip"),
        "predicate ops P3 must not introduce zip behavior: {fns:?}"
    );
}
