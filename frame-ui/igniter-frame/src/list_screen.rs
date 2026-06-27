//! LAB-FRAME-LAYOUT-VOCAB-P2 — a declarative list/detail screen built ENTIRELY on the `layout`
//! engine (no screen-specific coordinate constants). Proves the authoring payoff: the screen
//! structure is composed from `LayoutBox`es and `solve`d, so a data-driven list (N item rows + an
//! "add" row) auto-flows when items are added — the projector never hand-computes a position.
//!
//! It is a thin domain over the same machine-free `FrameRuntime`: items are world FACTS
//! (`item:<n>` → `{label, done}`), the only mutable state is facts, and `select`/`toggle`/`add`
//! are pure reducer deltas. Deterministic, replayable, WASM-clean.

use crate::host::Viewport;
use crate::layout::{solve, LayoutBox, Size};
use crate::runtime::FrameRuntime;
use crate::widget_host::WidgetRenderHost;
use crate::{Frame, IntentReducer, ProjectedNode, Projector};
use serde_json::{json, Value};

const CANVAS_W: i64 = 720;
const CANVAS_H: i64 = 440;
const ROW_H: i64 = 40;

// ── State ────────────────────────────────────────────────────────────────────────────────────────

/// Initial world: three items + a selection + a next-id counter. Items are facts; structure is data.
pub fn initial_world() -> Vec<(String, Value)> {
    vec![
        ("item:0".into(), json!({ "label": "Review Ada's lead", "done": false })),
        ("item:1".into(), json!({ "label": "Call Grace back", "done": true })),
        ("item:2".into(), json!({ "label": "Send Linus the quote", "done": false })),
        ("__sel__".into(), json!({ "id": "item:0" })),
        ("__next__".into(), json!({ "n": 3 })),
    ]
}

/// Items (`item:<n>`) sorted by their NUMERIC suffix (so `item:10` follows `item:9`, not `item:1`).
fn items(world: &[(String, Value)]) -> Vec<(String, Value)> {
    let mut v: Vec<(String, Value)> = world
        .iter()
        .filter(|(k, _)| k.starts_with("item:"))
        .cloned()
        .collect();
    v.sort_by_key(|(k, _)| k["item:".len()..].parse::<u64>().unwrap_or(u64::MAX));
    v
}

fn st<'a>(world: &'a [(String, Value)], id: &str) -> Option<&'a Value> {
    world.iter().find(|(k, _)| k == id).map(|(_, v)| v)
}

// ── Projection: world facts → composed layout tree → frame nodes ────────────────────────────────

fn world_digest(world: &[(String, Value)]) -> String {
    let mut sorted = world.to_vec();
    sorted.sort_by(|a, b| a.0.cmp(&b.0));
    format!(
        "sha256:{}",
        blake3::hash(serde_json::to_string(&sorted).unwrap_or_default().as_bytes()).to_hex()
    )
}

pub struct ListProjector;

impl Projector for ListProjector {
    fn project(&self, world: &[(String, Value)], frame_index: u64, source_receipt_id: Option<String>) -> Frame {
        let its = items(world);
        let sel = st(world, "__sel__")
            .and_then(|v| v.get("id"))
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();

        // 1. COMPOSE the screen as a box tree (no coordinate constants) ----------------------------
        let mut sidebar_rows: Vec<LayoutBox> = its
            .iter()
            .map(|(id, _)| LayoutBox::leaf(id.clone(), Size::Fixed(ROW_H)))
            .collect();
        sidebar_rows.push(LayoutBox::leaf("add", Size::Fixed(ROW_H)));

        let tree = LayoutBox::row(
            "screen",
            Size::Fixed(0),
            vec![
                LayoutBox::col("sidebar", Size::Fixed(248), sidebar_rows).pad(12).gap(8),
                LayoutBox::col(
                    "detail",
                    Size::Flex(1),
                    vec![
                        LayoutBox::leaf("detail:title", Size::Fixed(30)),
                        LayoutBox::leaf("toggle", Size::Fixed(48)),
                        LayoutBox::leaf("detail:hint", Size::Fixed(26)),
                    ],
                )
                .pad(18)
                .gap(14),
            ],
        );

        // 2. SOLVE to absolute integer rects, then decorate each id with intent + render data ------
        let sel_item = st(world, &sel).cloned();
        let nodes: Vec<ProjectedNode> = solve(&tree, 0, 0, CANVAS_W, CANVAS_H)
            .iter()
            .map(|r| {
                let id = r.id.as_str();
                if id.starts_with("item:") {
                    let v = st(world, id).cloned().unwrap_or(json!({}));
                    ProjectedNode::from_rect(
                        r,
                        Some(json!({ "action": "select" })),
                        json!({
                            "kind": "row",
                            "label": v.get("label").cloned().unwrap_or(json!("")),
                            "done": v.get("done").and_then(|b| b.as_bool()).unwrap_or(false),
                            "selected": id == sel,
                        }),
                    )
                } else if id == "add" {
                    ProjectedNode::from_rect(r, Some(json!({ "action": "add" })), json!({ "kind": "button", "label": "＋ add item", "tone": "add" }))
                } else if id == "toggle" {
                    let done = sel_item.as_ref().and_then(|v| v.get("done")).and_then(|b| b.as_bool()).unwrap_or(false);
                    let label = if done { "✓ done — mark not done" } else { "○ mark done" };
                    ProjectedNode::from_rect(r, Some(json!({ "action": "toggle" })), json!({ "kind": "button", "label": label, "tone": if done { "go" } else { "neutral" } }))
                } else if id == "detail:title" {
                    let label = sel_item.as_ref().and_then(|v| v.get("label")).and_then(|s| s.as_str()).unwrap_or("— select an item —").to_string();
                    ProjectedNode::from_rect(r, None, json!({ "kind": "title", "label": label }))
                } else if id == "detail:hint" {
                    let n_done = items(world).iter().filter(|(_, v)| v.get("done").and_then(|b| b.as_bool()).unwrap_or(false)).count();
                    ProjectedNode::from_rect(r, None, json!({ "kind": "note", "tone": "dim", "label": format!("{} of {} done · click a row to select, ＋ to add", n_done, items(world).len()) }))
                } else {
                    let label = match id { "sidebar" => "Items", "detail" => "Detail", _ => "" };
                    ProjectedNode::from_rect(r, None, json!({ "kind": "panel", "label": label }))
                }
            })
            .collect();

        Frame { frame_index, world_digest: world_digest(world), source_receipt_id, nodes }
    }
}

// ── Reducer: select / add (auto-flows the list) / toggle the selected item ──────────────────────

pub fn list_reducer() -> IntentReducer {
    Box::new(|intent, world| {
        let sel_id = || {
            world.iter().find(|(k, _)| k == "__sel__")
                .and_then(|(_, v)| v.get("id").and_then(|s| s.as_str()).map(|s| s.to_string()))
                .unwrap_or_default()
        };
        match intent.action.as_str() {
            "select" => match &intent.target {
                Some(t) => vec![("__sel__".into(), json!({ "id": t }))],
                None => vec![],
            },
            "add" => {
                let n = world.iter().find(|(k, _)| k == "__next__")
                    .and_then(|(_, v)| v.get("n").and_then(|n| n.as_u64()))
                    .unwrap_or(0);
                let id = format!("item:{n}");
                vec![
                    (id.clone(), json!({ "label": format!("New item {}", n + 1), "done": false })),
                    ("__next__".into(), json!({ "n": n + 1 })),
                    ("__sel__".into(), json!({ "id": id })), // select the new row
                ]
            }
            "toggle" => {
                let id = sel_id();
                match world.iter().find(|(k, _)| *k == id).map(|(_, v)| v.clone()) {
                    Some(mut v) => {
                        let cur = v.get("done").and_then(|b| b.as_bool()).unwrap_or(false);
                        v["done"] = json!(!cur);
                        vec![(id, v)]
                    }
                    None => vec![],
                }
            }
            _ => vec![],
        }
    })
}

// ── Runtime (wraps the shared FrameRuntime; renders via the shared WidgetRenderHost) ────────────

pub struct ListScreenRuntime {
    inner: FrameRuntime,
}

impl Default for ListScreenRuntime {
    fn default() -> Self {
        Self::new()
    }
}

impl ListScreenRuntime {
    pub fn new() -> Self {
        let inner = FrameRuntime::with_projector(
            initial_world(),
            list_reducer(),
            Box::new(ListProjector),
            Viewport { css_w: CANVAS_W as f64, css_h: CANVAS_H as f64, frame_w: CANVAS_W, frame_h: CANVAS_H },
            Box::new(WidgetRenderHost::new(CANVAS_W, CANVAS_H)),
        );
        Self { inner }
    }

    pub fn click(&mut self, css_x: f64, css_y: f64) -> bool {
        self.inner.click(css_x, css_y)
    }
    pub fn render_svg(&self) -> String {
        self.inner.render_svg()
    }
    pub fn frame(&self) -> Frame {
        self.inner.frame()
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
        self.inner = Self::new().inner;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::hit_test;

    fn rect_of(rt: &ListScreenRuntime, id: &str) -> (i64, i64, i64, i64) {
        let f = rt.frame();
        let n = f.nodes.iter().find(|n| n.id == id).unwrap_or_else(|| panic!("no node {id}"));
        (n.sx, n.sy, n.sw.unwrap(), n.sh.unwrap())
    }

    #[test]
    fn rows_are_laid_out_by_composition_and_select_routes() {
        let rt = ListScreenRuntime::new();
        // sidebar pad 12 gap 8, ROW_H 40: item:0 y=12, item:1 y=60, item:2 y=108, add y=156
        assert_eq!(rect_of(&rt, "item:0").1, 12);
        assert_eq!(rect_of(&rt, "item:1").1, 60);
        assert_eq!(rect_of(&rt, "item:2").1, 108);
        assert_eq!(rect_of(&rt, "add").1, 156);
        // a click inside item:1's row hits the row (innermost), not the sidebar/screen panel
        let (x, y, w, _) = rect_of(&rt, "item:1");
        let f = rt.frame();
        assert_eq!(hit_test(&f, x + w / 2, y + 20).unwrap().id, "item:1");
    }

    #[test]
    fn add_auto_flows_the_list_no_constant_edits() {
        let mut rt = ListScreenRuntime::new();
        let add_before = rect_of(&rt, "add").1; // 156 (after 3 items)
        // click the add row
        let (ax, ay, aw, _) = rect_of(&rt, "add");
        assert!(rt.click((ax + aw / 2) as f64, (ay + 10) as f64));
        // a 4th item flowed in at the old add position; add moved DOWN one row — zero constant edits
        assert_eq!(rect_of(&rt, "item:3").1, add_before);
        assert_eq!(rect_of(&rt, "add").1, add_before + ROW_H + 8);
        // the new item is auto-selected
        let title = rt.frame().nodes.iter().find(|n| n.id == "detail:title").unwrap().data.clone();
        assert_eq!(title.get("label").and_then(|s| s.as_str()), Some("New item 4"));
    }

    #[test]
    fn select_then_toggle_marks_the_selected_item() {
        let mut rt = ListScreenRuntime::new();
        // select item:2 (not done), then toggle via the detail button
        let (x, y, w, _) = rect_of(&rt, "item:2");
        assert!(rt.click((x + w / 2) as f64, (y + 20) as f64));
        let (tx, ty, tw, _) = rect_of(&rt, "toggle");
        assert!(rt.click((tx + tw / 2) as f64, (ty + 24) as f64));
        // item:2 row now shows done
        let row = rt.frame().nodes.iter().find(|n| n.id == "item:2").unwrap().data.clone();
        assert_eq!(row.get("done").and_then(|b| b.as_bool()), Some(true));
    }

    #[test]
    fn deterministic_replay_of_a_click_log() {
        let log = [(100.0, 60.0), (380.0, 200.0), (120.0, 170.0)]; // select, toggle, add (approx)
        let run = || {
            let mut rt = ListScreenRuntime::new();
            for (x, y) in log {
                rt.click(x, y);
            }
            (rt.frame_index(), rt.render_digest())
        };
        assert_eq!(run(), run(), "same start + same input log → byte-identical frame");
    }
}
