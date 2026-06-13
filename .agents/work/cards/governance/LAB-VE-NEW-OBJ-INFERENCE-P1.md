# LAB-VE-NEW-OBJ-INFERENCE-P1

**Status:** CLOSED — 2026-06-13  
**Route:** lab / app-pressure / vector_editor Ruby residual  
**Date:** 2026-06-13  
**Scope:** classify and resolve `VE-P09` (`new_obj`)  
**Authority:** app-pressure proof and narrow app/compiler routing only

## Goal

Investigate the last `vector_editor` Ruby diagnostic after Wave P8:

```text
OOF-P1 Unresolved symbol: new_obj
```

Rust is already clean. Ruby has one residual blocker in `tools.ig` around `compute new_obj = { ... }` feeding `call_contract("AddObjectToDoc", doc, "layer-1", new_obj)`.

The card must determine whether `VE-P09` is:

1. an app-source shape issue, fixable by annotation/refactor;
2. a missed Ruby record literal inference case after `LANG-RUBY-RECORD-LITERAL-INFERENCE-P3/P5`;
3. a `call_contract` argument propagation/order issue;
4. a type-shape ambiguity in `GraphicObject`.

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/vector_editor/PRESSURE_REGISTRY.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/vector_editor/types.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/vector_editor/tools.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/vector_editor/document.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/.agents/work/cards/lang/LANG-RUBY-RECORD-LITERAL-INFERENCE-P3.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/.agents/work/cards/lang/LANG-RUBY-RECORD-LITERAL-INFERENCE-P5.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/experiments/record_literal_inference_proof/verify_record_literal_inference_p3.rb`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/lib/igniter_lang/typechecker.rb`

## Questions

1. What exact type should `new_obj` infer to?
2. Does `new_obj` structurally match exactly one known type shape?
3. Does any field in `new_obj` remain `Unknown` before inference?
4. Would `compute new_obj : GraphicObject = { ... }` clear the Ruby diagnostic?
5. Does a source-only annotation preserve Rust clean status?
6. If annotation clears it, should this be an app hygiene migration rather than compiler work?
7. If annotation does not clear it, what Ruby TC gap remains?

## Deliverables

- Proof runner: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_ve_new_obj_inference_p1.rb`, target at least 35 checks.
- Lab doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/governance/lab-ve-new-obj-inference-p1-v0.md`.
- Optional source edit only if proof shows a narrow app annotation/refactor is sufficient.
- Update `vector_editor/PRESSURE_REGISTRY.md`.
- Card update and portfolio update after closure.

## Acceptance

- Current Ruby/Rust statuses are captured first.
- A minimal fixture reproduces `new_obj` failure outside the full app.
- The chosen route is explicit: app annotation/refactor, compiler follow-up, or no-safe-change.
- If source is changed, vector_editor must remain Rust clean and Ruby must improve or become clean.

## Closed Surfaces

- No broad record inference changes unless a separate language card is opened.
- No runtime or UI semantics.
- No changes to `GraphicObject` semantics unless the app evidence proves the shape is wrong.

## Completion Notes

**Classification:** 1 — app-source shape issue.

**Root cause:** `GraphicObject` has 7 fields in `@type_shapes`; the parser strips `?` from optional annotations so all appear required. Original `new_obj` had 5 fields. P3 structural matching requires exact field set equality → no candidates → Unknown → OOF-P1.

**Fix:** `tools.ig` only — added `compute default_text = { content: "", font_size: 0 }`, annotated `compute new_obj : GraphicObject = { ... }`, added `path_pts: []` and `text_data: default_text`.

**Result:** Ruby ok/0, Rust ok/0. vector_editor DUAL-CLEAN. Fleet is now 9/12 DUAL-CLEAN.

**Proof:** `igniter-lab/igniter-view-engine/proofs/verify_lab_ve_new_obj_inference_p1.rb` — 38/38 PASS.

**Design observation flagged (not actioned):** `?` suffix on type annotations has no semantic effect on partial record initialization. Warrants `LANG-OPTIONAL-FIELD-PARTIAL-RECORD-P1`.
