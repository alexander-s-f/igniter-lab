# Lab: Native GUI Binding Expression & Rule Hardening (v0)

Status: `experimental · lab-only · research · no-canon · no-stable-schema`
Track: `lab-native-gui-binding-expression-and-rule-hardening-v0`
Card: `LAB-NATIVE-GUI-P4`
Date: 2026-06-06
Proof: 17/17 checks passed (62/62 cumulative) — `run_proof.rb`

---

## 1. Overview

This document presents the implementation and validation proof of **evaluator hardening and schema constraint gates** inside the headless SlotValues-to-Scene binding engine (`SlotBinder`) in `igniter-lab/igniter-gui-engine`.

Building on top of the P3 reactive compilation layer, NGUI-P4 introduces robust, fail-closed guards to validate display rules, expression syntax/operators, style properties, structural bounds overwrites, and payload size bounds as raw data before rendering can take place.

---

## 2. Updated Directory Structure

The files and artifacts involved in this proof track are:

```
igniter-lab/igniter-gui-engine/
  ├── lib/
  │   ├── scene_tree.rb               # (canonical reference schemas)
  │   ├── slot_binder.rb              # (hardened) structural validations, style whitelisting, size guards
  │   └── ... (P1/P2/P3 classes)
  ├── out/
  │   ├── scene_binding_receipt.json       # success receipt with diagnostic_code: SUCCESS
  │   ├── scene_binding_error_receipt.json # error receipt with check_id diagnostic code and lineage
  │   └── ... (P1/P2/P3 outputs)
  └── run_proof.rb                    # (updated) runs the 62-check proof matrix
```

---

## 3. Hardening & Validation gates

The evaluator implements the following validation gates to ensure strict fail-closed safety:

### A. Payload Size Guards
To prevent memory exhaustion and DoS vectors, the `SlotBinder` verifies that:
* Key count in the `SlotValues` payload does not exceed **50**.
* String size of any individual value does not exceed **1000 bytes**.
* Total serialized JSON representation does not exceed **5000 bytes**.

### B. Display Rule Structural Verification
Display rules are swept prior to evaluation to assert they conform to strict array boundaries:
* `style` rules must have exactly 4 elements: `["style", condition, true_patch, false_patch]`.
* `match` rules must have exactly 4 elements: `["match", subject, cases, default_patch]`.
* Mismatches raise `ValidationError` with code `NGUI-P4-4` or `NGUI-P4-5`.

### C. Expression Operators & Syntax Verification
All conditional expressions are parsed recursively to verify:
* Operators are whitelisted (`slot`, `eq`, `gt`, `lt`, `not`).
* Operator argument lengths are correct (`slot` & `not` expect 1 argument; `eq`, `gt`, `lt` expect 2).
* Literals are typed safely (NilClass, Integer, Float, String, TrueClass, FalseClass).

### D. Visual Style Whitelisting & Structural Guiding
* **Visual Style Whitelist**: Only whitelisted styling keys can be patched: `x, y, width, height, w, h, fill, stroke, opacity, visible, active, font, size, text_color, rx, ry, r, border_color, border_width, color, background`.
* **Structural Bounds Protection**: Modifying structural keys (`x, y, width, height, w, h, margin, padding, layout`) is blocked by default unless the node explicitly overrides this by setting `"allow_structural_overwrites": true`.
* **Shape Type Checkers**: Color fields are validated against Hex color shape regex (`\A#(?:[0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})\z`), opacity must be a Numeric within `[0.0, 1.0]`, and other visual variables are shape-constrained.

---

## 4. Proof Matrix Results (62/62 Cumulative PASS)

All 17 checks of the NGUI-P4 hardening matrix pass successfully:

| ID | Check | Status | Verification Detail |
|---|---|---|---|
| **NGUI-P4-1** | P1/P2/P3 checks remain green | **PASS** | No regressions detected; cumulative 45/45 prior checks remain green. |
| **NGUI-P4-2** | Unknown expression operator fails closed | **PASS** | `["unknown_op", ...]` raises ValidationError `NGUI-P4-2`. |
| **NGUI-P4-3** | Malformed expression fails closed | **PASS** | `["eq", a, b, c]` (wrong argument count) raises ValidationError `NGUI-P4-3`. |
| **NGUI-P4-4** | Malformed display rule fails closed | **PASS** | Rule with size != 4 elements raises ValidationError `NGUI-P4-4`. |
| **NGUI-P4-5** | Unsupported display rule type fails closed | **PASS** | Rule of type `"unsupported_rule_type"` raises ValidationError `NGUI-P4-5`. |
| **NGUI-P4-6** | Unsafe style patch key fails closed | **PASS** | Overriding `"onclick"` inside styling patch raises ValidationError `NGUI-P4-6`. |
| **NGUI-P4-7** | Structural bound overwrite is blocked | **PASS** | Patching `"x"` on a node without explicit allow raises ValidationError `NGUI-P4-7`. |
| **NGUI-P4-8** | Invalid patch value type fails closed | **PASS** | Non-hex color `"red"` or opacity `1.5` raises ValidationError `NGUI-P4-8`. |
| **NGUI-P4-9** | Oversized SlotValues payload fails closed | **PASS** | Payloads >50 keys or >1000 char strings raise ValidationError `NGUI-P4-9`. |
| **NGUI-P4-10** | Receipt records diagnostic code & lineage | **PASS** | Success receipt records `SUCCESS` and error receipt records `NGUI-P3-8`. |
| **NGUI-P4-11** | Valid binding path still passes | **PASS** | Valid warnings payload binds successfully and updates visibility and text content. |
| **NGUI-P4-12** | Outputs contain no local absolute paths | **PASS** | Receipts contain relative identifiers only. |
| **NGUI-P4-13** | No GPU/windowing runtime loaded | **PASS** | Execution remains fully headless. |
| **NGUI-P4-14** | No VM or contract execution occurs | **PASS** | Asserted that VM execution libraries are isolated. |
| **NGUI-P4-15** | No network/storage access introduced | **PASS** | Verified that standard libraries remain sandboxed. |
| **NGUI-P4-16** | igniter-lang/** remains untouched | **PASS** | Git status confirms mainline remains untouched. |
| **NGUI-P4-17** | Compliance markers remain present | **PASS** | Source headers check confirms compliance tags. |

---

## 5. Key Design Decisions

* **D1 — Default Strict Binding**: Shifted strict binding checking to `true` by default in SlotBinder interface, forcing compile-time slot declaration validation on all experimental features.
* **D2 — Structural Protection Gate**: Implemented `"allow_structural_overwrites": true` as a property check on scene tree nodes. This allows visual elements (like sliding tab indicators) to mutate layout boundaries while locking structural containers to layout resolver coordinates.
* **D3 — Hex Color Guard**: Added hex color formatting regex patterns to style value checkers, blocking arbitrary CSS class injections or invalid graphics formatting strings.
* **D4 — Error Receipt Generation**: Outlined a standard error receipt format written to `scene_binding_error_receipt.json` to capture validation codes and exception traces.

---

## 6. Recommendation for LAB-NATIVE-GUI-P5

We recommend moving toward **Headless Scene Animation & Playback Timeline Proof**:
1. Define a schema for declaring visual transitions and animations inside `scene_tree.json`.
2. Implement a headless timeline resolver that evaluates styling properties (such as translation, scaling, or opacity) at discrete time offsets.
3. Validate by outputting frame state snapshots as structured data at offsets `t=0ms`, `t=250ms`, `t=500ms` to check interpolation correctness headlessly.
