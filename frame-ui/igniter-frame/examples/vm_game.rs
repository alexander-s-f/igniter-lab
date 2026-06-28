//! LAB-FRAME-3D-GAME-IG-P3 — the GAME LOGIC runs as `.ig` on igniter-vm.
//!
//! The physics step is the `.ig` `Step(world, boom) -> world` contract (`specimens/vm_game_app.ig`).
//! The host re-runs it to advance / replay / time-travel, so the gamedev determinism payoff is proven
//! THROUGH the language:
//!   • the `.ig` `Step` is bit-identical to the Rust `game_loop` step at every tick (cross-check);
//!   • REPLAY     — the same input log reruns to the same world;
//!   • TIME-TRAVEL— `world_at(t)` = re-run `.ig` `Step` from the initial world over the input log.
//!
//! Usage: `cargo run --no-default-features --example vm_game -- <vm_game_app.igapp> <path/to/igniter-vm>`
//! Self-checks (panics on mismatch), so running it IS the live proof.

use igniter_frame::game_loop::{
    initial_world_json, kick_world_json, render_scene_json, scene_hit, scene_json_of_world,
    step_world_json,
};
use serde_json::{json, Value};
use std::io::Write;
use std::process::{exit, Command};

/// Run one `.ig` contract on the VM, returning its `.result` as a JSON string. `entry` selects it.
fn ig_run(vm: &str, igapp: &str, entry: &str, input: &Value) -> String {
    let mut tmp = std::env::temp_dir();
    tmp.push(format!("vm_game_{entry}.json"));
    std::fs::File::create(&tmp).unwrap().write_all(input.to_string().as_bytes()).unwrap();
    let out = Command::new(vm)
        .args(["run", "--contract", igapp, "--entry", entry, "--inputs", tmp.to_str().unwrap(), "--json"])
        .output()
        .unwrap_or_else(|e| { eprintln!("spawn {vm}: {e}"); exit(2); });
    let stdout = String::from_utf8_lossy(&out.stdout);
    let line = stdout.lines().find(|l| l.trim_start().starts_with("{\"latency")).unwrap_or_else(|| {
        eprintln!("no envelope from {entry}:\n{stdout}\n{}", String::from_utf8_lossy(&out.stderr));
        exit(1);
    });
    let env: Value = serde_json::from_str(line.trim()).unwrap();
    if env["status"] != "success" { eprintln!("{entry} failed: {env}"); exit(1); }
    env["result"].to_string()
}

/// One `.ig` `Step` on the VM: `world` (a `World` JSON) + `boom` (0/1) → the new `World` JSON.
fn ig_step(vm: &str, igapp: &str, world: &str, boom: bool) -> String {
    let input = json!({ "world": serde_json::from_str::<Value>(world).unwrap(), "boom": if boom { 1 } else { 0 } });
    let mut tmp = std::env::temp_dir();
    tmp.push("vm_game_step.json");
    std::fs::File::create(&tmp).unwrap().write_all(input.to_string().as_bytes()).unwrap();
    let out = Command::new(vm)
        .args(["run", "--contract", igapp, "--entry", "Step", "--inputs", tmp.to_str().unwrap(), "--json"])
        .output()
        .unwrap_or_else(|e| { eprintln!("spawn {vm}: {e}"); exit(2); });
    let stdout = String::from_utf8_lossy(&out.stdout);
    let line = stdout.lines().find(|l| l.trim_start().starts_with("{\"latency")).unwrap_or_else(|| {
        eprintln!("no envelope:\n{stdout}\n{}", String::from_utf8_lossy(&out.stderr));
        exit(1);
    });
    let env: Value = serde_json::from_str(line.trim()).unwrap();
    if env["status"] != "success" { eprintln!("Step failed: {env}"); exit(1); }
    env["result"].to_string()
}

/// `world_at(t)` driven by the `.ig` `Step` — re-simulate from the initial world over the boom log.
fn ig_world_at(vm: &str, igapp: &str, booms: &[u64], t: u64) -> String {
    let mut w = initial_world_json();
    for k in 0..t {
        w = ig_step(vm, igapp, &w, booms.contains(&k));
    }
    w
}

fn main() {
    let mut args = std::env::args().skip(1);
    let igapp = args.next().unwrap_or_else(|| { eprintln!("usage: vm_game <igapp> <igniter-vm>"); exit(2); });
    let vm = args.next().unwrap_or_else(|| { eprintln!("usage: vm_game <igapp> <igniter-vm>"); exit(2); });

    let booms = [4u64]; // one boom at tick 4
    const K: u64 = 12;

    // ---- cross-check: the `.ig` Step is bit-identical to the Rust step at EVERY tick ----------------
    let mut wi = initial_world_json(); // .ig world
    let mut wr = initial_world_json(); // rust world
    for k in 0..K {
        let boom = booms.contains(&k);
        wi = ig_step(&vm, &igapp, &wi, boom);
        wr = step_world_json(&wr, boom);
        assert_eq!(
            serde_json::from_str::<Value>(&wi).unwrap(),
            serde_json::from_str::<Value>(&wr).unwrap(),
            "tick {}: .ig Step diverged from the Rust step", k + 1
        );
    }
    println!("cross-check  ·  .ig Step  ==  Rust step  for all {K} ticks (boom at {booms:?})  ✓");

    // ---- replay: the same input log reruns to the same world ---------------------------------------
    let again = ig_world_at(&vm, &igapp, &booms, K);
    assert_eq!(serde_json::from_str::<Value>(&again).unwrap(), serde_json::from_str::<Value>(&wi).unwrap());
    println!("replay       ·  same log → same world  ✓");

    // ---- time-travel: world_at is pure — seek back to 6, forward to K, identical --------------------
    let at_k = ig_world_at(&vm, &igapp, &booms, K);
    let at_6 = ig_world_at(&vm, &igapp, &booms, 6);
    let at_k_again = ig_world_at(&vm, &igapp, &booms, K);
    assert_ne!(serde_json::from_str::<Value>(&at_6).unwrap(), serde_json::from_str::<Value>(&at_k).unwrap());
    assert_eq!(serde_json::from_str::<Value>(&at_k_again).unwrap(), serde_json::from_str::<Value>(&at_k).unwrap());
    println!("time-travel  ·  world_at(t) re-runs the .ig sim purely  ✓");

    // ---- the VIEW is ALSO .ig: View(world) on the VM projects 3D→2D, cross-checked vs Rust ----------
    let scene_ig = ig_run(&vm, &igapp, "View", &json!({ "world": serde_json::from_str::<Value>(&wi).unwrap() }));
    let scene_rust = scene_json_of_world(&wi);
    assert_eq!(
        serde_json::from_str::<Value>(&scene_ig).unwrap(),
        serde_json::from_str::<Value>(&scene_rust).unwrap(),
        ".ig View projection diverged from the Rust mirror"
    );
    println!("view         ·  .ig View(world) == Rust projection — the projection is on the VM  ✓");

    // ---- the host's ONLY job: render the VM-projected scene -----------------------------------------
    let svg = render_scene_json(&scene_ig);
    assert!(svg.contains("<rect"));
    println!("render       ·  the host draws the .ig-projected scene (logic + view both .ig)  ✓");

    // ---- INTERACTION: a click hit-tests a body's marker → the .ig REDUCER kicks that body (VM) ------
    let world0 = initial_world_json();
    let scene0 = ig_run(&vm, &igapp, "View", &json!({ "world": serde_json::from_str::<Value>(&world0).unwrap() }));
    // a click at the centre of body 1's marker
    let m1 = &serde_json::from_str::<Value>(&scene0).unwrap()["markers"][1];
    let (cx, cy) = (m1["x"].as_i64().unwrap() + m1["w"].as_i64().unwrap() / 2, m1["y"].as_i64().unwrap() + m1["h"].as_i64().unwrap() / 2);
    let target = scene_hit(&scene0, cx, cy).expect("a marker under the click");
    let kicked_ig = ig_run(&vm, &igapp, "Reduce", &json!({ "world": serde_json::from_str::<Value>(&world0).unwrap(), "target": target }));
    assert_eq!(
        serde_json::from_str::<Value>(&kicked_ig).unwrap(),
        serde_json::from_str::<Value>(&kick_world_json(&world0, target)).unwrap(),
        ".ig Reduce(kick) diverged from the Rust mirror"
    );
    let bodies = serde_json::from_str::<Value>(&kicked_ig).unwrap()["bodies"].clone();
    assert_eq!(bodies[target as usize]["vy"], 1400, "the clicked body was kicked up");
    assert_eq!(bodies[0]["vy"], 0, "a non-clicked body is untouched");
    println!("click→kick   ·  hit-test marker {target} → .ig Reduce kicks ONLY that body (vy 0→1400)  ✓");

    println!("\nOK — a FULL, INTERACTIVE Igniter game on igniter-vm: logic (.ig Step), view (.ig View),\n     and interaction (.ig Reduce) — deterministic, replayable; the host only ticks, renders, hit-tests.");
}
