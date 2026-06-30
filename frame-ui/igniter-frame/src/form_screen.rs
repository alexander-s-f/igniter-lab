//! LAB-FRAME-LAYOUT-VOCAB-P5 — a settings FORM that broadens the 2D widget vocabulary: toggles, a
//! checkbox, a segmented control, a stepper, and action buttons — each a row of `label (flex) +
//! control (fixed cross-size, cross-aligned)`. It exercises the new cross-axis alignment (`align` +
//! `CrossSize::Fixed`) so controls sit right-aligned and vertically centered without coordinate math.
//! All interactions are click-driven (no keyboard yet); state is world facts; deterministic + machine
//! free — the same `FrameRuntime`/layout path as the list and table screens.

use crate::host::Viewport;
use crate::layout::{solve, Align, LayoutBox, Size};
use crate::runtime::FrameRuntime;
use crate::widget_host::WidgetRenderHost;
use crate::{Frame, IntentReducer, ProjectedNode, Projector};
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
                        node(None, json!({ "kind": "note", "tone": "ok", "label": s }))
                    }
                    l if l.starts_with("lbl-") => node(None, json!({ "kind": "label", "label": label_for(l) })),
                    "tog-notif" => node(Some(json!({"action":"toggle","key":"notifications"})), json!({"kind":"toggle","on":flag(world,"notifications")})),
                    "tog-dark" => node(Some(json!({"action":"toggle","key":"dark_mode"})), json!({"kind":"toggle","on":flag(world,"dark_mode")})),
                    "chk-news" => node(Some(json!({"action":"toggle","key":"newsletter"})), json!({"kind":"checkbox","on":flag(world,"newsletter")})),
                    s if s.starts_with("seg:") => {
                        let i: i64 = s[4..].parse().unwrap_or(-1);
                        node(Some(json!({"action":"set_plan","value":i})),
                             json!({"kind":"segment","label":PLANS.get(i as usize).copied().unwrap_or(""),"selected":i==plan}))
                    }
                    "step:dec" => node(Some(json!({"action":"step","delta":-1})), json!({"kind":"stepper_btn","glyph":"−"})),
                    "step:inc" => node(Some(json!({"action":"step","delta":1})), json!({"kind":"stepper_btn","glyph":"+"})),
                    "step:val" => node(None, json!({"kind":"stepper_val","label":int(world,"seats").to_string()})),
                    "seg-plan" => node(None, json!({"kind":"panel","variant":"group"})),
                    "step-seats" => node(None, json!({"kind":"panel","variant":"group"})),
                    "reset" => node(Some(json!({"action":"reset"})), json!({"kind":"button","label":"Reset","tone":"neutral"})),
                    "submit" => node(Some(json!({"action":"submit"})), json!({"kind":"button","label":"Save changes","tone":"go"})),
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
                Box::new(WidgetRenderHost::new(CANVAS_W, CANVAS_H)),
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
