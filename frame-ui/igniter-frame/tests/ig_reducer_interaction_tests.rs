//! LAB-FRAME-VIEW-IG-REDUCER-INTERACTION-P5 — close the view+logic loop.
//!
//! P2–P4/P1 proved an Igniter-authored `Element` tree (real `igniter-vm` runtime output, or the
//! desugared form's output) renders through the frame-ui bridge. This proves the SAME semantic nodes
//! drive the existing input loop: a click hit-tests a node, `derive_intent` lifts the AUTHORED intent
//! (with the node id as target), and a reducer updates state — input → effect → next frame (a
//! re-projection from new state), never a frame mutation. Machine-free; no SVG scraping.

use igniter_frame::host::Viewport;
use igniter_frame::ig_bridge::project_ig_element;
use igniter_frame::runtime::FrameRuntime;
use igniter_frame::{derive_intent, Frame, InputEvent, IntentReducer, Projector};
use serde_json::{json, Value};

const DYNAMIC: &str = include_str!("fixtures/list_view_dynamic.runtime.json"); // P4 (map specimen)
const FORM: &str = include_str!("fixtures/list_view_form.runtime.json"); // P1 (desugared col{row{}})

const W: i64 = 720;
const H: i64 = 440;

fn tree_of(envelope: &str) -> String {
    serde_json::from_str::<Value>(envelope).unwrap()["result"].to_string()
}

/// A projector over a FIXED `.ig` `Element` tree plus a `__sel__` selection fact: it builds the
/// bridge's semantic nodes and marks the selected node — so the NEXT frame reflects new state.
struct IgViewProjector {
    tree: String,
}
impl Projector for IgViewProjector {
    fn project(&self, world: &[(String, Value)], frame_index: u64, src: Option<String>) -> Frame {
        let sel = world.iter().find(|(k, _)| k == "__sel__").and_then(|(_, v)| v.as_str()).unwrap_or("").to_string();
        let mut f = project_ig_element(&self.tree, W, H);
        for n in &mut f.nodes {
            if n.id == sel {
                n.data["selected"] = json!(true);
            }
        }
        f.frame_index = frame_index;
        f.source_receipt_id = src;
        f
    }
}

/// A no-op render host: this proof exercises SEMANTICS (hit-test → intent → reducer), not SVG.
struct NoRender;
impl igniter_frame::RenderHost for NoRender {
    fn render(&self, _f: &Frame) -> String {
        String::new()
    }
}

/// App-local reducer: an authored `select` sets `__sel__` to the clicked node's id (the intent target).
/// Pure `(intent, state) -> deltas`, machine-free.
fn reducer() -> IntentReducer {
    Box::new(|intent, _world| match intent.action.as_str() {
        "select" => intent.target.clone().map(|t| vec![("__sel__".to_string(), json!(t))]).unwrap_or_default(),
        _ => vec![],
    })
}

fn runtime_over(tree: String) -> FrameRuntime {
    FrameRuntime::with_projector(
        vec![("__sel__".to_string(), json!(""))],
        reducer(),
        Box::new(IgViewProjector { tree }),
        Viewport { css_w: W as f64, css_h: H as f64, frame_w: W, frame_h: H },
        Box::new(NoRender),
    )
}

/// The full loop proof, parameterised so it holds for BOTH the dynamic-runtime and the desugared-form
/// fixtures (Q5).
fn proof(envelope: &str) {
    let tree = tree_of(envelope);
    let mut rt = runtime_over(tree);

    // Q1: an authored intent survived into a hit-testable node (intent on ProjectedNode.intent).
    let f0 = rt.frame();
    let node = f0
        .nodes
        .iter()
        .find(|n| n.intent.as_ref().and_then(|i| i.get("action")).and_then(|a| a.as_str()) == Some("select"))
        .expect("a node carrying the authored `select` intent")
        .clone();
    let (cx, cy) = (node.sx + 4, node.sy + 4);
    let id = node.id.clone();
    assert!(!f0.nodes.iter().find(|n| n.id == id).unwrap().data.get("selected").and_then(|v| v.as_bool()).unwrap_or(false));

    // Q2: hit-test + derive_intent yields the AUTHORED action with the node id as target — not host-invented.
    let intent = derive_intent(&f0, &InputEvent { kind: "click".into(), x: cx, y: cy, payload: json!(null) })
        .expect("click derives an intent");
    assert_eq!(intent.action, "select");
    assert_eq!(intent.target.as_deref(), Some(id.as_str()));

    // Q3 + Q4: a real click drives reducer → effect → next frame (lineage), not a frame mutation.
    let f_before = rt.frame_index();
    assert!(rt.click(cx as f64, cy as f64), "click on an intent node produces an effect");
    assert_eq!(rt.frame_index(), f_before + 1, "the step advanced");
    let lineage: Value = serde_json::from_str(&rt.lineage_json()).unwrap();
    assert_eq!(lineage["input_receipt_id"], json!(format!("input:{f_before}")));
    assert_eq!(lineage["effect_receipt_id"], json!(format!("effect:{f_before}")));
    assert_eq!(lineage["frame_index"], json!(f_before + 1));
    // the NEXT frame is re-projected from the new `__sel__` state (selection now marks the node).
    let f1 = rt.frame();
    assert_eq!(f1.nodes.iter().find(|n| n.id == id).unwrap().data.get("selected"), Some(&json!(true)));
}

#[test]
fn dynamic_runtime_view_click_drives_reducer() {
    proof(DYNAMIC);
}

#[test]
fn desugared_form_view_click_drives_reducer() {
    proof(FORM); // Q5: same loop holds for the desugared-form fixture
}

#[test]
fn a_miss_produces_no_effect_and_no_state_change() {
    let mut rt = runtime_over(tree_of(DYNAMIC));
    // a click well outside any node
    assert!(!rt.click(10_000.0, 10_000.0), "a miss must not produce an effect");
    assert_eq!(rt.frame_index(), 0);
    let lineage: Value = serde_json::from_str(&rt.lineage_json()).unwrap();
    assert_eq!(lineage["effect_receipt_id"], json!(null), "no effect on a miss");
}

#[test]
fn deterministic_replay_of_a_click_log() {
    let run = || {
        let mut rt = runtime_over(tree_of(DYNAMIC));
        let f = rt.frame();
        let pts: Vec<(i64, i64)> = f
            .nodes
            .iter()
            .filter(|n| n.intent.is_some())
            .take(3)
            .map(|n| (n.sx + 4, n.sy + 4))
            .collect();
        for (x, y) in pts {
            rt.click(x as f64, y as f64);
        }
        (rt.frame_index(), rt.render_digest())
    };
    assert_eq!(run(), run());
}
