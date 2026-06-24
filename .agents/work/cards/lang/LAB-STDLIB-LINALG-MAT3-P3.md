# LAB-STDLIB-LINALG-MAT3-P3 - fixed-shape Mat3 local package proof

Status: CLOSED
Lane: stdlib science / linear algebra
Type: implementation proof
Date: 2026-06-24
Skill: idd-agent-protocol

## Context

`LAB-STDLIB-LINALG-VEC3-PACKAGE-P2` proved a local Float `Vec3` package through the real workspace resolver,
lock/verify, compiler, and VM. The follow-on named there is `Mat3`: fixed-shape records, no generic matrix.

This is useful for rotations, simulation state transforms, small physics/control systems, and as pressure for
future complex/quantum work without inventing a generic tensor system.

## Goal

Add a local-package proof for `Mat3` over Float `Vec3` rows.

## Verify First

Read:

- `lab-docs/lang/lab-stdlib-linalg-vec3-package-p2-v0.md`;
- existing Vec3 package/fixture files;
- workspace package resolver tests;
- any governance `mat3.ig` or vector_math examples.

Do not move anything into canon or prelude.

## Requirements / Acceptance

- [x] Define `Mat3` as a fixed-shape record of three `Vec3` rows or an explicitly justified equivalent.
- [x] Provide pure `.ig` helpers at minimum:
      `identity`, `transpose`, `add`, `scale`, `mat_vec_mul`, `mat_mul`.
- [x] Add at least one rotation helper if already present in governance examples; otherwise document why deferred.
- [x] Prove exact VM results for:
      identity * v = v;
      transpose(transpose(m)) = m;
      scale/add sanity;
      known matrix-vector multiplication.
- [x] Prove workspace resolver + lock/verify still works for Vec3 + Mat3 package.
- [x] Keep `norm`/`det_norm` policy unchanged; no fast-vs-det confusion.
- [x] Add proof doc `lab-docs/lang/lab-stdlib-linalg-mat3-p3-v0.md`.
- [x] `git diff --check` clean.

## Closed Surfaces

- No generic Matrix[R,C].
- No BLAS/SIMD/GPU.
- No dynamic dimensions.
- No Complex/qubit surface.
- No canon promotion.

## Expected Checks

Run the focused package/VM tests you add, plus the existing Vec3 package proof if practical.

## Closing Report

Proof doc: `lab-docs/lang/lab-stdlib-linalg-mat3-p3-v0.md`.

**Decision:** built Mat3 over the **Float** P2 Vec3 (three `Vec3` rows). The governance
`apps/igniter-apps/vector_math/mat3.ig` is the **structural** reference only — it uses the Integer milli-unit
(`/1000`) convention, which is a separate fixed-point track (no coercion with Float). New isolated fixture
`linalg_mat3/` so the P2 `linalg_vec3` fixture/tests are untouched.

**Package files added (all new, no shared source changed):**
- `lang/igniter-compiler/tests/fixtures/project_mode/linalg_mat3/linalg/{igniter.toml,src/vec3.ig,src/mat3.ig}`
- `lang/igniter-compiler/tests/fixtures/project_mode/linalg_mat3/app/{igniter.toml,src/main.ig}`
- `lang/igniter-vm/tests/linalg_mat3_tests.rs` ; `lang/igniter-compiler/tests/linalg_mat3_tests.rs`

**Contracts:** `Mat3Identity`, `Mat3Transpose`, `Mat3Add`, `Mat3Scale`, `Mat3MulVec3`, `Mat3Mul`
(matrix-matrix — new vs governance), `Mat3MakeRotationZ` (cos/sin precomputed Float inputs — trig kept
outside, so norm/det_norm policy unchanged, no fast-vs-det confusion).

**Exact VM outputs** (m=[[1,2,3],[4,5,6],[7,8,9]]):
- identity = diag(1,1,1); identity·(1,2,3) = (1,2,3)
- transpose(m) = [[1,4,7],[2,5,8],[3,6,9]]; transpose(transpose(m)) = m
- m+ones = [[2,3,4],[5,6,7],[8,9,10]]; m·2 = [[2,4,6],[8,10,12],[14,16,18]]
- m·(1,0,0) = (1,4,7); shearₐ·shear_b = [[7,2,0],[3,1,0],[0,0,1]]
- rotZ(cos=0,sin=1)·(1,0,0) = (0,1,0)

**Resolver/lock evidence:** `igc compile --project-root linalg_mat3/app` → `status: ok`, 0 errors;
`igc lock` + `igc verify --strict` → ok + integrity ok.

**Commands & results:**
- `cargo test --test linalg_mat3_tests` (compiler) → 2 passed
- `cargo test --test linalg_mat3_tests` (vm) → 1 passed (9 value checks)
- `cargo test --test linalg_vec3_tests` (compiler+vm) → 3 passed (P2 regression clean)
- `git diff --check` → clean

**Deferred surfaces:** Mat3 determinant/inverse; Integer milli-unit Mat3 (fixed-point track); generic
`Matrix[R,C]`; canon/prelude promotion. No generic matrix / BLAS-SIMD-GPU / dynamic dims / Complex-qubit added.
