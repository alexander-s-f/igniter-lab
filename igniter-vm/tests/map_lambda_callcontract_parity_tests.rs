// LAB-VM-MAP-LAMBDA-CALLCONTRACT-PARITY-P1
// Focused runtime regression for the blocked shape:
// `map(Collection[T], item -> call_contract(local_static_contract, captured_value, item))`.
// The card's CLI proof covers the canonical Ruby `igc` artifact path; this test keeps the VM
// runtime shape guarded through the lab Rust compiler + VM path.

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
    let dir = std::env::temp_dir().join(format!("map_callcontract_{}_{}", tag, std::process::id()));
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
        "compile must be ok: {cout}"
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

#[test]
fn map_lambda_can_call_local_contract_with_capture_and_item() {
    let src = r#"
type Row { prefix : String  label : String }

pure contract Leaf {
  input prefix : String
  input label  : String
  compute out = { prefix: prefix, label: label }
  output out : Row
}

pure contract Main {
  input labels : Collection[String]
  compute prefix = "row:"
  compute rows = map(labels, item -> call_contract("Leaf", prefix, item))
  output rows : Collection[Row]
}
"#;

    let Some(out) = compile_and_run(src, "Main", "{\"labels\":[\"Ada\",\"Grace\"]}", "rows") else {
        eprintln!("skip: ../igniter-compiler not built");
        return;
    };

    assert!(
        !out.contains("map expects exactly 2 arguments, got 1"),
        "must not regress to dropped-lambda arity failure: {out}"
    );
    assert!(
        out.contains("Ada") && out.contains("Grace"),
        "labels preserved: {out}"
    );
    assert!(
        out.contains("row:"),
        "captured prefix passed to callee: {out}"
    );
}
