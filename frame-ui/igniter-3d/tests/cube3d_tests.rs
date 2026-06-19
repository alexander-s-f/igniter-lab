//! LAB-FRAME-3D-POC-REHOME-P7 — the 3D POC, re-homed over igniter-frame, stays deterministic and
//! replay-identical, and renders a projection-heavy wireframe through the same RenderHost boundary.
//! Imports only `igniter_3d` (+ `igniter_frame` transitively, machine-free) → no machine.

use igniter_3d::{Cube3dRuntime, EDGES, VERTS};

fn digest_sequence(ticks: usize) -> Vec<String> {
    let mut rt = Cube3dRuntime::new();
    let mut seq = vec![rt.render_digest()];
    for _ in 0..ticks {
        rt.tick();
        seq.push(rt.render_digest());
    }
    seq
}

#[test]
fn wireframe_renders_through_render_host_boundary() {
    let rt = Cube3dRuntime::new();
    let svg = rt.render_svg();
    // projection-heavy: 8 vertices + 12 edges drawn via the WireframeRenderHost (a RenderHost).
    assert_eq!(svg.matches("<line").count(), EDGES.len(), "12 cube edges");
    assert_eq!(
        svg.matches("<circle").count(),
        VERTS.len(),
        "8 cube vertices"
    );
    assert!(svg.contains("viewBox=\"0 0 400 400\""));
}

#[test]
fn tick_advances_and_changes_the_frame() {
    let mut rt = Cube3dRuntime::new();
    let before = rt.render_digest();
    assert_eq!(rt.frame_index(), 0);
    assert!(rt.tick());
    assert_eq!(rt.frame_index(), 1, "a tick advances the step");
    assert_ne!(
        rt.render_digest(),
        before,
        "rotation changes the projected frame"
    );
}

#[test]
fn world_tick_is_deterministic() {
    // Two independent runs of the same tick count → identical frame-digest sequences.
    let a = digest_sequence(40);
    let b = digest_sequence(40);
    assert_eq!(
        a, b,
        "same start + same tick count → byte-identical frame digests"
    );
    assert_eq!(a.len(), 41);
}

#[test]
fn replay_is_byte_identical() {
    // A "recorded" run vs a "replayed" run produce the exact same digest stream.
    let recorded = digest_sequence(30);
    let replayed = digest_sequence(30);
    assert_eq!(recorded, replayed);
    // and the cube actually animated (not a frozen frame)
    let distinct: std::collections::HashSet<_> = recorded.iter().collect();
    assert!(
        distinct.len() > 5,
        "the wireframe genuinely rotates over the run"
    );
}

#[test]
fn lineage_uses_the_same_runtime_discipline() {
    let mut rt = Cube3dRuntime::new();
    rt.tick();
    let lineage: serde_json::Value = serde_json::from_str(&rt.lineage_json()).unwrap();
    assert_eq!(lineage["input_receipt_id"], "tick:0");
    assert_eq!(lineage["effect_receipt_id"], "effect:0");
    assert_eq!(lineage["frame_index"], 1);
}

#[test]
fn reset_returns_to_initial_frame() {
    let mut rt = Cube3dRuntime::new();
    let initial = rt.render_digest();
    for _ in 0..10 {
        rt.tick();
    }
    assert_ne!(rt.render_digest(), initial);
    rt.reset();
    assert_eq!(
        rt.render_digest(),
        initial,
        "reset reproduces the initial frame exactly"
    );
    assert_eq!(rt.frame_index(), 0);
}
