//! LAB-FRAME-LAYOUT-VOCAB-P7 — scroll/overflow + keyboard nav + hover, on one scrollable list.
//!
//! A list of `N_ITEMS` rows in a fixed `PANEL_ROWS`-tall viewport (row-snapped, so no partial-row
//! clipping — the visible window is `items[off .. off+PANEL_ROWS]`, exact hit-test). It demonstrates:
//!   • SCROLL  — the mouse wheel routes a VIEW-only `scroll` intent; the reducer clamps `__scroll__`.
//!   • HOVER   — pointer-move routes a VIEW-only `hover` intent; the hovered row highlights.
//!   • TAB NAV — Tab/Shift-Tab/Arrows move a keyboard focus ring (`__focus__`) and AUTO-SCROLL to
//!               keep it visible; Enter/Space selects the focused row.
//! Hover and scroll are presentation state (`view_send`, no semantic step); nav/select are domain
//! effects (bump the frame index + lineage). Deterministic + machine-free.

use crate::host::Viewport;
use crate::layout::{solve, Align, LayoutBox, Size};
use crate::runtime::FrameRuntime;
use crate::{Frame, IntentReducer, ProjectedNode, Projector, RenderHost};
use serde_json::{json, Value};

const CANVAS_W: i64 = 560;
const CANVAS_H: i64 = 410;
const N_ITEMS: i64 = 24;
const ITEM_H: i64 = 30;
const PANEL_ROWS: i64 = 10;
const SB_W: i64 = 8; // scrollbar width
const NAMES: [&str; 8] = ["Aria", "Bjorn", "Cleo", "Dax", "Esme", "Finn", "Gwen", "Hugo"];

fn maxoff() -> i64 {
    (N_ITEMS - PANEL_ROWS).max(0)
}

pub fn initial_world() -> Vec<(String, Value)> {
    let mut w: Vec<(String, Value)> = (0..N_ITEMS)
        .map(|i| (format!("item:{i}"), json!({ "label": format!("{:02}  {}", i + 1, NAMES[(i as usize) % NAMES.len()]) })))
        .collect();
    w.push(("__scroll__".into(), json!(0)));
    w.push(("__focus__".into(), json!("item:0")));
    w.push(("__hover__".into(), json!("")));
    w.push(("__sel__".into(), json!("")));
    w.push(("__status__".into(), json!("")));
    w
}

fn iget<'a>(world: &'a [(String, Value)], k: &str) -> Option<&'a Value> {
    world.iter().find(|(key, _)| key == k).map(|(_, v)| v)
}
fn off_of(world: &[(String, Value)]) -> i64 {
    iget(world, "__scroll__").and_then(|v| v.as_i64()).unwrap_or(0).clamp(0, maxoff())
}
fn focus_idx(world: &[(String, Value)]) -> i64 {
    iget(world, "__focus__").and_then(|v| v.as_str()).and_then(|s| s.strip_prefix("item:"))
        .and_then(|n| n.parse().ok()).unwrap_or(-1)
}

fn world_digest(world: &[(String, Value)]) -> String {
    let mut sorted = world.to_vec();
    sorted.sort_by(|a, b| a.0.cmp(&b.0));
    format!("sha256:{}", blake3::hash(serde_json::to_string(&sorted).unwrap_or_default().as_bytes()).to_hex())
}

pub struct ScrollListProjector;

impl Projector for ScrollListProjector {
    fn project(&self, world: &[(String, Value)], frame_index: u64, source_receipt_id: Option<String>) -> Frame {
        let off = off_of(world);
        let sel = iget(world, "__sel__").and_then(|v| v.as_str()).unwrap_or("").to_string();
        let hov = iget(world, "__hover__").and_then(|v| v.as_str()).unwrap_or("").to_string();
        let foc = iget(world, "__focus__").and_then(|v| v.as_str()).unwrap_or("").to_string();

        let tree = LayoutBox::col(
            "screen",
            Size::Fixed(0),
            vec![
                LayoutBox::row("header", Size::Fixed(30), vec![
                    LayoutBox::leaf("title", Size::Flex(1)),
                    LayoutBox::leaf("hint", Size::Fixed(250)).cross(18),
                ]).align(Align::Center),
                LayoutBox::leaf("list", Size::Fixed(PANEL_ROWS * ITEM_H)),
                LayoutBox::leaf("footer", Size::Fixed(22)),
            ],
        )
        .pad(16)
        .gap(12);

        let rects = solve(&tree, 0, 0, CANVAS_W, CANVAS_H);
        let r = |id: &str| rects.iter().find(|r| r.id == id).cloned().unwrap();
        let panel = r("list");
        let row_w = panel.w - SB_W - 4;

        let mut nodes: Vec<ProjectedNode> = Vec::new();
        let push = |nodes: &mut Vec<ProjectedNode>, rect: &crate::layout::Rect, intent, data| {
            nodes.push(ProjectedNode::from_rect(rect, intent, data));
        };

        // chrome
        push(&mut nodes, &r("title"), None, json!({ "kind": "title", "label": "Scrollable list" }));
        push(&mut nodes, &r("hint"), None, json!({ "kind": "hint", "label": "wheel · tab · hover" }));
        push(&mut nodes, &panel, None, json!({ "kind": "panel" }));
        let status = iget(world, "__status__").and_then(|v| v.as_str()).unwrap_or("");
        let foot = format!("{}   ·   showing {}–{} of {}", status, off + 1, (off + PANEL_ROWS).min(N_ITEMS), N_ITEMS);
        push(&mut nodes, &r("footer"), None, json!({ "kind": "footer", "label": foot }));

        // visible rows (row-snapped window)
        for idx in off..(off + PANEL_ROWS).min(N_ITEMS) {
            let id = format!("item:{idx}");
            let label = iget(world, &id).and_then(|v| v.get("label")).and_then(|v| v.as_str()).unwrap_or("").to_string();
            let rect = crate::layout::Rect { id: id.clone(), x: panel.x, y: panel.y + (idx - off) * ITEM_H, w: row_w, h: ITEM_H };
            push(&mut nodes, &rect, Some(json!({ "action": "select", "item": id.clone() })),
                json!({ "kind": "item", "label": label, "selected": id == sel, "hovered": id == hov, "focused": id == foc }));
        }

        // scrollbar (track + proportional thumb) — visual only
        let track = crate::layout::Rect { id: "sb-track".into(), x: panel.x + panel.w - SB_W, y: panel.y, w: SB_W, h: panel.h };
        let thumb_h = (panel.h * PANEL_ROWS / N_ITEMS).max(22);
        let thumb_y = panel.y + if maxoff() > 0 { (panel.h - thumb_h) * off / maxoff() } else { 0 };
        let thumb = crate::layout::Rect { id: "sb-thumb".into(), x: panel.x + panel.w - SB_W, y: thumb_y, w: SB_W, h: thumb_h };
        push(&mut nodes, &track, None, json!({ "kind": "sbtrack" }));
        push(&mut nodes, &thumb, None, json!({ "kind": "sbthumb" }));

        Frame { frame_index, world_digest: world_digest(world), source_receipt_id, nodes }
    }
}

pub fn scroll_list_reducer() -> IntentReducer {
    Box::new(|intent, world| {
        let off = off_of(world);
        // keep the focused row inside the [off, off+PANEL_ROWS) window
        let autoscroll = |fi: i64, off: i64| -> i64 {
            if fi < off { fi } else if fi >= off + PANEL_ROWS { fi - PANEL_ROWS + 1 } else { off }
            .clamp(0, maxoff())
        };
        match intent.action.as_str() {
            "hover" => {
                let id = intent.params.get("id").and_then(|v| v.as_str()).unwrap_or("");
                let next = if id.starts_with("item:") { id } else { "" };
                if iget(world, "__hover__").and_then(|v| v.as_str()).unwrap_or("") == next {
                    vec![] // unchanged → no redraw
                } else {
                    vec![("__hover__".to_string(), json!(next))]
                }
            }
            "scroll" => {
                let dy = intent.params.get("dy").and_then(|v| v.as_i64()).unwrap_or(0);
                let dir = if dy > 0 { 1 } else if dy < 0 { -1 } else { 0 };
                let next = (off + dir).clamp(0, maxoff());
                if next == off { vec![] } else { vec![("__scroll__".to_string(), json!(next))] }
            }
            "nav" => {
                let dir = intent.params.get("dir").and_then(|v| v.as_i64()).unwrap_or(0);
                let fi = (focus_idx(world) + dir).clamp(0, N_ITEMS - 1);
                vec![
                    ("__focus__".to_string(), json!(format!("item:{fi}"))),
                    ("__scroll__".to_string(), json!(autoscroll(fi, off))),
                ]
            }
            "select" => intent.params.get("item").and_then(|v| v.as_str()).map(|id| {
                let label = iget(world, id).and_then(|v| v.get("label")).and_then(|v| v.as_str()).unwrap_or("").to_string();
                vec![
                    ("__sel__".to_string(), json!(id)),
                    ("__focus__".to_string(), json!(id)),
                    ("__status__".to_string(), json!(format!("Selected {}", label.trim()))),
                ]
            }).unwrap_or_default(),
            "activate" => {
                let fi = focus_idx(world);
                if fi < 0 { return vec![]; }
                let id = format!("item:{fi}");
                let label = iget(world, &id).and_then(|v| v.get("label")).and_then(|v| v.as_str()).unwrap_or("").to_string();
                vec![("__sel__".into(), json!(id)), ("__status__".into(), json!(format!("Selected {}", label.trim())))]
            }
            _ => vec![],
        }
    })
}

fn esc(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;")
}

pub struct ScrollListRenderHost;

impl RenderHost for ScrollListRenderHost {
    fn render(&self, frame: &Frame) -> String {
        let mut body = String::new();
        for n in &frame.nodes {
            let (x, y, w, h) = (n.sx, n.sy, n.sw.unwrap_or(0), n.sh.unwrap_or(0));
            let kind = n.data.get("kind").and_then(|v| v.as_str()).unwrap_or("");
            let lbl = n.data.get("label").and_then(|v| v.as_str()).unwrap_or("");
            match kind {
                "title" => body.push_str(&format!("  <text x=\"{x}\" y=\"{}\" font-family=\"monospace\" font-size=\"15\" font-weight=\"bold\" fill=\"#e6edf3\">{}</text>\n", y + 18, esc(lbl))),
                "hint" => body.push_str(&format!("  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"12\" fill=\"#8b949e\" text-anchor=\"end\">{}</text>\n", x + w, y + h / 2 + 4, esc(lbl))),
                "footer" => body.push_str(&format!("  <text x=\"{x}\" y=\"{}\" font-family=\"monospace\" font-size=\"12\" fill=\"#3fb950\">{}</text>\n", y + h / 2 + 4, esc(lbl))),
                "panel" => body.push_str(&format!("  <rect x=\"{x}\" y=\"{y}\" width=\"{w}\" height=\"{h}\" rx=\"8\" fill=\"#0d1117\" stroke=\"#30363d\"/>\n")),
                "item" => {
                    let sel = n.data.get("selected").and_then(|v| v.as_bool()).unwrap_or(false);
                    let hov = n.data.get("hovered").and_then(|v| v.as_bool()).unwrap_or(false);
                    let foc = n.data.get("focused").and_then(|v| v.as_bool()).unwrap_or(false);
                    let fill = if sel { "#16304f" } else if hov { "#161b22" } else { "#0d1117" };
                    body.push_str(&format!("  <rect x=\"{}\" y=\"{}\" width=\"{}\" height=\"{}\" rx=\"5\" fill=\"{fill}\"/>\n", x + 2, y + 2, (w - 4).max(0), (h - 4).max(0)));
                    if foc {
                        body.push_str(&format!("  <rect x=\"{}\" y=\"{}\" width=\"{}\" height=\"{}\" rx=\"5\" fill=\"none\" stroke=\"#1f6feb\" stroke-width=\"2\"/>\n", x + 2, y + 2, (w - 4).max(0), (h - 4).max(0)));
                    }
                    let dot = if sel { "#3fb950" } else { "#484f58" };
                    body.push_str(&format!("  <circle cx=\"{}\" cy=\"{}\" r=\"3\" fill=\"{dot}\"/>\n", x + 14, y + h / 2));
                    body.push_str(&format!("  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"13\" fill=\"#c9d1d9\">{}</text>\n", x + 28, y + h / 2 + 5, esc(lbl)));
                }
                "sbtrack" => body.push_str(&format!("  <rect x=\"{x}\" y=\"{y}\" width=\"{w}\" height=\"{h}\" rx=\"4\" fill=\"#0d1117\"/>\n")),
                "sbthumb" => body.push_str(&format!("  <rect x=\"{x}\" y=\"{y}\" width=\"{w}\" height=\"{h}\" rx=\"4\" fill=\"#30363d\"/>\n")),
                _ => {}
            }
        }
        format!("<svg viewBox=\"0 0 {CANVAS_W} {CANVAS_H}\" xmlns=\"http://www.w3.org/2000/svg\">\n  <rect width=\"{CANVAS_W}\" height=\"{CANVAS_H}\" fill=\"#010409\"/>\n{body}</svg>\n")
    }
}

pub struct ScrollListRuntime {
    inner: FrameRuntime,
}

impl Default for ScrollListRuntime {
    fn default() -> Self {
        Self::new()
    }
}

impl ScrollListRuntime {
    pub fn new() -> Self {
        Self {
            inner: FrameRuntime::with_projector(
                initial_world(),
                scroll_list_reducer(),
                Box::new(ScrollListProjector),
                Viewport { css_w: CANVAS_W as f64, css_h: CANVAS_H as f64, frame_w: CANVAS_W, frame_h: CANVAS_H },
                Box::new(ScrollListRenderHost),
            ),
        }
    }

    pub fn click(&mut self, css_x: f64, css_y: f64) -> bool { self.inner.click(css_x, css_y) }
    pub fn hover(&mut self, css_x: f64, css_y: f64) -> bool { self.inner.hover(css_x, css_y) }
    pub fn scroll(&mut self, css_x: f64, css_y: f64, dy: f64) -> bool { self.inner.scroll(css_x, css_y, dy) }

    /// Keyboard nav: Tab / Shift-Tab / Arrows move the focus ring; Enter / Space select.
    pub fn key(&mut self, k: &str, shift: bool) -> bool {
        match k {
            "Tab" => self.inner.send("nav", json!({ "dir": if shift { -1 } else { 1 } })),
            "ArrowDown" => self.inner.send("nav", json!({ "dir": 1 })),
            "ArrowUp" => self.inner.send("nav", json!({ "dir": -1 })),
            "Enter" | " " => self.inner.send("activate", json!(null)),
            _ => false,
        }
    }

    pub fn render_svg(&self) -> String { self.inner.render_svg() }
    pub fn frame(&self) -> Frame { self.inner.frame() }
    pub fn render_digest(&self) -> String { self.inner.render_digest() }
    pub fn frame_index(&self) -> u64 { self.inner.frame_index() }
    pub fn lineage_json(&self) -> String { self.inner.lineage_json() }
    pub fn reset(&mut self) { self.inner = Self::new().inner; }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn visible(rt: &ScrollListRuntime) -> Vec<String> {
        rt.frame().nodes.iter().filter(|n| n.data.get("kind") == Some(&json!("item"))).map(|n| n.id.clone()).collect()
    }
    fn item<'a>(f: &'a Frame, id: &str) -> Option<&'a ProjectedNode> {
        f.nodes.iter().find(|n| n.id == id)
    }
    fn focused(rt: &ScrollListRuntime) -> Option<String> {
        rt.frame().nodes.iter().find(|n| n.data.get("focused") == Some(&json!(true))).map(|n| n.id.clone())
    }

    #[test]
    fn wheel_scrolls_the_window_and_clamps_without_advancing_frame() {
        let mut rt = ScrollListRuntime::new();
        assert!(visible(&rt).contains(&"item:0".to_string()));
        assert!(!visible(&rt).contains(&"item:10".to_string()));
        let f0 = rt.frame_index();
        for _ in 0..5 { rt.scroll(260.0, 200.0, 40.0); } // wheel down 5 rows
        assert_eq!(rt.frame_index(), f0, "scroll is view-only — no semantic step");
        assert!(visible(&rt).contains(&"item:10".to_string()));
        // clamp at the end: off maxes at N-PANEL_ROWS=14 → window 14..23
        for _ in 0..50 { rt.scroll(260.0, 200.0, 40.0); }
        assert!(visible(&rt).contains(&"item:23".to_string()));
        assert!(!visible(&rt).contains(&"item:13".to_string()));
        // and scroll back up clamps at 0
        for _ in 0..50 { rt.scroll(260.0, 200.0, -40.0); }
        assert!(visible(&rt).contains(&"item:0".to_string()));
    }

    #[test]
    fn hover_highlights_the_row_under_the_cursor_without_advancing_frame() {
        let mut rt = ScrollListRuntime::new();
        let f0 = rt.frame_index();
        let n = item(&rt.frame(), "item:2").unwrap().clone();
        assert!(rt.hover((n.sx + 6) as f64, (n.sy + 6) as f64));
        assert_eq!(rt.frame_index(), f0, "hover is view-only");
        assert!(item(&rt.frame(), "item:2").unwrap().data["hovered"].as_bool().unwrap());
        // moving onto another row moves the highlight; re-hovering the same row is a no-op
        assert!(!rt.hover((n.sx + 6) as f64, (n.sy + 6) as f64), "same target → no redraw");
        let m = item(&rt.frame(), "item:4").unwrap().clone();
        rt.hover((m.sx + 6) as f64, (m.sy + 6) as f64);
        assert!(!item(&rt.frame(), "item:2").unwrap().data["hovered"].as_bool().unwrap());
        assert!(item(&rt.frame(), "item:4").unwrap().data["hovered"].as_bool().unwrap());
    }

    #[test]
    fn tab_moves_focus_and_autoscrolls_then_enter_selects() {
        let mut rt = ScrollListRuntime::new();
        assert_eq!(focused(&rt), Some("item:0".into()));
        for _ in 0..12 { rt.key("Tab", false); } // focus 0 → 12 (each Tab is a semantic step)
        assert_eq!(focused(&rt), Some("item:12".into()));
        assert!(visible(&rt).contains(&"item:12".to_string()), "auto-scrolled to keep focus visible");
        assert!(!visible(&rt).contains(&"item:0".to_string()));
        rt.key("Enter", false); // select the focused row
        assert!(item(&rt.frame(), "item:12").unwrap().data["selected"].as_bool().unwrap());
        // Shift-Tab walks back up and re-reveals earlier rows
        for _ in 0..12 { rt.key("Tab", true); }
        assert_eq!(focused(&rt), Some("item:0".into()));
        assert!(visible(&rt).contains(&"item:0".to_string()));
    }

    #[test]
    fn click_selects_a_visible_row() {
        let mut rt = ScrollListRuntime::new();
        let n = item(&rt.frame(), "item:3").unwrap().clone();
        assert!(rt.click((n.sx + n.sw.unwrap() / 2) as f64, (n.sy + n.sh.unwrap() / 2) as f64));
        assert!(item(&rt.frame(), "item:3").unwrap().data["selected"].as_bool().unwrap());
    }

    #[test]
    fn deterministic_replay_across_scroll_hover_nav() {
        let run = || {
            let mut rt = ScrollListRuntime::new();
            rt.scroll(260.0, 200.0, 40.0);
            rt.hover(120.0, 120.0);
            rt.key("Tab", false);
            rt.key("Tab", false);
            rt.key("Enter", false);
            (rt.frame_index(), rt.render_digest())
        };
        assert_eq!(run(), run());
    }
}
