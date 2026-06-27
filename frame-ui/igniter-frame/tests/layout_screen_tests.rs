//! LAB-FRAME-LAYOUT-VOCAB-P1 — end-to-end proof that a screen authored by COMPOSING `layout` boxes
//! (no hand-tuned screen constants) drives a real interactive, deterministic frame: solve → nodes →
//! hit-test routes clicks to the innermost child, and adding an item auto-flows the layout.

use igniter_frame::layout::{layout_digest, Dir, LayoutBox, Size};
use igniter_frame::{hit_test, Frame, ProjectedNode};
use serde_json::json;

/// Author a 2-column screen as a composed box tree: a fixed sidebar listing `leads` + a flex main
/// with `fields`. NO screen-specific coordinate constants — only structure + sizes.
fn screen_tree(leads: &[&str], fields: &[&str]) -> LayoutBox {
    let lead_rows: Vec<LayoutBox> = leads
        .iter()
        .map(|l| LayoutBox::leaf(format!("lead:{l}"), Size::Fixed(34)))
        .collect();
    let field_rows: Vec<LayoutBox> = fields
        .iter()
        .map(|f| LayoutBox::leaf(format!("fld:{f}"), Size::Fixed(44)))
        .collect();

    LayoutBox::row(
        "screen",
        Size::Fixed(0),
        vec![
            LayoutBox::col("sidebar", Size::Fixed(180), lead_rows)
                .pad(8)
                .gap(6),
            LayoutBox::col("main", Size::Flex(1), field_rows)
                .pad(12)
                .gap(8),
        ],
    )
}

/// Map solved rects → box `ProjectedNode`s, attaching a `select` intent to lead rows (the seam a
/// projector uses). Panels carry no intent, so hit-test routes a click to the lead inside them.
fn nodes_from(tree: &LayoutBox) -> Vec<ProjectedNode> {
    igniter_frame::layout::solve(tree, 0, 0, 720, 440)
        .iter()
        .map(|r| {
            if r.id.starts_with("lead:") {
                ProjectedNode::from_rect(
                    r,
                    Some(json!({ "action": "select" })),
                    json!({ "kind": "listitem", "label": r.id }),
                )
            } else {
                ProjectedNode::from_rect(r, None, json!({ "kind": "panel" }))
            }
        })
        .collect()
}

fn frame_of(tree: &LayoutBox) -> Frame {
    Frame {
        frame_index: 0,
        world_digest: "test".into(),
        source_receipt_id: None,
        nodes: nodes_from(tree),
    }
}

#[test]
fn composed_screen_feeds_real_hit_test() {
    let tree = screen_tree(&["Ada", "Grace", "Linus"], &["priority", "stage"]);
    let frame = frame_of(&tree);

    // sidebar pad 8, gap 6, leads Fixed(34): lead0 y=8, lead1 y=48, lead2 y=88 (all inside x∈[8,172])
    // a click inside lead1 (Grace) must route to the LEAD, not the enclosing sidebar/screen panel.
    let hit = hit_test(&frame, 90, 65).expect("a node is hit");
    assert_eq!(hit.id, "lead:Grace", "innermost child wins over enclosing panels");
    assert_eq!(
        hit.intent.as_ref().and_then(|i| i.get("action")).and_then(|a| a.as_str()),
        Some("select"),
        "the composed lead carries its declared interaction"
    );

    // the main column is flex: width = 720 - 180 = 540, fields inside its pad-12 content
    let main = frame.nodes.iter().find(|n| n.id == "main").unwrap();
    assert_eq!((main.sx, main.sw), (180, Some(540)));
    let f0 = frame.nodes.iter().find(|n| n.id == "fld:priority").unwrap();
    assert_eq!((f0.sx, f0.sy, f0.sw), (192, 12, Some(540 - 24)));
}

#[test]
fn adding_an_item_auto_flows_no_constant_edits() {
    let lead_ys = |leads: &[&str]| -> Vec<i64> {
        let rects = igniter_frame::layout::solve(&screen_tree(leads, &["priority"]), 0, 0, 720, 440);
        leads
            .iter()
            .map(|l| rects.iter().find(|r| r.id == format!("lead:{l}")).unwrap().sy_y())
            .collect()
    };
    let three = lead_ys(&["Ada", "Grace", "Linus"]);
    let four = lead_ys(&["Ada", "Grace", "Linus", "Mwangi"]);
    assert_eq!(three, vec![8, 48, 88]);
    // the first three positions are IDENTICAL; the 4th simply flows in — zero constant edits.
    assert_eq!(&four[..3], &three[..]);
    assert_eq!(four[3], 128);
}

#[test]
fn deterministic_layout_digest() {
    let tree = screen_tree(&["Ada", "Grace"], &["priority", "stage"]);
    let a = igniter_frame::layout::solve(&tree, 0, 0, 720, 440);
    let b = igniter_frame::layout::solve(&tree, 0, 0, 720, 440);
    assert_eq!(layout_digest(&a), layout_digest(&b));
    assert_eq!(a, b);
    // and the layout direction is honored (root is a Row)
    assert_eq!(tree.dir, Dir::Row);
}

// tiny helper: a layout Rect's y, named to read in the test above
trait RectY {
    fn sy_y(&self) -> i64;
}
impl RectY for igniter_frame::layout::Rect {
    fn sy_y(&self) -> i64 {
        self.y
    }
}
