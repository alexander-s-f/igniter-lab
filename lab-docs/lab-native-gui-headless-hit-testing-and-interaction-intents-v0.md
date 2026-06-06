# Lab: Native GUI Headless Hit-Testing & Interaction Intents (v0)

Status: `experimental · lab-only · research · no-canon · no-stable-schema`
Track: `lab-native-gui-headless-hit-testing-and-interaction-intents-v0`
Card: `LAB-NATIVE-GUI-P2`
Date: 2026-06-06
Proof: 15/15 checks passed (29/29 cumulative) — `run_proof.rb`

---

## 1. Overview

This document presents the implementation and validation proof of a **headless spatial hit-testing engine** and a **secure interaction-intent routing system** inside `igniter-lab/igniter-gui-engine`.

Building on top of the layout coordinates resolved in NGUI-P1, the hit tester resolves pointer events (like click) against computed bounding boxes while enforcing strict security filters to block unauthorized actions and slot leaks.

---

## 2. Updated Directory Structure

The `igniter-gui-engine` now includes the hit-testing core and new fixtures:

```
igniter-lab/igniter-gui-engine/
  ├── fixtures/
  │   ├── overlap_scene.json          # multiple overlapping boxes with varying z_index
  │   ├── invalid_intent_action.json  # fails parsing (unsafe action name)
  │   ├── invalid_intent_slot.json    # fails parsing (references undeclared slot)
  │   └── ... (P1 fixtures)
  ├── lib/
  │   ├── scene_tree.rb               # (updated) validates event kinds & whitelists intents
  │   ├── hit_tester.rb               # (new) stale checks, bounding box queries, z-order sorting
  │   └── ... (P1 classes)
  ├── out/
  │   ├── hit_test_receipt.json       # (new) receipt for the nav_item_1 target hit
  │   └── ... (P1 layout outputs)
  └── run_proof.rb                    # (updated) runs the 29-check proof matrix
```

---

## 3. Hit-Testing & Overlap Resolution

The `HitTester` resolves coordinate inputs `(x, y)` using the following algorithm:

1. **Stale Check**: Verifies that the layout result's `scene_digest` matches the active `SceneTree` digest, failing closed if they differ (preventing stale interaction routing).
2. **Boundary Check**: Gathers nodes whose computed coordinates encompass `x` and `y` (`x >= bounds.x && x <= bounds.x + bounds.w` and `y >= bounds.y && y <= bounds.y + bounds.h`).
3. **Overlap Resolution (Z-Order sorting)**:
   * Candidates are sorted by `z_index` descending (unspecified z_index defaults to `0`).
   * Ties are broken by **node declaration order index descending** (meaning nodes declared later in the scene tree are stacked on top of earlier ones).
   * The first node in this sorted candidate list is the target.
4. **Intent Matching**:
   * Inspects the target's `interaction_intents` for the corresponding event (e.g. `on_click` for `"click"`).
   * If matched, returns the structured intent. If the target defines no event handler, it returns `matched_intent: nil` (non-interactive nodes still block coordinates but produce no intent).

---

## 4. Security Gates

To comply with the **Language Covenant**, the interaction pipeline implements three secure gates:
1. **Event Whitelisting**: Only whitelisted event kinds (`on_click`, `on_mousedown`, `on_mouseup`, `on_mousemove`) are parsed.
2. **Intent Whitelisting**: Only whitelisted actions (`select_tab`, `toggle_sidebar`, `submit_form`, `close_modal`) are accepted. Unsafe commands (like raw command execution or file writes) fail compile/parse time.
3. **Parameter Slot Leak Gate**: If an intent parameter references a slot (e.g. `["slot", "name"]`), the validator verifies that the slot name exists in the view's top-level `slots` declarations, preventing unauthorized memory reads.

---

## 5. Proof Matrix Results (29/29 PASS)

All checks passed successfully:

| ID | Check | Status | Verification Detail |
|---|---|---|---|
| **NGUI-P2-1** | P1 proof remains green | **PASS** | Running P1 checks alongside P2 checks produces zero regressions. |
| **NGUI-P2-2** | valid coordinate hits expected interactive node | **PASS** | Click at `(28, 108)` successfully hits `nav_item_1` and returns `select_tab` intent. |
| **NGUI-P2-3** | outside coordinate returns no-target receipt | **PASS** | Click at `(2000, 2000)` returns `hit: false` and `target: nil`. |
| **NGUI-P2-4** | overlapping nodes resolve deterministically | **PASS** | Confirms `box4` (z_index 5) is hit first; removing it resolves to `box2` (declared last). |
| **NGUI-P2-5** | non-interactive nodes do not produce intents | **PASS** | Click on `logo` returns a valid hit with `matched_intent: nil`. |
| **NGUI-P2-6** | unknown action fails closed | **PASS** | `invalid_intent_action.json` throws ValidationError (unsafe action). |
| **NGUI-P2-7** | unsupported event kind fails closed | **PASS** | Call with event kind `"doubleclick"` throws ValidationError (unsupported kind). |
| **NGUI-P2-8** | stale scene digest fails closed | **PASS** | Alters `scene_digest` in layout and asserts HitTester rejects execution. |
| **NGUI-P2-9** | undeclared slot/capability in intent fails closed | **PASS** | `invalid_intent_slot.json` throws ValidationError (slot leak). |
| **NGUI-P2-10** | receipts contain no local absolute paths | **PASS** | `hit_test_receipt.json` verified to have no user/absolute paths. |
| **NGUI-P2-11** | no VM execution occurs | **PASS** | Verified that VM and Contract contexts are not loaded. |
| **NGUI-P2-12** | no GPU/window/native bridge is introduced | **PASS** | Verified code is fully headless and window-free. |
| **NGUI-P2-13** | no network/fetch/storage access is introduced | **PASS** | Checks source code for fetch, http, and storage APIs. |
| **NGUI-P2-14** | lab-only markers remain present | **PASS** | All new files carry `lab-only` metadata in their headers. |
| **NGUI-P2-15** | igniter-lang/** remains untouched | **PASS** | Git status confirms no changes to canonical folders. |

---

## 6. Key Design Decisions

* **D1 — Dual-Key Robustness**: HitTester is written to search bounding box keys using both String and Symbol representations (`res_node["id"] || res_node[:id]`), allowing it to accept direct Ruby Hash outputs from the LayoutResolver as well as parsed JSON strings.
* **D2 — Hit-Blocking Non-Interactive Nodes**: Solid non-interactive elements (like logos or borders) still capture coordinates and block clicks from reaching elements underneath. They do not pass clicks through unless explicitly requested by layout logic.
* **D3 — Early Digest Checking**: The stale check runs at the very beginning of the hit-testing invocation, avoiding layout queries on mismatching structures.

---

## 7. Recommendation for LAB-NATIVE-GUI-P3

We recommend the next slice focus on **SlotValues-to-Scene Binding Proof**:
* Implement a state binding layer that merges a static `scene_tree.json` with a mock runtime result packet (SlotValues).
* Prove that display rules (like showing/hiding nodes or changing node styles based on slot values) are evaluated headlessly.
* Do not introduce graphics rendering yet; output the resolved styled node tree as data to verify the reactive binding logic first.
