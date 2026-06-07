# Headless Layout Constraint Solver Proof

**Status**: experimental · lab-only · no-canon · no-stable-schema · no-performance-claim
**Track**: `lab-native-gui-headless-layout-constraint-solver-proof-v0`
**Design Layer**: Headless Layout Constraint Solver (NGUI-P8)

This document describes the implementation and verification of a bounded headless layout constraint solver for native GUI scene trees.

---

## 1. Constraint Layout Engine

The layout resolver supports three layout modes: `absolute` (default), `row` (horizontal flow), and `column` (vertical flow).

### Padding, Margin, and Gap Spacing
- **Padding**: Spacing inside the parent container, shrinking the available layout area (content box). Supports Numeric shorthand or key-value structures (`left`, `right`, `top`, `bottom`).
- **Margin**: Spacing outside individual child elements, shifting their position relative to the content flow. Supports Numeric shorthand or key-value structures.
- **Gap**: Deterministic spacing inserted between successive visible children in `row` and `column` layout flows.

### Child Size Resolution and Capping
- Children resolve their width and height relative to their parent's inner content dimensions.
- **Cross-Axis Capping**: In `row` and `column` layouts, the cross-axis dimension of each child is capped to the parent's available cross-axis content area (`inner_w - (margin.left + margin.right)` for column cross-axis width, `inner_h - (margin.top + margin.bottom)` for row cross-axis height) to prevent clipping or layout breaking. This capping does not apply to `flex` layouts (the legacy runtime flow), which allows children to overflow.
- **Proportional Weight Allocation**: Children can specify layout/style weights. The remaining available space in the parent container after placing all fixed-size children and gaps is allocated proportionally among weighted children.

---

## 2. Alignment Logic

Alignment controls how children are arranged on the layout axis (main-axis alignment) and how they are positioned on the cross-axis (cross-axis alignment):
- **Start**: Children are aligned to the start of the layout box (offset by parent padding and child margin).
- **Center**: Children are centered within the available parent space, shifting the start offset by half of the unused dimension.
- **End**: Children are pushed to the end of the layout box, shifting the start offset by the full unused dimension.

---

## 3. Explicit Overflow Policy

To support advanced rendering flows (e.g. scroll areas or explicit overlays), the composition preflight boundary check implements an explicit overflow policy:
- By default, all descendant nodes of a `subview` must lie strictly within the geometric bounds of that subview.
- If the parent subview node declares `overflow: "allow"` or `overflow: "scroll"` in either its `layout` or `style` definitions, the preflight geometric containment checks are bypassed, permitting controlled overflow.

---

## 4. Bounded Security and Validation Invariants

The constraint solver acts as a security gate, failing closed for the following invalid parameters:
- **Non-Numeric Values**: Non-numeric values for gap, padding, margin, weights, and layout positions.
- **Negative Values**: Negative dimensions, padding, margins, or gaps.
- **Excessive Depth**: Nested child nodes exceeding 9 levels of parent links (depth $\ge$ 10) are rejected with `NGUI-P8-14`.
- **Composition Cycles**: Cyclic parent references (e.g., `A` -> `B` -> `A`) are detected during validation and rejected with `NGUI-P1-6`.
- **P7 Safeguards**: Unsafe XML attributes, non-whitelisted SVG tags, and malicious javascript payloads are successfully rejected.

---

## 5. Verification Results

All 133 proof runner checks pass successfully:

```text
=== NGUI Proof Runner ===
Date: 2026-06-06 12:03
OS: Mac (headless)
Status: SUCCESS (ALL PASS)
Total: 133/133
```

### New P8 Checks

| Check ID | Description | Status |
| :--- | :--- | :--- |
| `NGUI-P8-1` | Row layout positions children deterministically including padding | PASS |
| `NGUI-P8-2` | Column layout positions children deterministically including padding | PASS |
| `NGUI-P8-3` | Padding and margin affect layout bounds correctly | PASS |
| `NGUI-P8-4` | Gap spacing is applied deterministically | PASS |
| `NGUI-P8-5` | Proportional weights allocate bounded space deterministically | PASS |
| `NGUI-P8-6` | Align start/center/end works for row and column | PASS |
| `NGUI-P8-7` | Nonnumeric layout values fail closed | PASS |
| `NGUI-P8-8` | Negative dimensions / gap / padding fail closed | PASS |
| `NGUI-P8-9` | Unsupported layout mode fails closed | PASS |
| `NGUI-P8-10`| Unsupported constraint key fails closed | PASS |
| `NGUI-P8-11`| Missing parent remains fail-closed | PASS |
| `NGUI-P8-12`| Composition cycles remain fail-closed | PASS |
| `NGUI-P8-13`| Subview overflow policy is explicit and enforced | PASS |
| `NGUI-P8-14`| Excessive node count/depth fails closed | PASS |
| `NGUI-P8-15`| Path/group remain unsupported for drawing | PASS |
| `NGUI-P8-16`| P7 unsafe id/font/transform/html payload checks still pass | PASS |
| `NGUI-P8-17`| Vector receipt records computed layout facts | PASS |
| `NGUI-P8-18`| Result packet is machine-readable JSON | PASS |
| `NGUI-P8-19`| No igniter-lang mainline files touched | PASS |
| `NGUI-P8-20`| Lab-only / frontier / no-canon wording preserved | PASS |
