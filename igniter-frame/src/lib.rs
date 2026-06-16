//! igniter-frame — a derived projection runtime over the igniter-machine substrate.
//!
//! (LAB-FRAME-PROJECTION-EXTRACT-P2.) The machine is the **state kernel** (facts, receipts,
//! capsules, capability IO, recovery). Projecting that state into an observable representation is
//! a **consumer** of the machine — a leaf/runtime layer, not the kernel. So `Frame` / `Camera` /
//! `RenderHost` / world projection live HERE, not in the machine.
//!
//! ```text
//! igniter-machine        = state kernel (TBackend facts / receipts / capsules / capability IO)
//! igniter-frame (this)   = projection runtime: ports + Frame + Camera + render-host abstraction
//! igniter-gui-engine     = UI/layout/hit-test over igniter-frame   (future)
//! igniter-3d-poc / -sim  = world/tick/camera/renderer              (future)
//! igniter-ide            = concrete app consuming those            (future)
//! ```
//!
//! The CORE is machine-agnostic — it depends only on three **ports** and builds with
//! `--no-default-features` (zero igniter-machine dependency):
//!
//! - `FrameSource`  — read the world state to project   (a `ProjectionSource`).
//! - `FrameSink`    — record a frame receipt             (`ReceiptLineage`).
//! - `RenderHost`   — turn a frame into an artifact      (swappable edge: SVG/JSON now, GPU later).
//!
//! The `machine` feature adds a thin adapter binding the ports to `igniter_machine::TBackend`.

use async_trait::async_trait;
use serde_json::{json, Value};

#[cfg(feature = "machine")]
pub mod machine_source;

/// Errors from a projection source/sink (kept independent of the machine's `EngineError`).
#[derive(Debug, Clone)]
pub enum FrameError {
    Source(String),
}

impl std::fmt::Display for FrameError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            FrameError::Source(m) => write!(f, "frame source error: {m}"),
        }
    }
}

/// PORT: where the world state to project comes from. The machine adapter reads facts; another
/// source could be a capsule snapshot, a trace, or an in-memory world — all the same to the core.
#[async_trait]
pub trait FrameSource {
    /// The world entities as `(id, value)` where `value` carries `{ "x", "y", "z", ... }`.
    async fn world(&self) -> Result<Vec<(String, Value)>, FrameError>;
}

/// PORT: record a projected frame (lineage). The machine adapter writes a `__frames__` fact so
/// the frame history is bitemporal/replayable (a time-travel frame viewer substrate).
#[async_trait]
pub trait FrameSink {
    async fn record(&self, frame: &Frame) -> Result<(), FrameError>;
}

/// A projected entity: world position + deterministic integer screen position.
#[derive(Clone, Debug, PartialEq)]
pub struct ProjectedNode {
    pub id: String,
    pub x: f64,
    pub y: f64,
    pub z: f64,
    pub sx: i64,
    pub sy: i64,
}

/// A deterministic projection of a world snapshot — render-agnostic data + lineage.
#[derive(Clone, Debug)]
pub struct Frame {
    pub frame_index: u64,
    pub world_digest: String,
    pub source_receipt_id: Option<String>,
    pub nodes: Vec<ProjectedNode>,
}

impl Frame {
    /// Digest of the PROJECTED frame (id + screen coords) — render-host-agnostic. Two independent
    /// projections of the same world yield byte-identical render digests.
    pub fn render_digest(&self) -> String {
        let proj: Vec<Value> = self.nodes.iter().map(|n| json!([n.id, n.sx, n.sy])).collect();
        digest(&proj)
    }
}

/// Deterministic camera/projection (fixed perspective; integer screen rounding).
#[derive(Clone, Copy)]
pub struct Camera {
    pub width: i64,
    pub height: i64,
    pub scale: f64,
    pub depth: f64,
}

impl Default for Camera {
    fn default() -> Self {
        Self { width: 400, height: 400, scale: 200.0, depth: 4.0 }
    }
}

impl Camera {
    fn project(&self, x: f64, y: f64, z: f64) -> (i64, i64) {
        let f = self.scale / (z + self.depth);
        let sx = (x * f + self.width as f64 / 2.0).round() as i64;
        let sy = (-y * f + self.height as f64 / 2.0).round() as i64; // flip Y for screen space
        (sx, sy)
    }
}

fn digest<T: serde::Serialize>(v: &T) -> String {
    format!("sha256:{}", blake3::hash(serde_json::to_string(v).unwrap_or_default().as_bytes()).to_hex())
}

/// Project the world from a `FrameSource` into a deterministic `Frame`. Pure, headless, replayable.
pub async fn project_frame(
    source: &dyn FrameSource,
    camera: &Camera,
    frame_index: u64,
    source_receipt_id: Option<String>,
) -> Result<Frame, FrameError> {
    let mut snap = source.world().await?;
    snap.sort_by(|a, b| a.0.cmp(&b.0)); // deterministic order by id
    let nodes = snap
        .iter()
        .map(|(id, val)| {
            let x = val.get("x").and_then(|v| v.as_f64()).unwrap_or(0.0);
            let y = val.get("y").and_then(|v| v.as_f64()).unwrap_or(0.0);
            let z = val.get("z").and_then(|v| v.as_f64()).unwrap_or(0.0);
            let (sx, sy) = camera.project(x, y, z);
            ProjectedNode { id: id.clone(), x, y, z, sx, sy }
        })
        .collect();
    Ok(Frame {
        frame_index,
        world_digest: digest(&snap),
        source_receipt_id,
        nodes,
    })
}

/// PORT: a swappable render host — turns a render-agnostic `Frame` into an artifact. SVG/JSON
/// now; a canvas/wgpu host is a later drop-in (the same leaf-change property as a capability executor).
pub trait RenderHost {
    fn render(&self, frame: &Frame) -> String;
}

/// SVG render host — each projected node as a point (headless vector artifact, no GPU).
pub struct SvgRenderHost {
    pub width: i64,
    pub height: i64,
}

impl Default for SvgRenderHost {
    fn default() -> Self {
        Self { width: 400, height: 400 }
    }
}

impl RenderHost for SvgRenderHost {
    fn render(&self, frame: &Frame) -> String {
        let mut body = String::new();
        for n in &frame.nodes {
            body.push_str(&format!("  <circle cx=\"{}\" cy=\"{}\" r=\"4\" fill=\"#39d353\"/>\n", n.sx, n.sy));
        }
        format!(
            "<svg viewBox=\"0 0 {} {}\" xmlns=\"http://www.w3.org/2000/svg\">\n  <rect width=\"{}\" height=\"{}\" fill=\"#0d1117\"/>\n{}</svg>\n",
            self.width, self.height, self.width, self.height, body
        )
    }
}

/// A trivial second host — proves the frame is host-agnostic (render-host is a swappable edge).
pub struct JsonRenderHost;

impl RenderHost for JsonRenderHost {
    fn render(&self, frame: &Frame) -> String {
        let pts: Vec<Value> = frame.nodes.iter().map(|n| json!({ "id": n.id, "sx": n.sx, "sy": n.sy })).collect();
        serde_json::to_string(&pts).unwrap_or_default()
    }
}
