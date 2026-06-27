//! LAB-FRAME-LAYOUT-VOCAB-P5 — a settings FORM that broadens the 2D widget vocabulary: toggles, a
//! checkbox, a segmented control, a stepper, and action buttons — each a row of `label (flex) +
//! control (fixed cross-size, cross-aligned)`. It exercises the new cross-axis alignment (`align` +
//! `CrossSize::Fixed`) so controls sit right-aligned and vertically centered without coordinate math.
//! All interactions are click-driven (no keyboard yet); state is world facts; deterministic + machine
//! free — the same `FrameRuntime`/layout path as the list and table screens.

use crate::host::Viewport;
use crate::layout::{solve, Align, LayoutBox, Size};
use crate::runtime::FrameRuntime;
use crate::{Frame, IntentReducer, ProjectedNode, Projector, RenderHost};
use serde_json::{json, Value};

const CANVAS_W: i64 = 720;
const CANVAS_H: i64 = 480;
const PLANS: [&str; 3] = ["Free", "Pro", "Team"];

pub fn initial_world() -> Vec<(String, Value)> {
    vec![
        ("notifications".into(), json!(true)),
        ("dark_mode".into(), json!(false)),
        ("newsletter".into(), json!(false)),
        ("plan".into(), json!(1)),
        ("seats".into(), json!(3)),
        ("__status__".into(), json!("")),
    ]
}

fn get<'a>(world: &'a [(String, Value)], k: &str) -> Option<&'a Value> {
    world.iter().find(|(key, _)| key == k).map(|(_, v)| v)
}
fn flag(world: &[(String, Value)], k: &str) -> bool {
    get(world, k).and_then(|v| v.as_bool()).unwrap_or(false)
}
fn int(world: &[(String, Value)], k: &str) -> i64 {
    get(world, k).and_then(|v| v.as_i64()).unwrap_or(0)
}

fn world_digest(world: &[(String, Value)]) -> String {
    let mut sorted = world.to_vec();
    sorted.sort_by(|a, b| a.0.cmp(&b.0));
    format!(
        "sha256:{}",
        blake3::hash(serde_json::to_string(&sorted).unwrap_or_default().as_bytes()).to_hex()
    )
}

/// One `label (flex) + control (fixed, cross-aligned)` row.
fn field_row(id: &str, control: LayoutBox) -> LayoutBox {
    LayoutBox::row(
        id,
        Size::Fixed(42),
        vec![LayoutBox::leaf(format!("lbl-{id}"), Size::Flex(1)), control],
    )
    .align(Align::Center)
}

pub struct FormProjector;

impl Projector for FormProjector {
    fn project(&self, world: &[(String, Value)], frame_index: u64, source_receipt_id: Option<String>) -> Frame {
        // segmented control: a fixed-width row of 3 equal cells, vertically centered
        let seg = LayoutBox::row(
            "seg-plan",
            Size::Fixed(240),
            vec![
                LayoutBox::leaf("seg:0", Size::Flex(1)),
                LayoutBox::leaf("seg:1", Size::Flex(1)),
                LayoutBox::leaf("seg:2", Size::Flex(1)),
            ],
        )
        .cross(30);

        // stepper: − [value] +
        let step = LayoutBox::row(
            "step-seats",
            Size::Fixed(120),
            vec![
                LayoutBox::leaf("step:dec", Size::Fixed(32)),
                LayoutBox::leaf("step:val", Size::Flex(1)),
                LayoutBox::leaf("step:inc", Size::Fixed(32)),
            ],
        )
        .cross(30)
        .gap(6);

        let tree = LayoutBox::col(
            "form",
            Size::Fixed(0),
            vec![
                LayoutBox::leaf("title", Size::Fixed(30)),
                field_row("notif", LayoutBox::leaf("tog-notif", Size::Fixed(56)).cross(28)),
                field_row("dark", LayoutBox::leaf("tog-dark", Size::Fixed(56)).cross(28)),
                field_row("news", LayoutBox::leaf("chk-news", Size::Fixed(24)).cross(24)),
                field_row("plan", seg),
                field_row("seats", step),
                LayoutBox::leaf("spacer", Size::Flex(1)),
                LayoutBox::row(
                    "actions",
                    Size::Fixed(46),
                    vec![
                        LayoutBox::leaf("reset", Size::Flex(1)),
                        LayoutBox::leaf("submit", Size::Flex(2)),
                    ],
                )
                .gap(10),
                LayoutBox::leaf("status", Size::Fixed(24)),
            ],
        )
        .pad(22)
        .gap(14);

        let label_for = |id: &str| match id {
            "lbl-notif" => "Email notifications",
            "lbl-dark" => "Dark mode",
            "lbl-news" => "Subscribe to newsletter",
            "lbl-plan" => "Plan",
            "lbl-seats" => "Seats",
            _ => "",
        };
        let plan = int(world, "plan");

        let nodes: Vec<ProjectedNode> = solve(&tree, 0, 0, CANVAS_W, CANVAS_H)
            .iter()
            .map(|r| {
                let id = r.id.as_str();
                let node = |intent: Option<Value>, data: Value| ProjectedNode::from_rect(r, intent, data);
                match id {
                    "title" => node(None, json!({ "kind": "title", "label": "Account settings" })),
                    "status" => {
                        let s = get(world, "__status__").and_then(|v| v.as_str()).unwrap_or("");
                        node(None, json!({ "kind": "status", "label": s }))
                    }
                    l if l.starts_with("lbl-") => node(None, json!({ "kind": "label", "label": label_for(l) })),
                    "tog-notif" => node(Some(json!({"action":"toggle","key":"notifications"})), json!({"kind":"toggle","on":flag(world,"notifications")})),
                    "tog-dark" => node(Some(json!({"action":"toggle","key":"dark_mode"})), json!({"kind":"toggle","on":flag(world,"dark_mode")})),
                    "chk-news" => node(Some(json!({"action":"toggle","key":"newsletter"})), json!({"kind":"checkbox","on":flag(world,"newsletter")})),
                    s if s.starts_with("seg:") => {
                        let i: i64 = s[4..].parse().unwrap_or(-1);
                        node(Some(json!({"action":"set_plan","value":i})),
                             json!({"kind":"seg","label":PLANS.get(i as usize).copied().unwrap_or(""),"selected":i==plan}))
                    }
                    "step:dec" => node(Some(json!({"action":"step","delta":-1})), json!({"kind":"stepbtn","glyph":"−"})),
                    "step:inc" => node(Some(json!({"action":"step","delta":1})), json!({"kind":"stepbtn","glyph":"+"})),
                    "step:val" => node(None, json!({"kind":"stepval","label":int(world,"seats").to_string()})),
                    "seg-plan" => node(None, json!({"kind":"seggroup"})),
                    "step-seats" => node(None, json!({"kind":"stepgroup"})),
                    "reset" => node(Some(json!({"action":"reset"})), json!({"kind":"btn","label":"Reset","tone":"neutral"})),
                    "submit" => node(Some(json!({"action":"submit"})), json!({"kind":"btn","label":"Save changes","tone":"go"})),
                    _ => node(None, json!({ "kind": "none" })),
                }
            })
            .collect();

        Frame { frame_index, world_digest: world_digest(world), source_receipt_id, nodes }
    }
}

pub fn form_reducer() -> IntentReducer {
    Box::new(|intent, world| {
        let set = |k: &str, v: Value| (k.to_string(), v);
        match intent.action.as_str() {
            "toggle" => intent.params.get("key").and_then(|k| k.as_str())
                .map(|k| vec![set(k, json!(!flag(world, k))), set("__status__", json!(""))])
                .unwrap_or_default(),
            "set_plan" => intent.params.get("value").and_then(|v| v.as_i64())
                .filter(|i| (0..3).contains(i))
                .map(|i| vec![set("plan", json!(i)), set("__status__", json!(""))])
                .unwrap_or_default(),
            "step" => {
                let d = intent.params.get("delta").and_then(|v| v.as_i64()).unwrap_or(0);
                let next = (int(world, "seats") + d).clamp(1, 99);
                vec![set("seats", json!(next)), set("__status__", json!(""))]
            }
            "reset" => {
                let mut w = initial_world();
                w.retain(|(k, _)| k != "__status__");
                w.push(set("__status__", json!("Reset to defaults")));
                w
            }
            "submit" => {
                let summary = format!(
                    "Saved ✓ — notifications {}, dark {}, newsletter {}, plan {}, {} seats",
                    if flag(world, "notifications") { "on" } else { "off" },
                    if flag(world, "dark_mode") { "on" } else { "off" },
                    if flag(world, "newsletter") { "on" } else { "off" },
                    PLANS.get(int(world, "plan") as usize).copied().unwrap_or("?"),
                    int(world, "seats"),
                );
                vec![set("__status__", json!(summary))]
            }
            _ => vec![],
        }
    })
}

fn esc(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;")
}

pub struct FormRenderHost;

impl RenderHost for FormRenderHost {
    fn render(&self, frame: &Frame) -> String {
        let mut body = String::new();
        for n in &frame.nodes {
            let (x, y, w, h) = (n.sx, n.sy, n.sw.unwrap_or(0), n.sh.unwrap_or(0));
            let kind = n.data.get("kind").and_then(|v| v.as_str()).unwrap_or("");
            let lbl = n.data.get("label").and_then(|v| v.as_str()).unwrap_or("");
            let on = n.data.get("on").and_then(|v| v.as_bool()).unwrap_or(false);
            let sel = n.data.get("selected").and_then(|v| v.as_bool()).unwrap_or(false);
            let cy = y + h / 2;
            match kind {
                "title" => body.push_str(&format!("  <text x=\"{x}\" y=\"{}\" font-family=\"monospace\" font-size=\"17\" font-weight=\"bold\" fill=\"#e6edf3\">{}</text>\n", y + 20, esc(lbl))),
                "label" => body.push_str(&format!("  <text x=\"{x}\" y=\"{}\" font-family=\"monospace\" font-size=\"14\" fill=\"#c9d1d9\">{}</text>\n", cy + 5, esc(lbl))),
                "status" => body.push_str(&format!("  <text x=\"{x}\" y=\"{}\" font-family=\"monospace\" font-size=\"12\" fill=\"#3fb950\">{}</text>\n", cy + 4, esc(lbl))),
                "toggle" => {
                    let track = if on { "#238636" } else { "#30363d" };
                    let knob_x = if on { x + w - h } else { x };
                    body.push_str(&format!("  <rect x=\"{x}\" y=\"{y}\" width=\"{w}\" height=\"{h}\" rx=\"{}\" fill=\"{track}\"/>\n", h / 2));
                    body.push_str(&format!("  <circle cx=\"{}\" cy=\"{cy}\" r=\"{}\" fill=\"#f0f6fc\"/>\n", knob_x + h / 2, h / 2 - 3));
                }
                "checkbox" => {
                    let fill = if on { "#238636" } else { "#0d1117" };
                    body.push_str(&format!("  <rect x=\"{x}\" y=\"{y}\" width=\"{w}\" height=\"{h}\" rx=\"5\" fill=\"{fill}\" stroke=\"#30363d\"/>\n"));
                    if on {
                        body.push_str(&format!("  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"15\" fill=\"#f0f6fc\" text-anchor=\"middle\">✓</text>\n", x + w / 2, cy + 5));
                    }
                }
                "seggroup" => body.push_str(&format!("  <rect x=\"{x}\" y=\"{y}\" width=\"{w}\" height=\"{h}\" rx=\"7\" fill=\"#0d1117\" stroke=\"#30363d\"/>\n")),
                "seg" => {
                    if sel {
                        body.push_str(&format!("  <rect x=\"{}\" y=\"{}\" width=\"{}\" height=\"{}\" rx=\"6\" fill=\"#1f6feb\"/>\n", x + 2, y + 2, (w - 4).max(0), (h - 4).max(0)));
                    }
                    let col = if sel { "#f0f6fc" } else { "#8b949e" };
                    body.push_str(&format!("  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"13\" fill=\"{col}\" text-anchor=\"middle\">{}</text>\n", x + w / 2, cy + 5, esc(lbl)));
                }
                "stepgroup" => body.push_str(&format!("  <rect x=\"{x}\" y=\"{y}\" width=\"{w}\" height=\"{h}\" rx=\"7\" fill=\"#0d1117\" stroke=\"#30363d\"/>\n")),
                "stepbtn" => {
                    let g = n.data.get("glyph").and_then(|v| v.as_str()).unwrap_or("");
                    body.push_str(&format!("  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"18\" fill=\"#58a6ff\" text-anchor=\"middle\">{}</text>\n", x + w / 2, cy + 6, esc(g)));
                }
                "stepval" => body.push_str(&format!("  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"15\" fill=\"#e6edf3\" text-anchor=\"middle\">{}</text>\n", x + w / 2, cy + 5, esc(lbl))),
                "btn" => {
                    let (fill, stroke) = if n.data.get("tone").and_then(|t| t.as_str()) == Some("go") { ("#238636", "#2ea043") } else { ("#21262d", "#30363d") };
                    body.push_str(&format!("  <rect x=\"{x}\" y=\"{y}\" width=\"{w}\" height=\"{h}\" rx=\"8\" fill=\"{fill}\" stroke=\"{stroke}\"/>\n"));
                    body.push_str(&format!("  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"14\" fill=\"#f0f6fc\" text-anchor=\"middle\">{}</text>\n", x + w / 2, cy + 5, esc(lbl)));
                }
                _ => {}
            }
        }
        format!(
            "<svg viewBox=\"0 0 {CANVAS_W} {CANVAS_H}\" xmlns=\"http://www.w3.org/2000/svg\">\n  <rect width=\"{CANVAS_W}\" height=\"{CANVAS_H}\" fill=\"#010409\"/>\n{body}</svg>\n"
        )
    }
}

pub struct FormScreenRuntime {
    inner: FrameRuntime,
}

impl Default for FormScreenRuntime {
    fn default() -> Self {
        Self::new()
    }
}

impl FormScreenRuntime {
    pub fn new() -> Self {
        Self {
            inner: FrameRuntime::with_projector(
                initial_world(),
                form_reducer(),
                Box::new(FormProjector),
                Viewport { css_w: CANVAS_W as f64, css_h: CANVAS_H as f64, frame_w: CANVAS_W, frame_h: CANVAS_H },
                Box::new(FormRenderHost),
            ),
        }
    }
    pub fn click(&mut self, css_x: f64, css_y: f64) -> bool { self.inner.click(css_x, css_y) }
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

    fn node<'a>(f: &'a Frame, id: &str) -> &'a ProjectedNode {
        f.nodes.iter().find(|n| n.id == id).unwrap_or_else(|| panic!("no node {id}"))
    }
    fn click_node(rt: &mut FormScreenRuntime, id: &str) -> bool {
        let n = node(&rt.frame(), id).clone();
        rt.click((n.sx + n.sw.unwrap() / 2) as f64, (n.sy + n.sh.unwrap() / 2) as f64)
    }

    #[test]
    fn controls_are_cross_aligned_and_hittable() {
        let rt = FormScreenRuntime::new();
        let f = rt.frame();
        // the toggle is right of its label, vertically centered in the 42-tall row (cross 28 → +7)
        let row = node(&f, "notif");
        let tog = node(&f, "tog-notif");
        assert!(tog.sx > node(&f, "lbl-notif").sx, "control sits right of the label");
        assert_eq!(tog.sy, row.sy + (row.sh.unwrap() - 28) / 2, "toggle vertically centered by align");
        assert_eq!(tog.sh.unwrap(), 28);
        // segmented cells are equal-width inside the 240-wide group
        assert_eq!(node(&f, "seg:0").sw.unwrap(), 80);
    }

    #[test]
    fn toggle_checkbox_segmented_stepper_drive_state() {
        let mut rt = FormScreenRuntime::new();
        // dark_mode starts off → toggle on
        assert!(!node(&rt.frame(), "tog-dark").data["on"].as_bool().unwrap());
        assert!(click_node(&mut rt, "tog-dark"));
        assert!(node(&rt.frame(), "tog-dark").data["on"].as_bool().unwrap());
        // plan starts Pro (1) → pick Team (seg:2)
        assert!(node(&rt.frame(), "seg:1").data["selected"].as_bool().unwrap());
        assert!(click_node(&mut rt, "seg:2"));
        assert!(node(&rt.frame(), "seg:2").data["selected"].as_bool().unwrap());
        // stepper: seats 3 → +1 +1 = 5, then submit summarizes
        assert_eq!(node(&rt.frame(), "step:val").data["label"], "3");
        click_node(&mut rt, "step:inc");
        click_node(&mut rt, "step:inc");
        assert_eq!(node(&rt.frame(), "step:val").data["label"], "5");
        assert!(click_node(&mut rt, "submit"));
        let status = node(&rt.frame(), "status").data["label"].as_str().unwrap().to_string();
        assert!(status.contains("Team") && status.contains("5 seats") && status.contains("dark on"), "status: {status}");
    }

    #[test]
    fn stepper_clamps_and_reset_restores_defaults() {
        let mut rt = FormScreenRuntime::new();
        for _ in 0..5 { click_node(&mut rt, "step:dec"); } // 3 → clamp at 1
        assert_eq!(node(&rt.frame(), "step:val").data["label"], "1");
        click_node(&mut rt, "tog-notif"); // flip something
        assert!(click_node(&mut rt, "reset"));
        assert_eq!(node(&rt.frame(), "step:val").data["label"], "3");
        assert!(node(&rt.frame(), "tog-notif").data["on"].as_bool().unwrap());
        assert_eq!(node(&rt.frame(), "status").data["label"], "Reset to defaults");
    }

    #[test]
    fn deterministic_replay() {
        let log = [(680.0, 86.0), (560.0, 214.0), (610.0, 256.0), (560.0, 430.0)];
        let run = || {
            let mut rt = FormScreenRuntime::new();
            for (x, y) in log { rt.click(x, y); }
            (rt.frame_index(), rt.render_digest())
        };
        assert_eq!(run(), run());
    }
}
