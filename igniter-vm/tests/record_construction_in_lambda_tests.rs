// LAB-LANG-RECORD-CONSTRUCTION-IN-LAMBDA-P1
// Record construction inside a HOF lambda body — `map(xs, o -> ({ field: expr, ... }))` — executes through
// the real compiler + VM, including the Kuramoto per-oscillator tick that returns `Collection[Oscillator]`
// directly (no `Collection[Float]` + external re-pairing workaround). The fix landed via the nested-HOF
// recovery (P3) + nested-fold (P4): the parenthesized record literal evaluates in eval_ast and the nested
// `map`/`sum` coupling inside the record fields runs.
//
// NOTE (no syntax change, per card scope): a BARE `o -> { field: expr }` parses as a block, not a record, so
// the record literal must be parenthesized `o -> ({ ... })`. That parser disambiguation is out of scope here.
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

fn compile_and_run(src: &str, entry: &str, inputs: &str, tag: &str) -> Option<String> {
    let igc = igc()?;
    let dir = std::env::temp_dir().join(format!("reclam_{}_{}", tag, std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let f = dir.join("m.ig");
    std::fs::write(&f, src).unwrap();
    let igapp = dir.join("out.igapp");
    let c = Command::new(&igc)
        .args(["compile", f.to_str().unwrap(), "--out", igapp.to_str().unwrap()])
        .output()
        .expect("run igniter_compiler");
    let cout = String::from_utf8_lossy(&c.stdout);
    assert!(cout.contains("\"status\": \"ok\""), "compile must be ok: {cout}");
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

const OSC: &str = "type Oscillator { theta : Float  omega : Float }\n";

/// Minimal map-to-record: `map(nodes, o -> ({ theta: o.theta + 1.0, omega: o.omega }))`.
#[test]
fn minimal_map_to_record_executes_with_fields_preserved() {
    let src = format!(
        "{OSC}pure contract Advance {{\n  input nodes : Collection[Oscillator]\n  compute next : Collection[Oscillator] = map(nodes, o -> ({{ theta: o.theta + 1.0, omega: o.omega }}))\n  output next : Collection[Oscillator]\n}}\n"
    );
    let Some(out) = compile_and_run(&src, "Advance", "{\"nodes\":[{\"theta\":0.0,\"omega\":0.5},{\"theta\":1.0,\"omega\":-0.5}]}", "minimal") else {
        eprintln!("skip: ../igniter-compiler not built");
        return;
    };
    // theta incremented by 1.0, omega carried through unchanged, both as Float records.
    assert!(out.contains("Record("), "output is records: {out}");
    assert!(out.contains("\"theta\": Float(1.0)") && out.contains("\"omega\": Float(0.5)"), "node 0 fields: {out}");
    assert!(out.contains("\"theta\": Float(2.0)") && out.contains("\"omega\": Float(-0.5)"), "node 1 fields: {out}");
    assert!(!out.contains("Unsupported"), "no late VM failure: {out}");
}

/// Kuramoto-shaped: the per-oscillator tick returns `Collection[Oscillator]` directly, constructing a record
/// whose `theta` field contains the nested all-to-all coupling `sum(map(...))` and carrying `omega` through.
#[test]
fn kuramoto_per_omega_record_tick_executes() {
    let src = format!(
        "{OSC}pure contract Tick {{\n  input nodes : Collection[Oscillator]\n  input k_over_n : Float\n  input dt : Float\n  compute next : Collection[Oscillator] = map(nodes, o -> ({{ theta: o.theta + (dt * (o.omega + (k_over_n * sum(map(nodes, x -> sin(x.theta - o.theta)))))), omega: o.omega }}))\n  output next : Collection[Oscillator]\n}}\n"
    );
    let inputs = "{\"nodes\":[{\"theta\":0.0,\"omega\":0.5},{\"theta\":1.0,\"omega\":-0.5}],\"k_over_n\":1.0,\"dt\":0.1}";
    let Some(out) = compile_and_run(&src, "Tick", inputs, "kuramoto") else {
        eprintln!("skip: ../igniter-compiler not built");
        return;
    };
    // Two opposite-frequency oscillators pulled together by coupling: theta ≈ [0.13415, 0.86585]; omega kept.
    assert!(out.contains("0.13414709"), "node 0 theta advanced by coupling: {out}");
    assert!(out.contains("0.86585") || out.contains("0.8658529"), "node 1 theta: {out}");
    assert!(out.contains("\"omega\": Float(0.5)") && out.contains("\"omega\": Float(-0.5)"), "omega preserved: {out}");
    assert!(!out.contains("Unsupported"), "no late VM failure: {out}");
}
