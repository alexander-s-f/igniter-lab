//! LAB-FRAME-3D-GAME-IG-P3 — the game LOGIC runs as `.ig` on igniter-vm.
//!
//! Deterministic cross-check over command-produced fixtures: one `.ig` `Step` of the physics
//! (`specimens/vm_game_app.ig`, run on `igniter-vm`) is BIT-IDENTICAL to the Rust `game_loop` step, for
//! both the quiet and the boom case — so the same deterministic engine (and its replay/time-travel,
//! proven in `game_loop` + live in `examples/vm_game.rs`) is authored entirely in Igniter.
//!
//! Regenerate the fixtures:
//! ```text
//! igc compile specimens/dx-view-d/vm_game_app.ig --out /tmp/vmgame.igapp
//! igniter-vm run --contract /tmp/vmgame.igapp --entry Step --inputs '{"world":<initial>,"boom":0}' --json  # noboom
//! igniter-vm run --contract /tmp/vmgame.igapp --entry Step --inputs '{"world":<initial>,"boom":1}' --json  # boom
//! ```
//! where `<initial>` is `game_loop::initial_world_json()`.

use igniter_frame::game_loop::{
    initial_world_json, render_scene_json, render_world_json, scene_json_of_world, step_world_json,
};
use serde_json::Value;

const NOBOOM: &str = include_str!("fixtures/vm_game_step_noboom.runtime.json");
const BOOM: &str = include_str!("fixtures/vm_game_step_boom.runtime.json");
const SCENE0: &str = include_str!("fixtures/vm_game_scene0.runtime.json");

fn result(envelope: &str) -> Value {
    let env: Value = serde_json::from_str(envelope).unwrap();
    assert_eq!(env["status"], "success");
    env["result"].clone()
}

fn json(s: &str) -> Value {
    serde_json::from_str(s).unwrap()
}

#[test]
fn ig_step_is_bit_identical_to_the_rust_step() {
    let init = initial_world_json();
    // the `.ig` `Step` run on igniter-vm == the Rust `game_loop` step — for the quiet and boom cases
    assert_eq!(json(&step_world_json(&init, false)), result(NOBOOM), ".ig Step(quiet) == Rust step");
    assert_eq!(json(&step_world_json(&init, true)), result(BOOM), ".ig Step(boom) == Rust step");
}

#[test]
fn a_boom_diverges_the_ig_world() {
    assert_ne!(result(NOBOOM), result(BOOM), "the boom impulse changes the world");
}

#[test]
fn the_vm_produced_world_renders_as_3d_wireframe() {
    let svg = render_world_json(&result(NOBOOM).to_string());
    assert!(svg.starts_with("<svg"));
    // bounding box (12 edges) + 6 bodies (12 each)
    assert_eq!(svg.matches("<line").count(), 12 * 7);
}

#[test]
fn step_world_json_is_total_on_garbage() {
    assert_eq!(json(&step_world_json("not json", false)), json(r#"{"bodies":[]}"#));
}

#[test]
fn ig_view_projection_is_bit_identical_to_the_rust_projection() {
    // the `.ig` `View(world)` (3D→2D projection, run on igniter-vm) == the Rust mirror
    let init = initial_world_json();
    assert_eq!(json(&scene_json_of_world(&init)), result(SCENE0), ".ig View == Rust projection");
}

#[test]
fn the_ig_scene_renders_to_svg() {
    let svg = render_scene_json(&result(SCENE0).to_string());
    assert!(svg.starts_with("<svg"));
    // background + one marker per body (6)
    assert_eq!(svg.matches("<rect").count(), 1 + 6);
}
