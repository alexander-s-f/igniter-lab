// LAB-VM-NESTED-HOF-EVAL-AST-RECOVERY-P3
// End-to-end proof that nested collection ops inside HOF lambda bodies now EXECUTE through the real compiler
// (`igniter_compiler`) + VM (`igniter-vm run`). Before P3 these typechecked then died at VM eval with
// "Unsupported operator: stdlib.collection.map"; eval_ast now has map/fold/sum arms + qualified-name
// normalization, and outer-lambda params are captured via the threaded `local_env`.
//
// Uses the sibling compiler binary at a relative path; if it is not built the test SKIPS (isolation-safe),
// matching the lab's guard-test convention.

use std::path::PathBuf;
use std::process::Command;

fn igc() -> Option<PathBuf> {
    let p = PathBuf::from("../igniter-compiler/target/debug/igniter_compiler");
    if p.exists() {
        Some(p)
    } else {
        None
    }
}

fn vm_bin() -> &'static str {
    env!("CARGO_BIN_EXE_igniter-vm")
}

/// Compile `src` then run `entry` with `inputs`; returns the `igniter-vm run` stdout (or None if the sibling
/// compiler is not built).
fn compile_and_run(src: &str, entry: &str, inputs: &str, tag: &str) -> Option<String> {
    let igc = igc()?;
    let dir = std::env::temp_dir().join(format!("nhof_{}_{}", tag, std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let f = dir.join("m.ig");
    std::fs::write(&f, src).unwrap();
    let igapp = dir.join("out.igapp");
    let c = Command::new(&igc)
        .args([
            "compile",
            f.to_str().unwrap(),
            "--out",
            igapp.to_str().unwrap(),
        ])
        .output()
        .expect("run igniter_compiler");
    let cout = String::from_utf8_lossy(&c.stdout);
    assert!(
        cout.contains("\"status\": \"ok\""),
        "compile must be ok (nested HOF supported): {cout}"
    );
    let inf = dir.join("in.json");
    std::fs::write(&inf, inputs).unwrap();
    let r = Command::new(vm_bin())
        .args([
            "run",
            "--contract",
            igapp.to_str().unwrap(),
            "--entry",
            entry,
            "--inputs",
            inf.to_str().unwrap(),
        ])
        .output()
        .expect("run igniter-vm");
    Some(String::from_utf8_lossy(&r.stdout).to_string())
}

/// The Kuramoto all-N tick in ONE contract via nested `map(x -> sum(map(...)))` — no `call_contract`.
#[test]
fn kuramoto_all_n_tick_executes_without_call_contract() {
    let src = "pure contract Tick {\n  input phases : Collection[Float]\n  input omega : Float\n  input k_over_n : Float\n  input dt : Float\n  compute new_phases : Collection[Float] = map(phases, p -> p + (dt * (omega + (k_over_n * sum(map(phases, q -> sin(q - p)))))))\n  output new_phases : Collection[Float]\n}\n";
    let inputs = "{\"phases\":[0.0,1.0,2.0],\"omega\":0.0,\"k_over_n\":1.0,\"dt\":0.1}";
    let Some(out) = compile_and_run(src, "Tick", inputs, "tick") else {
        eprintln!("skip: ../igniter-compiler not built");
        return;
    };
    // Expected ≈ [0.17507684, 1.0, 1.82492316] (one explicit-Euler step, all-to-all coupling).
    assert!(out.contains("0.17507684"), "p0 advanced by coupling: {out}");
    assert!(out.contains("1.8249231"), "p2 advanced by coupling: {out}");
    assert!(
        !out.contains("Unsupported"),
        "must not hit the old late VM failure: {out}"
    );
}

/// Pure nested map: `map(rows, row -> map(row, x -> x + 1.0))`.
#[test]
fn nested_map_in_map_executes() {
    let src = "pure contract C {\n  input xss : Collection[Collection[Float]]\n  compute d : Collection[Collection[Float]] = map(xss, row -> map(row, x -> x + 1.0))\n  output d : Collection[Collection[Float]]\n}\n";
    let Some(out) = compile_and_run(src, "C", "{\"xss\":[[10.0,20.0],[30.0]]}", "mapinmap") else {
        eprintln!("skip: ../igniter-compiler not built");
        return;
    };
    assert!(
        out.contains("11.0") && out.contains("21.0") && out.contains("31.0"),
        "elementwise +1 nested: {out}"
    );
}

/// Nested 1-arg scalar sum over a captured collection: `map(rows, row -> sum(row))`.
#[test]
fn nested_scalar_sum_executes() {
    let src = "pure contract C {\n  input xss : Collection[Collection[Float]]\n  compute d : Collection[Float] = map(xss, row -> sum(row))\n  output d : Collection[Float]\n}\n";
    let Some(out) = compile_and_run(src, "C", "{\"xss\":[[0.5,2.0,3.0],[1.5]]}", "sumrow") else {
        eprintln!("skip: ../igniter-compiler not built");
        return;
    };
    assert!(
        out.contains("5.5") && out.contains("1.5"),
        "per-row sum: {out}"
    );
}
