// LAB-FRAME-RENDERER-HOST-P4 demo: drive the host over a pointer log and emit the host frames
// (SVG + lineage) as JSON. A browser viewer plays these EXACT Rust-computed frames.
//
//   cargo run --example render_demo > out.json

use igniter_frame::host::{drive, MemWorld, Viewport};
use igniter_frame::{Camera, Intent, IntentReducer};
use serde_json::{json, Value};

fn move_right_reducer() -> IntentReducer {
    Box::new(|intent: &Intent, world: &[(String, Value)]| {
        if intent.action != "move_right" {
            return vec![];
        }
        let target = intent.target.clone().unwrap_or_default();
        world
            .iter()
            .filter(|(id, _)| *id == target)
            .map(|(id, val)| {
                let mut v = val.clone();
                v["x"] = json!(v["x"].as_f64().unwrap_or(0.0) + 1.0);
                (id.clone(), v)
            })
            .collect()
    })
}

#[tokio::main]
async fn main() {
    // a clickable entity between two static reference posts
    let world = MemWorld::new(
        vec![
            ("post_l".into(), json!({ "x": -1.5, "y": 0.0, "z": 0.0 })),
            ("post_r".into(), json!({ "x": 1.5, "y": 0.0, "z": 0.0 })),
            ("e1".into(), json!({ "x": -1.0, "y": 0.0, "z": 0.0, "on_click": { "action": "move_right" } })),
        ],
        move_right_reducer(),
    );
    let camera = Camera::default();
    let vp = Viewport { css_w: 800.0, css_h: 800.0, frame_w: 400, frame_h: 400 };

    // click e1 as it walks right: screen sx 150 → 200 → 250 (CSS = sx*2), sy 200 → CSS 400
    let pointer_log = [(300.0, 400.0), (400.0, 400.0), (500.0, 400.0)];

    let frames = drive(&world, &camera, &vp, &pointer_log).await.unwrap();
    let out: Vec<Value> = frames.iter().map(|f| f.to_json()).collect();
    println!("{}", serde_json::to_string(&out).unwrap());
}
