# Hardened Vector Attributes and Composition Preflight

**Status**: experimental · lab-only · no-canon · no-stable-schema · no-performance-claim
**Track**: `lab-native-gui-vector-attribute-hardening-and-composition-preflight-v0`
**Design Layer**: Hardened Rendering & Composition Preflight (NGUI-P7)

This document describes the validation hardening of SVG element attribute emissions and the design of the structural composition preflight module.

---

## 1. Hardened SVG Attribute Emissions

To prevent script or XML/HTML tag injection into compiled vector drawings, strict attribute validation is enforced during pre-render checks:

- **Unsafe Fragment Rejection**: Any node `id`, `font-family` (or `font`), or `transform` string containing quotes (`"`, `'`), angle brackets (`<`, `>`), event handlers (patterns starting with `on` preceded by start-of-string or non-letters, such as `onload` or `_onclick`), `javascript:`, or `url()` is rejected and fails closed.
- **Node ID Format Rules**: Node IDs must conform strictly to alphanumeric characters, hyphens, underscores, and dots (`\A[a-zA-Z0-9\-_.]+\z`). Any format mismatch (e.g. including symbols like `$`) fails closed.
- **Transform Hardening**: Layout transformations (such as `transform_scale`, `transform_translate_x`, and `transform_translate_y`) are validated as Numeric. Raw `transform` strings must match translation/scaling whitelist patterns, failing closed if any rotation (`rotate`) or skewing operations are encountered.
- **XML Escaping**: All attribute string emissions (including `id`, `font-family`, and text baseline content) are escaped via `CGI.escapeHTML` to prevent DOM/XML syntax manipulation.

---

## 2. Structural Node Policy & Circle Primitives

- **Non-Drawable Structural Nodes**: Node types `container` and `subview` are allowed in the scene tree but are recognized as structural non-drawables. The renderer skips primitive drawing generation for these nodes.
- **Unsupported Drawables**: Primitives `path` and `group` remain unsupported by the renderer and fail closed during validation.
- **Circle Mapping**: Circle elements specify layout boundaries (`x`, `y`, `width`, `height`) and an optional radius `r`. The renderer computes the center coordinates `(cx, cy)` as:
  $$\text{cx} = x + \frac{w}{2}$$
  $$\text{cy} = y + \frac{h}{2}$$
  And resolves `r` from either the node's radius property or `w / 2`, producing a positive representation `<circle cx="..." cy="..." r="..." />`.

---

## 3. Composition Preflight Module

The `CompositionPreflight` module inspects the parent/child hierarchy of the scene tree prior to rendering to enforce structural invariants:

1. **Missing Parent Check**: Every non-root node referencing a `parent` ID must correspond to a node that exists in the scene tree, preventing orphan references.
2. **Cycle Detection**: Parent links are traversed back to the root. If a node is visited twice in the same chain, a cycle is detected, and the validation fails closed.
3. **Subview Boundary Containment**: A node of type `"subview"` defines a layout boundary box. All descendants of this subview node must lie geometrically within its computed bounds:
   $$x_{\text{descendant}} \ge x_{\text{subview}}$$
   $$x_{\text{descendant}} + w_{\text{descendant}} \le x_{\text{subview}} + w_{\text{subview}}$$
   $$y_{\text{descendant}} \ge y_{\text{subview}}$$
   $$y_{\text{descendant}} + h_{\text{descendant}} \le y_{\text{subview}} + h_{\text{subview}}$$
   If any descendant overflows, preflight fails closed.

---

## 4. Verification Results

All 113 checks pass successfully:

```text
=== NGUI Proof Runner ===
Date: 2026-06-06 11:55
OS: Mac (headless)
Status: SUCCESS (ALL PASS)
Total: 113/113
```

### New P7 Checks

| Check ID | Description | Status |
| :--- | :--- | :--- |
| `NGUI-P7-1` | Prior check layers remain green | PASS |
| `NGUI-P7-2` | Valid SVG ID format characters accepted | PASS |
| `NGUI-P7-3` | Unsafe ID attributes (quotes, script tags, event handlers) rejected | PASS |
| `NGUI-P7-4` | ID symbol mismatches (e.g. `$`) fail closed | PASS |
| `NGUI-P7-5` | Unsafe font-family values rejected | PASS |
| `NGUI-P7-6` | Unsafe transform strings (javascript:, url(), rotate) rejected | PASS |
| `NGUI-P7-7` | Container and subview skipped during drawing emission | PASS |
| `NGUI-P7-8` | Circle primitives successfully compiled with correct cx/cy/r values | PASS |
| `NGUI-P7-9` | Primitives 'path' and 'group' fail closed | PASS |
| `NGUI-P7-10`| Duplicate `get_slot_value` definition removed from `SlotBinder` | PASS |
| `NGUI-P7-11`| Missing parent reference fails closed | PASS |
| `NGUI-P7-12`| Cyclic composition hierarchies fail closed | PASS |
| `NGUI-P7-13`| Descendant node overflowing subview boundary fails closed | PASS |
| `NGUI-P7-14`| Preflight receipt generated with timestamp and scene digest | PASS |
| `NGUI-P7-15`| Receipts and outputs contain no absolute paths | PASS |
| `NGUI-P7-16`| Headless execution without GPU/Window/DOM | PASS |
| `NGUI-P7-17`| Zero VM contract dispatch or bytecode execution | PASS |
| `NGUI-P7-18`| Portability boundary preserved and compliance markers present | PASS |
