# Headless Vector Renderer Artifact Proof

**Status**: experimental · lab-only · no-canon · no-stable-schema · no-performance-claim
**Track**: `lab-native-gui-headless-vector-renderer-artifact-proof-v0`
**Design Layer**: Headless Vector Rendering (NGUI-P6)

This document presents the design and verification of the headless vector renderer (`VectorRenderer`) implemented inside the experimental `igniter-gui-engine`. It translates state-bound, layout-resolved, and animated frame snapshots into a structured primitive JSON format and valid SVG string wrapper without requiring GPU or windowing dependencies.

---

## 1. Core Architecture

The vector renderer translates the flat list of bound layout nodes from a given frame (e.g., `frame_250ms.json`) into deterministic drawing instructions.

```text
       Bound Scene Tree (Hash)
                 │
                 ▼
     Pre-render Validation Gates (color formats, layout bounds, injection prevention)
                 │
                 ▼
      Painter's Algorithm Sorting (z-index ascending, declaration order ascending)
                 │
                 ▼
      Primitive Specific Mapping (rect, rounded_rect, circle, text)
                 │
      ┌──────────┴──────────┐
      ▼                     ▼
JSON Primitives      Raw SVG Element Compilation
```

### Painter's Algorithm Sorting
Unlike hit-testing (which traverses the scene top-to-bottom to catch the foremost clicked item), the renderer must build the elements bottom-to-top (from back to front) to overlay objects correctly.
1. Nodes are filtered to include only whitelisted drawable primitive shapes (`rect`, `rounded_rect`, `circle`, `text`).
2. Invisible/inactive nodes are skipped.
3. The remaining nodes are sorted ascending by `z_index` (defaulting to 0) and then by their source declaration index ascending.

---

## 2. Pre-render Hardening & Guard Gates

To secure the rendering pipeline, the following validations run before any output is generated:

- **Unsupported Primitives**: Only whitelisted types are compiled. If any other type (such as `path` or container groups) is present, the pipeline fails closed with a validation error (Check `NGUI-P6-5`).
- **Layout Boundaries**: All drawable primitives must possess defined layout parameters (`x`, `y`, `width`, `height` as Numeric types) under their styles, otherwise the renderer fails closed (`NGUI-P6-6`).
- **HTML/Script Injection Guard**: Text node values are inspected for HTML tags or script injection patterns (e.g., `/<[^>]+>/` or `<script>`), raising validation errors if any matches are found (`NGUI-P6-7`).
- **Color Validation**: Color-related attributes (like `fill`, `stroke`, `border_color`) must match strict hex color shapes starting with `#` followed by 3, 4, 6, or 8 hex digits, preventing malformed values (`NGUI-P6-8`).
- **Transform Validation**: Standard layout values (like `transform_scale`, `transform_translate_x`, `transform_translate_y`) must be Numeric. Custom `transform` strings must strictly conform to basic translation/scaling formats, failing closed if any rotation or shearing values are supplied (`NGUI-P6-9`).

---

## 3. Primitives & SVG Mapping Table

| Primitive Type | Dimensions/Shape Properties | SVG Element Mapping |
| :--- | :--- | :--- |
| **`rect`** | `x`, `y`, `width`, `height` | `<rect x="..." y="..." width="..." height="..." />` |
| **`rounded_rect`** | `x`, `y`, `width`, `height`, `rx`, `ry` | `<rect x="..." y="..." width="..." height="..." rx="..." ry="..." />` |
| **`circle`** | Center `(cx, cy)` resolved from `x + w/2`, `y + h/2`, and radius `r` | `<circle cx="..." cy="..." r="..." />` |
| **`text`** | `x`, `y` (baseline adjusted by size * 0.8), `content` (escaped), font, size | `<text x="..." y="..." font-family="..." font-size="...">...</text>` |

---

## 4. Verification Matrix

The proof suite successfully validates all NGUI checks, demonstrating robust error handling and correct rendering properties:

```text
=== NGUI Headless Proof Summary ===
Status: SUCCESS (ALL PASS)
Total Checks: 95/95
```

### Vector Renderer Results (NGUI-P6)

| Check ID | Verification Description | Status |
| :--- | :--- | :--- |
| `NGUI-P6-1` | Prior proof layers remain green and regression-free | PASS |
| `NGUI-P6-2` | Valid mapping of scene nodes to structured JSON and raw SVG | PASS |
| `NGUI-P6-3` | Transform translation, scaling, and opacity carry-through | PASS |
| `NGUI-P6-4` | Interpolating Red and Blue at midpoint yields purple `#7f007f` | PASS |
| `NGUI-P6-5` | Unsupported primitive type fails closed | PASS |
| `NGUI-P6-6` | Missing/malformed layout bounds fail closed | PASS |
| `NGUI-P6-7` | HTML/Script text payload injection fails closed | PASS |
| `NGUI-P6-8` | Invalid hex color format fails closed | PASS |
| `NGUI-P6-9` | Unsupported transform attributes fail closed | PASS |
| `NGUI-P6-10`| Painter's Algorithm sorting (z_index + declaration order) is deterministic | PASS |
| `NGUI-P6-11`| Vector receipt includes VM lineage and diagnostic codes | PASS |
| `NGUI-P6-12`| Rendered outputs contain no absolute user paths | PASS |
| `NGUI-P6-13`| Fully headless (no GPU/Window/Vello runtime required) | PASS |
| `NGUI-P6-14`| Zero VM bytecode execution or contract dispatch | PASS |
| `NGUI-P6-15`| No network, storage, or streaming APIs utilized | PASS |
| `NGUI-P6-16`| Mainline codebase untouched and lab-only compliance markers present | PASS |
