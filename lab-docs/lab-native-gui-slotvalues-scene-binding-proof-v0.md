# Lab: Native GUI SlotValues-to-Scene Binding (v0)

Status: `experimental · lab-only · research · no-canon · no-stable-schema`
Track: `lab-native-gui-slotvalues-scene-binding-proof-v0`
Card: `LAB-NATIVE-GUI-P3`
Date: 2026-06-06
Proof: 16/16 checks passed (45/45 cumulative) — `run_proof.rb`

---

## 1. Overview

This document presents the implementation and validation proof of a **headless SlotValues-to-Scene binding engine** inside `igniter-lab/igniter-gui-engine`.

This module (`SlotBinder`) serves as the presentation state compiler. It merges layout-resolved bounding boxes and drawing instructions with mock VM execution result packets (SlotValues) to evaluate reactive display rules, styling patches, visibility toggles, and inline text substitutions as data.

---

## 2. Updated Directory Structure

The `igniter-gui-engine` has been updated with the slot binding module, new test fixtures, and updated runner results:

```
igniter-lab/igniter-gui-engine/
  ├── fixtures/
  │   ├── invalid_slot_value.json      # mock SlotValues containing undeclared slot keys (fails closed)
  │   ├── invalid_binding_strict.json  # scene tree with rules referencing undeclared slots under strict mode
  │   └── ... (P1/P2 fixtures)
  ├── lib/
  │   ├── scene_tree.rb               # (canonical reference schemas)
  │   ├── slot_binder.rb              # (new) stale checks, type validation, display rules evaluator, text templating
  │   └── ... (P1/P2 classes)
  ├── out/
  │   ├── bound_scene_tree.json       # (new) resolved vector drawing scene ready for rasterization
  │   ├── scene_binding_receipt.json  # (new) binding verification trace documenting lineage & timestamp
  │   └── ... (P1/P2 outputs)
  └── run_proof.rb                    # (updated) runs the 45-check proof matrix
```

---

## 3. Slot Binding & Presentation Evaluation

The `SlotBinder` performs state-to-view compiling using the following pipeline:

1. **Digest Consistency Gate**: Asserts that `layout_result["scene_digest"]` is identical to `scene_tree.digest`, preventing the binding of stale layout calculations.
2. **Slot Key Access Validation**: Validates that all keys in the `SlotValues` payload correspond to declared slots in the view's schema. Undeclared keys fail closed with a `ValidationError` (preventing presentation state leaks).
3. **Slot Value Type Guarding**: Enforces runtime type matching between SlotValues and slot type metadata (`integer`, `boolean`, `string`), failing closed if a mismatch occurs.
4. **Strict Binding Verification**: If strict mode is enabled, the binder sweeps all display rules and inline placeholders to ensure they do not reference undeclared slots.
5. **Display Rules Evaluation**:
   * **Style Rules**: Computes conditional expressions against active SlotValues. Merges result patches (e.g. background color swaps, border radius overrides) into node styles.
   * **Match Rules**: Evaluates subjects against multiple cases, merging corresponding style overrides, visibility changes, or active states.
6. **Text Placeholder Substitutions**: Parses string templates (e.g. `{slot:warnings_count}`) and performs inline value interpolation.
7. **Lineage Receipts**: Emits a deterministic lineage receipt containing the source VM receipt ID, digest, and timestamp.

---

## 4. Security & Isolation Gates

To comply with the **Language Covenant**, the slot binder enforces:
1. **Ignignore Sandbox**: The binder runs completely in-memory as data-in-data-out. No Ruby VM hooks, thread pool dispatch, or contract code is loaded.
2. **False/Nil Boolean Safety**: The expression resolver uses a dedicated helper (`get_slot_value`) to resolve slot values from string/symbol key-agnostic structures, preventing the classic Ruby `false || nil` evaluation bugs.
3. **Marker Compliance Check**: All new source code and JSON files are checked for `lab-only`, `no-canon`, and `no-stable-schema` markers.

---

## 5. Proof Matrix Results (45/45 Cumulative PASS)

All 16 P3 checks passed successfully alongside NGUI-P1 and NGUI-P2:

| ID | Check | Status | Verification Detail |
|---|---|---|---|
| **NGUI-P3-1** | P2 proof checks are green | **PASS** | Running P1 and P2 checks alongside P3 produces zero regressions. |
| **NGUI-P3-2** | SlotBinder successfully binds valid SlotValues | **PASS** | Valid mock values bind successfully, producing `bound_scene_tree.json` and `scene_binding_receipt.json`. |
| **NGUI-P3-3** | Conditional style updates evaluate correctly | **PASS** | Rect node fill swaps color from gray to `#00ff00` when `is_active` is true. |
| **NGUI-P3-4** | Conditional visibility flags evaluate correctly | **PASS** | `warning_badge` becomes visible (`visible: true`) only when `warnings_count > 0`. |
| **NGUI-P3-5** | Match expression rules evaluate correctly | **PASS** | Correctly maps different tab values to coordinate styling overrides. |
| **NGUI-P3-6** | Inline text substitutions occur correctly | **PASS** | Substitutes `{slot:user_name}` and `{slot:msg_count}` inside text nodes. |
| **NGUI-P3-7** | Undeclared slot keys in SlotValues fail closed | **PASS** | `invalid_slot_value.json` with unauthorized keys raises ValidationError. |
| **NGUI-P3-8** | Strict mode fails on display rule undeclared slot | **PASS** | Rejects rules referencing nonexistent slots under strict mode. |
| **NGUI-P3-9** | Strict mode fails on text placeholder undeclared slot | **PASS** | Rejects placeholder templates referencing nonexistent slots under strict mode. |
| **NGUI-P3-10** | Slot value type mismatches fail closed | **PASS** | Passing a string value to an integer slot raises ValidationError. |
| **NGUI-P3-11** | Stale scene digest check fails closed | **PASS** | Rejects layout result when `scene_digest` does not match scene tree digest. |
| **NGUI-P3-12** | Receipts contain no local absolute paths | **PASS** | Output files contain zero local user paths. |
| **NGUI-P3-13** | No GPU/windowing runtime is required | **PASS** | Execution is fully headless and library-isolated. |
| **NGUI-P3-14** | No VM or contract execution occurs | **PASS** | Asserts that `Igniter::Contract` or VM constants are not loaded. |
| **NGUI-P3-15** | No network/storage access is introduced | **PASS** | Evaluated source files contain no fetch or local storage calls. |
| **NGUI-P3-16** | Lab-only markers remain present | **PASS** | Verifies markers in new files and confirms `igniter-lang` is untouched. |

---

## 6. Key Design Decisions

* **D1 — Key Agnostic Resolution Helper**: Integrated a robust helper `get_slot_value` to support hash lookups agnostic of string/symbol keys. Crucially, it resolves keys explicitly via `.key?` checking, preventing bugs when handling boolean `false` values which would otherwise fall back incorrectly when using `||`.
* **D2 — Style Overwrite during Layout Injection**: Style updates resulting from display rules (like color swaps) are merged directly into the node's styling block, preserving resolved boundaries (`x`, `y`, `width`, `height`) injected from layout results.
* **D3 — Metadata Agnostic Integrity**: Ensures that the `non_claims` key present in raw files is bypassed in core validation passes, keeping metadata separated from functional data structures.

---

## 7. Recommendation for LAB-NATIVE-GUI-P4

We recommend that the P4 milestone focus on **Headless Scene Animation & Playback Timeline Proof**:
* Define a schema for declaring scene animations (transitions, keyframes, time-offsets) inside `scene_tree.json` or an animation manifest.
* Implement a headless timeline resolver that interpolates node styles (like opacity, translation, scaling) over time offsets.
* Verify the animated results headlessly by writing out frames as snapshots of bound scene trees at discrete timestamp offsets (e.g. `t=0ms`, `t=250ms`, `t=500ms`).
