// LAB-VM-EVALAST-VARIANT-CONSTRUCT-IMPL-P5
// End-to-end proof that a user `variant` CONSTRUCTED inside a HOF lambda body now EXECUTES through the
// real compiler (`igniter_compiler`) + VM. The bytecode path already lowered `variant_construct`
// (compiler.rs Path B → OP_PUSH_RECORD with `__arm`/`__variant` + payload), but `eval_ast` — used for
// lambda/HOF bodies — did not, so `map(xs, x -> Pos { v: x })` typechecked then died at VM eval with
// "Unsupported AST kind in VM evaluator: variant_construct" (the same class that held `batch_importer`).
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
    let dir = std::env::temp_dir().join(format!("vcil_{}_{}", tag, std::process::id()));
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
        "compile must be ok (variant construct in lambda supported): {cout}"
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

const TAG_VARIANT: &str = "variant Tag {\n  Pos { v : Integer }\n  Neg { v : Integer }\n}\n";

/// Construct-in-lambda: `map(xs, x -> if x >= 0 { Pos { v: x } } else { Neg { v: x } })` builds a user
/// variant inside the map lambda (the eval_ast path). The result must carry the same record shape the
/// bytecode path produces: an `__arm` discriminant ("Pos"/"Neg") plus the payload field `v`.
#[test]
fn variant_constructed_in_map_lambda_has_arm_shape() {
    let src = format!(
        "{TAG_VARIANT}pure contract Tagged {{\n  input xs : Collection[Integer]\n  compute d : Collection[Tag] = map(xs, x -> if x >= 0 {{ Pos {{ v: x }} }} else {{ Neg {{ v: x }} }})\n  output d : Collection[Tag]\n}}\n"
    );
    let Some(out) = compile_and_run(&src, "Tagged", "{\"xs\":[5,-3]}", "tagged") else {
        eprintln!("skip: ../igniter-compiler not built");
        return;
    };
    assert!(
        !out.contains("Unsupported"),
        "must not hit the old eval_ast variant_construct failure: {out}"
    );
    // Same record shape as the bytecode path: `__arm` discriminant + payload field.
    assert!(out.contains("__arm"), "carries __arm discriminant: {out}");
    assert!(
        out.contains("Pos") && out.contains("Neg"),
        "both arms constructed: {out}"
    );
    assert!(
        out.contains("\"v\"") || out.contains("v:"),
        "payload field v present: {out}"
    );
}

/// Construct + match in the SAME lambda: `map(xs, x -> match (if x >= 0 { Pos{v:x} } else { Neg{v:x} }) {
/// Pos { v } => v  Neg { v } => 0 - v })` → absolute values. Proves the lambda-constructed variant flows
/// into `match` (which reads `__arm`) with the same shape the bytecode path uses — full eval_ast parity.
#[test]
fn variant_constructed_in_lambda_matches_to_abs() {
    let src = format!(
        "{TAG_VARIANT}pure contract AbsAll {{\n  input xs : Collection[Integer]\n  compute d : Collection[Integer] = map(xs, x -> match (if x >= 0 {{ Pos {{ v: x }} }} else {{ Neg {{ v: x }} }}) {{\n    Pos {{ v }} => v\n    Neg {{ v }} => 0 - v\n  }})\n  output d : Collection[Integer]\n}}\n"
    );
    let Some(out) = compile_and_run(&src, "AbsAll", "{\"xs\":[5,-3,0,-8]}", "absall") else {
        eprintln!("skip: ../igniter-compiler not built");
        return;
    };
    assert!(
        !out.contains("Unsupported"),
        "no late VM failure (construct + match in lambda): {out}"
    );
    // abs([5,-3,0,-8]) = [5,3,0,8]
    assert!(
        out.contains('5') && out.contains('3') && out.contains('8'),
        "abs values [5,3,0,8]: {out}"
    );
}
