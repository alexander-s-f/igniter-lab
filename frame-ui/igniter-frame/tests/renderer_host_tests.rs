//! LAB-FRAME-RENDERER-HOST-P4 — the host renders frames + forwards real pointer events.
//!
//! Machine-FREE on purpose (this file imports ONLY `igniter_frame`): the whole render+input loop
//! runs with zero kernel (browser/WASM-ready). The host maps a real (CSS) pointer to frame coords
//! and forwards to `input_step`; it computes no intent itself.

use igniter_frame::host::{drive, MemWorld, Viewport};
use igniter_frame::{Camera, Intent, IntentReducer};
use serde_json::{json, Value};

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap()
}

fn move_right_reducer() -> IntentReducer {
    Box::new(|intent: &Intent, world: &[(String, Value)]| {
        if intent.action != "move_right" {
            return vec![];
        }
        let target = match &intent.target {
            Some(t) => t,
            None => return vec![],
        };
        world
            .iter()
            .filter(|(id, _)| id == target)
            .map(|(id, val)| {
                let mut v = val.clone();
                v["x"] = json!(v["x"].as_f64().unwrap_or(0.0) + 1.0);
                (id.clone(), v)
            })
            .collect()
    })
}

fn cube_world() -> MemWorld {
    MemWorld::new(
        vec![("e1".to_string(), json!({ "x": 0.0, "y": 0.0, "z": 0.0, "on_click": { "action": "move_right" } }))],
        move_right_reducer(),
    )
}

fn viewport() -> Viewport {
    Viewport { css_w: 800.0, css_h: 800.0, frame_w: 400, frame_h: 400 }
}

// real pointer (CSS) coordinates map onto frame coordinates
#[test]
fn pointer_to_frame_mapping() {
    let vp = viewport(); // 800css → 400frame = half scale
    assert_eq!(vp.pointer_to_frame(0.0, 0.0), (0, 0));
    assert_eq!(vp.pointer_to_frame(400.0, 400.0), (200, 200));
    assert_eq!(vp.pointer_to_frame(800.0, 800.0), (400, 400));
}

// a forwarded pointer event runs the loop and changes the next rendered frame
#[test]
fn drive_changes_next_frame() {
    rt().block_on(async {
        let world = cube_world();
        // click at CSS (400,400) → frame (200,200) → hits e1 at (200,200)
        let frames = drive(&world, &Camera::default(), &viewport(), &[(400.0, 400.0)]).await.unwrap();
        assert_eq!(frames.len(), 2); // initial + after click
        assert!(frames[0].svg.contains("<svg") && frames[1].svg.contains("<circle"));
        assert_ne!(frames[0].render_digest, frames[1].render_digest); // the click moved the entity
    });
}

// the host forwards every click; the LOOP decides (hit → effect, miss → none) — no host filtering
#[test]
fn host_forwards_loop_decides() {
    rt().block_on(async {
        // hit
        let hit = drive(&cube_world(), &Camera::default(), &viewport(), &[(400.0, 400.0)]).await.unwrap();
        assert!(hit[1].effect_receipt_id.is_some());
        // miss (CSS (10,10) → frame (5,5), far from the entity)
        let miss = drive(&cube_world(), &Camera::default(), &viewport(), &[(10.0, 10.0)]).await.unwrap();
        assert!(miss[1].effect_receipt_id.is_none());
        assert_eq!(miss[0].render_digest, miss[1].render_digest); // miss → no state change
    });
}

// lineage ids are present + debuggable on each interactive host frame
#[test]
fn lineage_visible_on_host_frame() {
    rt().block_on(async {
        let frames = drive(&cube_world(), &Camera::default(), &viewport(), &[(400.0, 400.0)]).await.unwrap();
        assert_eq!(frames[1].input_receipt_id.as_deref(), Some("input:0"));
        assert_eq!(frames[1].effect_receipt_id.as_deref(), Some("effect:0"));
    });
}

// deterministic replay of a captured pointer-event log → identical host frames
#[test]
fn deterministic_replay_of_pointer_log() {
    rt().block_on(async {
        // follow the entity as it moves right: frame x 200→250→300 ⇒ CSS 400→500→600
        let log = [(400.0, 400.0), (500.0, 400.0), (600.0, 400.0)];
        let a = drive(&cube_world(), &Camera::default(), &viewport(), &log).await.unwrap();
        let b = drive(&cube_world(), &Camera::default(), &viewport(), &log).await.unwrap();
        let da: Vec<_> = a.iter().map(|f| f.render_digest.clone()).collect();
        let db: Vec<_> = b.iter().map(|f| f.render_digest.clone()).collect();
        assert_eq!(da, db);
        assert_eq!(da.len(), 4); // initial + 3
        assert_ne!(da[1], da[2]); // each step advanced
    });
}

// the loop ran fully in-process with NO kernel (this file imports only igniter_frame)
#[test]
fn runs_machine_free() {
    rt().block_on(async {
        let world = cube_world();
        let frames = drive(&world, &Camera::default(), &viewport(), &[(400.0, 400.0)]).await.unwrap();
        assert!(!frames.is_empty());
        assert_eq!(world.recorded_inputs(), 1);
        assert!(world.recorded_frames() >= 1);
    });
}
