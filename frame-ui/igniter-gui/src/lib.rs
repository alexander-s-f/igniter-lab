//! igniter-gui — the GUI engine's reactive loop, re-homed over igniter-frame
//! (LAB-FRAME-GUI-ENGINE-REHOME-P8).
//!
//! This mirrors the disciplined headless GUI engine (`igniter-gui-engine`, Ruby NGUI-P1..P13) onto
//! igniter-frame's actual ports/runtime, the third domain over one runtime:
//!
//!   * widgets are world FACTS (`{role, label, …, on_click}`);
//!   * LAYOUT is an orthographic `LayoutProjector` (igniter-frame's `Projector` port) — a box stack,
//!     not a perspective camera;
//!   * HIT-TEST → INTENT is igniter-frame's box-aware `hit_test` + `derive_intent`, driven by
//!     `FrameRuntime::click` (the same input loop the 2D demo uses);
//!   * the UPDATE logic (toggle / add + recompute) is an `IntentReducer`;
//!   * RENDER is a `GuiRenderHost` implementing igniter-frame's `RenderHost` trait.
//!
//! Same frame / digest / lineage / deterministic-replay model as the 2D and 3D domains. Depends on
//! `igniter_frame` with `default-features = false` → no `igniter-machine` in the core/browser path.

use igniter_frame::host::Viewport;
use igniter_frame::runtime::FrameRuntime;
use igniter_frame::{Frame, IntentReducer, ProjectedNode, Projector, RenderHost};
use serde_json::{json, Value};

#[cfg(feature = "wasm")]
pub mod wasm;

const MARGIN: i64 = 20;
const PANEL_W: i64 = 360;
const ROW_H: i64 = 44;
const GAP: i64 = 8;
const CANVAS: i64 = 400;

/// The initial widget world: an "add" button, two task rows, and a counter display.
pub fn initial_world() -> Vec<(String, Value)> {
    vec![
        (
            "ctrl_add".to_string(),
            json!({ "role": "button", "label": "+ add task", "on_click": { "action": "add" } }),
        ),
        (
            "task_1".to_string(),
            json!({ "role": "row", "label": "task 1", "done": false, "on_click": { "action": "toggle" } }),
        ),
        (
            "task_2".to_string(),
            json!({ "role": "row", "label": "task 2", "done": false, "on_click": { "action": "toggle" } }),
        ),
        (
            "counter".to_string(),
            json!({ "role": "display", "label": "0 / 2 done" }),
        ),
    ]
}

fn role_rank(role: &str) -> u8 {
    match role {
        "button" => 0,
        "row" => 1,
        "display" => 2,
        _ => 3,
    }
}

fn world_digest(world: &[(String, Value)]) -> String {
    let mut sorted = world.to_vec();
    sorted.sort_by(|a, b| a.0.cmp(&b.0));
    format!(
        "sha256:{}",
        blake3::hash(
            serde_json::to_string(&sorted)
                .unwrap_or_default()
                .as_bytes()
        )
        .to_hex()
    )
}

/// Orthographic box-layout projection: widgets are laid out as a vertical stack (buttons, then rows
/// by id, then displays), each a screen rectangle carrying its render payload in `data`. This is a
/// `Projector` — a drop-in for the perspective `CameraProjector` over the same runtime.
#[derive(Default)]
pub struct LayoutProjector;

impl Projector for LayoutProjector {
    fn project(
        &self,
        world: &[(String, Value)],
        frame_index: u64,
        source_receipt_id: Option<String>,
    ) -> Frame {
        let mut items: Vec<&(String, Value)> = world.iter().collect();
        items.sort_by(|a, b| {
            let ra = role_rank(a.1.get("role").and_then(|v| v.as_str()).unwrap_or(""));
            let rb = role_rank(b.1.get("role").and_then(|v| v.as_str()).unwrap_or(""));
            ra.cmp(&rb).then_with(|| a.0.cmp(&b.0)) // deterministic: by role, then id
        });
        let nodes = items
            .iter()
            .enumerate()
            .map(|(i, (id, val))| {
                let sx = MARGIN;
                let sy = MARGIN + i as i64 * (ROW_H + GAP);
                ProjectedNode {
                    id: id.clone(),
                    x: sx as f64,
                    y: sy as f64,
                    z: 0.0,
                    sx,
                    sy,
                    intent: val.get("on_click").cloned(),
                    sw: Some(PANEL_W),
                    sh: Some(ROW_H),
                    data: (*val).clone(),
                }
            })
            .collect();
        Frame {
            frame_index,
            world_digest: world_digest(world),
            source_receipt_id,
            nodes,
        }
    }
}

fn esc(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
}

/// Render the widget boxes to SVG (rects + labels + a checkbox for rows). Implements igniter-frame's
/// `RenderHost` — the same boundary the 2D `SvgRenderHost` and the 3D `WireframeRenderHost` use.
pub struct GuiRenderHost {
    pub width: i64,
    pub height: i64,
}

impl RenderHost for GuiRenderHost {
    fn render(&self, frame: &Frame) -> String {
        let mut body = String::new();
        for n in &frame.nodes {
            let (w, h) = (n.sw.unwrap_or(0), n.sh.unwrap_or(0));
            let role = n.data.get("role").and_then(|v| v.as_str()).unwrap_or("");
            let label = n.data.get("label").and_then(|v| v.as_str()).unwrap_or("");
            let done = n
                .data
                .get("done")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
            let fill = match role {
                "button" => "#1f6feb",
                "display" => "#161b22",
                _ if done => "#238636",
                _ => "#21262d",
            };
            body.push_str(&format!(
                "  <rect x=\"{}\" y=\"{}\" width=\"{}\" height=\"{}\" rx=\"6\" fill=\"{}\" stroke=\"#30363d\"/>\n",
                n.sx, n.sy, w, h, fill
            ));
            let text = if role == "row" {
                format!("{} {}", if done { "[x]" } else { "[ ]" }, label)
            } else {
                label.to_string()
            };
            body.push_str(&format!(
                "  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"15\" fill=\"#e6edf3\">{}</text>\n",
                n.sx + 14,
                n.sy + h / 2 + 5,
                esc(&text)
            ));
        }
        format!(
            "<svg viewBox=\"0 0 {} {}\" xmlns=\"http://www.w3.org/2000/svg\">\n  <rect width=\"{}\" height=\"{}\" fill=\"#0d1117\"/>\n{}</svg>\n",
            self.width, self.height, self.width, self.height, body
        )
    }
}

fn recount(
    world: &[(String, Value)],
    toggle: Option<(&str, bool)>,
    adding: bool,
) -> (String, Value) {
    let mut total = 0;
    let mut done = 0;
    for (id, v) in world {
        if v.get("role").and_then(|r| r.as_str()) == Some("row") {
            total += 1;
            let mut d = v.get("done").and_then(|b| b.as_bool()).unwrap_or(false);
            if let Some((tid, nd)) = toggle {
                if id == tid {
                    d = nd;
                }
            }
            if d {
                done += 1;
            }
        }
    }
    if adding {
        total += 1; // the new row is not done
    }
    (
        "counter".to_string(),
        json!({ "role": "display", "label": format!("{} / {} done", done, total) }),
    )
}

/// The GUI update reducer: `toggle` flips a row's done-state, `add` appends a new row; both recompute
/// the counter. Pure `(intent, world) -> deltas` — the GUI's reactive update as an `IntentReducer`.
pub fn gui_reducer() -> IntentReducer {
    Box::new(|intent, world| match intent.action.as_str() {
        "toggle" => {
            let Some(target) = &intent.target else {
                return vec![];
            };
            let Some((_, cur)) = world.iter().find(|(k, _)| k == target) else {
                return vec![];
            };
            if cur.get("role").and_then(|r| r.as_str()) != Some("row") {
                return vec![];
            }
            let new_done = !cur.get("done").and_then(|b| b.as_bool()).unwrap_or(false);
            let mut row = cur.clone();
            row["done"] = json!(new_done);
            vec![
                (target.clone(), row),
                recount(world, Some((target, new_done)), false),
            ]
        }
        "add" => {
            let n = world
                .iter()
                .filter(|(_, v)| v.get("role").and_then(|r| r.as_str()) == Some("row"))
                .count();
            let id = format!("task_{}", n + 1);
            let row = json!({ "role": "row", "label": format!("task {}", n + 1), "done": false, "on_click": { "action": "toggle" } });
            vec![(id, row), recount(world, None, true)]
        }
        _ => vec![],
    })
}

/// The GUI runtime: a thin wrapper over igniter-frame's `FrameRuntime`, built with the widget world,
/// the orthographic layout projector, the GUI reducer, and the rect render host. `click` runs the
/// same input loop (hit-test → intent → effect → re-project) as the 2D demo.
pub struct GuiRuntime {
    inner: FrameRuntime,
}

impl GuiRuntime {
    pub fn new() -> Self {
        let inner = FrameRuntime::with_projector(
            initial_world(),
            gui_reducer(),
            Box::new(LayoutProjector),
            Viewport {
                css_w: CANVAS as f64,
                css_h: CANVAS as f64,
                frame_w: CANVAS,
                frame_h: CANVAS,
            },
            Box::new(GuiRenderHost {
                width: CANVAS,
                height: CANVAS,
            }),
        );
        Self { inner }
    }

    pub fn click(&mut self, css_x: f64, css_y: f64) -> bool {
        self.inner.click(css_x, css_y)
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

impl Default for GuiRuntime {
    fn default() -> Self {
        Self::new()
    }
}
