# LAB-VECTOR-MATH-FIELD-ALIGNMENT-P1

**Status:** CLOSED — PROVED 49/49 — VM-P10 RESOLVED (Ruby 36→0; Rust ok/0 preserved)  
**Route:** lab / app-pressure / vector_math source hygiene  
**Date:** 2026-06-13  
**Scope:** classify and fix `VM-P10` field name mismatch  
**Authority:** app source migration only unless proof discovers a compiler bug

## Goal

Resolve the remaining `vector_math` Ruby blocker:

```text
record literal missing required field: r0/r1/r2
unexpected field: x/y/z
```

Wave P8 status:

- Rust: `ok/0`
- Ruby: `oof/36`
- All 36 diagnostics are `VM-P10` field-name mismatch.

The registry currently says the app likely has record literal shapes using `x/y/z` where the inferred expected type is `Mat3` (`r0/r1/r2`) or vice versa. This card must prove the exact mismatch source and either apply a narrow app source alignment or open a language follow-up.

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/vector_math/PRESSURE_REGISTRY.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/vector_math/types.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/vector_math/vec2.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/vector_math/vec3.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/vector_math/mat3.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/vector_math/geometry.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/vector_math/example.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/.agents/work/cards/lang/LANG-RUBY-RECORD-LITERAL-INFERENCE-P3.md`

## Questions

1. Which contracts produce the 36 Ruby field mismatch diagnostics?
2. Are the offending record literals intended to be `Vec2`, `Vec3`, `Vec4`, `Mat3`, or `AABB`?
3. Is Ruby selecting the wrong candidate type, or is app source ambiguous/misaligned?
4. Does adding compute annotations disambiguate the expected type?
5. Does the same source edit preserve Rust `ok/0`?
6. Is there any need for compiler work, or is this app-local hygiene?

## Deliverables

- Proof runner: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_vector_math_field_alignment_p1.rb`, target at least 45 checks.
- Lab doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/governance/lab-vector-math-field-alignment-p1-v0.md`.
- Optional narrow app source edits if the proof shows a clear alignment fix.
- Update `vector_math/PRESSURE_REGISTRY.md`.
- Card update and portfolio update after closure.

## Acceptance

- Ruby diagnostics drop from 36 to 0, or the next blocker is precisely named.
- Rust remains clean.
- The proof distinguishes wrong candidate selection from real app field mismatch.
- No unrelated math model or fixed-point changes are made.

## Closed Surfaces

- No compiler changes unless the proof demonstrates a language bug.
- No numeric semantics changes.
- No broad renaming outside the specific mismatched shapes.

## Findings

### Root cause (compiler inference gap)

`infer_record_literal` propagates the outer node_name ("result") into inner
field-value literal inference via `fields.transform_values { |v| infer_expr(v, ..., node_name) }`.
When `@output_type_hints["result"] = Mat3` (from `output result : Mat3`), every
inner `{x,y,z}` literal inside the outer `{r0:..., r1:..., r2:...}` literal is
validated against Mat3 — wrong.

6 mat3.ig contracts affected: Mat3Identity, Mat3Transpose, Mat3Add, Mat3Scale,
MakeRotation2D, MakeScale3D. Each contributes 6 deduped errors → 36 total.

Attribution note: `CompilationReport.enrich` uses `contracts[0].name` for all
diagnostics; `MultifileResolver` puts `SimulateFrame` first, so errors appeared
under SimulateFrame in the multifile run. The actual source was always mat3.ig.

### Fix applied (app source migration)

6 mat3.ig contracts: extracted inner Vec3 row literals as annotated computes
(`compute r0 : Vec3 = {...}`). Each annotated compute installs a temporary
`@output_type_hints["r0"] = Vec3` scoped only to that compute's inference,
preventing Mat3 hint pollution. Outer `compute result = {r0: r0, r1: r1, r2: r2}`
uses symbol references — validates correctly against Mat3 hint.

## Deliverables

| Artefact | Path | Status |
|----------|------|--------|
| App source edit | `igniter-lab/igniter-apps/vector_math/mat3.ig` | 6 contracts updated |
| Proof runner | `igniter-lab/igniter-view-engine/proofs/verify_lab_vector_math_field_alignment_p1.rb` | 49/49 PASS |
| Lab doc | `igniter-lab/lab-docs/governance/lab-vector-math-field-alignment-p1-v0.md` | Written |
| PRESSURE_REGISTRY | `igniter-lab/igniter-apps/vector_math/PRESSURE_REGISTRY.md` | VM-P10 RESOLVED, Wave P9 added |
| This card | CLOSED |
| Portfolio | `igniter-lab/.agents/portfolio-index.md` | Prepended |

## Open Routes

| Card | Scope |
|------|-------|
| `LAB-NESTED-RECORD-LITERAL-TYPING-P1` | Compiler fix: do not propagate outer record node_name into field value literal inference |
| `APP-RECHECK-WAVE-P9` | Re-freeze vector_math baseline (now DUAL-CLEAN) |
