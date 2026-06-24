// LAB-STDLIB-COLLECTION-ZIP-PROOF-P2
//
// Proves and LOCKS the semantics of the (previously wired-but-untested) `zip` collection op through the
// real compiler + VM:
//   - `zip(a, b)` pairs positionally into `Collection[Pair[A, B]]`, each element a `Record{first, second}`;
//   - UNEQUAL LENGTHS TRUNCATE to `min(len_a, len_b)` (silent, deterministic — Python/Elixir-consistent);
//   - the synthetic `Pair[A, B]` now TYPECHECKS field access (`p.first` → A, `p.second` → B) so paired
//     iteration `map(zip(a, b), p -> f(p.first, p.second))` compiles and runs (the P2 typechecker fix);
//   - empty input → empty result; fixed source order ⇒ deterministic.
//
// The downstream consumer is `covariance`/`correlation` (a separate card); none implemented here.
//
// Sibling-compiler guarded (skips if `../igniter-compiler` is not built), matching the lab convention.

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

/// Compile `src` and run `entry` with `inputs`. Returns the VM stdout, or `None` if the sibling
/// compiler is not built (skip). Asserts the compile is `status: ok` (a typecheck failure fails the test).
fn compile_and_run(src: &str, entry: &str, inputs: &str, tag: &str) -> Option<String> {
    let igc = igc()?;
    let dir = std::env::temp_dir().join(format!("zip_{}_{}", tag, std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let f = dir.join("m.ig");
    std::fs::write(&f, src).unwrap();
    let igapp = dir.join("out.igapp");
    let c = Command::new(&igc)
        .args(["compile", f.to_str().unwrap(), "--out", igapp.to_str().unwrap()])
        .output()
        .expect("run igniter_compiler");
    let cout = String::from_utf8_lossy(&c.stdout);
    assert!(
        cout.contains("\"status\": \"ok\""),
        "compile must be ok for {tag}: {cout}"
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

/// Raw `zip` shape: each element is a `Record{first, second}`, paired positionally.
#[test]
fn zip_pairs_have_first_second_fields() {
    let src = "pure contract Z {\n  input a : Collection[Integer]\n  input b : Collection[Integer]\n  compute z : Collection[Unknown] = zip(a, b)\n  output z : Collection[Unknown]\n}\n";
    let Some(out) = compile_and_run(src, "Z", "{\"a\":[1,2],\"b\":[7,8]}", "shape") else {
        eprintln!("skip: ../igniter-compiler not built");
        return;
    };
    assert!(
        out.contains("Record({\"first\": Integer(1), \"second\": Integer(7)})"),
        "pair 0 = {{first:1, second:7}}: {out}"
    );
    assert!(
        out.contains("Record({\"first\": Integer(2), \"second\": Integer(8)})"),
        "pair 1 = {{first:2, second:8}}: {out}"
    );
    assert!(!out.contains("Unsupported"), "no late VM failure: {out}");
}

/// Unequal lengths truncate to the shorter — left longer.
#[test]
fn zip_truncates_to_shorter_left_longer() {
    let src = "pure contract T {\n  input a : Collection[Integer]\n  input b : Collection[Integer]\n  compute s : Collection[Integer] = map(zip(a, b), p -> p.first + p.second)\n  output s : Collection[Integer]\n}\n";
    let Some(out) = compile_and_run(src, "T", "{\"a\":[1,2,3,4,5],\"b\":[10,20]}", "trunc_l") else {
        eprintln!("skip: ../igniter-compiler not built");
        return;
    };
    // min(5,2)=2 → [1+10, 2+20]; the tail of `a` is dropped.
    assert!(
        out.contains("Array([Integer(11), Integer(22)])"),
        "truncates to min=2: {out}"
    );
}

/// Unequal lengths truncate to the shorter — right longer.
#[test]
fn zip_truncates_to_shorter_right_longer() {
    let src = "pure contract T {\n  input a : Collection[Integer]\n  input b : Collection[Integer]\n  compute s : Collection[Integer] = map(zip(a, b), p -> p.first + p.second)\n  output s : Collection[Integer]\n}\n";
    let Some(out) = compile_and_run(src, "T", "{\"a\":[1],\"b\":[10,20,30]}", "trunc_r") else {
        eprintln!("skip: ../igniter-compiler not built");
        return;
    };
    assert!(
        out.contains("Array([Integer(11)])"),
        "truncates to min=1: {out}"
    );
}

/// The P2 fix: `Pair.first`/`.second` TYPECHECK (Integer arithmetic) so paired iteration compiles + runs.
#[test]
fn zip_field_access_typechecks_integer() {
    let src = "pure contract S {\n  input a : Collection[Integer]\n  input b : Collection[Integer]\n  compute s : Collection[Integer] = map(zip(a, b), p -> p.first + p.second)\n  output s : Collection[Integer]\n}\n";
    let Some(out) = compile_and_run(src, "S", "{\"a\":[1,2,3],\"b\":[10,20,30]}", "int") else {
        eprintln!("skip: ../igniter-compiler not built");
        return;
    };
    assert!(
        out.contains("Array([Integer(11), Integer(22), Integer(33)])"),
        "paired sum: {out}"
    );
}

/// Field access types preserve the element type: `Float * Float` pairwise product typechecks + runs.
#[test]
fn zip_field_access_typechecks_float() {
    let src = "pure contract P {\n  input a : Collection[Float]\n  input b : Collection[Float]\n  compute s : Collection[Float] = map(zip(a, b), p -> p.first * p.second)\n  output s : Collection[Float]\n}\n";
    let Some(out) = compile_and_run(src, "P", "{\"a\":[1.5,2.0],\"b\":[4.0,3.0]}", "flt") else {
        eprintln!("skip: ../igniter-compiler not built");
        return;
    };
    assert!(
        out.contains("Array([Float(6.0), Float(6.0)])"),
        "pairwise product [1.5*4.0, 2.0*3.0]: {out}"
    );
}

/// Empty input (either side empty) → empty result.
#[test]
fn zip_empty_yields_empty() {
    let src = "pure contract E {\n  input a : Collection[Integer]\n  input b : Collection[Integer]\n  compute s : Collection[Integer] = map(zip(a, b), p -> p.first + p.second)\n  output s : Collection[Integer]\n}\n";
    let Some(out) = compile_and_run(src, "E", "{\"a\":[],\"b\":[10,20]}", "empty") else {
        eprintln!("skip: ../igniter-compiler not built");
        return;
    };
    assert!(out.contains("Array([])"), "empty zip → empty: {out}");
}
