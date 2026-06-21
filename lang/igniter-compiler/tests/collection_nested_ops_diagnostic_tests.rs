// tests/collection_nested_ops_diagnostic_tests.rs — LAB-COLLECTION-NESTED-OPS-DIAGNOSTIC-P2
// Some collection ops nested INSIDE a higher-order collection lambda remain non-executable in v0. The
// typechecker rejects that shape early with `OOF-COL-NESTED` and names the `call_contract` workaround.
// P3 recovered nested map/filter/scalar-sum, so this test keeps both the remaining diagnostic and the
// recovered green cases honest.

use std::process::Command;

fn bin() -> &'static str {
    env!("CARGO_BIN_EXE_igniter_compiler")
}

fn compile(src: &str, tag: &str) -> String {
    let dir = std::env::temp_dir().join(format!("nestedcol_{}_{}", tag, std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let f = dir.join("m.ig");
    std::fs::write(&f, src).unwrap();
    let out = dir.join("out");
    let output = Command::new(bin())
        .args([
            "compile",
            f.to_str().unwrap(),
            "--out",
            out.to_str().unwrap(),
        ])
        .output()
        .expect("run igniter_compiler");
    String::from_utf8_lossy(&output.stdout).to_string()
}

fn is_ok(s: &str) -> bool {
    s.contains("\"status\": \"ok\"")
}
fn has_nested_diag(s: &str) -> bool {
    s.contains("OOF-COL-NESTED")
}

// ── rejected: collection op inside a HOF lambda ─────────────────────────────────────────────────────

#[test]
fn nested_map_in_map_now_compiles() {
    // LAB-VM-NESTED-HOF-EVAL-AST-RECOVERY-P3: map-in-map now EXECUTES, so it is no longer rejected.
    // (Output is Collection[Collection[Float]] — the inner map keeps each row.)
    let src = "pure contract C {\n  input xss : Collection[Collection[Float]]\n  compute d : Collection[Collection[Float]] = map(xss, row -> map(row, x -> x + 1.0))\n  output d : Collection[Collection[Float]]\n}\n";
    let o = compile(src, "mapinmap");
    assert!(
        is_ok(&o) && !has_nested_diag(&o),
        "nested map-in-map now compiles (executes nested): {o}"
    );
}

#[test]
fn map_with_sum_of_map_now_compiles() {
    // P3: `map(x -> sum(map(...)))` (the Kuramoto all-N tick shape) now executes nested → no diagnostic.
    let src = "pure contract C {\n  input phases : Collection[Float]\n  compute d : Collection[Float] = map(phases, p -> p + sum(map(phases, q -> sin(q - p))))\n  output d : Collection[Float]\n}\n";
    let o = compile(src, "sumofmap");
    assert!(
        is_ok(&o) && !has_nested_diag(&o),
        "map(x -> sum(map(...))) now compiles: {o}"
    );
}

#[test]
fn map_with_fold_is_still_rejected() {
    // `fold` lowers to a `map_reduce_aggregate` SIR node eval_ast can't run nested, so it stays guarded.
    let src = "pure contract C {\n  input phases : Collection[Float]\n  compute d : Collection[Float] = map(phases, p -> fold(phases, 0.0, (a, q) -> a + sin(q - p)))\n  output d : Collection[Float]\n}\n";
    let o = compile(src, "foldinmap");
    assert!(
        has_nested_diag(&o),
        "map(x -> fold(...)) still emits OOF-COL-NESTED (fold unsupported nested): {o}"
    );
}

#[test]
fn nested_diag_message_names_the_call_contract_workaround() {
    // Uses a still-guarded shape (fold-in-map) to exercise the message.
    let src = "pure contract C {\n  input phases : Collection[Float]\n  compute d : Collection[Float] = map(phases, p -> fold(phases, 0.0, (a, q) -> a + q))\n  output d : Collection[Float]\n}\n";
    let o = compile(src, "msg");
    assert!(
        has_nested_diag(&o) && o.contains("call_contract"),
        "message must name the call_contract workaround: {o}"
    );
}

// ── NOT rejected (non-regression) ───────────────────────────────────────────────────────────────────

#[test]
fn single_level_map_with_math_is_clean() {
    let src = "pure contract C {\n  input phases : Collection[Float]\n  compute d : Collection[Float] = map(phases, q -> sin(q))\n  output d : Collection[Float]\n}\n";
    let o = compile(src, "single");
    assert!(
        is_ok(&o) && !has_nested_diag(&o),
        "single-level map+math must stay green: {o}"
    );
}

#[test]
fn top_level_sum_of_map_is_clean() {
    let src = "pure contract C {\n  input phases : Collection[Float]\n  compute s : Float = sum(map(phases, q -> sin(q)))\n  output s : Float\n}\n";
    let o = compile(src, "toplevel");
    assert!(
        is_ok(&o) && !has_nested_diag(&o),
        "top-level sum(map(...)) must stay green: {o}"
    );
}

#[test]
fn top_level_fold_with_det_is_clean() {
    // Mirrors the parallel N-body order-parameter authoring (fold + det_* at compute level).
    let src = "pure contract C {\n  input phases : Collection[Float]\n  compute sc : Float = fold(phases, 0.0, (acc, theta) -> acc + det_cos(theta))\n  output sc : Float\n}\n";
    let o = compile(src, "foldtoplevel");
    assert!(
        is_ok(&o) && !has_nested_diag(&o),
        "top-level fold+det_* must stay green: {o}"
    );
}

#[test]
fn call_contract_workaround_is_clean() {
    let src = "pure contract Inner {\n  input xs : Collection[Float]\n  input p : Float\n  compute c : Float = fold(xs, 0.0, (acc, q) -> acc + sin(q - p))\n  output c : Float\n}\n\npure contract Outer {\n  input xs : Collection[Float]\n  compute d : Collection[Float] = map(xs, p -> call_contract(\"Inner\", xs, p))\n  output d : Collection[Float]\n}\n";
    let o = compile(src, "workaround");
    assert!(
        is_ok(&o) && !has_nested_diag(&o),
        "call_contract-per-element workaround must stay green: {o}"
    );
}
