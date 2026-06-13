# LAB-VE-NEW-OBJ-INFERENCE-P1 — Lab Doc v0

**Date:** 2026-06-13  
**Card:** LAB-VE-NEW-OBJ-INFERENCE-P1  
**App:** `igniter-apps/vector_editor`  
**Pressure:** VE-P09 — `Unresolved symbol: new_obj` (Ruby OOF-P1)  
**Outcome:** RESOLVED — app source annotation/refactor (Classification 1)

---

## Context

After APP-RECHECK-WAVE-P8, `vector_editor` was the only non-DUAL-CLEAN app with a single Ruby residual:

```
OOF-P1  Unresolved symbol: new_obj  (tools.ig)
```

Rust was already ok/0. The goal was to classify VE-P09 and resolve it without compiler changes.

---

## Root Cause

**Classification 1 — app-source shape issue.**

`GraphicObject` is declared in `types.ig` with 7 fields:

| Field | Annotation |
|---|---|
| `id` | `String` |
| `kind` | `String` |
| `style` | `Style` |
| `pos` | `Point` |
| `path_pts` | `Collection[Point]?` |
| `rect_data` | `RectData?` |
| `text_data` | `TextData?` |

The `?` optional suffix is **stripped by the parser** before `@type_shapes` is built (typechecker.rb:217). All 7 fields appear as required in the structural matching table.

The original `new_obj` literal provided only 5 fields:

```
compute new_obj = {
  id: "rect-new",
  kind: "rect",
  style: default_style,
  pos: click_pos,
  rect_data: r_data
}
```

P3 structural matching (typechecker.rb:3072) requires exact field set equality:  
`shape_fields.keys.sort == literal_field_names`

With 5 fields vs 7 required → no candidates → `new_obj` infers to `Unknown` → OOF-P1.

---

## Sub-findings

### A — Annotation alone (5 fields) does not resolve

Adding `compute new_obj : GraphicObject = { ... }` with only 5 fields activates the hint path (typechecker.rb:3030), which also requires all declared fields to match shape fields. The hint path performs its own field-level type check and still returns OOF-TY0 for the missing fields.

### B — Inline nested literal under annotation inherits outer hint scope

When `compute new_obj : GraphicObject = { ..., text_data: { content: "", font_size: 0 } }` is used, the inner `{ content: "", font_size: 0 }` literal is inferred under the same `node_name = "new_obj"` hint — allowing it to resolve as `TextData` correctly.

### C — Named intermediate compute breaks hint scope

A separate `compute default_text = { content: "", font_size: 0 }` uses its own node_name `"default_text"` and has no hint in `@output_type_hints`. It resolves via P3 structural matching (exact fields: `content`, `font_size` match `TextData`). This is the safer approach used in the final fix.

---

## Fix Applied

**Scope:** `tools.ig` only. Three additions + one annotation:

```
compute default_text = {
  content: "",
  font_size: 0
}

compute new_obj : GraphicObject = {
  id: "rect-new",
  kind: "rect",
  style: default_style,
  pos: click_pos,
  path_pts: [],
  rect_data: r_data,
  text_data: default_text
}
```

Changes from the original:
1. New `compute default_text` block (3 lines) providing `TextData`-shaped literal
2. Annotation `compute new_obj : GraphicObject =` (was unannotated)
3. Added `path_pts: []` field
4. Added `text_data: default_text` field

**Result:** Ruby ok/0, Rust ok/0. vector_editor is DUAL-CLEAN.

---

## Design Observation (out of scope)

The `?` suffix on type annotations is stripped by the parser and has no semantic effect on type shape matching. A developer who writes `field : Type?` intending it to be optional in record literal initialization is currently unable to partially initialize that record — all fields must be provided regardless of `?`. This is a language gap that warrants a separate card (`LANG-OPTIONAL-FIELD-PARTIAL-RECORD-P1`).

---

## Proof

`igniter-lab/igniter-view-engine/proofs/verify_lab_ve_new_obj_inference_p1.rb`  
38/38 PASS

Sections covered:
- A: Source guards (pre-fix state confirmed oof/1)
- B: Root cause (hint path vs structural path behavior)
- C: Hint path gate (annotation alone insufficient)
- D: Inline literal gate (inline text_data under annotation)
- E: Structural fix (all 7 fields, no annotation)
- F: Annotation fix (7 fields + annotation)
- G: Full app compile with fix applied (ok/0 Ruby, ok/0 Rust)
- H: Regression (other vector_editor files unaffected)

---

## Artifacts

| Artifact | Path |
|---|---|
| Proof runner | `igniter-lab/igniter-view-engine/proofs/verify_lab_ve_new_obj_inference_p1.rb` |
| Source fix | `igniter-lab/igniter-apps/vector_editor/tools.ig` |
| PRESSURE_REGISTRY | `igniter-lab/igniter-apps/vector_editor/PRESSURE_REGISTRY.md` |
| Card | `igniter-lab/.agents/work/cards/governance/LAB-VE-NEW-OBJ-INFERENCE-P1.md` |
| Portfolio | `igniter-gov/portfolio/governance/2026-06-13-lab-ve-new-obj-inference-p1-v0.md` |
