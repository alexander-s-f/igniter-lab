// LAB-STDLIB-STATISTICS-DESCRIPTIVE-P2
//
// Pure-`.ig` descriptive statistics (`Mean`/`Variance`/`Stddev` over `Collection[Float]` → `Option[Float]`),
// proven end-to-end through the REAL compiler (`igniter_compiler`) + VM (`igniter-vm run`). No VM builtin —
// these are authored `.ig` contracts using live `count`/`sum`/`map`/`to_float`/`det_sqrt` (post P7/P8/P10).
// Empty → `none()`; non-empty → `some(value)`. Population variance (two-pass, fixed authored-order fold via
// `sum`; no parallel reassociation). `stddev` uses `det_sqrt` (replay-safe). v0 assumes finite input.
//
// Skips if the sibling compiler is not built (isolation-safe, the lab's guard-test convention).

use std::path::PathBuf;
use std::process::Command;

/// The statistics library, authored in pure `.ig`. `m` is guarded (`if n==0 {0.0}`) so the empty case never
/// computes a discarded NaN; the `Option` guard returns `none()` on empty.
const STATS_IG: &str = "module Stdlib.Statistics\n\
\n\
pure contract Mean {\n\
  input xs : Collection[Float]\n\
  compute n : Integer = count(xs)\n\
  compute r : Option[Float] = if n == 0 { none() } else { some(sum(xs) / to_float(n)) }\n\
  output r : Option[Float]\n\
}\n\
\n\
pure contract Variance {\n\
  input xs : Collection[Float]\n\
  compute n : Integer = count(xs)\n\
  compute m : Float = if n == 0 { 0.0 } else { sum(xs) / to_float(n) }\n\
  compute devs : Collection[Float] = map(xs, x -> (x - m) * (x - m))\n\
  compute v : Option[Float] = if n == 0 { none() } else { some(sum(devs) / to_float(n)) }\n\
  output v : Option[Float]\n\
}\n\
\n\
pure contract Stddev {\n\
  input xs : Collection[Float]\n\
  compute n : Integer = count(xs)\n\
  compute m : Float = if n == 0 { 0.0 } else { sum(xs) / to_float(n) }\n\
  compute devs : Collection[Float] = map(xs, x -> (x - m) * (x - m))\n\
  compute v : Float = if n == 0 { 0.0 } else { sum(devs) / to_float(n) }\n\
  compute s : Option[Float] = if n == 0 { none() } else { some(det_sqrt(v)) }\n\
  output s : Option[Float]\n\
}\n";

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

/// Compile `STATS_IG`, then `igniter-vm run` `entry` with `inputs`; return stdout (or None if not built).
fn run_stat(entry: &str, inputs: &str, tag: &str) -> Option<String> {
    let igc = igc()?;
    let dir = std::env::temp_dir().join(format!("stats_{}_{}", tag, std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let f = dir.join("statistics.ig");
    std::fs::write(&f, STATS_IG).unwrap();
    let igapp = dir.join("out.igapp");
    let c = Command::new(&igc)
        .args(["compile", f.to_str().unwrap(), "--out", igapp.to_str().unwrap()])
        .output()
        .expect("run igniter_compiler");
    let cout = String::from_utf8_lossy(&c.stdout);
    assert!(cout.contains("\"status\": \"ok\""), "stats lib must compile: {cout}");
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

fn skip() {
    eprintln!("skip: ../igniter-compiler not built");
}

#[test]
fn mean_of_three_is_some_2() {
    let Some(o) = run_stat("Mean", "{\"xs\":[1.0,2.0,3.0]}", "mean3") else {
        return skip();
    };
    assert!(o.contains("Some") && o.contains("2.0"), "mean([1,2,3]) = some(2.0): {o}");
}

#[test]
fn mean_of_empty_is_none() {
    let Some(o) = run_stat("Mean", "{\"xs\":[]}", "mean0") else {
        return skip();
    };
    // Check the RESULT record specifically (the run stdout's bytecode listing names both arm constructors).
    assert!(
        o.contains("Output: Record({\"__arm\": String(\"None\")"),
        "mean([]) = none(): {o}"
    );
}

#[test]
fn variance_of_three_is_population_two_thirds() {
    let Some(o) = run_stat("Variance", "{\"xs\":[1.0,2.0,3.0]}", "var3") else {
        return skip();
    };
    // population variance of [1,2,3] = ((1+0+1))/3 = 2/3 = 0.6666…
    assert!(o.contains("Some") && o.contains("0.6666666666666666"), "variance([1,2,3]) = some(2/3): {o}");
}

#[test]
fn variance_of_empty_is_none() {
    let Some(o) = run_stat("Variance", "{\"xs\":[]}", "var0") else {
        return skip();
    };
    assert!(
        o.contains("Output: Record({\"__arm\": String(\"None\")"),
        "variance([]) = none(): {o}"
    );
}

#[test]
fn stddev_of_three_uses_det_sqrt() {
    let Some(o) = run_stat("Stddev", "{\"xs\":[1.0,2.0,3.0]}", "std3") else {
        return skip();
    };
    // sqrt(2/3) = 0.816496580927726 (det_sqrt, IEEE-correct).
    assert!(o.contains("Some") && o.contains("0.816496580927726"), "stddev([1,2,3]) = some(sqrt(2/3)): {o}");
}
