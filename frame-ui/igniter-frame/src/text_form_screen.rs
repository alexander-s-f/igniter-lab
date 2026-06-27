//! LAB-FRAME-LAYOUT-VOCAB-P6 — keyboard TEXT ENTRY: a contact form whose fields you click to focus
//! and then TYPE into. Completes the "form" story — the controls are no longer click-only. It needs
//! NO runtime change: a click derives a `focus` intent (hit-test) and a keystroke is routed as a
//! SYSTEM intent through `FrameRuntime::send("type"/"backspace"/"submit", …)` (no hit-test), so the
//! reducer edits whichever field `__focus__` names. Deterministic + machine-free, same frame path.

use crate::host::Viewport;
use crate::layout::{LayoutBox, Size, solve};
use crate::runtime::FrameRuntime;
use crate::{Frame, IntentReducer, ProjectedNode, Projector, RenderHost};
use serde_json::{json, Value};

const CANVAS_W: i64 = 720;
const CANVAS_H: i64 = 460;
const MAX_LEN: usize = 40;

/// Fields, in order: (fact id, label, placeholder).
const FIELDS: [(&str, &str, &str); 3] = [
    ("field:name", "Name", "Your name"),
    ("field:email", "Email", "you@example.com"),
    ("field:msg", "Message", "Say something…"),
];

pub fn initial_world() -> Vec<(String, Value)> {
    let mut w: Vec<(String, Value)> = FIELDS.iter().map(|(id, _, _)| (id.to_string(), json!(""))).collect();
    w.push(("__focus__".into(), json!("")));
    w.push(("__status__".into(), json!("")));
    w
}

fn s<'a>(world: &'a [(String, Value)], k: &str) -> &'a str {
    world.iter().find(|(key, _)| key == k).and_then(|(_, v)| v.as_str()).unwrap_or("")
}

fn world_digest(world: &[(String, Value)]) -> String {
    let mut sorted = world.to_vec();
    sorted.sort_by(|a, b| a.0.cmp(&b.0));
    format!("sha256:{}", blake3::hash(serde_json::to_string(&sorted).unwrap_or_default().as_bytes()).to_hex())
}

pub struct TextFormProjector;

impl Projector for TextFormProjector {
    fn project(&self, world: &[(String, Value)], frame_index: u64, source_receipt_id: Option<String>) -> Frame {
        let focus = s(world, "__focus__");

        let mut children = vec![LayoutBox::leaf("title", Size::Fixed(28))];
        for (id, _, _) in FIELDS {
            let key = &id["field:".len()..];
            let input_main = if key == "msg" { Size::Flex(1) } else { Size::Fixed(36) };
            children.push(
                LayoutBox::col(
                    format!("fld-{key}"),
                    if key == "msg" { Size::Flex(1) } else { Size::Fixed(58) },
                    vec![
                        LayoutBox::leaf(format!("lbl-{key}"), Size::Fixed(16)),
                        LayoutBox::leaf(format!("in-{key}"), input_main),
                    ],
                )
                .gap(5),
            );
        }
        children.push(
            LayoutBox::row(
                "actions",
                Size::Fixed(44),
                vec![LayoutBox::leaf("clear", Size::Flex(1)), LayoutBox::leaf("submit", Size::Flex(2))],
            )
            .gap(10),
        );
        children.push(LayoutBox::leaf("status", Size::Fixed(24)));

        let tree = LayoutBox::col("form", Size::Fixed(0), children).pad(22).gap(14);

        let meta = |key: &str| FIELDS.iter().find(|(id, _, _)| &id["field:".len()..] == key);

        let nodes: Vec<ProjectedNode> = solve(&tree, 0, 0, CANVAS_W, CANVAS_H)
            .iter()
            .map(|r| {
                let id = r.id.as_str();
                let node = |intent: Option<Value>, data: Value| ProjectedNode::from_rect(r, intent, data);
                if id == "title" {
                    node(None, json!({ "kind": "title", "label": "Contact us" }))
                } else if id == "status" {
                    node(None, json!({ "kind": "status", "label": s(world, "__status__") }))
                } else if let Some(key) = id.strip_prefix("lbl-") {
                    node(None, json!({ "kind": "label", "label": meta(key).map(|m| m.1).unwrap_or("") }))
                } else if let Some(key) = id.strip_prefix("in-") {
                    let field = format!("field:{key}");
                    let val = s(world, &field);
                    node(
                        Some(json!({ "action": "focus", "field": field.clone() })),
                        json!({ "kind": "input", "value": val, "placeholder": meta(key).map(|m| m.2).unwrap_or(""),
                                "focused": focus == field, "multiline": key == "msg" }),
                    )
                } else if id == "clear" {
                    node(Some(json!({ "action": "clear" })), json!({ "kind": "btn", "label": "Clear", "tone": "neutral" }))
                } else if id == "submit" {
                    node(Some(json!({ "action": "submit" })), json!({ "kind": "btn", "label": "Send message", "tone": "go" }))
                } else {
                    node(None, json!({ "kind": "none" }))
                }
            })
            .collect();

        Frame { frame_index, world_digest: world_digest(world), source_receipt_id, nodes }
    }
}

pub fn text_form_reducer() -> IntentReducer {
    Box::new(|intent, world| {
        let focus = s(world, "__focus__").to_string();
        let is_field = |f: &str| FIELDS.iter().any(|(id, _, _)| *id == f);
        let edit_focused = |f: &dyn Fn(&str) -> String| -> Vec<(String, Value)> {
            if is_field(&focus) {
                let next = f(s(world, &focus));
                vec![(focus.clone(), json!(next)), ("__status__".into(), json!(""))]
            } else {
                vec![]
            }
        };
        match intent.action.as_str() {
            "focus" => intent.params.get("field").and_then(|v| v.as_str())
                .filter(|f| is_field(f))
                .map(|f| vec![("__focus__".to_string(), json!(f))])
                .unwrap_or_default(),
            "type" => {
                let ch = intent.params.get("char").and_then(|v| v.as_str()).unwrap_or("");
                if ch.is_empty() { return vec![]; }
                edit_focused(&|cur| {
                    if cur.chars().count() >= MAX_LEN { cur.to_string() } else { format!("{cur}{ch}") }
                })
            }
            "backspace" => edit_focused(&|cur| {
                let mut c: Vec<char> = cur.chars().collect();
                c.pop();
                c.into_iter().collect()
            }),
            "clear" => {
                let mut out: Vec<(String, Value)> = FIELDS.iter().map(|(id, _, _)| (id.to_string(), json!(""))).collect();
                out.push(("__status__".into(), json!("Cleared")));
                out
            }
            "submit" => {
                let summary = format!(
                    "Sent ✓ — name “{}”, email “{}”, {} chars of message",
                    s(world, "field:name"), s(world, "field:email"), s(world, "field:msg").chars().count()
                );
                vec![("__status__".into(), json!(summary))]
            }
            _ => vec![],
        }
    })
}

fn esc(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;")
}

pub struct TextFormRenderHost;

impl RenderHost for TextFormRenderHost {
    fn render(&self, frame: &Frame) -> String {
        let mut body = String::new();
        for n in &frame.nodes {
            let (x, y, w, h) = (n.sx, n.sy, n.sw.unwrap_or(0), n.sh.unwrap_or(0));
            let kind = n.data.get("kind").and_then(|v| v.as_str()).unwrap_or("");
            let lbl = n.data.get("label").and_then(|v| v.as_str()).unwrap_or("");
            match kind {
                "title" => body.push_str(&format!("  <text x=\"{x}\" y=\"{}\" font-family=\"monospace\" font-size=\"17\" font-weight=\"bold\" fill=\"#e6edf3\">{}</text>\n", y + 20, esc(lbl))),
                "label" => body.push_str(&format!("  <text x=\"{x}\" y=\"{}\" font-family=\"monospace\" font-size=\"12\" fill=\"#8b949e\">{}</text>\n", y + 12, esc(lbl))),
                "status" => body.push_str(&format!("  <text x=\"{x}\" y=\"{}\" font-family=\"monospace\" font-size=\"12\" fill=\"#3fb950\">{}</text>\n", y + h / 2 + 4, esc(lbl))),
                "input" => {
                    let focused = n.data.get("focused").and_then(|v| v.as_bool()).unwrap_or(false);
                    let val = n.data.get("value").and_then(|v| v.as_str()).unwrap_or("");
                    let stroke = if focused { "#1f6feb" } else { "#30363d" };
                    body.push_str(&format!("  <rect x=\"{x}\" y=\"{y}\" width=\"{w}\" height=\"{h}\" rx=\"6\" fill=\"#0d1117\" stroke=\"{stroke}\"/>\n"));
                    let ty = y + 22; // text baseline near the top (so multiline message reads top-down)
                    if val.is_empty() && !focused {
                        let ph = n.data.get("placeholder").and_then(|v| v.as_str()).unwrap_or("");
                        body.push_str(&format!("  <text x=\"{}\" y=\"{ty}\" font-family=\"monospace\" font-size=\"13\" fill=\"#484f58\">{}</text>\n", x + 10, esc(ph)));
                    } else {
                        let caret = if focused { "▏" } else { "" };
                        body.push_str(&format!("  <text x=\"{}\" y=\"{ty}\" font-family=\"monospace\" font-size=\"13\" fill=\"#e6edf3\">{}{caret}</text>\n", x + 10, esc(val)));
                    }
                }
                "btn" => {
                    let (fill, st) = if n.data.get("tone").and_then(|t| t.as_str()) == Some("go") { ("#238636", "#2ea043") } else { ("#21262d", "#30363d") };
                    body.push_str(&format!("  <rect x=\"{x}\" y=\"{y}\" width=\"{w}\" height=\"{h}\" rx=\"8\" fill=\"{fill}\" stroke=\"{st}\"/>\n"));
                    body.push_str(&format!("  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"14\" fill=\"#f0f6fc\" text-anchor=\"middle\">{}</text>\n", x + w / 2, y + h / 2 + 5, esc(lbl)));
                }
                _ => {}
            }
        }
        format!("<svg viewBox=\"0 0 {CANVAS_W} {CANVAS_H}\" xmlns=\"http://www.w3.org/2000/svg\">\n  <rect width=\"{CANVAS_W}\" height=\"{CANVAS_H}\" fill=\"#010409\"/>\n{body}</svg>\n")
    }
}

pub struct TextFormRuntime {
    inner: FrameRuntime,
}

impl Default for TextFormRuntime {
    fn default() -> Self {
        Self::new()
    }
}

impl TextFormRuntime {
    pub fn new() -> Self {
        Self {
            inner: FrameRuntime::with_projector(
                initial_world(),
                text_form_reducer(),
                Box::new(TextFormProjector),
                Viewport { css_w: CANVAS_W as f64, css_h: CANVAS_H as f64, frame_w: CANVAS_W, frame_h: CANVAS_H },
                Box::new(TextFormRenderHost),
            ),
        }
    }

    pub fn click(&mut self, css_x: f64, css_y: f64) -> bool {
        self.inner.click(css_x, css_y)
    }

    /// Route a browser key into the focused field. Printable single characters are typed; `Backspace`
    /// deletes; `Enter` submits. Modifier/navigation keys (multi-char names) are ignored. Returns
    /// `true` iff state changed (so the host can `preventDefault`).
    pub fn key(&mut self, k: &str) -> bool {
        match k {
            "Backspace" => self.inner.send("backspace", json!(null)),
            "Enter" => self.inner.send("submit", json!(null)),
            ch if ch.chars().count() == 1 => self.inner.send("type", json!({ "char": ch })),
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

    fn node<'a>(f: &'a Frame, id: &str) -> &'a ProjectedNode {
        f.nodes.iter().find(|n| n.id == id).unwrap_or_else(|| panic!("no node {id}"))
    }
    fn input_val(rt: &TextFormRuntime, key: &str) -> String {
        node(&rt.frame(), &format!("in-{key}")).data["value"].as_str().unwrap().to_string()
    }
    fn focus_field(rt: &mut TextFormRuntime, key: &str) -> bool {
        let n = node(&rt.frame(), &format!("in-{key}")).clone();
        rt.click((n.sx + n.sw.unwrap() / 2) as f64, (n.sy + n.sh.unwrap() / 2) as f64)
    }
    fn typ(rt: &mut TextFormRuntime, text: &str) {
        for c in text.chars() { rt.key(&c.to_string()); }
    }

    #[test]
    fn click_focuses_then_typing_lands_in_that_field() {
        let mut rt = TextFormRuntime::new();
        // typing with nothing focused is a no-op
        assert!(!rt.key("a"));
        assert!(focus_field(&mut rt, "name"));
        assert!(node(&rt.frame(), "in-name").data["focused"].as_bool().unwrap());
        typ(&mut rt, "Ada");
        assert_eq!(input_val(&rt, "name"), "Ada");
        assert_eq!(input_val(&rt, "email"), ""); // other fields untouched
        // refocus to email, type there
        focus_field(&mut rt, "email");
        typ(&mut rt, "ada@x.io");
        assert_eq!(input_val(&rt, "email"), "ada@x.io");
        assert_eq!(input_val(&rt, "name"), "Ada");
    }

    #[test]
    fn backspace_clear_and_submit() {
        let mut rt = TextFormRuntime::new();
        focus_field(&mut rt, "name");
        typ(&mut rt, "GraceX");
        assert!(rt.key("Backspace"));
        assert_eq!(input_val(&rt, "name"), "Grace");
        focus_field(&mut rt, "email");
        typ(&mut rt, "g@h.io");
        // Enter submits → status summarizes
        assert!(rt.key("Enter"));
        let status = node(&rt.frame(), "status").data["label"].as_str().unwrap().to_string();
        assert!(status.contains("Grace") && status.contains("g@h.io"), "status: {status}");
        // Clear wipes all fields (global — no focus needed)
        let n = node(&rt.frame(), "clear").clone();
        rt.click((n.sx + n.sw.unwrap() / 2) as f64, (n.sy + n.sh.unwrap() / 2) as f64);
        assert_eq!(input_val(&rt, "name"), "");
        assert_eq!(input_val(&rt, "email"), "");
    }

    #[test]
    fn input_is_length_capped_and_ignores_modifier_keys() {
        let mut rt = TextFormRuntime::new();
        focus_field(&mut rt, "name");
        for _ in 0..60 { rt.key("z"); }
        assert_eq!(input_val(&rt, "name").chars().count(), MAX_LEN);
        // multi-char keys (Shift, ArrowLeft, Tab) are ignored
        assert!(!rt.key("Shift"));
        assert!(!rt.key("ArrowLeft"));
    }

    #[test]
    fn deterministic_replay_of_focus_and_typing() {
        let run = || {
            let mut rt = TextFormRuntime::new();
            focus_field(&mut rt, "name");
            typ(&mut rt, "Hi");
            focus_field(&mut rt, "email");
            typ(&mut rt, "a@b.c");
            rt.key("Enter");
            (rt.frame_index(), rt.render_digest())
        };
        assert_eq!(run(), run());
    }
}
