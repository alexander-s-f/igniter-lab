# Agent Handoff: LAB-NATIVE-GUI-P2

Card: LAB-NATIVE-GUI-P2
Agent: [Igniter-Lang Implementation Agent]
Role: implementation-agent
Track: lab-native-gui-headless-hit-testing-and-interaction-intents-v0
Status: done

---

## [D] Decisions

- **D1 — Event-Bubbling Omission**: Opted out of complex child-to-parent event bubbling for this prototype. Coordinates targeted at nested text nodes will hit the text node, which returns `matched_intent: nil` unless the click coordinate targets the parent button directly, or unless the parent defines a separate hit bounding box.
- **D2 — Z-Order & stable scene index sort**: Resolved overlapping element hits by sorting candidates by `z_index` descending, then by the node's declaration index in the nodes list descending (so nodes declared later in the file are hit first).
- **D3 — String/Symbol Agnostic Access**: Configured HitTester key lookups to support both Strings and Symbols (`bounds["x"] || bounds[:x]`), allowing it to accept raw Ruby hashes from the layout resolver or parsed JSON results.
- **D4 — Stale scene validation**: Enforced validation comparing `layout_result["scene_digest"]` and `scene_tree.digest` at the beginning of hit-testing. Mismatch triggers ValidationError, failing closed.

## [S] Shipped / Signals

- **Core Module**: Created [hit_tester.rb](../igniter-gui-engine/lib/hit_tester.rb) containing bounding box hit checks, stale digest validations, and overlap sorting.
- **Schema Validation**: Updated [scene_tree.rb](../igniter-gui-engine/lib/scene_tree.rb) with whitelisted event kinds and intent validations.
- **JSON Fixtures**: Created [overlap_scene.json](../igniter-gui-engine/fixtures/overlap_scene.json), [invalid_intent_action.json](../igniter-gui-engine/fixtures/invalid_intent_action.json), and [invalid_intent_slot.json](../igniter-gui-engine/fixtures/invalid_intent_slot.json).
- **Proof Updates**: Updated [run_proof.rb](../igniter-gui-engine/run_proof.rb) to cover NGUI-P2 checks and output [hit_test_receipt.json](../igniter-gui-engine/out/hit_test_receipt.json).
- **Proof Documentation**: Shipped [lab-native-gui-headless-hit-testing-and-interaction-intents-v0.md](../lab-docs/lab-native-gui-headless-hit-testing-and-interaction-intents-v0.md) and [LAB-NATIVE-GUI-P2.md](../.agents/LAB-NATIVE-GUI-P2.md).

## [T] Tests / Proofs

- **Proof Runner Passed (29/29)**: `ruby igniter-lab/igniter-gui-engine/run_proof.rb` passes all checks successfully and writes out summary receipts.
- **Click Routing Verified**:
  - Click at `(28, 108)` inside `nav_item_1` successfully returns `select_tab` intent.
  - Click at `(2000, 2000)` outside matches nothing and returns `hit: false` and `target: nil`.
  - Overlap click on `overlap_scene.json` at `(150, 150)` returns `box4` (z-index 5) first, and `box2` (declared last) when `box4` is removed.

## [R] Risks / Recommendations

- **Risks**:
  - **Undeclared slot parameter leakage**: Allowing intents to carry references to slots could let interactive nodes expose sensitive memory. Checked and failed closed by validator.
- **Recommendations**: Continue keeping the hit-testing core fully decoupled from window manager event polling. OS events (e.g. from winit) should be converted into coordinate numbers before calling hit-testing.

## [Next] Suggested next slice

- **Card: LAB-NATIVE-GUI-P3**
- **Goal**: Implement a headless slot-binding layer that merges a static `scene_tree.json` with a mock runtime result packet (SlotValues), evaluating `display_rules` (like style/color changes and visibility) based on slot conditions.
