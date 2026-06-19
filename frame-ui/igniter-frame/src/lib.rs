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

pub mod host;
pub mod runtime;

#[cfg(feature = "wasm")]
pub mod wasm;

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

/// A projected entity: world position + deterministic integer screen position. `intent` is the
/// node's declared interaction (from the world fact's `on_click`), if any — the hit-testable hook.
///
/// `sw`/`sh` are an OPTIONAL screen box size: when present the node is a rectangle (a GUI widget,
/// with `sx`/`sy` its top-left) and `hit_test` uses point-in-rect; when absent the node is a point
/// (a 2D/3D entity centred at `sx`/`sy`) and `hit_test` uses a radius. `data` carries arbitrary
/// domain render payload (e.g. a GUI label / toggle state) for the render host; it is `Null` for
/// point domains, so their render digests are unchanged.
#[derive(Clone, Debug, PartialEq)]
pub struct ProjectedNode {
    pub id: String,
    pub x: f64,
    pub y: f64,
    pub z: f64,
    pub sx: i64,
    pub sy: i64,
    pub intent: Option<Value>,
    pub sw: Option<i64>,
    pub sh: Option<i64>,
    pub data: Value,
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
        let proj: Vec<Value> = self
            .nodes
            .iter()
            .map(|n| match (n.sw, n.sh) {
                // box widgets digest position + size + render payload; points stay [id,sx,sy]
                // (so 2D/3D render digests are unchanged).
                (Some(w), Some(h)) => json!([n.id, n.sx, n.sy, w, h, n.data]),
                _ => json!([n.id, n.sx, n.sy]),
            })
            .collect();
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
        Self {
            width: 400,
            height: 400,
            scale: 200.0,
            depth: 4.0,
        }
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
    format!(
        "sha256:{}",
        blake3::hash(serde_json::to_string(v).unwrap_or_default().as_bytes()).to_hex()
    )
}

/// Project a world SNAPSHOT into a deterministic `Frame` — the pure, SYNCHRONOUS core (no IO).
/// Used directly by an in-memory runtime (e.g. WASM, where async + a reactor are undesirable).
pub fn project_snapshot(
    mut snap: Vec<(String, Value)>,
    camera: &Camera,
    frame_index: u64,
    source_receipt_id: Option<String>,
) -> Frame {
    snap.sort_by(|a, b| a.0.cmp(&b.0)); // deterministic order by id
    let nodes = snap
        .iter()
        .map(|(id, val)| {
            let x = val.get("x").and_then(|v| v.as_f64()).unwrap_or(0.0);
            let y = val.get("y").and_then(|v| v.as_f64()).unwrap_or(0.0);
            let z = val.get("z").and_then(|v| v.as_f64()).unwrap_or(0.0);
            let (sx, sy) = camera.project(x, y, z);
            ProjectedNode {
                id: id.clone(),
                x,
                y,
                z,
                sx,
                sy,
                intent: val.get("on_click").cloned(),
                sw: None,
                sh: None,
                data: Value::Null,
            }
        })
        .collect();
    Frame {
        frame_index,
        world_digest: digest(&snap),
        source_receipt_id,
        nodes,
    }
}

/// PORT: a projection strategy — world facts → a deterministic `Frame`. `CameraProjector`
/// (perspective points) is the default; a GUI supplies an orthographic box-layout projector. The
/// runtime is projection-agnostic: the SAME `FrameRuntime` drives a 3D camera scene and a GUI
/// layout by swapping the projector.
pub trait Projector {
    fn project(
        &self,
        world: &[(String, Value)],
        frame_index: u64,
        source_receipt_id: Option<String>,
    ) -> Frame;
}

/// The default projector: perspective points via a `Camera` (wraps `project_snapshot`).
pub struct CameraProjector {
    pub camera: Camera,
}

impl CameraProjector {
    pub fn new(camera: Camera) -> Self {
        Self { camera }
    }
}

impl Projector for CameraProjector {
    fn project(
        &self,
        world: &[(String, Value)],
        frame_index: u64,
        source_receipt_id: Option<String>,
    ) -> Frame {
        project_snapshot(world.to_vec(), &self.camera, frame_index, source_receipt_id)
    }
}

/// Project the world from a `FrameSource` into a deterministic `Frame`. Pure, headless, replayable.
pub async fn project_frame(
    source: &dyn FrameSource,
    camera: &Camera,
    frame_index: u64,
    source_receipt_id: Option<String>,
) -> Result<Frame, FrameError> {
    let snap = source.world().await?;
    Ok(project_snapshot(
        snap,
        camera,
        frame_index,
        source_receipt_id,
    ))
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
        Self {
            width: 400,
            height: 400,
        }
    }
}

impl RenderHost for SvgRenderHost {
    fn render(&self, frame: &Frame) -> String {
        let mut body = String::new();
        for n in &frame.nodes {
            body.push_str(&format!(
                "  <circle cx=\"{}\" cy=\"{}\" r=\"4\" fill=\"#39d353\"/>\n",
                n.sx, n.sy
            ));
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
        let pts: Vec<Value> = frame
            .nodes
            .iter()
            .map(|n| json!({ "id": n.id, "sx": n.sx, "sy": n.sy }))
            .collect();
        serde_json::to_string(&pts).unwrap_or_default()
    }
}

// ── Input loop: state → frame → input → intent → state (LAB-FRAME-INPUT-LOOP-P3) ──
//
// Closes the platform cycle. An input event is hit-tested against the CURRENT frame's nodes → an
// `Intent`. The intent is NOT applied to the frame — it goes through an `IntentSink` (a
// capability-IO-style effect) that changes STATE (writes a new fact). The NEXT frame is then
// re-projected from the new state. Lineage chains `input_receipt → effect_receipt → frame_receipt`;
// the loop is deterministic (ids from the step index, time from the caller), so the same state +
// the same input log replay to the same frames. No browser/GPU/window.

/// A raw input event in screen space (a pointer click for P3).
#[derive(Clone, Debug)]
pub struct InputEvent {
    pub kind: String,
    pub x: i64,
    pub y: i64,
    pub payload: Value,
}

/// A derived interaction intent — the semantic action a hit produced. Domain-agnostic.
#[derive(Clone, Debug, PartialEq)]
pub struct Intent {
    pub action: String,
    pub target: Option<String>,
    pub params: Value,
}

const HIT_RADIUS: i64 = 14;

/// Hit-test, deterministic (frame.nodes are id-sorted). Box widgets (those with `sw`/`sh`) are
/// tested by point-in-rect, and the SMALLEST-area containing box wins (innermost child over an
/// enclosing panel) — so nested composition (a panel background behind interactive children) routes
/// the click to the child. If no box contains the point, point nodes are tested by
/// nearest-within-`HIT_RADIUS`. Point-only scenes behave exactly as before. `None` on a miss.
pub fn hit_test(frame: &Frame, x: i64, y: i64) -> Option<&ProjectedNode> {
    // box widgets: innermost (smallest-area) containing rect wins, tie-broken by node order
    let mut best: Option<&ProjectedNode> = None;
    let mut best_area = i64::MAX;
    for n in &frame.nodes {
        if let (Some(w), Some(h)) = (n.sw, n.sh) {
            if x >= n.sx && x <= n.sx + w && y >= n.sy && y <= n.sy + h {
                let area = w.saturating_mul(h);
                if area < best_area {
                    best_area = area;
                    best = Some(n);
                }
            }
        }
    }
    if best.is_some() {
        return best;
    }
    // point entities: nearest within radius
    let r2 = HIT_RADIUS * HIT_RADIUS;
    frame
        .nodes
        .iter()
        .filter(|n| n.sw.is_none() && n.sh.is_none())
        .filter_map(|n| {
            let d2 = (n.sx - x) * (n.sx - x) + (n.sy - y) * (n.sy - y);
            if d2 <= r2 {
                Some((d2, n))
            } else {
                None
            }
        })
        .min_by_key(|(d2, _)| *d2)
        .map(|(_, n)| n)
}

/// Derive an `Intent` from an input + the current frame: hit-test → the hit node's declared
/// `on_click` intent (with `target` = the node id). `None` if the click misses or the node has no
/// declared interaction (non-interactive nodes are hit but produce no intent).
pub fn derive_intent(frame: &Frame, input: &InputEvent) -> Option<Intent> {
    let node = hit_test(frame, input.x, input.y)?;
    let decl = node.intent.as_ref()?;
    Some(Intent {
        action: decl
            .get("action")
            .and_then(|a| a.as_str())
            .unwrap_or("")
            .to_string(),
        target: Some(node.id.clone()),
        params: decl.clone(),
    })
}

/// A reducer: `(intent, current world) -> changed entity facts`. This is the DOMAIN logic (a game
/// tick / a GUI reducer); it is pure and lives outside the kernel.
pub type IntentReducer =
    Box<dyn Fn(&Intent, &[(String, Value)]) -> Vec<(String, Value)> + Send + Sync>;

/// PORT: apply an intent as a STATE effect (never a frame mutation). The machine adapter reduces
/// the intent → a new world fact through the substrate, and records receipts for lineage.
#[async_trait]
pub trait IntentSink {
    /// Record the raw input event (the lineage root).
    async fn record_input(
        &self,
        input: &InputEvent,
        input_receipt_id: &str,
        now: f64,
    ) -> Result<(), FrameError>;
    /// Apply the intent as a state change; links `effect_receipt_id` ← `input_receipt_id`.
    async fn apply(
        &self,
        intent: &Intent,
        input_receipt_id: &str,
        effect_receipt_id: &str,
        now: f64,
    ) -> Result<(), FrameError>;
}

/// The result of one input-loop step — the before/after frames + the lineage chain.
pub struct InputStepResult {
    pub frame_before: Frame,
    pub intent: Option<Intent>,
    pub input_receipt_id: String,
    pub effect_receipt_id: Option<String>,
    pub frame_after: Frame,
}

/// One turn of `state → frame → input → intent → state`. Deterministic: lineage ids come from
/// `frame_index`, time from `now` (the caller's deterministic clock). The intent flows through the
/// `IntentSink` effect; the frame is RE-PROJECTED from the new state, never patched by the input.
#[allow(clippy::too_many_arguments)]
pub async fn input_step(
    source: &dyn FrameSource,
    intent_sink: &dyn IntentSink,
    frame_sink: &dyn FrameSink,
    camera: &Camera,
    input: &InputEvent,
    frame_index: u64,
    now: f64,
) -> Result<InputStepResult, FrameError> {
    let frame_before = project_frame(source, camera, frame_index, None).await?;
    let input_receipt_id = format!("input:{frame_index}");
    intent_sink
        .record_input(input, &input_receipt_id, now)
        .await?;

    let intent = derive_intent(&frame_before, input);
    let effect_receipt_id = if let Some(i) = &intent {
        let eid = format!("effect:{frame_index}");
        intent_sink.apply(i, &input_receipt_id, &eid, now).await?; // state effect, NOT a frame mutation
        Some(eid)
    } else {
        None
    };

    // the next frame is a re-projection of the NEW state (lineage = the effect receipt).
    let frame_after =
        project_frame(source, camera, frame_index + 1, effect_receipt_id.clone()).await?;
    frame_sink.record(&frame_after).await?;

    Ok(InputStepResult {
        frame_before,
        intent,
        input_receipt_id,
        effect_receipt_id,
        frame_after,
    })
}
