//! Renderer host (LAB-FRAME-RENDERER-HOST-P4). The host is a THIN layer: render a `Frame`,
//! map a real pointer event to frame coordinates, and forward it to `input_step`. It does NOT
//! compute intent — the proven P3 loop (in Rust) decides; the host only renders + forwards.
//!
//! This module is machine-free (it depends only on the core ports), so the whole loop runs
//! with zero kernel — a browser/WASM host calls `drive` (or `pointer_to_frame` + `input_step`)
//! directly. `MemWorld` is an in-memory `FrameSource + FrameSink + IntentSink` for exactly that.

use crate::{
    input_step, project_frame, Camera, Frame, FrameError, FrameSink, FrameSource, InputEvent,
    Intent, IntentReducer, IntentSink, RenderHost, SvgRenderHost,
};
use async_trait::async_trait;
use serde_json::{json, Value};
use std::sync::Mutex;

/// Maps real (CSS-pixel) pointer coordinates onto frame coordinates. A browser host fills this in
/// from the rendered element's size; the mapping is pure + deterministic.
pub struct Viewport {
    pub css_w: f64,
    pub css_h: f64,
    pub frame_w: i64,
    pub frame_h: i64,
}

impl Viewport {
    pub fn pointer_to_frame(&self, css_x: f64, css_y: f64) -> (i64, i64) {
        let fx = (css_x / self.css_w * self.frame_w as f64).round() as i64;
        let fy = (css_y / self.css_h * self.frame_h as f64).round() as i64;
        (fx, fy)
    }
}

/// An in-memory world implementing all three ports — lets the input loop run with no machine
/// (browser/WASM-ready). State + recorded frames/inputs live behind a `Mutex`.
pub struct MemWorld {
    state: Mutex<Vec<(String, Value)>>,
    frames: Mutex<Vec<Frame>>,
    inputs: Mutex<Vec<(String, InputEvent)>>,
    reducer: IntentReducer,
}

impl MemWorld {
    pub fn new(entities: Vec<(String, Value)>, reducer: IntentReducer) -> Self {
        Self {
            state: Mutex::new(entities),
            frames: Mutex::new(Vec::new()),
            inputs: Mutex::new(Vec::new()),
            reducer,
        }
    }
    pub fn recorded_frames(&self) -> usize {
        self.frames.lock().unwrap().len()
    }
    pub fn recorded_inputs(&self) -> usize {
        self.inputs.lock().unwrap().len()
    }
}

#[async_trait]
impl FrameSource for MemWorld {
    async fn world(&self) -> Result<Vec<(String, Value)>, FrameError> {
        Ok(self.state.lock().unwrap().clone())
    }
}

#[async_trait]
impl FrameSink for MemWorld {
    async fn record(&self, frame: &Frame) -> Result<(), FrameError> {
        self.frames.lock().unwrap().push(frame.clone());
        Ok(())
    }
}

#[async_trait]
impl IntentSink for MemWorld {
    async fn record_input(
        &self,
        input: &InputEvent,
        input_receipt_id: &str,
        _now: f64,
    ) -> Result<(), FrameError> {
        self.inputs
            .lock()
            .unwrap()
            .push((input_receipt_id.to_string(), input.clone()));
        Ok(())
    }
    async fn apply(
        &self,
        intent: &Intent,
        _input_receipt_id: &str,
        _effect_receipt_id: &str,
        _now: f64,
    ) -> Result<(), FrameError> {
        let mut state = self.state.lock().unwrap();
        let deltas = (self.reducer)(intent, &state);
        for (id, val) in deltas {
            if let Some(slot) = state.iter_mut().find(|(k, _)| *k == id) {
                slot.1 = val;
            } else {
                state.push((id, val));
            }
        }
        Ok(())
    }
}

/// One rendered host frame: the SVG artifact + digests + lineage ids (debuggable).
#[derive(Clone, Debug)]
pub struct HostFrame {
    pub frame_index: u64,
    pub svg: String,
    pub world_digest: String,
    pub render_digest: String,
    pub input_receipt_id: Option<String>,
    pub effect_receipt_id: Option<String>,
}

impl HostFrame {
    fn of(
        frame: &Frame,
        svg_host: &SvgRenderHost,
        input: Option<String>,
        effect: Option<String>,
    ) -> Self {
        Self {
            frame_index: frame.frame_index,
            svg: svg_host.render(frame),
            world_digest: frame.world_digest.clone(),
            render_digest: frame.render_digest(),
            input_receipt_id: input,
            effect_receipt_id: effect,
        }
    }

    pub fn to_json(&self) -> Value {
        json!({
            "frame_index": self.frame_index,
            "svg": self.svg,
            "world_digest": self.world_digest,
            "render_digest": self.render_digest,
            "input_receipt_id": self.input_receipt_id,
            "effect_receipt_id": self.effect_receipt_id,
        })
    }
}

/// Drive the host over a captured pointer-event log (CSS coords). Each event is mapped to frame
/// coords and FORWARDED to `input_step` (the host computes no intent); the resulting frame is
/// rendered. Returns `[initial_frame, frame_after_event_0, ...]`. Deterministic: same world +
/// same pointer log → same host frames.
pub async fn drive(
    world: &MemWorld,
    camera: &Camera,
    viewport: &Viewport,
    pointer_log: &[(f64, f64)],
) -> Result<Vec<HostFrame>, FrameError> {
    let svg_host = SvgRenderHost {
        width: viewport.frame_w,
        height: viewport.frame_h,
    };
    let mut out = Vec::new();

    let f0 = project_frame(world, camera, 0, None).await?;
    out.push(HostFrame::of(&f0, &svg_host, None, None));

    for (i, (cx, cy)) in pointer_log.iter().enumerate() {
        let (fx, fy) = viewport.pointer_to_frame(*cx, *cy); // real pointer → frame coords
        let input = InputEvent {
            kind: "click".to_string(),
            x: fx,
            y: fy,
            payload: json!(null),
        };
        let res = input_step(
            world,
            world,
            world,
            camera,
            &input,
            i as u64,
            10.0 + i as f64,
        )
        .await?;
        out.push(HostFrame::of(
            &res.frame_after,
            &svg_host,
            Some(res.input_receipt_id),
            res.effect_receipt_id,
        ));
    }
    Ok(out)
}
