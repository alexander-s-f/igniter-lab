//! LAB-FRAME-DX-VIEW-D host bridge — render an `.ig`-authored `Element` tree through the frame-ui
//! pipeline, closing the loop end-to-end.
//!
//! The view-language design (Candidate D) authors a view as PURE igniter element-contracts that build
//! a recursive descriptor:
//!
//! ```text
//! Element { tag: String, attrs: { dir, main, flex, pad, gap }, text, intent, children: [Element] }
//! ```
//!
//! That descriptor carries STRUCTURE (dir/main/flex/pad/gap) but no coordinates — exactly what the
//! frame-ui layout engine consumes. This bridge maps the Element tree → a `LayoutBox`, `solve`s it to
//! integer rects, then emits canonical widget nodes rendered by the shared `WidgetRenderHost`. So the
//! `.ig` view's typed output renders through the SAME machine-free pipeline as every hand-written
//! screen — proving "the descriptor IR is exactly what the host renders".
//!
//! (The Element JSON here is the type-verified output shape of `list_view_dynamic.ig`, which compiles
//! `ok` on the real `igc`. Driving the live `igc run` VM surface to PRODUCE this JSON is a separate,
//! passport-gated follow-on; the bridge itself is engine-agnostic about how the JSON was made.)

use crate::layout::{solve, Dir, LayoutBox, Rect, Size};
use crate::widget_host::WidgetRenderHost;
use crate::{ProjectedNode, RenderHost};
use serde_json::{json, Value};
use std::collections::HashMap;

/// Per-element render info, keyed by the path-id assigned while building the layout tree.
struct ElInfo {
    tag: String,
    text: String,
    intent: String,
    pad: i64,
}

fn attr_i(el: &Value, key: &str) -> i64 {
    el.get("attrs").and_then(|a| a.get(key)).and_then(|v| v.as_i64()).unwrap_or(0)
}

/// Recursively turn an `Element` JSON node into a `LayoutBox`, assigning each node a stable path id
/// (`"0"`, `"0/1"`, …) and recording its render info in `info`. Structure comes from `attrs`:
/// `flex == 1` ⇒ `Flex(main)`, else `Fixed(main)`; `dir` ⇒ Row/Col (a leaf is a childless Col).
fn element_to_layout(el: &Value, path: String, info: &mut HashMap<String, ElInfo>) -> LayoutBox {
    let tag = el.get("tag").and_then(|v| v.as_str()).unwrap_or("leaf").to_string();
    let dir = if tag == "row" { Dir::Row } else { Dir::Col };
    let main_n = attr_i(el, "main");
    let main = if attr_i(el, "flex") == 1 { Size::Flex(main_n.max(1)) } else { Size::Fixed(main_n.max(0)) };
    let pad = attr_i(el, "pad");
    let gap = attr_i(el, "gap");

    info.insert(
        path.clone(),
        ElInfo {
            tag: tag.clone(),
            text: el.get("text").and_then(|v| v.as_str()).unwrap_or("").to_string(),
            intent: el.get("intent").and_then(|v| v.as_str()).unwrap_or("").to_string(),
            pad,
        },
    );

    let children: Vec<LayoutBox> = el
        .get("children")
        .and_then(|c| c.as_array())
        .map(|arr| {
            arr.iter()
                .enumerate()
                .map(|(i, ch)| element_to_layout(ch, format!("{path}/{i}"), info))
                .collect()
        })
        .unwrap_or_default();

    let mut b = LayoutBox {
        id: path,
        dir,
        main,
        cross: crate::layout::CrossSize::Stretch,
        align: crate::layout::Align::Start,
        pad,
        gap,
        children,
    };
    // builders clamp; assign directly above is fine since values come from clamped attrs
    b.pad = b.pad.max(0);
    b.gap = b.gap.max(0);
    b
}

/// Map an `.ig` element (tag/text/intent) to a canonical widget node for the shared host:
/// `button` → button, an interactive `leaf` (carries an intent) → a row, a static `leaf` → a label,
/// and a padded container (`col`/`row` with pad) → a panel. Structural containers without padding
/// render nothing (they only shape the layout).
fn node_for(rect: &Rect, i: &ElInfo) -> ProjectedNode {
    match i.tag.as_str() {
        "button" => {
            let tone = if i.intent == "add" { "add" } else { "go" };
            ProjectedNode::from_rect(rect, Some(json!({ "action": i.intent })), json!({ "kind": "button", "label": i.text, "tone": tone }))
        }
        "leaf" if !i.intent.is_empty() => ProjectedNode::from_rect(
            rect,
            Some(json!({ "action": i.intent })),
            json!({ "kind": "row", "label": i.text, "selected": false }),
        ),
        "leaf" => ProjectedNode::from_rect(rect, None, json!({ "kind": "label", "label": i.text })),
        "col" | "row" if i.pad > 0 => ProjectedNode::from_rect(rect, None, json!({ "kind": "panel" })),
        _ => ProjectedNode::from_rect(rect, None, json!({ "kind": "none" })),
    }
}

/// Render an `.ig` `Element` tree (as JSON) to an SVG via the frame-ui pipeline (layout → solve →
/// canonical widgets → shared host). Total: malformed/missing fields degrade to empty/zero, no panic.
pub fn render_ig_view(element_json: &str, w: i64, h: i64) -> String {
    let host = WidgetRenderHost::new(w, h);
    let el: Value = match serde_json::from_str(element_json) {
        Ok(v) => v,
        Err(e) => return error_svg(&format!("bad Element JSON: {e}"), w, h),
    };
    let mut info: HashMap<String, ElInfo> = HashMap::new();
    let tree = element_to_layout(&el, "0".to_string(), &mut info);
    let rects = solve(&tree, 0, 0, w, h);
    let nodes: Vec<ProjectedNode> = rects
        .iter()
        .filter_map(|r| info.get(&r.id).map(|i| node_for(r, i)))
        .collect();
    let frame = crate::Frame { frame_index: 0, world_digest: String::new(), source_receipt_id: None, nodes };
    host.render(&frame)
}

fn error_svg(msg: &str, w: i64, h: i64) -> String {
    let safe = msg.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;");
    format!(
        "<svg viewBox=\"0 0 {w} {h}\" xmlns=\"http://www.w3.org/2000/svg\">\n  <rect width=\"{w}\" height=\"{h}\" fill=\"#010409\"/>\n  <text x=\"16\" y=\"28\" font-family=\"monospace\" font-size=\"13\" fill=\"#f85149\">{safe}</text>\n</svg>\n"
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The type-verified output shape of `list_view_dynamic.ig` (3 leads + add, a detail column).
    fn list_element_tree() -> Value {
        let a_row = json!({ "dir": "leaf", "main": 40, "flex": 0, "pad": 0, "gap": 0 });
        let leaf = |text: &str| json!({ "tag": "leaf", "attrs": a_row, "text": text, "intent": "select", "children": [] });
        json!({
            "tag": "row",
            "attrs": { "dir": "row", "main": 0, "flex": 0, "pad": 0, "gap": 0 },
            "text": "", "intent": "",
            "children": [
                {
                    "tag": "col",
                    "attrs": { "dir": "col", "main": 248, "flex": 0, "pad": 12, "gap": 8 },
                    "text": "", "intent": "",
                    "children": [
                        leaf("Review Ada's lead"), leaf("Call Grace back"), leaf("Send Linus the quote"),
                        { "tag": "button", "attrs": a_row, "text": "+ add item", "intent": "add", "children": [] }
                    ]
                },
                {
                    "tag": "col",
                    "attrs": { "dir": "col", "main": 1, "flex": 1, "pad": 18, "gap": 14 },
                    "text": "", "intent": "",
                    "children": [
                        { "tag": "leaf", "attrs": { "dir": "leaf", "main": 30, "flex": 0, "pad": 0, "gap": 0 }, "text": "Review Ada's lead", "intent": "", "children": [] },
                        { "tag": "button", "attrs": { "dir": "leaf", "main": 48, "flex": 0, "pad": 0, "gap": 0 }, "text": "mark done", "intent": "toggle", "children": [] }
                    ]
                }
            ]
        })
    }

    #[test]
    fn ig_element_tree_lays_out_like_the_handwritten_list() {
        let mut info = HashMap::new();
        let tree = element_to_layout(&list_element_tree(), "0".into(), &mut info);
        let rects = solve(&tree, 0, 0, 720, 440);
        let r = |id: &str| rects.iter().find(|r| r.id == id).unwrap().clone();
        // root row → sidebar Fixed(248) on the left, detail Flex(1) filling the rest
        assert_eq!(r("0/0").w, 248);
        assert_eq!(r("0/1").x, 248);
        assert_eq!(r("0/1").w, 720 - 248);
        // sidebar pad 12, gap 8, 40px rows: item0 y=12, item1 y=60, item2 y=108, add y=156
        assert_eq!((r("0/0/0").x, r("0/0/0").y, r("0/0/0").h), (12, 12, 40));
        assert_eq!(r("0/0/1").y, 60);
        assert_eq!(r("0/0/2").y, 108);
        assert_eq!(r("0/0/3").y, 156); // the add button
    }

    #[test]
    fn renders_ig_tree_to_svg_through_the_shared_host() {
        let svg = render_ig_view(&list_element_tree().to_string(), 720, 440);
        assert!(svg.starts_with("<svg"));
        // the leads' text + the buttons survive the bridge into the rendered SVG
        assert!(svg.contains("Review Ada&#39;s lead") || svg.contains("Review Ada's lead"));
        assert!(svg.contains("Call Grace back"));
        assert!(svg.contains("+ add item"));
        assert!(svg.contains("mark done"));
        // and it routed through canonical widgets: a button rect + row/label text exist
        assert!(svg.contains("rx=\"8\"")); // button rounded rect
    }

    #[test]
    fn malformed_json_is_total_no_panic() {
        let svg = render_ig_view("{ not json", 200, 80);
        assert!(svg.contains("bad Element JSON"));
    }

    #[test]
    fn deterministic_render() {
        let j = list_element_tree().to_string();
        assert_eq!(render_ig_view(&j, 720, 440), render_ig_view(&j, 720, 440));
    }
}
