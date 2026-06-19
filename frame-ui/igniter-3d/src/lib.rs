//! igniter-3d — re-home of the deterministic 3D POC over igniter-frame
//! (LAB-FRAME-3D-POC-REHOME-P7).
//!
//! The 3D POC's standalone model is gone: here the 3D world IS igniter-frame world facts (one fact
//! per cube vertex, `{x,y,z}`); the world TICK is an `IntentReducer` dispatched through the SAME
//! `FrameRuntime` (`dispatch("tick")`); the PROJECTION is igniter-frame's `Camera` (already
//! perspective); and the RENDER is a `WireframeRenderHost` implementing igniter-frame's
//! `RenderHost` trait — the SAME render-host boundary the 2D point UI uses, now drawing a
//! projection-heavy wireframe. No GPU, no window, and (because it depends on `igniter_frame` with
//! `default-features = false`) NO `igniter-machine` in the core path.

use igniter_frame::host::Viewport;
use igniter_frame::runtime::FrameRuntime;
use igniter_frame::{Camera, Frame, IntentReducer, RenderHost};
use serde_json::{json, Value};
use std::collections::HashMap;

#[cfg(feature = "wasm")]
pub mod wasm;

/// The 8 cube vertices (sign pattern), ids `v0..v7`. Back face z=-1, front face z=+1.
pub const VERTS: [(&str, f64, f64, f64); 8] = [
    ("v0", -1.0, -1.0, -1.0),
    ("v1", 1.0, -1.0, -1.0),
    ("v2", 1.0, 1.0, -1.0),
    ("v3", -1.0, 1.0, -1.0),
    ("v4", -1.0, -1.0, 1.0),
    ("v5", 1.0, -1.0, 1.0),
    ("v6", 1.0, 1.0, 1.0),
    ("v7", -1.0, 1.0, 1.0),
];

/// The 12 cube edges as vertex-id pairs (back face, front face, connectors).
pub const EDGES: [(&str, &str); 12] = [
    ("v0", "v1"),
    ("v1", "v2"),
    ("v2", "v3"),
    ("v3", "v0"),
    ("v4", "v5"),
    ("v5", "v6"),
    ("v6", "v7"),
    ("v7", "v4"),
    ("v0", "v4"),
    ("v1", "v5"),
    ("v2", "v6"),
    ("v3", "v7"),
];

const ANGLE_STEP: f64 = 0.12; // radians per tick
const QUANT: f64 = 1_000_000.0; // round vertex coords → digest-stable across replay

fn round_q(v: f64) -> f64 {
    (v * QUANT).round() / QUANT
}

/// The initial cube world as igniter-frame facts.
pub fn cube_world() -> Vec<(String, Value)> {
    VERTS
        .iter()
        .map(|(id, x, y, z)| (id.to_string(), json!({ "x": x, "y": y, "z": z })))
        .collect()
}

/// The tick reducer: rotate EVERY vertex around the Y axis by `ANGLE_STEP` (deterministic,
/// quantized). Pure `(intent, world) -> deltas` — the 3D world step expressed as an igniter-frame
/// reducer, exactly like a 2D GUI reducer.
pub fn tick_reducer() -> IntentReducer {
    Box::new(|intent, world| {
        if intent.action != "tick" {
            return vec![];
        }
        let (s, c) = (ANGLE_STEP.sin(), ANGLE_STEP.cos());
        world
            .iter()
            .map(|(id, val)| {
                let x = val.get("x").and_then(|v| v.as_f64()).unwrap_or(0.0);
                let y = val.get("y").and_then(|v| v.as_f64()).unwrap_or(0.0);
                let z = val.get("z").and_then(|v| v.as_f64()).unwrap_or(0.0);
                let nx = round_q(x * c - z * s);
                let nz = round_q(x * s + z * c);
                (id.clone(), json!({ "x": nx, "y": round_q(y), "z": nz }))
            })
            .collect()
    })
}

/// A wireframe render host — connects the projected vertices by the 12 cube edges. Implements
/// igniter-frame's `RenderHost` trait, so it is a drop-in swap for `SvgRenderHost` over the SAME
/// boundary (projection-heavy 3D vs 2D points, one interface).
pub struct WireframeRenderHost {
    pub width: i64,
    pub height: i64,
}

impl RenderHost for WireframeRenderHost {
    fn render(&self, frame: &Frame) -> String {
        let pos: HashMap<&str, (i64, i64)> = frame
            .nodes
            .iter()
            .map(|n| (n.id.as_str(), (n.sx, n.sy)))
            .collect();
        let mut body = String::new();
        for (a, b) in EDGES.iter() {
            if let (Some(&(ax, ay)), Some(&(bx, by))) = (pos.get(a), pos.get(b)) {
                body.push_str(&format!(
                    "  <line x1=\"{}\" y1=\"{}\" x2=\"{}\" y2=\"{}\" stroke=\"#39d353\" stroke-width=\"1.5\"/>\n",
                    ax, ay, bx, by
                ));
            }
        }
        for n in &frame.nodes {
            body.push_str(&format!(
                "  <circle cx=\"{}\" cy=\"{}\" r=\"2.5\" fill=\"#39d353\"/>\n",
                n.sx, n.sy
            ));
        }
        format!(
            "<svg viewBox=\"0 0 {} {}\" xmlns=\"http://www.w3.org/2000/svg\">\n  <rect width=\"{}\" height=\"{}\" fill=\"#0d1117\"/>\n{}</svg>\n",
            self.width, self.height, self.width, self.height, body
        )
    }
}

/// The 3D runtime: a thin wrapper over igniter-frame's `FrameRuntime`, constructed with the cube
/// world + tick reducer + a perspective camera + the wireframe host. `tick()` advances the
/// simulation through the SAME runtime/loop the 2D UI uses; rendering/digest/lineage come from
/// igniter-frame unchanged.
pub struct Cube3dRuntime {
    inner: FrameRuntime,
}

impl Cube3dRuntime {
    pub fn new() -> Self {
        let camera = Camera {
            width: 400,
            height: 400,
            scale: 150.0,
            depth: 4.0,
        };
        let viewport = Viewport {
            css_w: 800.0,
            css_h: 800.0,
            frame_w: 400,
            frame_h: 400,
        };
        let inner = FrameRuntime::new(
            cube_world(),
            tick_reducer(),
            camera,
            viewport,
            Box::new(WireframeRenderHost {
                width: 400,
                height: 400,
            }),
        );
        Self { inner }
    }

    /// Advance the world one tick (rotate). Returns `true` (the tick always changes state).
    pub fn tick(&mut self) -> bool {
        self.inner.dispatch("tick")
    }

    pub fn render_svg(&self) -> String {
        self.inner.render_svg()
    }

    pub fn render_digest(&self) -> String {
        self.inner.render_digest()
    }

    pub fn frame_index(&self) -> u64 {
        self.inner.frame_index()
    }

    pub fn lineage_json(&self) -> String {
        self.inner.lineage_json()
    }

    pub fn reset(&mut self) {
        *self = Self::new();
    }
}

impl Default for Cube3dRuntime {
    fn default() -> Self {
        Self::new()
    }
}
