# Lab: Native GUI Scene Tree & Headless Layout Proof (v0)

Status: `experimental · lab-only · research · no-canon · no-stable-schema`
Track: `lab-native-gui-scene-tree-headless-layout-proof-v0`
Card: `LAB-NATIVE-GUI-P1`
Date: 2026-06-06
Proof: 14/14 checks passed — `run_proof.rb`

---

## 1. Overview

This document presents the implementation and validation proof of a **minimal native GUI scene tree schema** and a **headless layout resolver** inside the `igniter-lab` playground.

This work represents Phase 1 of our native graphics exploration (NGUI), showing that a vector scene graph can be parsed, structurally validated, and laid out (using relative positioning and Flexbox directions) entirely within a headless, pure-data environment.

---

## 2. Structure of `igniter-gui-engine`

We have structured the prototype directory as follows:

```
igniter-lab/igniter-gui-engine/
  ├── fixtures/
  │   ├── valid_dashboard.json       # root flex container, sidebar, and primitive shapes
  │   ├── missing_node_id.json       # fails validation (id missing)
  │   ├── cyclic_reference.json      # fails resolver (parent cycle loop)
  │   ├── invalid_slot_ref.json      # generates slot warning diagnostic
  │   ├── unsupported_primitive.json # fails validation (unknown primitive type)
  │   └── malformed_scene.json       # fails parser (invalid JSON syntax)
  ├── lib/
  │   ├── scene_tree.rb              # parses, validates, whitelists, and digests JSON trees
  │   └── layout_resolver.rb         # cycle detection & bounding box calculations
  ├── out/                           # generated during proof runs
  │   ├── layout_result.json         # final resolved absolute coordinates and bounds
  │   ├── summary.json               # JSON results of the proof runner
  │   └── summary.md                 # human-readable proof markdown matrix
  └── run_proof.rb                   # NGUI-P1 14-check proof runner
```

No canonical files under `igniter-lang/` were touched during this implementation.

---

## 3. The `scene_tree.json` Schema

The scene tree format is designed to be platform-independent, serializing drawing primitives and layout rules:

```json
{
  "view_id": "igniter.lab.dashboard",
  "canvas": { "width": 1024, "height": 768 },
  "slots": {
    "warnings_count": { "type": "integer", "contract_ref": "compiler.warnings_count" }
  },
  "nodes": [
    {
      "id": "root",
      "type": "container",
      "layout": { "type": "flex", "direction": "horizontal" },
      "style": { "width": 1024, "height": 768, "margin": 0, "padding": 0 }
    },
    {
      "id": "sidebar",
      "type": "container",
      "parent": "root",
      "layout": { "type": "flex", "direction": "vertical" },
      "style": { "width": 240, "height": 768, "padding": 20 }
    },
    {
      "id": "logo",
      "type": "rect",
      "parent": "sidebar",
      "style": { "width": 200, "height": 60, "margin": 10 },
      "fill": "#ff6a3d"
    }
  ],
  "non_claims": [
    "lab-only", "experimental", "no-canon", "no-stable-schema", "no-performance-claim"
  ]
}
```

---

## 4. Headless Layout Math

The `LayoutResolver` processes the flat node list, ordering parent-child dependencies and recursively computing coordinates downwards.

### Layout Rules Implemented
1. **Absolute Layout**: Children position themselves relative to the parent box utilizing custom layout offsets (`x` / `y`) and padding.
2. **Flex Layout**: Children stack sequentially inside the parent container:
   * `"horizontal"` direction: stacks children side-by-side, incrementing x-offsets by padding, width, and child margins.
   * `"vertical"` direction: stacks children top-to-bottom, incrementing y-offsets.
3. **Dimensions Resolution**: Handles explicit number coordinates, percentages (e.g. `"100%"`), and defaults to parent sizes.

### Verified Bounds (from `fixtures/valid_dashboard.json`)
The proof runner verified the following computed coordinates for the flex dashboard layout:
* `root`: `[0, 0, 1024, 768]`
* `sidebar` (1st flex item of root): `[0, 0, 240, 768]`
* `content_area` (2nd flex item of root): `[240, 0, 784, 768]` (offset x by sidebar width)
* `logo` (1st vertical flex item of sidebar): `[30, 30, 200, 60]` (offset x/y by parent padding 20 and margin 10)
* `nav_item_1` (2nd vertical flex item of sidebar): `[25, 105, 200, 40]` (starts vertically at y=105, offset by margin/size of logo)

---

## 5. Proof Matrix Results (14/14 PASS)

All checks passed successfully:

| ID | Check | Status | Verification Detail |
|---|---|---|---|
| **NGUI-P1-1** | scene_tree schema loads valid fixture | **PASS** | Validates `valid_dashboard.json` without errors. |
| **NGUI-P1-2** | scene digest is deterministic | **PASS** | Digests match across duplicate loads; ignores `non_claims` metadata alterations. |
| **NGUI-P1-3** | headless layout computes stable bounding boxes | **PASS** | Exact coordinate assertions for flex layout matched. |
| **NGUI-P1-4** | missing required node fields fail closed | **PASS** | Triggers error for missing `id`; catches malformed JSON parse errors. |
| **NGUI-P1-5** | duplicate node ids fail closed | **PASS** | Duplicate ID `item` throws ValidationError during validation. |
| **NGUI-P1-6** | cyclic parent/layout references fail closed | **PASS** | Detects `root -> child1 -> child2 -> root` cycle, throwing ValidationError. |
| **NGUI-P1-7** | unsupported primitive fails closed | **PASS** | Invalid node type `cylinder` fails whitelisting check. |
| **NGUI-P1-8** | invalid slot reference is diagnosed | **PASS** | Warns for display rule referencing undeclared `nonexistent_slot`. |
| **NGUI-P1-9** | layout result has no local absolute paths | **PASS** | Confirms no absolute paths or directories exist inside `layout_result.json`. |
| **NGUI-P1-10** | no GPU/window/winit/vello runtime is required | **PASS** | Runs in standard CLI environment. |
| **NGUI-P1-11** | no VM execution or contract dispatch occurs | **PASS** | Runs without loading `Igniter::Contract` or virtual machine context. |
| **NGUI-P1-12** | no network/fetch/storage/bridge added | **PASS** | Source code checked for fetch/storage/IPC strings. |
| **NGUI-P1-13** | lab-only markers present | **PASS** | Verified that headers carry `lab-only` metadata in all source files. |
| **NGUI-P1-14** | igniter-lang/** remains untouched | **PASS** | Git diff shows zero changes under canonical `igniter-lang/`. |

---

## 6. Key Design Decisions

* **D1 — Flat Node Array Representation**: Nodes are kept in a single flat array rather than nested JSON children. This simplifies schema validation, duplicate ID detection, and spatial hit-testing (quad-trees). parent-child relationships are declared explicitly via a `"parent"` key.
* **D2 — Double-Pass Resolver**: First pass builds hierarchical references and runs depth-first cycle detection (DAG checker). Second pass recursively computes size and coordinates. This separates cycle safety from placement math.
* **D3 — Duck-Typed Dimensions**: Layout dimension values (width, height) are allowed to be Numbers (absolute pixels) or Strings (percentages like `"50%"`). String dimensions without percentage indicators default to parent size, avoiding layout engine crashes.
* **D4 — Non-Blocking Slot Warnings**: Mismatched slot references are treated as warnings rather than hard validation errors, keeping view compiling decoupled from the active VM instance.

---

## 7. Recommendation for LAB-NATIVE-GUI-P2

We recommend the next slice focus on **Hit-Testing and Event Routing (Static Proof)**:
* Define click events in the scene tree and map them to interaction intents.
* Implement a spatial **Quad-Tree / R-Tree hit-testing resolver** in `igniter-gui-engine`.
* Supply coordinates representing mouse clicks and verify that the resolver routes to the correct target node.
* Do not introduce active OS windowing or GPU shaders yet; prove the input resolution pipeline headlessly first.
