//! Synchronous in-memory frame runtime (LAB-FRAME-WASM-LIVE-STEP-P5). The SAME input loop
//! (`derive_intent` + reducer + re-project) as P3/P4, but driven SYNCHRONOUSLY — no async, no
//! reactor, no `block_on`. This is what makes the runtime cleanly compilable to (and callable
//! from) WASM: a browser holds one `FrameRuntime`, calls `render_svg` / `click` / `lineage_json`,
//! and the intent/move/projection all happen HERE, in Rust. The JS host computes no intent.
//!
//! Machine-free: depends only on the core projection + the pure hit-test/reducer. The async ports
//! (`FrameSource`/`IntentSink`) are for the machine adapter; this runtime bypasses them by holding
//! the world directly and using `project_snapshot` (the sync core of `project_frame`).

use crate::host::Viewport;
use crate::{
    derive_intent, Camera, CameraProjector, Frame, InputEvent, Intent, IntentReducer, Projector,
    RenderHost, SvgRenderHost,
};
use serde_json::{json, Value};

/// A synchronous interface runtime: world + reducer + a swappable `Projector` + viewport + a
/// swappable `RenderHost`, stepped by `click` (pointer) or `dispatch` (a system/tick event). Both
/// the projection (perspective points vs. orthographic GUI boxes) and the render host (SVG points /
/// 3D wireframe / GUI rects) are pluggable, so the SAME runtime drives a 2D point UI, a 3D sim, and
/// a GUI layout.
pub struct FrameRuntime {
    world: Vec<(String, Value)>,
    reducer: IntentReducer,
    projector: Box<dyn Projector>,
    viewport: Viewport,
    render_host: Box<dyn RenderHost>,
    step: u64,
    last_input: Option<String>,
    last_effect: Option<String>,
}

impl FrameRuntime {
    /// Construct with the default perspective `CameraProjector` (back-compat for point domains).
    pub fn new(
        entities: Vec<(String, Value)>,
        reducer: IntentReducer,
        camera: Camera,
        viewport: Viewport,
        render_host: Box<dyn RenderHost>,
    ) -> Self {
        Self::with_projector(entities, reducer, Box::new(CameraProjector::new(camera)), viewport, render_host)
    }

    /// Construct with an explicit projection strategy (e.g. a GUI orthographic box layout).
    pub fn with_projector(
        entities: Vec<(String, Value)>,
        reducer: IntentReducer,
        projector: Box<dyn Projector>,
        viewport: Viewport,
        render_host: Box<dyn RenderHost>,
    ) -> Self {
        Self { world: entities, reducer, projector, viewport, render_host, step: 0, last_input: None, last_effect: None }
    }

    /// The demo world from `examples/render_demo`: a clickable entity (`e1`) between two static
    /// posts; `move_right` nudges the clicked entity +1 in world-x. Used by the WASM viewer + tests.
    pub fn demo() -> Self {
        let world = vec![
            ("post_l".to_string(), json!({"x": -1.5, "y": 0.0, "z": 0.0})),
            ("post_r".to_string(), json!({"x":  1.5, "y": 0.0, "z": 0.0})),
            ("e1".to_string(), json!({"x": -1.0, "y": 0.0, "z": 0.0, "on_click": {"action": "move_right"}})),
        ];
        Self::new(
            world,
            demo_reducer(),
            Camera::default(),
            Viewport { css_w: 800.0, css_h: 800.0, frame_w: 400, frame_h: 400 },
            Box::new(SvgRenderHost { width: 400, height: 400 }),
        )
    }

    /// Project the current world → the current `Frame` (sync; `source_receipt_id` = the last effect).
    fn current_frame(&self) -> Frame {
        self.projector.project(&self.world, self.step, self.last_effect.clone())
    }

    pub fn render_svg(&self) -> String {
        self.render_host.render(&self.current_frame())
    }

    /// The current projected `Frame` (nodes + digests + lineage) — for a console/IDE that inspects
    /// or diffs the frame history. Read-only; does not advance the runtime.
    pub fn frame(&self) -> Frame {
        self.current_frame()
    }

    pub fn render_digest(&self) -> String {
        self.current_frame().render_digest()
    }

    pub fn frame_index(&self) -> u64 {
        self.step
    }

    /// Lineage of the current state: `input → effect → frame` (debuggable, like the host frame).
    pub fn lineage_json(&self) -> String {
        json!({
            "input_receipt_id": self.last_input,
            "effect_receipt_id": self.last_effect,
            "frame_index": self.step,
        })
        .to_string()
    }

    /// Forward a real (CSS-pixel) pointer click: map → frame coords, hit-test the CURRENT frame,
    /// and (on a hit with a declared intent) apply it as a STATE change via the reducer, then
    /// advance. Returns `true` iff an effect happened. The input NEVER mutates the frame; the next
    /// `render_svg`/`current_frame` is RE-PROJECTED from the new world. Deterministic (ids from the
    /// step index). This is exactly the P3 loop, run synchronously.
    pub fn click(&mut self, css_x: f64, css_y: f64) -> bool {
        let (fx, fy) = self.viewport.pointer_to_frame(css_x, css_y); // real pointer → frame coords
        let frame = self.current_frame();
        let input = InputEvent { kind: "click".to_string(), x: fx, y: fy, payload: json!(null) };
        self.last_input = Some(format!("input:{}", self.step));
        match derive_intent(&frame, &input) {
            Some(intent) => {
                let deltas = (self.reducer)(&intent, &self.world);
                for (id, val) in deltas {
                    if let Some(slot) = self.world.iter_mut().find(|(k, _)| *k == id) {
                        slot.1 = val;
                    } else {
                        self.world.push((id, val));
                    }
                }
                self.last_effect = Some(format!("effect:{}", self.step));
                self.step += 1;
                true
            }
            None => {
                self.last_effect = None; // a miss is recorded as an input with no effect
                false
            }
        }
    }

    /// Dispatch a SYSTEM event (not a pointer): a 3D world tick, an animation step, etc. Equivalent
    /// to `send(action, Null)`.
    pub fn dispatch(&mut self, action: &str) -> bool {
        self.send(action, json!(null))
    }

    /// Send a SYSTEM intent carrying `params` (no hit-test): e.g. a keystroke routed to a focused
    /// field (`send("type", {"char":"a"})`). Built as `Intent { action, target: None, params }` and
    /// applied through the reducer with the same "intent → effect → next frame" discipline + lineage
    /// (`<action>:N → effect:N → frame:N+1`). The host routes the event; the reducer owns the state.
    /// Returns `true` iff state changed.
    pub fn send(&mut self, action: &str, params: Value) -> bool {
        let intent = Intent { action: action.to_string(), target: None, params };
        self.last_input = Some(format!("{}:{}", action, self.step));
        let deltas = (self.reducer)(&intent, &self.world);
        if deltas.is_empty() {
            self.last_effect = None;
            return false;
        }
        for (id, val) in deltas {
            if let Some(slot) = self.world.iter_mut().find(|(k, _)| *k == id) {
                slot.1 = val;
            } else {
                self.world.push((id, val));
            }
        }
        self.last_effect = Some(format!("effect:{}", self.step));
        self.step += 1;
        true
    }
}

/// The demo domain reducer: `move_right` bumps the target entity +1 in world-x (everything else
/// untouched). Pure `(intent, world) -> deltas` — the same shape a game tick / GUI reducer uses.
pub fn demo_reducer() -> IntentReducer {
    Box::new(|intent, world| {
        if intent.action != "move_right" {
            return vec![];
        }
        let Some(target) = &intent.target else { return vec![] };
        let Some((_, cur)) = world.iter().find(|(k, _)| k == target) else { return vec![] };
        let x = cur.get("x").and_then(|v| v.as_f64()).unwrap_or(0.0) + 1.0;
        let mut next = cur.clone();
        next["x"] = json!(x);
        vec![(target.clone(), next)]
    })
}
