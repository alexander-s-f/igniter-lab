//! LAB-FRAME-PROJECTION-EXTRACT-P2 — the same 6 FP-P1 checks, now in the extracted crate,
//! binding the projection PORTS (`FrameSource`/`FrameSink`/`RenderHost`) to the machine substrate
//! via the `machine` adapter. The machine knows nothing about Frame/Camera/render.

use igniter_frame::machine_source::{TBackendFrameSink, TBackendFrameSource, FRAMES_STORE, WORLD_STORE};
use igniter_frame::{project_frame, Camera, FrameSink, JsonRenderHost, RenderHost, SvgRenderHost};
use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::fact::Fact;
use igniter_machine::machine::IgniterMachine;
use serde_json::json;
use std::sync::Arc;

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap()
}

fn entity(id: &str, x: f64, y: f64, z: f64, tt: f64) -> Fact {
    Fact {
        id: format!("{}:{}", id, tt),
        store: WORLD_STORE.to_string(),
        key: id.to_string(),
        value: json!({ "x": x, "y": y, "z": z }),
        value_hash: String::new(),
        causation: None,
        transaction_time: tt,
        valid_time: None,
        schema_version: 1,
        producer: None,
        derivation: None,
    }
}

fn source(b: &Arc<dyn TBackend>) -> TBackendFrameSource {
    TBackendFrameSource::world_store(b.clone())
}

// 1: world state read from machine/TBackend facts → Frame with lineage + world_digest
#[test]
fn project_from_machine_facts() {
    rt().block_on(async {
        let m = IgniterMachine::new(None, "in_memory").unwrap();
        m.write_fact(entity("e1", 0.0, 0.0, 0.0, 1.0)).await.unwrap();
        m.write_fact(entity("e2", 1.0, 0.0, 0.0, 1.0)).await.unwrap();
        m.write_fact(entity("e3", -1.0, 0.5, 0.0, 1.0)).await.unwrap();

        let src = source(&m.storage);
        let frame = project_frame(&src, &Camera::default(), 0, Some("machine_receipt_abc".into())).await.unwrap();
        assert_eq!(frame.nodes.len(), 3);
        assert!(frame.world_digest.starts_with("sha256:"));
        assert_eq!(frame.source_receipt_id.as_deref(), Some("machine_receipt_abc"));
        let e1 = frame.nodes.iter().find(|n| n.id == "e1").unwrap();
        assert_eq!((e1.sx, e1.sy), (200, 200));
    });
}

// 2: deterministic — two independent replays → byte-identical frame digests
#[test]
fn deterministic_replay() {
    rt().block_on(async {
        let w: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        w.write_fact(entity("e1", 0.3, -0.2, 1.0, 1.0)).await.unwrap();
        w.write_fact(entity("e2", -0.5, 0.7, 0.5, 1.0)).await.unwrap();
        let a = project_frame(&source(&w), &Camera::default(), 0, None).await.unwrap();
        let b = project_frame(&source(&w), &Camera::default(), 0, None).await.unwrap();
        assert_eq!(a.render_digest(), b.render_digest());
        assert_eq!(a.world_digest, b.world_digest);
    });
}

// 3: changing a fact changes the frame digest predictably
#[test]
fn fact_change_changes_frame_predictably() {
    rt().block_on(async {
        let w: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        w.write_fact(entity("e1", 0.0, 0.0, 0.0, 1.0)).await.unwrap();
        let before = project_frame(&source(&w), &Camera::default(), 0, None).await.unwrap();
        w.write_fact(entity("e1", 1.0, 0.0, 0.0, 2.0)).await.unwrap();
        let after = project_frame(&source(&w), &Camera::default(), 1, None).await.unwrap();
        assert_ne!(before.render_digest(), after.render_digest());
        assert_eq!(before.nodes[0].sx, 200);
        assert_eq!(after.nodes[0].sx, 250); // 1 * (200/4) + 200
    });
}

// 4: render host swappable — same Frame → SVG or JSON, host-agnostic
#[test]
fn render_host_swappable() {
    rt().block_on(async {
        let w: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        w.write_fact(entity("e1", 0.0, 0.0, 0.0, 1.0)).await.unwrap();
        w.write_fact(entity("e2", 0.5, 0.0, 0.0, 1.0)).await.unwrap();
        let frame = project_frame(&source(&w), &Camera::default(), 0, None).await.unwrap();
        let svg = SvgRenderHost::default().render(&frame);
        let js = JsonRenderHost.render(&frame);
        assert!(svg.contains("<svg") && svg.matches("<circle").count() == 2);
        assert!(js.starts_with("[") && js.contains("\"id\":\"e1\""));
        assert_ne!(svg, js);
    });
}

// 5: a frame is itself a FACT → replayable, auditable bitemporal frame history (time-travel)
#[test]
fn frame_is_a_fact() {
    rt().block_on(async {
        let store: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        store.write_fact(entity("e1", 0.0, 0.0, 0.0, 1.0)).await.unwrap();
        let frame = project_frame(&source(&store), &Camera::default(), 7, Some("rcpt_42".into())).await.unwrap();

        let sink = TBackendFrameSink { backend: store.clone(), now: 100.0 };
        sink.record(&frame).await.unwrap();
        let back = store.read_as_of(FRAMES_STORE, "frame:7", f64::MAX).await.unwrap().unwrap();
        assert_eq!(back.value["frame_index"], json!(7));
        assert_eq!(back.value["world_digest"], json!(frame.world_digest));
        assert_eq!(back.value["render_digest"], json!(frame.render_digest()));
        assert_eq!(back.value["source_receipt_id"], json!("rcpt_42"));
        assert_eq!(back.causation.as_deref(), Some("rcpt_42"));
    });
}

// 6: fail-safe — empty world → empty, stable frame
#[test]
fn empty_world_is_stable() {
    rt().block_on(async {
        let w: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let a = project_frame(&source(&w), &Camera::default(), 0, None).await.unwrap();
        let b = project_frame(&source(&w), &Camera::default(), 0, None).await.unwrap();
        assert_eq!(a.nodes.len(), 0);
        assert_eq!(a.render_digest(), b.render_digest());
        assert!(SvgRenderHost::default().render(&a).contains("<svg"));
    });
}
