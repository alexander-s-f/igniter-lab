//! LAB-FRAME-VIEW-DYNAMIC-RUNTIME-BRIDGE-P4 (+ P3) — the bridge renders REAL runtime output.
//!
//! Both fixtures are produced by executing a compiled `.ig` specimen on `igniter-vm run` (NOT hand
//! authored), then captured verbatim. The runtime envelope is `{ latency_us, observations, result,
//! status }`; the extraction rule is `.result` (the Element tree).
//!
//! - P4 (headline): `list_view_dynamic.ig` — the DYNAMIC specimen, whose rows are built by
//!   `map(lead_labels, l -> call_contract("Leaf", a_row, l))`. After the canon VM `map` parity fix it
//!   runs `status: success`, and its runtime tree renders through the frame-ui bridge.
//! - P3 (kept green): `list_view_inline.ig` — the static sibling. Proven byte-identical to the dynamic
//!   output, so `map` and hand-unrolled construction converge on the same tree.
//!
//! Packets: `lab-docs/lang/lab-frame-view-{dynamic-runtime-bridge-p4,igc-run-element-extraction-p3}-v0.md`.

use igniter_frame::ig_bridge::render_ig_view;
use serde_json::Value;

const DYNAMIC_ENVELOPE: &str = include_str!("fixtures/list_view_dynamic.runtime.json");
const INLINE_ENVELOPE: &str = include_str!("fixtures/list_view_inline.runtime.json");
const DEMO_FIXTURE: &str = include_str!("../web/list_view.element.json");

const LABELS: [&str; 5] = [
    "Review Ada's lead",
    "Call Grace back",
    "Send Linus the quote",
    "+ add item",
    "mark done",
];

fn result_of(envelope: &str) -> Value {
    let env: Value = serde_json::from_str(envelope).expect("fixture is valid JSON");
    assert_eq!(env["status"], "success", "runtime envelope status");
    env.get("result").expect("runtime envelope carries `.result`").clone()
}

#[test]
fn dynamic_runtime_element_tree_renders_through_the_bridge() {
    // the map-built specimen's REAL runtime output → bridge → SVG
    let element = result_of(DYNAMIC_ENVELOPE);
    assert_eq!(element["tag"], "row", "top-level Element is the screen row");

    let svg = render_ig_view(&element.to_string(), 720, 440);
    assert!(svg.starts_with("<svg"));
    for needle in LABELS {
        assert!(svg.contains(needle), "rendered SVG missing {needle:?}");
    }
    assert!(svg.contains("rx=\"8\""), "expected a button rect in the rendered output");
}

#[test]
fn demo_fixture_equals_dynamic_runtime_result() {
    // the live demo (web/list_view.element.json) IS the extracted dynamic runtime `.result` — no mirror
    let demo: Value = serde_json::from_str(DEMO_FIXTURE).unwrap();
    assert_eq!(result_of(DYNAMIC_ENVELOPE), demo, "demo fixture must equal the dynamic runtime .result");
}

#[test]
fn dynamic_and_inline_runtime_trees_are_identical() {
    // map-based and hand-unrolled construction converge on the same Element tree (P3 stays green)
    assert_eq!(result_of(DYNAMIC_ENVELOPE), result_of(INLINE_ENVELOPE));
}

#[test]
fn static_inline_runtime_tree_still_renders() {
    let svg = render_ig_view(&result_of(INLINE_ENVELOPE).to_string(), 720, 440);
    for needle in LABELS {
        assert!(svg.contains(needle), "inline render missing {needle:?}");
    }
}
