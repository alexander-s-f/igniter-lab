//! igniter-console — operator-console / IDE-shell (LAB-FRAME-APP-CONSOLE-P13).
//!
//! The FIRST app built FROM the kit. It takes a ViewArtifact-authored screen (an
//! `igniter-ui-kit` workbench compiled from JSON), runs it, and wraps it with developer tooling:
//!
//!   * a REPLAY STRIP of every recorded frame (time-travel scrubbing);
//!   * a FRAME VIEWER that renders the selected frame (the target's own SVG, embedded);
//!   * a LINEAGE INSPECTOR (`input → effect → frame`, digests) for the selected step;
//!   * a FRAME DIFF over the recorded frame history (what changed vs the previous frame).
//!
//! It invents no layout primitives: it reuses `igniter-frame`'s `Frame`/`ProjectedNode`/`hit_test`
//! for its own chrome and embeds the target's rendered SVG. No `igniter-machine` in the path.

use igniter_frame::{hit_test, Frame, ProjectedNode};
use igniter_ui_kit::composition::WorkbenchRuntime;
use igniter_ui_kit::view_artifact::ViewError;
use serde_json::{json, Value};
use std::collections::HashMap;

#[cfg(feature = "wasm")]
pub mod wasm;

const CW: i64 = 940;
const CH: i64 = 600;
// the embedded target viewer box (console coords) and the target's own frame size
const VX: i64 = 28;
const VY: i64 = 120;
const VW: i64 = 576;
const VH: i64 = 352;
const TARGET_W: f64 = 720.0;
const TARGET_H: f64 = 440.0;

/// One recorded frame in the history (a frame-as-fact: digest + lineage + the projected nodes).
#[derive(Clone)]
pub struct FrameRecord {
    pub step: usize,
    pub frame_index: u64,
    pub input_receipt: Option<String>,
    pub effect_receipt: Option<String>,
    pub render_digest: String,
    pub world_digest: String,
    pub svg: String,
    pub frame: Frame,
    pub label: String,
}

/// A single node-level change between two frames.
#[derive(Clone, Debug, PartialEq)]
pub struct NodeChange {
    pub id: String,
    pub change: String, // "added" | "removed" | "moved" | "changed"
}

/// The console: a target workbench under inspection + its recorded frame history + a scrub cursor.
pub struct Console {
    target: WorkbenchRuntime,
    log: Vec<FrameRecord>,
    selected: usize,
}

impl Console {
    /// Build a console around a ViewArtifact-authored workbench (the app being inspected).
    pub fn from_artifact(json: &str) -> Result<Self, ViewError> {
        let target = WorkbenchRuntime::from_artifact(json)?;
        let mut c = Self { target, log: Vec::new(), selected: 0 };
        c.record("(init)");
        Ok(c)
    }

    fn record(&mut self, label: &str) {
        let lin: Value = serde_json::from_str(&self.target.lineage_json()).unwrap_or_else(|_| json!({}));
        let frame = self.target.frame();
        self.log.push(FrameRecord {
            step: self.log.len(),
            frame_index: self.target.frame_index(),
            input_receipt: lin.get("input_receipt_id").and_then(|v| v.as_str()).map(String::from),
            effect_receipt: lin.get("effect_receipt_id").and_then(|v| v.as_str()).map(String::from),
            render_digest: self.target.render_digest(),
            world_digest: frame.world_digest.clone(),
            svg: self.target.render_svg(),
            frame,
            label: label.to_string(),
        });
        self.selected = self.log.len() - 1;
    }

    // ── target interaction (records a new frame, selects the latest) ──
    fn click_target(&mut self, target_x: f64, target_y: f64) {
        let changed = self.target.click(target_x, target_y);
        self.record(if changed { "click" } else { "click (no-op)" });
    }
    pub fn key(&mut self, ch: &str) {
        if self.target.key(ch) {
            self.record(&format!("key '{ch}'"));
        }
    }
    pub fn backspace(&mut self) {
        if self.target.backspace() {
            self.record("backspace");
        }
    }

    // ── time-travel ──
    pub fn select_step(&mut self, i: usize) {
        if i < self.log.len() {
            self.selected = i;
        }
    }
    pub fn selected(&self) -> usize {
        self.selected
    }
    pub fn len(&self) -> usize {
        self.log.len()
    }
    pub fn is_empty(&self) -> bool {
        self.log.is_empty()
    }
    pub fn is_live(&self) -> bool {
        self.selected + 1 == self.log.len()
    }

    /// The frame diff for the selected step vs. its predecessor (empty at step 0).
    pub fn diff(&self) -> Vec<NodeChange> {
        if self.selected == 0 {
            return Vec::new();
        }
        diff_frames(&self.log[self.selected - 1].frame, &self.log[self.selected].frame)
    }

    // ── console chrome: interactive nodes (strip chips + the viewer box) for hit-testing ──
    fn chip_rect(i: usize) -> (i64, i64, i64, i64) {
        (24 + i as i64 * 64, 22, 56, 38)
    }

    fn chrome(&self) -> Frame {
        let mut nodes: Vec<ProjectedNode> = Vec::new();
        for i in 0..self.log.len() {
            let (x, y, w, h) = Self::chip_rect(i);
            nodes.push(node(format!("step:{i}"), x, y, w, h, Some(json!({ "action": "select" }))));
        }
        nodes.push(node("viewer".into(), VX, VY, VW, VH, Some(json!({ "action": "forward" }))));
        Frame { frame_index: 0, world_digest: String::new(), source_receipt_id: None, nodes }
    }

    /// Route a console-space pointer click: a strip chip → select that step (time-travel); inside
    /// the viewer → translate to target coords and forward to the target runtime. Returns whether
    /// the console reacted.
    pub fn click(&mut self, cx: f64, cy: f64) -> bool {
        let chrome = self.chrome();
        let Some(hit) = hit_test(&chrome, cx.round() as i64, cy.round() as i64) else { return false };
        let id = hit.id.clone();
        if let Some(rest) = id.strip_prefix("step:") {
            if let Ok(i) = rest.parse::<usize>() {
                self.select_step(i);
                return true;
            }
        }
        if id == "viewer" {
            let tx = (cx - VX as f64) / VW as f64 * TARGET_W;
            let ty = (cy - VY as f64) / VH as f64 * TARGET_H;
            self.click_target(tx, ty);
            return true;
        }
        false
    }

    /// Render the whole IDE shell (strip + viewer + lineage + diff) to one SVG.
    pub fn render_svg(&self) -> String {
        let mut b = String::new();
        b.push_str(&format!("<svg viewBox=\"0 0 {CW} {CH}\" xmlns=\"http://www.w3.org/2000/svg\">\n"));
        b.push_str(&format!("  <rect width=\"{CW}\" height=\"{CH}\" fill=\"#010409\"/>\n"));

        // panels
        panel(&mut b, 16, 12, 908, 58, "replay");
        panel(&mut b, 16, 82, 600, 406, &format!("frame viewer — step {}/{}{}", self.selected, self.log.len() - 1, if self.is_live() { " (live)" } else { " (replay)" }));
        panel(&mut b, 632, 82, 292, 158, "lineage");
        panel(&mut b, 632, 250, 292, 238, "frame diff vs prev");

        // replay strip: a chip per recorded frame
        for (i, rec) in self.log.iter().enumerate() {
            let (x, y, w, h) = Self::chip_rect(i);
            let fill = if i == self.selected { "#1f6feb" } else { "#161b22" };
            rect(&mut b, x, y, w, h, 6, fill, "#30363d");
            text(&mut b, x + w / 2, y + 16, 11, "#e6edf3", "middle", &format!("f{}", rec.frame_index));
            text(&mut b, x + w / 2, y + 30, 9, "#8b949e", "middle", &short(&rec.render_digest, 5));
        }

        // frame viewer: embed the selected frame's own SVG (nested svg, re-scaled into the box)
        let rec = &self.log[self.selected];
        let embedded = rec.svg.replacen(
            "<svg ",
            &format!("<svg x=\"{VX}\" y=\"{VY}\" width=\"{VW}\" height=\"{VH}\" "),
            1,
        );
        b.push_str(&embedded);

        // lineage inspector
        let mut ly = 112;
        let kv = |b: &mut String, ly: &mut i64, k: &str, v: &str| {
            text(b, 644, *ly, 12, "#9da7b3", "start", &format!("{k}: {v}"));
            *ly += 22;
        };
        kv(&mut b, &mut ly, "step", &rec.step.to_string());
        kv(&mut b, &mut ly, "event", &rec.label);
        kv(&mut b, &mut ly, "input", rec.input_receipt.as_deref().unwrap_or("—"));
        kv(&mut b, &mut ly, "effect", rec.effect_receipt.as_deref().unwrap_or("—"));
        kv(&mut b, &mut ly, "frame", &format!("frame:{}", rec.frame_index));
        kv(&mut b, &mut ly, "render", &short(&rec.render_digest, 10));

        // frame diff
        let diff = self.diff();
        let mut dy = 280;
        if diff.is_empty() {
            text(&mut b, 644, dy, 12, "#6e7681", "start", if self.selected == 0 { "(initial frame)" } else { "(no change)" });
        } else {
            for ch in diff.iter().take(9) {
                let color = match ch.change.as_str() {
                    "added" => "#3fb950",
                    "removed" => "#f85149",
                    "moved" => "#58a6ff",
                    _ => "#d29922",
                };
                text(&mut b, 644, dy, 11, color, "start", &format!("{:<7} {}", ch.change, short(&ch.id, 22)));
                dy += 20;
            }
            if diff.len() > 9 {
                text(&mut b, 644, dy, 11, "#6e7681", "start", &format!("… +{} more", diff.len() - 9));
            }
        }

        b.push_str("</svg>\n");
        b
    }

    // ── accessors for tests/host ──
    pub fn selected_render_digest(&self) -> String {
        self.log[self.selected].render_digest.clone()
    }
    pub fn lineage_json(&self) -> String {
        let r = &self.log[self.selected];
        json!({ "step": r.step, "input_receipt_id": r.input_receipt, "effect_receipt_id": r.effect_receipt, "frame_index": r.frame_index }).to_string()
    }
    pub fn diff_json(&self) -> String {
        let d: Vec<Value> = self.diff().iter().map(|c| json!({ "id": c.id, "change": c.change })).collect();
        Value::Array(d).to_string()
    }
}

fn node(id: String, x: i64, y: i64, w: i64, h: i64, intent: Option<Value>) -> ProjectedNode {
    ProjectedNode { id, x: x as f64, y: y as f64, z: 0.0, sx: x, sy: y, intent, sw: Some(w), sh: Some(h), data: Value::Null }
}

fn diff_frames(prev: &Frame, cur: &Frame) -> Vec<NodeChange> {
    let pm: HashMap<&str, &ProjectedNode> = prev.nodes.iter().map(|n| (n.id.as_str(), n)).collect();
    let cm: HashMap<&str, &ProjectedNode> = cur.nodes.iter().map(|n| (n.id.as_str(), n)).collect();
    let mut out = Vec::new();
    for n in &cur.nodes {
        match pm.get(n.id.as_str()) {
            None => out.push(NodeChange { id: n.id.clone(), change: "added".into() }),
            Some(p) => {
                if p.sx != n.sx || p.sy != n.sy {
                    out.push(NodeChange { id: n.id.clone(), change: "moved".into() });
                } else if p.data != n.data {
                    out.push(NodeChange { id: n.id.clone(), change: "changed".into() });
                }
            }
        }
    }
    for n in &prev.nodes {
        if !cm.contains_key(n.id.as_str()) {
            out.push(NodeChange { id: n.id.clone(), change: "removed".into() });
        }
    }
    out
}

// ── tiny SVG helpers (the console chrome; the target frame is embedded verbatim) ──
fn esc(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;")
}
fn rect(b: &mut String, x: i64, y: i64, w: i64, h: i64, r: i64, fill: &str, stroke: &str) {
    b.push_str(&format!("  <rect x=\"{x}\" y=\"{y}\" width=\"{w}\" height=\"{h}\" rx=\"{r}\" fill=\"{fill}\" stroke=\"{stroke}\"/>\n"));
}
fn text(b: &mut String, x: i64, y: i64, size: i64, fill: &str, anchor: &str, s: &str) {
    b.push_str(&format!("  <text x=\"{x}\" y=\"{y}\" font-family=\"monospace\" font-size=\"{size}\" fill=\"{fill}\" text-anchor=\"{anchor}\">{}</text>\n", esc(s)));
}
fn panel(b: &mut String, x: i64, y: i64, w: i64, h: i64, title: &str) {
    rect(b, x, y, w, h, 8, "#0d1117", "#30363d");
    text(b, x + 12, y + 20, 12, "#8b949e", "start", title);
}
fn short(s: &str, n: usize) -> String {
    let s = s.strip_prefix("sha256:").unwrap_or(s);
    if s.chars().count() > n {
        format!("{}…", s.chars().take(n).collect::<String>())
    } else {
        s.to_string()
    }
}
