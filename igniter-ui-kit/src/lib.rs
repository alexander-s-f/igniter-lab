//! igniter-ui-kit — a proto UI-components kit (forms) over igniter-frame
//! (LAB-FRAME-UI-KIT-FORMS-P9).
//!
//! The point: author UI from a small declarative component vocabulary, not hand-rolled rect facts.
//! A `Form` (a vertical stack of `Component`s) compiles to state facts + projects to frame nodes;
//! input events route to component intents; field/checkbox/select state changes flow through an
//! `IntentReducer` (NOT the host); validation appears from state on submit. Same frame / digest /
//! lineage / deterministic-replay model as the 2D, 3D, and GUI domains; `default-features = false`
//! on `igniter_frame` → no `igniter-machine` in the core/browser path.
//!
//! Vocabulary: `Form`, `Label`, `Text`(input), `Select`, `Checkbox`, `Button` (a `Stack` is the
//! form body), plus auto `ValidationMessage` nodes. The host stays thin: a browser may catch DOM
//! keyboard events, but it only ROUTES them (`send("type", {char})`); the reducer owns the value.

use igniter_frame::host::Viewport;
use igniter_frame::runtime::FrameRuntime;
use igniter_frame::{Frame, IntentReducer, ProjectedNode, Projector, RenderHost};
use serde_json::{json, Map, Value};

pub mod binding;
pub mod composition;
pub mod view_artifact;

#[cfg(feature = "wasm")]
pub mod wasm;

const MARGIN: i64 = 20;
const PANEL_W: i64 = 360;
const CANVAS_W: i64 = 400;
const CANVAS_H: i64 = 460;
const GAP: i64 = 8;

// ── Component vocabulary (the authoring model) ──────────────────────────────────────────────────

/// A UI component. A `Form` body is a vertical `Stack` of these.
#[derive(Clone, Debug)]
pub enum Component {
    Label(String),
    Text { id: String, label: String, required: bool },
    Select { id: String, label: String, options: Vec<String>, required: bool },
    Checkbox { id: String, label: String },
    Button { id: String, label: String, action: String },
}

pub fn label(s: &str) -> Component {
    Component::Label(s.to_string())
}
pub fn text(id: &str, label: &str, required: bool) -> Component {
    Component::Text { id: id.to_string(), label: label.to_string(), required }
}
pub fn select(id: &str, label: &str, options: &[&str], required: bool) -> Component {
    Component::Select { id: id.to_string(), label: label.to_string(), options: options.iter().map(|s| s.to_string()).collect(), required }
}
pub fn checkbox(id: &str, label: &str) -> Component {
    Component::Checkbox { id: id.to_string(), label: label.to_string() }
}
pub fn button(id: &str, label: &str, action: &str) -> Component {
    Component::Button { id: id.to_string(), label: label.to_string(), action: action.to_string() }
}

/// A form: a title + a vertical stack of components.
#[derive(Clone, Debug)]
pub struct Form {
    pub title: String,
    pub body: Vec<Component>,
}

impl Form {
    /// The DX example: a Lead Intake form (close to SparkCRM/Igniter).
    pub fn lead_intake() -> Self {
        Form {
            title: "Lead Intake".to_string(),
            body: vec![
                label("New Lead"),
                text("name", "Name", true),
                text("phone", "Phone", true),
                select("source", "Source", &["web", "referral", "ad"], true),
                checkbox("qualified", "Qualified"),
                button("submit", "Submit", "submit"),
            ],
        }
    }

    /// Compile the component tree into initial STATE facts (one per stateful component) + a form
    /// meta fact. Layout/structure stays in the component tree; only mutable state is a fact.
    pub fn initial_world(&self) -> Vec<(String, Value)> {
        let mut w = Vec::new();
        for c in &self.body {
            match c {
                Component::Text { id, .. } => w.push((id.clone(), json!({ "kind": "text", "value": "", "focused": false }))),
                Component::Select { id, .. } => w.push((id.clone(), json!({ "kind": "select", "selected": -1 }))),
                Component::Checkbox { id, .. } => w.push((id.clone(), json!({ "kind": "checkbox", "checked": false }))),
                _ => {}
            }
        }
        w.push(("__form__".to_string(), json!({ "submitted": false, "ok": false, "errors": {} })));
        w
    }

    fn text_ids(&self) -> Vec<String> {
        self.body.iter().filter_map(|c| if let Component::Text { id, .. } = c { Some(id.clone()) } else { None }).collect()
    }
}

// ── Projection: component tree + state → frame nodes (a Projector) ──────────────────────────────

fn world_digest(world: &[(String, Value)]) -> String {
    let mut sorted = world.to_vec();
    sorted.sort_by(|a, b| a.0.cmp(&b.0));
    format!("sha256:{}", blake3::hash(serde_json::to_string(&sorted).unwrap_or_default().as_bytes()).to_hex())
}

/// Projects the form's component tree + current state into a vertical stack of frame nodes (boxes
/// carrying `{kind,label,value,focused,checked,error,…}` in `data`). A `Projector` — the runtime
/// is unchanged; only this strategy knows about components.
pub struct FormProjector {
    pub form: Form,
}

impl Projector for FormProjector {
    fn project(&self, world: &[(String, Value)], frame_index: u64, source_receipt_id: Option<String>) -> Frame {
        let st = |id: &str| world.iter().find(|(k, _)| k == id).map(|(_, v)| v.clone()).unwrap_or(json!({}));
        let form_meta = st("__form__");
        let errors = form_meta.get("errors").cloned().unwrap_or(json!({}));
        let err_for = |id: &str| errors.get(id).and_then(|e| e.as_str()).map(|s| s.to_string());

        let mut nodes = Vec::new();
        let mut y = MARGIN;
        let push = |nodes: &mut Vec<ProjectedNode>, y: &mut i64, id: String, h: i64, intent: Option<Value>, data: Value| {
            nodes.push(ProjectedNode {
                id,
                x: MARGIN as f64,
                y: *y as f64,
                z: 0.0,
                sx: MARGIN,
                sy: *y,
                intent,
                sw: Some(PANEL_W),
                sh: Some(h),
                data,
            });
            *y += h + GAP;
        };

        for (i, c) in self.form.body.iter().enumerate() {
            match c {
                Component::Label(txt) => {
                    push(&mut nodes, &mut y, format!("lbl:{}", i), 28, None, json!({ "kind": "label", "label": txt }));
                }
                Component::Text { id, label, .. } => {
                    let s = st(id);
                    push(&mut nodes, &mut y, id.clone(), 50, Some(json!({ "action": "focus" })), json!({
                        "kind": "text", "label": label,
                        "value": s.get("value").cloned().unwrap_or(json!("")),
                        "focused": s.get("focused").cloned().unwrap_or(json!(false)),
                    }));
                    if let Some(e) = err_for(id) {
                        push(&mut nodes, &mut y, format!("err:{}", id), 20, None, json!({ "kind": "validation", "label": e }));
                    }
                }
                Component::Select { id, label, options, .. } => {
                    let sel = st(id).get("selected").and_then(|v| v.as_i64()).unwrap_or(-1);
                    let shown = if sel >= 0 { options.get(sel as usize).cloned().unwrap_or_default() } else { "— select —".to_string() };
                    push(&mut nodes, &mut y, id.clone(), 50, Some(json!({ "action": "cycle" })), json!({
                        "kind": "select", "label": label, "value": shown,
                    }));
                    if let Some(e) = err_for(id) {
                        push(&mut nodes, &mut y, format!("err:{}", id), 20, None, json!({ "kind": "validation", "label": e }));
                    }
                }
                Component::Checkbox { id, label } => {
                    let checked = st(id).get("checked").and_then(|v| v.as_bool()).unwrap_or(false);
                    push(&mut nodes, &mut y, id.clone(), 40, Some(json!({ "action": "toggle" })), json!({
                        "kind": "checkbox", "label": label, "checked": checked,
                    }));
                }
                Component::Button { id, label, action } => {
                    push(&mut nodes, &mut y, id.clone(), 44, Some(json!({ "action": action })), json!({ "kind": "button", "label": label }));
                }
            }
        }

        if form_meta.get("submitted").and_then(|v| v.as_bool()).unwrap_or(false)
            && form_meta.get("ok").and_then(|v| v.as_bool()).unwrap_or(false)
        {
            push(&mut nodes, &mut y, "__banner__".to_string(), 32, None, json!({ "kind": "banner", "label": "\u{2713} lead submitted" }));
        }

        Frame { frame_index, world_digest: world_digest(world), source_receipt_id, nodes }
    }
}

// ── Render host (rects + labels + caret + checkbox + validation) ────────────────────────────────

fn esc(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;")
}

/// Renders the form nodes to SVG. Implements igniter-frame's `RenderHost` — the same boundary the
/// 2D/3D/GUI domains use.
pub struct FormRenderHost;

impl RenderHost for FormRenderHost {
    fn render(&self, frame: &Frame) -> String {
        let mut body = String::new();
        for n in &frame.nodes {
            let (w, h) = (n.sw.unwrap_or(0), n.sh.unwrap_or(0));
            let kind = n.data.get("kind").and_then(|v| v.as_str()).unwrap_or("");
            let lbl = n.data.get("label").and_then(|v| v.as_str()).unwrap_or("");
            match kind {
                "label" => body.push_str(&format!(
                    "  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"16\" font-weight=\"bold\" fill=\"#e6edf3\">{}</text>\n",
                    n.sx, n.sy + 18, esc(lbl)
                )),
                "text" | "select" => {
                    let focused = n.data.get("focused").and_then(|v| v.as_bool()).unwrap_or(false);
                    let value = n.data.get("value").and_then(|v| v.as_str()).unwrap_or("");
                    let border = if focused { "#1f6feb" } else { "#30363d" };
                    body.push_str(&format!(
                        "  <rect x=\"{}\" y=\"{}\" width=\"{}\" height=\"{}\" rx=\"6\" fill=\"#010409\" stroke=\"{}\"/>\n",
                        n.sx, n.sy, w, h, border
                    ));
                    body.push_str(&format!(
                        "  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"11\" fill=\"#8b949e\">{}</text>\n",
                        n.sx + 10, n.sy + 16, esc(lbl)
                    ));
                    let shown = if focused && kind == "text" { format!("{}\u{2502}", value) } else { value.to_string() };
                    let marker = if kind == "select" { "\u{25be} " } else { "" };
                    body.push_str(&format!(
                        "  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"15\" fill=\"#e6edf3\">{}{}</text>\n",
                        n.sx + 10, n.sy + 38, marker, esc(&shown)
                    ));
                }
                "checkbox" => {
                    let checked = n.data.get("checked").and_then(|v| v.as_bool()).unwrap_or(false);
                    body.push_str(&format!(
                        "  <rect x=\"{}\" y=\"{}\" width=\"{}\" height=\"{}\" rx=\"6\" fill=\"#161b22\" stroke=\"#30363d\"/>\n",
                        n.sx, n.sy, w, h
                    ));
                    body.push_str(&format!(
                        "  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"15\" fill=\"#e6edf3\">{} {}</text>\n",
                        n.sx + 12, n.sy + h / 2 + 5, if checked { "[x]" } else { "[ ]" }, esc(lbl)
                    ));
                }
                "button" => {
                    body.push_str(&format!(
                        "  <rect x=\"{}\" y=\"{}\" width=\"{}\" height=\"{}\" rx=\"6\" fill=\"#238636\" stroke=\"#2ea043\"/>\n",
                        n.sx, n.sy, w, h
                    ));
                    body.push_str(&format!(
                        "  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"15\" fill=\"#ffffff\" text-anchor=\"middle\">{}</text>\n",
                        n.sx + w / 2, n.sy + h / 2 + 5, esc(lbl)
                    ));
                }
                "validation" => body.push_str(&format!(
                    "  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"12\" fill=\"#f85149\">! {}</text>\n",
                    n.sx + 4, n.sy + 14, esc(lbl)
                )),
                "banner" => body.push_str(&format!(
                    "  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"15\" fill=\"#3fb950\">{}</text>\n",
                    n.sx, n.sy + 20, esc(lbl)
                )),
                _ => {}
            }
        }
        format!(
            "<svg viewBox=\"0 0 {} {}\" xmlns=\"http://www.w3.org/2000/svg\">\n  <rect width=\"{}\" height=\"{}\" fill=\"#0d1117\"/>\n{}</svg>\n",
            CANVAS_W, CANVAS_H, CANVAS_W, CANVAS_H, body
        )
    }
}

// ── Reducer: route component intents to state changes (NOT the host) ────────────────────────────

/// The form reducer: focus / type / backspace / toggle / cycle / submit. Validation on submit reads
/// the captured component structure (required fields). Pure `(intent, world) -> deltas`.
pub fn form_reducer(form: &Form) -> IntentReducer {
    let text_ids = form.text_ids();
    let required_text: Vec<String> = form.body.iter().filter_map(|c| match c {
        Component::Text { id, required: true, .. } => Some(id.clone()),
        _ => None,
    }).collect();
    let selects: Vec<(String, usize, bool)> = form.body.iter().filter_map(|c| match c {
        Component::Select { id, options, required, .. } => Some((id.clone(), options.len(), *required)),
        _ => None,
    }).collect();

    Box::new(move |intent, world| {
        let find = |id: &str| world.iter().find(|(k, _)| k == id).map(|(_, v)| v.clone());
        match intent.action.as_str() {
            "focus" => {
                let Some(target) = &intent.target else { return vec![] };
                // exactly one text field focused
                text_ids.iter().filter_map(|id| {
                    find(id).map(|mut v| {
                        v["focused"] = json!(id == target);
                        (id.clone(), v)
                    })
                }).collect()
            }
            "type" => {
                let ch = intent.params.get("char").and_then(|c| c.as_str()).unwrap_or("");
                if ch.is_empty() {
                    return vec![];
                }
                if let Some((id, v)) = world.iter().find(|(_, v)| v.get("kind").and_then(|k| k.as_str()) == Some("text") && v.get("focused").and_then(|f| f.as_bool()) == Some(true)) {
                    let cur = v.get("value").and_then(|s| s.as_str()).unwrap_or("");
                    if cur.chars().count() < 24 {
                        let mut nv = v.clone();
                        nv["value"] = json!(format!("{}{}", cur, ch));
                        return vec![(id.clone(), nv)];
                    }
                }
                vec![]
            }
            "backspace" => {
                if let Some((id, v)) = world.iter().find(|(_, v)| v.get("kind").and_then(|k| k.as_str()) == Some("text") && v.get("focused").and_then(|f| f.as_bool()) == Some(true)) {
                    let cur = v.get("value").and_then(|s| s.as_str()).unwrap_or("");
                    let mut chars = cur.chars().collect::<Vec<_>>();
                    chars.pop();
                    let mut nv = v.clone();
                    nv["value"] = json!(chars.into_iter().collect::<String>());
                    return vec![(id.clone(), nv)];
                }
                vec![]
            }
            "toggle" => {
                let Some(target) = &intent.target else { return vec![] };
                let Some(mut v) = find(target) else { return vec![] };
                if v.get("kind").and_then(|k| k.as_str()) != Some("checkbox") {
                    return vec![];
                }
                let checked = v.get("checked").and_then(|b| b.as_bool()).unwrap_or(false);
                v["checked"] = json!(!checked);
                vec![(target.clone(), v)]
            }
            "cycle" => {
                let Some(target) = &intent.target else { return vec![] };
                let Some((_, len, _)) = selects.iter().find(|(id, _, _)| id == target) else { return vec![] };
                let Some(mut v) = find(target) else { return vec![] };
                let sel = v.get("selected").and_then(|s| s.as_i64()).unwrap_or(-1);
                v["selected"] = json!((sel + 1).rem_euclid(*len as i64));
                vec![(target.clone(), v)]
            }
            "submit" => {
                let mut errors = Map::new();
                for id in &required_text {
                    let empty = find(id).and_then(|v| v.get("value").and_then(|s| s.as_str()).map(|s| s.is_empty())).unwrap_or(true);
                    if empty {
                        errors.insert(id.clone(), json!("required"));
                    }
                }
                for (id, _, required) in &selects {
                    if *required {
                        let sel = find(id).and_then(|v| v.get("selected").and_then(|s| s.as_i64())).unwrap_or(-1);
                        if sel < 0 {
                            errors.insert(id.clone(), json!("select one"));
                        }
                    }
                }
                let ok = errors.is_empty();
                vec![("__form__".to_string(), json!({ "submitted": true, "ok": ok, "errors": errors }))]
            }
            _ => vec![],
        }
    })
}

// ── Runtime ─────────────────────────────────────────────────────────────────────────────────────

/// The form runtime over igniter-frame's `FrameRuntime`. `click` routes pointer→component intent;
/// `key`/`backspace` route keystrokes to the focused field (the host catches DOM keys, the reducer
/// owns the value). Same render/digest/lineage/replay as every other domain.
pub struct FormRuntime {
    inner: FrameRuntime,
    form: Form,
}

impl FormRuntime {
    pub fn new(form: Form) -> Self {
        let inner = FrameRuntime::with_projector(
            form.initial_world(),
            form_reducer(&form),
            Box::new(FormProjector { form: form.clone() }),
            Viewport { css_w: CANVAS_W as f64, css_h: CANVAS_H as f64, frame_w: CANVAS_W, frame_h: CANVAS_H },
            Box::new(FormRenderHost),
        );
        Self { inner, form }
    }

    pub fn lead_intake() -> Self {
        Self::new(Form::lead_intake())
    }

    /// Build a form runtime from a `form`-layout ViewArtifact JSON (the portable authoring layer).
    pub fn from_artifact(json: &str) -> Result<Self, crate::view_artifact::ViewError> {
        Ok(Self::new(crate::view_artifact::compile_form(json)?))
    }

    pub fn click(&mut self, css_x: f64, css_y: f64) -> bool {
        self.inner.click(css_x, css_y)
    }

    /// Route a typed character to the focused field (host catches it; reducer applies it).
    pub fn key(&mut self, ch: &str) -> bool {
        self.inner.send("type", json!({ "char": ch }))
    }

    pub fn backspace(&mut self) -> bool {
        self.inner.send("backspace", json!(null))
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
        *self = Self::new(self.form.clone());
    }
}
