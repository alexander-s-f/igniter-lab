//! LAB-FRAME-VIEW-IG-VM-IN-THE-LOOP-P6 — the host orchestrates a FULLY Igniter-authored view+logic
//! loop. frame-ui (this binary) only hit-tests a click and threads JSON; the VIEW and the REDUCER are
//! `.ig` contracts run on `igniter-vm`.
//!
//! ```text
//! View(state)  --igniter-vm-->  Element  --frame-ui hit_test/derive_intent-->  (action, key)
//!   --igniter-vm Reduce(state,key)-->  state'  --igniter-vm View(state')-->  Element'  (re-projection)
//! ```
//!
//! Usage:
//! ```bash
//! cargo run --no-default-features --example vm_loop -- <vm_loop_app.igapp> <path/to/igniter-vm>
//! ```
//! Self-checks the transition (panics on mismatch), so running it IS the live proof.

use igniter_frame::ig_bridge::project_ig_element;
use igniter_frame::{derive_intent, InputEvent};
use serde_json::{json, Value};
use std::io::Write;
use std::process::{exit, Command};

const W: i64 = 720;
const H: i64 = 440;

/// Run one `.ig` contract on igniter-vm and return its `.result` (the contract output).
fn run_vm(vm: &str, igapp: &str, entry: &str, input: &Value) -> Value {
    let mut tmp = std::env::temp_dir();
    tmp.push(format!("vm_loop_{entry}.json"));
    std::fs::File::create(&tmp)
        .unwrap()
        .write_all(input.to_string().as_bytes())
        .unwrap();
    let out = Command::new(vm)
        .args([
            "run",
            "--contract",
            igapp,
            "--entry",
            entry,
            "--inputs",
            tmp.to_str().unwrap(),
            "--json",
        ])
        .output()
        .unwrap_or_else(|e| {
            eprintln!("failed to spawn {vm}: {e}");
            exit(2);
        });
    let stdout = String::from_utf8_lossy(&out.stdout);
    // the --json envelope is a single line `{"latency_us":…,"result":…,"status":…}`
    let line = stdout
        .lines()
        .find(|l| l.trim_start().starts_with("{\"latency"))
        .unwrap_or_else(|| {
            eprintln!(
                "no result envelope from {entry}:\n{stdout}\n{}",
                String::from_utf8_lossy(&out.stderr)
            );
            exit(1);
        });
    let env: Value = serde_json::from_str(line.trim()).unwrap();
    if env["status"] != "success" {
        eprintln!("{entry} did not succeed: {env}");
        exit(1);
    }
    env["result"].clone()
}

/// The status leaf is the last child; its text echoes `state.sel` (the view's state-dependent render).
/// P7: the bridge-projected `selected` flag for the row whose label is `label`. Selection is the
/// AUTHORED `.ig` equality (`row_key == state.sel`) the VM computed — not a host-side decision.
fn row_selected(element: &Value, label: &str) -> bool {
    let frame = project_ig_element(&element.to_string(), W, H);
    frame
        .nodes
        .iter()
        .find(|n| n.data.get("label").and_then(|v| v.as_str()) == Some(label))
        .and_then(|n| n.data.get("selected").and_then(|v| v.as_bool()))
        .unwrap_or(false)
}

fn main() {
    let mut args = std::env::args().skip(1);
    let igapp = args.next().unwrap_or_else(|| {
        eprintln!("usage: vm_loop <igapp> <igniter-vm>");
        exit(2);
    });
    let vm = args.next().unwrap_or_else(|| {
        eprintln!("usage: vm_loop <igapp> <igniter-vm>");
        exit(2);
    });

    // ---- frame 0: render the initial state via the .ig VIEW on the VM --------------------------------
    let state0 = json!({ "sel": "" });
    let element0 = run_vm(&vm, &igapp, "View", &json!({ "state": state0 }));
    println!(
        "frame 0  ·  View(sel=\"\")  ·  any row selected = {}",
        row_selected(&element0, "Call Grace back")
    );

    // ---- frame-ui hit-tests a click on the 2nd lead; lifts the AUTHORED intent + domain key ----------
    let frame = project_ig_element(&element0.to_string(), W, H);
    let lead = frame
        .nodes
        .iter()
        .find(|n| n.data.get("label").and_then(|v| v.as_str()) == Some("Call Grace back"))
        .expect("the 2nd lead node");
    let (cx, cy) = (lead.sx + 6, lead.sy + 6);
    let intent = derive_intent(
        &frame,
        &InputEvent {
            kind: "click".into(),
            x: cx,
            y: cy,
            payload: json!(null),
        },
    )
    .expect("click derives an intent");
    let key = intent
        .params
        .get("key")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    println!(
        "click ({cx},{cy})  ·  derive_intent -> action={:?} key={:?}",
        intent.action, key
    );
    assert_eq!(intent.action, "select");
    assert_eq!(key, "lead:1", "the authored key reached the host");

    // ---- the .ig REDUCER runs on the VM: (state, key) -> state' --------------------------------------
    let state1 = run_vm(
        &vm,
        &igapp,
        "Reduce",
        &json!({ "state": state0, "key": key }),
    );
    println!("Reduce(state, key)  ·  VM  ·  state' = {state1}");
    assert_eq!(state1["sel"], "lead:1");

    // ---- frame 1: the .ig VIEW RE-RUNS on the new state — re-projection reflects VM-reduced state -----
    let element1 = run_vm(&vm, &igapp, "View", &json!({ "state": state1 }));
    println!(
        "frame 1  ·  View(sel=\"lead:1\")  ·  'Call Grace back' selected = {}",
        row_selected(&element1, "Call Grace back")
    );
    // P7: selection is the AUTHORED `.ig` equality (`row_key == state.sel`) computed on the VM.
    assert!(
        !row_selected(&element0, "Call Grace back"),
        "frame 0 has no selected row"
    );
    assert!(
        row_selected(&element1, "Call Grace back"),
        "the re-projected view marks the clicked row selected"
    );
    assert!(
        !row_selected(&element1, "Review Ada's lead"),
        "an unclicked row stays unselected"
    );

    println!("\nOK — full .ig view+logic loop: click -> .ig Reduce (VM) -> .ig View (VM) -> re-projection,\n     with selection authored by real `.ig` equality (no host-side `n.id == sel`).");
}
