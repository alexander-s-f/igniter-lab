//! Composable screens (LAB-FRAME-UI-KIT-COMPOSITION-P10): a `Workbench` of nested panels
//! (Sidebar[List] / Main[Form] / Inspector[KeyValuePanel]) over igniter-frame. Proves the
//! screen-composition DX before any IDE: nested component tree → frame nodes, multi-region layout,
//! stable ids, nested event routing, focus survival across layout changes, scoped (per-lead)
//! validation, selection driving another panel, deterministic replay. Same runtime/ports as P9; no
//! machine in the core path.

use igniter_frame::host::Viewport;
use igniter_frame::runtime::FrameRuntime;
use igniter_frame::{Frame, IntentReducer, ProjectedNode, Projector, RenderHost};
use serde_json::{json, Map, Value};

const CANVAS_W: i64 = 720;
const CANVAS_H: i64 = 440;
// columns (x, width)
const SIDEBAR: (i64, i64) = (16, 180);
const MAIN: (i64, i64) = (212, 264);
const INSPECTOR: (i64, i64) = (492, 212);
const PANEL_Y: i64 = 12;
const PANEL_H: i64 = 416;
const BODY_TOP: i64 = 48;

// ── Vocabulary / structure ──────────────────────────────────────────────────────────────────────

#[derive(Clone)]
pub enum FieldKind {
    Text,
    Select(Vec<String>),
    Checkbox,
}

#[derive(Clone)]
pub struct FieldSpec {
    pub id: String,
    pub label: String,
    pub kind: FieldKind,
    pub required: bool,
}

/// A workbench: a list of selectable records (sidebar) + a per-record form (main) + a derived
/// key/value inspector. The structure is authored; only mutable state is a fact.
#[derive(Clone)]
pub struct Workbench {
    pub leads: Vec<String>,
    pub fields: Vec<FieldSpec>,
}

impl Workbench {
    /// The DX example: a lead-review workbench.
    pub fn lead_review() -> Self {
        Workbench {
            leads: vec!["Ada".into(), "Grace".into(), "Linus".into()],
            fields: vec![
                FieldSpec { id: "priority".into(), label: "Priority".into(), kind: FieldKind::Text, required: true },
                FieldSpec { id: "stage".into(), label: "Stage".into(), kind: FieldKind::Select(vec!["new".into(), "qualified".into(), "won".into()]), required: true },
                FieldSpec { id: "hot".into(), label: "Hot lead".into(), kind: FieldKind::Checkbox, required: false },
            ],
        }
    }

    /// Compile to initial STATE facts: one per (lead, field), + selection + focus.
    pub fn initial_world(&self) -> Vec<(String, Value)> {
        let mut w = Vec::new();
        for lead in &self.leads {
            for f in &self.fields {
                let id = format!("fld:{}:{}", lead, f.id);
                let v = match &f.kind {
                    FieldKind::Text => json!({ "kind": "text", "value": "" }),
                    FieldKind::Select(_) => json!({ "kind": "select", "selected": -1 }),
                    FieldKind::Checkbox => json!({ "kind": "checkbox", "checked": false }),
                };
                w.push((id, v));
            }
        }
        w.push(("__selection__".into(), json!({ "lead": self.leads[0] })));
        w.push(("__focus__".into(), json!({ "id": Value::Null })));
        w
    }
}

/// `fld:<lead>:<field>` → the lead part (for focus-scope checks).
fn lead_of(field_id: &str) -> Option<&str> {
    field_id.strip_prefix("fld:").and_then(|r| r.split(':').next())
}

// ── Projection: nested tree + state → frame nodes ───────────────────────────────────────────────

fn world_digest(world: &[(String, Value)]) -> String {
    let mut sorted = world.to_vec();
    sorted.sort_by(|a, b| a.0.cmp(&b.0));
    format!("sha256:{}", blake3::hash(serde_json::to_string(&sorted).unwrap_or_default().as_bytes()).to_hex())
}

pub struct WorkbenchProjector {
    pub wb: Workbench,
}

impl WorkbenchProjector {
    fn node(id: String, x: i64, y: i64, w: i64, h: i64, intent: Option<Value>, data: Value) -> ProjectedNode {
        ProjectedNode { id, x: x as f64, y: y as f64, z: 0.0, sx: x, sy: y, intent, sw: Some(w), sh: Some(h), data }
    }
}

impl Projector for WorkbenchProjector {
    fn project(&self, world: &[(String, Value)], frame_index: u64, source_receipt_id: Option<String>) -> Frame {
        let st = |id: &str| world.iter().find(|(k, _)| k == id).map(|(_, v)| v.clone()).unwrap_or(json!({}));
        let selected = st("__selection__").get("lead").and_then(|v| v.as_str()).unwrap_or("").to_string();
        let focus_id = st("__focus__").get("id").and_then(|v| v.as_str()).map(|s| s.to_string());
        let errors = st(&format!("err:{}", selected));
        let err_for = |fid: &str| errors.get(fid).and_then(|e| e.as_str()).map(|s| s.to_string());

        let mut nodes: Vec<ProjectedNode> = Vec::new();

        // panels first (background; innermost hit-test routes clicks to children)
        nodes.push(Self::node("panel:sidebar".into(), SIDEBAR.0, PANEL_Y, SIDEBAR.1, PANEL_H, None, json!({ "kind": "panel", "label": "Leads" })));
        nodes.push(Self::node("panel:main".into(), MAIN.0, PANEL_Y, MAIN.1, PANEL_H, None, json!({ "kind": "panel", "label": format!("Lead · {}", selected) })));
        nodes.push(Self::node("panel:inspector".into(), INSPECTOR.0, PANEL_Y, INSPECTOR.1, PANEL_H, None, json!({ "kind": "panel", "label": "Details" })));

        // sidebar list
        let mut y = BODY_TOP;
        for lead in &self.wb.leads {
            nodes.push(Self::node(
                format!("lead:{}", lead),
                SIDEBAR.0 + 8, y, SIDEBAR.1 - 16, 34,
                Some(json!({ "action": "select" })),
                json!({ "kind": "listitem", "label": lead, "selected": lead == &selected }),
            ));
            y += 40;
        }

        // main form (the SELECTED lead's fields)
        let mut my = BODY_TOP;
        let (mx, mw) = (MAIN.0 + 8, MAIN.1 - 16);
        for f in &self.wb.fields {
            let fid = format!("fld:{}:{}", selected, f.id);
            let s = st(&fid);
            match &f.kind {
                FieldKind::Text => {
                    nodes.push(Self::node(fid.clone(), mx, my, mw, 44, Some(json!({ "action": "focus" })), json!({
                        "kind": "text", "label": f.label,
                        "value": s.get("value").cloned().unwrap_or(json!("")),
                        "focused": focus_id.as_deref() == Some(fid.as_str()),
                        "error": err_for(&f.id),
                    })));
                    my += 56;
                }
                FieldKind::Select(opts) => {
                    let sel = s.get("selected").and_then(|v| v.as_i64()).unwrap_or(-1);
                    let shown = if sel >= 0 { opts.get(sel as usize).cloned().unwrap_or_default() } else { "— select —".to_string() };
                    nodes.push(Self::node(fid.clone(), mx, my, mw, 44, Some(json!({ "action": "cycle" })), json!({
                        "kind": "select", "label": f.label, "value": shown, "error": err_for(&f.id),
                    })));
                    my += 56;
                }
                FieldKind::Checkbox => {
                    let checked = s.get("checked").and_then(|v| v.as_bool()).unwrap_or(false);
                    nodes.push(Self::node(fid.clone(), mx, my, mw, 36, Some(json!({ "action": "toggle" })), json!({
                        "kind": "checkbox", "label": f.label, "checked": checked,
                    })));
                    my += 44;
                }
            }
        }
        nodes.push(Self::node("act:submit".into(), mx, my, mw, 40, Some(json!({ "action": "submit" })), json!({ "kind": "button", "label": "Submit" })));

        // inspector: key/value derived from the selected lead's state (read-only)
        let mut iy = BODY_TOP;
        let (ix, iw) = (INSPECTOR.0 + 8, INSPECTOR.1 - 16);
        let kv = |nodes: &mut Vec<ProjectedNode>, iy: &mut i64, key: &str, val: String| {
            nodes.push(Self::node(format!("kv:{}", key), ix, *iy, iw, 24, None, json!({ "kind": "kv", "label": format!("{}: {}", key, val) })));
            *iy += 28;
        };
        kv(&mut nodes, &mut iy, "lead", selected.clone());
        for f in &self.wb.fields {
            let s = st(&format!("fld:{}:{}", selected, f.id));
            let val = match &f.kind {
                FieldKind::Text => s.get("value").and_then(|v| v.as_str()).unwrap_or("").to_string(),
                FieldKind::Select(opts) => {
                    let sel = s.get("selected").and_then(|v| v.as_i64()).unwrap_or(-1);
                    if sel >= 0 { opts.get(sel as usize).cloned().unwrap_or_default() } else { "—".to_string() }
                }
                FieldKind::Checkbox => if s.get("checked").and_then(|v| v.as_bool()).unwrap_or(false) { "yes".into() } else { "no".into() },
            };
            kv(&mut nodes, &mut iy, &f.id, val);
        }
        let err_count = errors.as_object().map(|m| m.len()).unwrap_or(0);
        kv(&mut nodes, &mut iy, "errors", err_count.to_string());

        Frame { frame_index, world_digest: world_digest(world), source_receipt_id, nodes }
    }
}

// ── Render host ─────────────────────────────────────────────────────────────────────────────────

fn esc(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;")
}

pub struct WorkbenchRenderHost;

impl RenderHost for WorkbenchRenderHost {
    fn render(&self, frame: &Frame) -> String {
        let mut body = String::new();
        for n in &frame.nodes {
            let (w, h) = (n.sw.unwrap_or(0), n.sh.unwrap_or(0));
            let kind = n.data.get("kind").and_then(|v| v.as_str()).unwrap_or("");
            let lbl = n.data.get("label").and_then(|v| v.as_str()).unwrap_or("");
            match kind {
                "panel" => {
                    body.push_str(&format!("  <rect x=\"{}\" y=\"{}\" width=\"{}\" height=\"{}\" rx=\"8\" fill=\"#0d1117\" stroke=\"#30363d\"/>\n", n.sx, n.sy, w, h));
                    body.push_str(&format!("  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"13\" font-weight=\"bold\" fill=\"#8b949e\">{}</text>\n", n.sx + 12, n.sy + 22, esc(lbl)));
                }
                "listitem" => {
                    let sel = n.data.get("selected").and_then(|v| v.as_bool()).unwrap_or(false);
                    let fill = if sel { "#1f6feb" } else { "#161b22" };
                    body.push_str(&format!("  <rect x=\"{}\" y=\"{}\" width=\"{}\" height=\"{}\" rx=\"6\" fill=\"{}\" stroke=\"#30363d\"/>\n", n.sx, n.sy, w, h, fill));
                    body.push_str(&format!("  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"14\" fill=\"#e6edf3\">{}</text>\n", n.sx + 12, n.sy + h / 2 + 5, esc(lbl)));
                }
                "text" | "select" => {
                    let focused = n.data.get("focused").and_then(|v| v.as_bool()).unwrap_or(false);
                    let value = n.data.get("value").and_then(|v| v.as_str()).unwrap_or("");
                    let border = if focused { "#1f6feb" } else { "#30363d" };
                    body.push_str(&format!("  <rect x=\"{}\" y=\"{}\" width=\"{}\" height=\"{}\" rx=\"6\" fill=\"#010409\" stroke=\"{}\"/>\n", n.sx, n.sy, w, h, border));
                    body.push_str(&format!("  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"10\" fill=\"#8b949e\">{}</text>\n", n.sx + 8, n.sy + 14, esc(lbl)));
                    let shown = if focused && kind == "text" { format!("{}\u{2502}", value) } else { value.to_string() };
                    let marker = if kind == "select" { "\u{25be} " } else { "" };
                    body.push_str(&format!("  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"14\" fill=\"#e6edf3\">{}{}</text>\n", n.sx + 8, n.sy + 34, marker, esc(&shown)));
                    if let Some(e) = n.data.get("error").and_then(|v| v.as_str()) {
                        body.push_str(&format!("  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"10\" fill=\"#f85149\">! {}</text>\n", n.sx + 2, n.sy + h + 10, esc(e)));
                    }
                }
                "checkbox" => {
                    let checked = n.data.get("checked").and_then(|v| v.as_bool()).unwrap_or(false);
                    body.push_str(&format!("  <rect x=\"{}\" y=\"{}\" width=\"{}\" height=\"{}\" rx=\"6\" fill=\"#161b22\" stroke=\"#30363d\"/>\n", n.sx, n.sy, w, h));
                    body.push_str(&format!("  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"14\" fill=\"#e6edf3\">{} {}</text>\n", n.sx + 10, n.sy + h / 2 + 5, if checked { "[x]" } else { "[ ]" }, esc(lbl)));
                }
                "button" => {
                    body.push_str(&format!("  <rect x=\"{}\" y=\"{}\" width=\"{}\" height=\"{}\" rx=\"6\" fill=\"#238636\" stroke=\"#2ea043\"/>\n", n.sx, n.sy, w, h));
                    body.push_str(&format!("  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"14\" fill=\"#fff\" text-anchor=\"middle\">{}</text>\n", n.sx + w / 2, n.sy + h / 2 + 5, esc(lbl)));
                }
                "kv" => body.push_str(&format!("  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"13\" fill=\"#9da7b3\">{}</text>\n", n.sx, n.sy + 16, esc(lbl))),
                _ => {}
            }
        }
        format!(
            "<svg viewBox=\"0 0 {} {}\" xmlns=\"http://www.w3.org/2000/svg\">\n  <rect width=\"{}\" height=\"{}\" fill=\"#010409\"/>\n{}</svg>\n",
            CANVAS_W, CANVAS_H, CANVAS_W, CANVAS_H, body
        )
    }
}

// ── Reducer: nested event routing + scoped validation + focus scoping ───────────────────────────

pub fn workbench_reducer(wb: &Workbench) -> IntentReducer {
    let wb = wb.clone();
    Box::new(move |intent, world| {
        let find = |id: &str| world.iter().find(|(k, _)| k == id).map(|(_, v)| v.clone());
        let selected = || world.iter().find(|(k, _)| k == "__selection__").and_then(|(_, v)| v.get("lead").and_then(|l| l.as_str()).map(|s| s.to_string())).unwrap_or_default();
        let focused_id = || world.iter().find(|(k, _)| k == "__focus__").and_then(|(_, v)| v.get("id").and_then(|i| i.as_str()).map(|s| s.to_string()));

        match intent.action.as_str() {
            "select" => {
                let Some(target) = &intent.target else { return vec![] };
                let lead = target.strip_prefix("lead:").unwrap_or(target).to_string();
                let mut deltas = vec![("__selection__".to_string(), json!({ "lead": lead.clone() }))];
                // focus survives only if the focused field still belongs to the (new) selected lead;
                // otherwise the focused component no longer exists on screen → clear focus
                if let Some(fid) = focused_id() {
                    if lead_of(&fid) != Some(lead.as_str()) {
                        deltas.push(("__focus__".to_string(), json!({ "id": Value::Null })));
                    }
                }
                deltas
            }
            "focus" => {
                let Some(target) = &intent.target else { return vec![] };
                vec![("__focus__".to_string(), json!({ "id": target }))]
            }
            "type" => {
                let ch = intent.params.get("char").and_then(|c| c.as_str()).unwrap_or("");
                let Some(fid) = focused_id() else { return vec![] };
                if ch.is_empty() {
                    return vec![];
                }
                if let Some(v) = find(&fid) {
                    if v.get("kind").and_then(|k| k.as_str()) == Some("text") {
                        let cur = v.get("value").and_then(|s| s.as_str()).unwrap_or("");
                        if cur.chars().count() < 18 {
                            let mut nv = v.clone();
                            nv["value"] = json!(format!("{}{}", cur, ch));
                            return vec![(fid, nv)];
                        }
                    }
                }
                vec![]
            }
            "backspace" => {
                let Some(fid) = focused_id() else { return vec![] };
                if let Some(v) = find(&fid) {
                    if v.get("kind").and_then(|k| k.as_str()) == Some("text") {
                        let mut chars: Vec<char> = v.get("value").and_then(|s| s.as_str()).unwrap_or("").chars().collect();
                        chars.pop();
                        let mut nv = v.clone();
                        nv["value"] = json!(chars.into_iter().collect::<String>());
                        return vec![(fid, nv)];
                    }
                }
                vec![]
            }
            "toggle" => {
                let Some(target) = &intent.target else { return vec![] };
                let Some(mut v) = find(target) else { return vec![] };
                if v.get("kind").and_then(|k| k.as_str()) != Some("checkbox") {
                    return vec![];
                }
                let c = v.get("checked").and_then(|b| b.as_bool()).unwrap_or(false);
                v["checked"] = json!(!c);
                vec![(target.clone(), v)]
            }
            "cycle" => {
                let Some(target) = &intent.target else { return vec![] };
                // length from the field spec
                let field = target.rsplit(':').next().unwrap_or("");
                let len = wb.fields.iter().find_map(|f| match &f.kind {
                    FieldKind::Select(o) if f.id == field => Some(o.len()),
                    _ => None,
                });
                let Some(len) = len else { return vec![] };
                let Some(mut v) = find(target) else { return vec![] };
                let sel = v.get("selected").and_then(|s| s.as_i64()).unwrap_or(-1);
                v["selected"] = json!((sel + 1).rem_euclid(len as i64));
                vec![(target.clone(), v)]
            }
            "submit" => {
                let lead = selected();
                let mut errors = Map::new();
                for f in &wb.fields {
                    if !f.required {
                        continue;
                    }
                    let fid = format!("fld:{}:{}", lead, f.id);
                    let bad = match &f.kind {
                        FieldKind::Text => find(&fid).and_then(|v| v.get("value").and_then(|s| s.as_str()).map(|s| s.is_empty())).unwrap_or(true),
                        FieldKind::Select(_) => find(&fid).and_then(|v| v.get("selected").and_then(|s| s.as_i64())).unwrap_or(-1) < 0,
                        FieldKind::Checkbox => false,
                    };
                    if bad {
                        errors.insert(f.id.clone(), json!(if matches!(f.kind, FieldKind::Select(_)) { "select one" } else { "required" }));
                    }
                }
                // scoped per lead — NOT a global string
                vec![(format!("err:{}", lead), Value::Object(errors))]
            }
            _ => vec![],
        }
    })
}

// ── Runtime ─────────────────────────────────────────────────────────────────────────────────────

pub struct WorkbenchRuntime {
    inner: FrameRuntime,
    wb: Workbench,
}

impl WorkbenchRuntime {
    pub fn new(wb: Workbench) -> Self {
        let inner = FrameRuntime::with_projector(
            wb.initial_world(),
            workbench_reducer(&wb),
            Box::new(WorkbenchProjector { wb: wb.clone() }),
            Viewport { css_w: CANVAS_W as f64, css_h: CANVAS_H as f64, frame_w: CANVAS_W, frame_h: CANVAS_H },
            Box::new(WorkbenchRenderHost),
        );
        Self { inner, wb }
    }

    pub fn lead_review() -> Self {
        Self::new(Workbench::lead_review())
    }

    pub fn click(&mut self, css_x: f64, css_y: f64) -> bool {
        self.inner.click(css_x, css_y)
    }
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
        *self = Self::new(self.wb.clone());
    }
}
