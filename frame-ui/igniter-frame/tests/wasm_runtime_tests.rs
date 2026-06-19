//! LAB-FRAME-WASM-LIVE-STEP-P5 — proof for the synchronous `FrameRuntime` that the WASM bindings
//! wrap. These run NATIVELY (the exact same Rust the browser calls; `#[wasm_bindgen]` is just a
//! thin delegating shell). Imports ONLY `igniter_frame` → machine-free.

use igniter_frame::runtime::FrameRuntime;

// e1 starts at world-x = -1 → screen sx = 150 (camera scale 200 / depth 4 → f=50; -1*50+200).
// A click maps css(300,400) on an 800×800 viewport → frame(150,200) — a hit on e1.
const ON_E1: (f64, f64) = (300.0, 400.0);
const MISS: (f64, f64) = (10.0, 10.0);

#[test]
fn click_hit_advances_state_and_moves_entity() {
    let mut rt = FrameRuntime::demo();
    assert_eq!(rt.frame_index(), 0);
    assert!(
        rt.render_svg().contains("cx=\"150\""),
        "e1 starts at sx=150"
    );

    let effected = rt.click(ON_E1.0, ON_E1.1);
    assert!(effected, "a hit on e1 produces a state effect");
    assert_eq!(rt.frame_index(), 1, "an effect advances the step");
    assert!(
        rt.render_svg().contains("cx=\"200\""),
        "e1 re-projected at sx=200 (moved +1 world-x)"
    );
    // input never mutated the frame: the move came from a RE-PROJECTION of new state.
}

#[test]
fn click_miss_no_effect_no_advance() {
    let mut rt = FrameRuntime::demo();
    let before = rt.render_digest();
    let effected = rt.click(MISS.0, MISS.1);
    assert!(!effected, "a miss produces no effect");
    assert_eq!(rt.frame_index(), 0, "a miss does not advance");
    assert_eq!(
        rt.render_digest(),
        before,
        "the frame is unchanged on a miss"
    );
}

#[test]
fn lineage_visible_after_hit() {
    let mut rt = FrameRuntime::demo();
    rt.click(ON_E1.0, ON_E1.1);
    let lineage: serde_json::Value = serde_json::from_str(&rt.lineage_json()).unwrap();
    assert_eq!(lineage["input_receipt_id"], "input:0");
    assert_eq!(lineage["effect_receipt_id"], "effect:0");
    assert_eq!(lineage["frame_index"], 1);
}

#[test]
fn deterministic_replay_of_click_log() {
    // The exact render_demo pointer log → e1 marches 150 → 200 → 250 → 300.
    let log = [(300.0, 400.0), (400.0, 400.0), (500.0, 400.0)];

    let run = |clicks: &[(f64, f64)]| {
        let mut rt = FrameRuntime::demo();
        let mut digests = vec![rt.render_digest()];
        for (x, y) in clicks {
            rt.click(*x, *y);
            digests.push(rt.render_digest());
        }
        digests
    };

    let a = run(&log);
    let b = run(&log);
    assert_eq!(
        a, b,
        "same start + same click log → byte-identical frame digests"
    );
    assert_eq!(a.len(), 4);

    // and the entity actually walked across the expected screen positions
    let mut rt = FrameRuntime::demo();
    for (x, y) in log {
        rt.click(x, y);
    }
    assert!(
        rt.render_svg().contains("cx=\"300\""),
        "e1 ended at sx=300 after 3 moves"
    );
    assert_eq!(rt.frame_index(), 3);
}

#[test]
fn reset_returns_to_initial_scene() {
    let mut rt = FrameRuntime::demo();
    let initial = rt.render_digest();
    rt.click(ON_E1.0, ON_E1.1);
    assert_ne!(rt.render_digest(), initial);
    // reset == reconstruct demo (mirrors WasmRuntime::reset for replay)
    rt = FrameRuntime::demo();
    assert_eq!(
        rt.render_digest(),
        initial,
        "reset reproduces the initial frame exactly"
    );
    assert_eq!(rt.frame_index(), 0);
}
