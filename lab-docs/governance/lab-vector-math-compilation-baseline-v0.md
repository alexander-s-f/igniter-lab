# Lab: Vector Math Compilation Baseline

**Track:** LAB-VECTOR-MATH-BASELINE-P1  
**Date:** 2026-06-12  
**Proof runner:** `igniter-lab/igniter-view-engine/proofs/verify_lab_vector_math_baseline_p1.rb`  
**Result:** 83/83 PASS

---

## Purpose

Freeze `vector_math` as a canonical regression baseline for multi-file Rust compilation.
This app exercises the full Igniter compilation pipeline across six source files with 37
contracts, no diagnostics, no stdlib imports, and no external capability claims. It serves
as the simplest stable test for: multi-file parse/classify/typecheck/emit/assemble, manifest
integrity, SIR structure, sourcemap presence, artifact hash determinism, and liveness counter
non-breach.

---

## App Structure

| File | Module | Contracts | Types |
|------|--------|-----------|-------|
| `types.ig` | VectorMathTypes | 0 | Vec2, Vec3, Vec4, Mat3, ScalarResult, Ray, AABB |
| `vec2.ig` | VectorMathVec2 | 9 | — |
| `vec3.ig` | VectorMathVec3 | 11 | — |
| `mat3.ig` | VectorMathMat3 | 8 | — |
| `geometry.ig` | VectorMathGeometry | 5 | — |
| `example.ig` | VectorMathExample | 4 | — |

**Total:** 6 source units, 37 contracts, 7 named types.

---

## Baseline Numbers (frozen 2026-06-12)

| Metric | Value |
|--------|-------|
| status | ok |
| source units | 6 |
| contracts | 37 |
| stages | parse ok / classify ok / typecheck ok / emit ok / assemble ok |
| diagnostics | 0 |
| warnings | 0 |
| source_hash | `sha256:14f7a9c13173eee88dc168103f9e44791bb1b3916a1da96dbc39c61b5edd48b5` |
| artifact_hash | `sha256:1f9daf1875c1e4dda41f388fce3d866ef096958e1b1a3353999cab28b3daf23c` |
| liveness: typechecker.infer_expr.max_depth | 8 (limit 1000) |
| liveness: form_resolver.walk_expr.max_depth | 7 (limit 1000) |
| liveness breaches | 0 |

Artifact hash was verified stable across two independent compilation runs of identical sources.

---

## Proof Matrix

| Section | Topic | Checks |
|---------|-------|--------|
| A | Preconditions (compiler binary + 6 source files) | 7 |
| B | Compilation status + diagnostics | 4 |
| C | Pipeline stages (all 5 ok) | 6 |
| D | Source units (count, modules, hashes, paths) | 11 |
| E | Contracts (count, names, SIR, index, files) | 9 |
| F | Artifact files (manifest, SIR, sourcemap, report, diag) | 8 |
| G | Hash stability (2 runs) | 9 |
| H | Semantic IR integrity | 6 |
| I | Sourcemap | 3 |
| J | Liveness counters non-breaching | 10 |
| K | Ruby parity gap (documented, not failure) | 3 |
| L | Manifest metadata | 7 |
| **Total** | | **83** |

---

## Ruby Parity Gap

The Ruby toolchain (`igniter-lang/bin/igc`) does not support multi-file compilation at this
baseline. Multi-file import resolution (`import ModuleName`) requires the Rust compiler. This
is a known, documented parity gap — it is NOT a baseline failure. The Ruby toolchain is
exercised by single-file proof runners elsewhere.

---

## Closed Surfaces

- No vector stdlib promotion (`Vec2`, `Vec3`, etc. remain app-local types)
- No numeric semantics change (arithmetic ops via `call_contract` only)
- No Ruby parity implementation (gap documented above)
- No source edits to the app (all files read-only for this proof)
- No new stdlib import authority

---

## Next Route

This baseline is a freeze, not an implementation milestone. Any future regression runner for
multi-file compilation should import these constants and verify against them. If the app is
extended, the baseline must be re-frozen under a new P-number with an updated proof runner.
