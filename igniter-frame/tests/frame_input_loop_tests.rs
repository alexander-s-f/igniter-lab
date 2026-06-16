//! LAB-FRAME-INPUT-LOOP-P3 — state → frame → input → intent → state.
//!
//! Input is hit-tested against the current frame → an intent. The intent goes through an
//! IntentSink EFFECT (a new state fact), never mutating the frame. The next frame is re-projected
//! from the new state. Lineage chains input → effect → frame. Deterministic replay. No browser/GPU.

use igniter_frame::machine_source::{
    TBackendFrameSink, TBackendFrameSource, TBackendIntentSink, EFFECT_STORE, INPUT_STORE,
    WORLD_STORE,
};
use igniter_frame::{
    derive_intent, hit_test, input_step, project_frame, Camera, FrameSource, InputEvent,
    IntentReducer,
};
use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::fact::Fact;
use serde_json::json;
use std::sync::Arc;

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap()
}

/// An interactive entity carrying an `on_click` intent.
fn entity(id: &str, x: f64, on_click: bool, tt: f64) -> Fact {
    let mut v = json!({ "x": x, "y": 0.0, "z": 0.0 });
    if on_click {
        v["on_click"] = json!({ "action": "move_right" });
    }
    Fact {
        id: format!("{}:{}", id, tt),
        store: WORLD_STORE.to_string(),
        key: id.to_string(),
        value: v,
        value_hash: String::new(),
        causation: None,
        transaction_time: tt,
        valid_time: None,
        schema_version: 1,
        producer: None,
        derivation: None,
    }
}

/// Domain reducer: `move_right` bumps the target entity's x by 1 (keeps everything else).
fn move_right_reducer() -> IntentReducer {
    Box::new(|intent, world| {
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

fn click(x: i64, y: i64) -> InputEvent {
    InputEvent { kind: "click".to_string(), x, y, payload: json!(null) }
}

fn source(b: &Arc<dyn TBackend>) -> TBackendFrameSource {
    TBackendFrameSource::world_store(b.clone())
}

// 1: a frame has hit-testable nodes; hit → declared intent; miss → none
#[test]
fn hit_test_and_derive_intent() {
    rt().block_on(async {
        let b: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        b.write_fact(entity("e1", 0.0, true, 1.0)).await.unwrap(); // at screen (200,200)
        let frame = project_frame(&source(&b), &Camera::default(), 0, None).await.unwrap();

        assert_eq!(hit_test(&frame, 200, 200).map(|n| n.id.as_str()), Some("e1"));
        assert!(hit_test(&frame, 50, 50).is_none()); // miss
        let intent = derive_intent(&frame, &click(200, 200)).unwrap();
        assert_eq!(intent.action, "move_right");
        assert_eq!(intent.target.as_deref(), Some("e1"));
    });
}

// 2: the intent flows through an EFFECT (a new state fact), never mutating the frame
#[test]
fn intent_via_effect_not_frame_mutation() {
    rt().block_on(async {
        let b: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        b.write_fact(entity("e1", 0.0, true, 1.0)).await.unwrap();
        let sink = TBackendIntentSink::new(b.clone(), move_right_reducer());
        let fsink = TBackendFrameSink { backend: b.clone(), now: 999.0 };

        let res = input_step(&source(&b), &sink, &fsink, &Camera::default(), &click(200, 200), 0, 10.0).await.unwrap();

        // frame was RE-PROJECTED from new state, not patched: e1 moved 0→1 ⇒ sx 200→250
        assert_eq!(res.frame_before.nodes[0].sx, 200);
        assert_eq!(res.frame_after.nodes[0].sx, 250);
        assert_ne!(res.frame_before.render_digest(), res.frame_after.render_digest());
        // the state change is a real new __world__ fact
        let world = source(&b).world().await.unwrap();
        assert_eq!(world.iter().find(|(id, _)| id == "e1").unwrap().1["x"], json!(1.0));
    });
}

// 3: lineage chains input_receipt → effect_receipt → frame_receipt
#[test]
fn lineage_chain() {
    rt().block_on(async {
        let b: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        b.write_fact(entity("e1", 0.0, true, 1.0)).await.unwrap();
        let sink = TBackendIntentSink::new(b.clone(), move_right_reducer());
        let fsink = TBackendFrameSink { backend: b.clone(), now: 999.0 };
        input_step(&source(&b), &sink, &fsink, &Camera::default(), &click(200, 200), 0, 10.0).await.unwrap();

        let inp = b.read_as_of(INPUT_STORE, "input:0", f64::MAX).await.unwrap().unwrap();
        let eff = b.read_as_of(EFFECT_STORE, "effect:0", f64::MAX).await.unwrap().unwrap();
        let frm = b.read_as_of("__frames__", "frame:1", f64::MAX).await.unwrap().unwrap();
        assert_eq!(inp.value["kind"], json!("click"));
        assert_eq!(eff.causation.as_deref(), Some("input:0")); // effect ← input
        assert_eq!(frm.value["source_receipt_id"], json!("effect:0")); // frame ← effect
        assert_eq!(frm.causation.as_deref(), Some("effect:0"));
    });
}

// 4: a click that hits nothing produces no intent, no effect, no state change
#[test]
fn no_hit_no_effect() {
    rt().block_on(async {
        let b: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        b.write_fact(entity("e1", 0.0, true, 1.0)).await.unwrap();
        let sink = TBackendIntentSink::new(b.clone(), move_right_reducer());
        let fsink = TBackendFrameSink { backend: b.clone(), now: 999.0 };

        let res = input_step(&source(&b), &sink, &fsink, &Camera::default(), &click(50, 50), 0, 10.0).await.unwrap();
        assert!(res.intent.is_none());
        assert!(res.effect_receipt_id.is_none());
        assert_eq!(res.frame_before.render_digest(), res.frame_after.render_digest()); // no state change
        assert!(b.read_as_of(EFFECT_STORE, "effect:0", f64::MAX).await.unwrap().is_none());
    });
}

// 5: deterministic replay — same start + same input log → same frame digests
#[test]
fn deterministic_replay_input_log() {
    rt().block_on(async {
        // a fixed input log following the entity as it moves right (screen 200→250→300)
        let log = [click(200, 200), click(250, 200), click(300, 200)];

        let run = || async {
            let b: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
            b.write_fact(entity("e1", 0.0, true, 1.0)).await.unwrap();
            let sink = TBackendIntentSink::new(b.clone(), move_right_reducer());
            let fsink = TBackendFrameSink { backend: b.clone(), now: 999.0 };
            let mut digs = vec![];
            for (i, ev) in log.iter().enumerate() {
                let res = input_step(&source(&b), &sink, &fsink, &Camera::default(), ev, i as u64, 10.0 + i as f64).await.unwrap();
                digs.push(res.frame_after.render_digest());
            }
            digs
        };

        let a = run().await;
        let c = run().await;
        assert_eq!(a, c);
        assert_eq!(a.len(), 3);
        // and it actually progressed (each frame distinct as the entity moved)
        assert_ne!(a[0], a[1]);
        assert_ne!(a[1], a[2]);
    });
}
