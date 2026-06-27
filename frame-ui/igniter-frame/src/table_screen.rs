//! LAB-FRAME-LAYOUT-VOCAB-P3 — a data-bound TABLE screen built on the layout engine's `table`
//! primitive. Proves the vocabulary ceiling the frame-ui audit named for real apps: a grid whose
//! columns ALIGN across rows for free (the layout resolves identical column x-positions for the
//! header and every data row), data-bound to world facts, interactive and deterministic.
//!
//! Leads are facts (`lead:<n>` → `{name, stage, hot}`). Clicking any cell selects its row; the
//! bottom controls cycle the selected lead's stage, toggle its hot flag, or add a row (the table
//! auto-flows). Machine-free, WASM-clean — the same `FrameRuntime`/layout path as the list screen.

use crate::host::Viewport;
use crate::layout::{solve, table, LayoutBox, Size};
use crate::runtime::FrameRuntime;
use crate::{Frame, IntentReducer, ProjectedNode, Projector, RenderHost};
use serde_json::{json, Value};

const CANVAS_W: i64 = 720;
const CANVAS_H: i64 = 440;
const STAGES: [&str; 3] = ["new", "qualified", "won"];

pub fn initial_world() -> Vec<(String, Value)> {
    vec![
        ("lead:0".into(), json!({ "name": "Ada Lovelace", "stage": 0, "hot": false })),
        ("lead:1".into(), json!({ "name": "Grace Hopper", "stage": 2, "hot": true })),
        ("lead:2".into(), json!({ "name": "Linus T.", "stage": 1, "hot": false })),
        ("__sel__".into(), json!({ "id": "lead:0" })),
        ("__next__".into(), json!({ "n": 3 })),
    ]
}

fn leads(world: &[(String, Value)]) -> Vec<(String, Value)> {
    let mut v: Vec<(String, Value)> = world
        .iter()
        .filter(|(k, _)| k.starts_with("lead:"))
        .cloned()
        .collect();
    v.sort_by_key(|(k, _)| k["lead:".len()..].parse::<u64>().unwrap_or(u64::MAX));
    v
}

fn st<'a>(world: &'a [(String, Value)], id: &str) -> Option<&'a Value> {
    world.iter().find(|(k, _)| k == id).map(|(_, v)| v)
}

fn stage_text(v: &Value) -> String {
    let i = v.get("stage").and_then(|s| s.as_i64()).unwrap_or(0).rem_euclid(3) as usize;
    STAGES[i].to_string()
}

fn world_digest(world: &[(String, Value)]) -> String {
    let mut sorted = world.to_vec();
    sorted.sort_by(|a, b| a.0.cmp(&b.0));
    format!(
        "sha256:{}",
        blake3::hash(serde_json::to_string(&sorted).unwrap_or_default().as_bytes()).to_hex()
    )
}

pub struct TableProjector;

impl Projector for TableProjector {
    fn project(&self, world: &[(String, Value)], frame_index: u64, source_receipt_id: Option<String>) -> Frame {
        let its = leads(world);
        let sel = st(world, "__sel__").and_then(|v| v.get("id")).and_then(|v| v.as_str()).unwrap_or("").to_string();

        // rows: (data-row container id, [cell ids per column]) — `n` is the lead's numeric suffix
        let rows: Vec<(String, Vec<String>)> = its
            .iter()
            .map(|(id, _)| {
                let n = &id["lead:".len()..];
                (format!("trow:{n}"), vec![format!("cell:{n}:name"), format!("cell:{n}:stage"), format!("cell:{n}:hot")])
            })
            .collect();

        // COMPOSE: title + table (columns auto-align) + a controls row — no coordinate constants
        let tree = LayoutBox::col(
            "screen",
            Size::Fixed(0),
            vec![
                LayoutBox::leaf("title", Size::Fixed(28)),
                table(
                    "leads",
                    &["th:name".into(), "th:stage".into(), "th:hot".into()],
                    &[3, 2, 1],
                    32,
                    34,
                    &rows,
                ),
                LayoutBox::row(
                    "controls",
                    Size::Fixed(46),
                    vec![
                        LayoutBox::leaf("cycle", Size::Flex(1)),
                        LayoutBox::leaf("toggle", Size::Flex(1)),
                        LayoutBox::leaf("add", Size::Flex(1)),
                    ],
                )
                .gap(10),
            ],
        )
        .pad(16)
        .gap(12);

        let header_label = |c: &str| match c { "name" => "Name", "stage" => "Stage", "hot" => "Hot", _ => "" };
        let nodes: Vec<ProjectedNode> = solve(&tree, 0, 0, CANVAS_W, CANVAS_H)
            .iter()
            .map(|r| {
                let id = r.id.as_str();
                if let Some(rest) = id.strip_prefix("th:") {
                    ProjectedNode::from_rect(r, None, json!({ "kind": "th", "label": header_label(rest) }))
                } else if let Some(rest) = id.strip_prefix("cell:") {
                    // rest = "<n>:<col>"
                    let mut it = rest.splitn(2, ':');
                    let n = it.next().unwrap_or("");
                    let col = it.next().unwrap_or("");
                    let lead_id = format!("lead:{n}");
                    let lv = st(world, &lead_id).cloned().unwrap_or(json!({}));
                    let text = match col {
                        "name" => lv.get("name").and_then(|s| s.as_str()).unwrap_or("").to_string(),
                        "stage" => stage_text(&lv),
                        "hot" => if lv.get("hot").and_then(|b| b.as_bool()).unwrap_or(false) { "✓".into() } else { "○".into() },
                        _ => String::new(),
                    };
                    ProjectedNode::from_rect(
                        r,
                        Some(json!({ "action": "select", "lead": lead_id })),
                        json!({ "kind": "cell", "col": col, "label": text, "selected": lead_id == sel,
                                "hot": col == "hot" && lv.get("hot").and_then(|b| b.as_bool()).unwrap_or(false) }),
                    )
                } else if let Some(n) = id.strip_prefix("trow:") {
                    let lead_id = format!("lead:{n}");
                    ProjectedNode::from_rect(r, None, json!({ "kind": "rowbg", "selected": lead_id == sel }))
                } else if id == "leads:header" {
                    ProjectedNode::from_rect(r, None, json!({ "kind": "hbar" }))
                } else if id == "title" {
                    let cnt = its.len();
                    let hot = its.iter().filter(|(_, v)| v.get("hot").and_then(|b| b.as_bool()).unwrap_or(false)).count();
                    ProjectedNode::from_rect(r, None, json!({ "kind": "title", "label": format!("Leads · {cnt} rows · {hot} hot") }))
                } else if id == "cycle" {
                    ProjectedNode::from_rect(r, Some(json!({ "action": "cycle" })), json!({ "kind": "btn", "label": "↻ cycle stage", "tone": "neutral" }))
                } else if id == "toggle" {
                    ProjectedNode::from_rect(r, Some(json!({ "action": "toggle" })), json!({ "kind": "btn", "label": "★ toggle hot", "tone": "warn" }))
                } else if id == "add" {
                    ProjectedNode::from_rect(r, Some(json!({ "action": "add" })), json!({ "kind": "btn", "label": "＋ add lead", "tone": "go" }))
                } else {
                    ProjectedNode::from_rect(r, None, json!({ "kind": "panel" }))
                }
            })
            .collect();

        Frame { frame_index, world_digest: world_digest(world), source_receipt_id, nodes }
    }
}

pub fn table_reducer() -> IntentReducer {
    Box::new(|intent, world| {
        let sel = || {
            world.iter().find(|(k, _)| k == "__sel__")
                .and_then(|(_, v)| v.get("id").and_then(|s| s.as_str()).map(|s| s.to_string()))
                .unwrap_or_default()
        };
        let edit_sel = |f: &dyn Fn(&mut Value)| -> Vec<(String, Value)> {
            let id = sel();
            match world.iter().find(|(k, _)| *k == id).map(|(_, v)| v.clone()) {
                Some(mut v) => { f(&mut v); vec![(id, v)] }
                None => vec![],
            }
        };
        match intent.action.as_str() {
            "select" => intent.params.get("lead").and_then(|l| l.as_str())
                .map(|l| vec![("__sel__".to_string(), json!({ "id": l }))]).unwrap_or_default(),
            "cycle" => edit_sel(&|v| {
                let s = v.get("stage").and_then(|s| s.as_i64()).unwrap_or(0);
                v["stage"] = json!((s + 1).rem_euclid(3));
            }),
            "toggle" => edit_sel(&|v| {
                let h = v.get("hot").and_then(|b| b.as_bool()).unwrap_or(false);
                v["hot"] = json!(!h);
            }),
            "add" => {
                let n = world.iter().find(|(k, _)| k == "__next__")
                    .and_then(|(_, v)| v.get("n").and_then(|n| n.as_u64())).unwrap_or(0);
                let id = format!("lead:{n}");
                vec![
                    (id.clone(), json!({ "name": format!("New lead {}", n + 1), "stage": 0, "hot": false })),
                    ("__next__".into(), json!({ "n": n + 1 })),
                    ("__sel__".into(), json!({ "id": id })),
                ]
            }
            _ => vec![],
        }
    })
}

fn esc(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;")
}

pub struct TableRenderHost;

impl RenderHost for TableRenderHost {
    fn render(&self, frame: &Frame) -> String {
        let mut body = String::new();
        for n in &frame.nodes {
            let (x, y, w, h) = (n.sx, n.sy, n.sw.unwrap_or(0), n.sh.unwrap_or(0));
            let kind = n.data.get("kind").and_then(|v| v.as_str()).unwrap_or("");
            let lbl = n.data.get("label").and_then(|v| v.as_str()).unwrap_or("");
            match kind {
                "title" => body.push_str(&format!("  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"15\" font-weight=\"bold\" fill=\"#e6edf3\">{}</text>\n", x, y + 20, esc(lbl))),
                "hbar" => body.push_str(&format!("  <rect x=\"{x}\" y=\"{y}\" width=\"{w}\" height=\"{h}\" fill=\"#161b22\" stroke=\"#30363d\" rx=\"6\"/>\n")),
                "th" => body.push_str(&format!("  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"12\" font-weight=\"bold\" fill=\"#8b949e\">{}</text>\n", x + 10, y + h / 2 + 4, esc(lbl))),
                "rowbg" => {
                    let sel = n.data.get("selected").and_then(|v| v.as_bool()).unwrap_or(false);
                    let fill = if sel { "#16304f" } else { "#0d1117" };
                    body.push_str(&format!("  <rect x=\"{x}\" y=\"{y}\" width=\"{w}\" height=\"{h}\" fill=\"{fill}\" stroke=\"#21262d\"/>\n"));
                }
                "cell" => {
                    let hot = n.data.get("hot").and_then(|v| v.as_bool()).unwrap_or(false);
                    let col = if hot { "#3fb950" } else { "#c9d1d9" };
                    body.push_str(&format!("  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"13\" fill=\"{}\">{}</text>\n", x + 10, y + h / 2 + 5, col, esc(lbl)));
                }
                "btn" => {
                    let (fill, stroke) = match n.data.get("tone").and_then(|t| t.as_str()).unwrap_or("neutral") {
                        "go" => ("#161b22", "#2ea043"),
                        "warn" => ("#161b22", "#d29922"),
                        _ => ("#21262d", "#30363d"),
                    };
                    body.push_str(&format!("  <rect x=\"{x}\" y=\"{y}\" width=\"{w}\" height=\"{h}\" rx=\"7\" fill=\"{fill}\" stroke=\"{stroke}\"/>\n"));
                    body.push_str(&format!("  <text x=\"{}\" y=\"{}\" font-family=\"monospace\" font-size=\"13\" fill=\"#e6edf3\" text-anchor=\"middle\">{}</text>\n", x + w / 2, y + h / 2 + 5, esc(lbl)));
                }
                _ => {}
            }
        }
        format!(
            "<svg viewBox=\"0 0 {CANVAS_W} {CANVAS_H}\" xmlns=\"http://www.w3.org/2000/svg\">\n  <rect width=\"{CANVAS_W}\" height=\"{CANVAS_H}\" fill=\"#010409\"/>\n{body}</svg>\n"
        )
    }
}

pub struct TableScreenRuntime {
    inner: FrameRuntime,
}

impl Default for TableScreenRuntime {
    fn default() -> Self {
        Self::new()
    }
}

impl TableScreenRuntime {
    pub fn new() -> Self {
        Self {
            inner: FrameRuntime::with_projector(
                initial_world(),
                table_reducer(),
                Box::new(TableProjector),
                Viewport { css_w: CANVAS_W as f64, css_h: CANVAS_H as f64, frame_w: CANVAS_W, frame_h: CANVAS_H },
                Box::new(TableRenderHost),
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
    use crate::hit_test;

    fn node<'a>(f: &'a Frame, id: &str) -> &'a ProjectedNode {
        f.nodes.iter().find(|n| n.id == id).unwrap_or_else(|| panic!("no node {id}"))
    }

    #[test]
    fn columns_align_and_cell_click_selects_the_row() {
        let mut rt = TableScreenRuntime::new();
        let f = rt.frame();
        // the table's columns align: header and data cells share x per column (the layout's doing)
        for col in ["name", "stage", "hot"] {
            let hx = node(&f, &format!("th:{col}")).sx;
            assert_eq!(node(&f, &format!("cell:0:{col}")).sx, hx);
            assert_eq!(node(&f, &format!("cell:1:{col}")).sx, hx);
        }
        // a click on lead:1's stage cell hits the cell and selects lead:1 (cells carry the row intent)
        let c = node(&f, "cell:1:stage").clone();
        assert_eq!(hit_test(&f, c.sx + 4, c.sy + 4).unwrap().id, "cell:1:stage");
        assert!(rt.click((c.sx + 4) as f64, (c.sy + 4) as f64));
        let sel = node(&rt.frame(), "cell:1:name").data.get("selected").and_then(|b| b.as_bool()).unwrap();
        assert!(sel, "clicking a cell selected its row");
    }

    #[test]
    fn select_cycle_toggle_add_drive_state() {
        let mut rt = TableScreenRuntime::new();
        let click_node = |rt: &mut TableScreenRuntime, id: &str| {
            let f = rt.frame();
            let n = f.nodes.iter().find(|n| n.id == id).unwrap().clone();
            rt.click((n.sx + n.sw.unwrap() / 2) as f64, (n.sy + n.sh.unwrap() / 2) as f64)
        };
        // select lead:2, cycle its stage (1→2 = won), toggle hot (false→true)
        assert!(click_node(&mut rt, "cell:2:name"));
        assert!(click_node(&mut rt, "cycle"));
        assert!(click_node(&mut rt, "toggle"));
        let l2 = node(&rt.frame(), "cell:2:stage").data.get("label").and_then(|s| s.as_str()).unwrap().to_string();
        assert_eq!(l2, "won", "cycle advanced stage 1→2");
        let hot = node(&rt.frame(), "cell:2:hot").data.get("hot").and_then(|b| b.as_bool()).unwrap();
        assert!(hot, "toggle set hot");
        // add a 4th lead → it flows into the table and auto-selects
        assert!(click_node(&mut rt, "add"));
        let added = node(&rt.frame(), "cell:3:name").data.get("label").and_then(|s| s.as_str()).unwrap().to_string();
        assert_eq!(added, "New lead 4");
    }

    #[test]
    fn deterministic_replay() {
        let log = [(120.0, 110.0), (120.0, 410.0), (300.0, 410.0)];
        let run = || {
            let mut rt = TableScreenRuntime::new();
            for (x, y) in log { rt.click(x, y); }
            (rt.frame_index(), rt.render_digest())
        };
        assert_eq!(run(), run());
    }
}
