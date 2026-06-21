# LAB-STDLIB-LINALG-VEC3-PACKAGE-P2 — Float Vec3 local package proof

Status: CLOSED
Lane: standard / stdlib science / linear algebra
Type: implementation proof
Delegation code: OPUS-STDLIB-LINALG-VEC3-PACKAGE-P2
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

Depends on:

- `LAB-STDLIB-LINALG-READINESS-P1` — chose fixed-shape records and a local package first.
- package-manager wave P1-P8 — local package + lock/verify infrastructure exists.
- `LAB-STDLIB-MATH-DET-TIER1-P5` — `det_sqrt` available.
- `LAB-STDLIB-MATH-NUMERIC-BASICS-P7` — scalar basics available.

The goal is not to canonize linalg into scalar stdlib. The goal is to prove the first science package shape:
fixed `Vec3` record + pure `.ig` helper contracts, imported by a small consumer app/test.

## Goal

Create a local package proof for Float `Vec3`:

- type `Vec3 { x: Float, y: Float, z: Float }`
- `vec3(x,y,z)`
- `add(a,b)`, `sub(a,b)`, `scale(v,k)`
- `dot(a,b)`
- `cross(a,b)`
- `norm(v)` using fast `sqrt`
- `det_norm(v)` using deterministic `det_sqrt`
- `distance(a,b)`

Use pure `.ig` contracts. No VM builtins.

## Verify first

- `lab-docs/lang/lab-stdlib-linalg-readiness-p1-v0.md`
- `apps/igniter-apps/vector_math/*`
- `apps/igniter-apps/neural_net/*`
- package/workspace examples and tests for local package imports.
- `lang/igniter-compiler/src/project.rs` and package lock/verify tests if package layout is needed.
- record construction and field access tests.

Let live package mechanics decide the file layout. Prefer a local lab package under the established package
fixture area; do not invent a new repo layout.

## Semantics

- All values are Float.
- `dot` = `a.x*b.x + a.y*b.y + a.z*b.z`.
- `cross` = right-handed vector product.
- `norm` = `sqrt(dot(v,v))`.
- `det_norm` = `det_sqrt(dot(v,v))`.
- `distance(a,b)` = `norm(sub(a,b))`, and optionally `det_distance` if needed to avoid ambiguity.
- No shape checks: shape is in the `Vec3` type.
- No implicit numeric coercion.

## Required implementation

- Add a local package or fixture with the `Vec3` type and pure contracts.
- Add a consumer proof that imports/uses the package through the real package/workspace resolver if feasible.
- If package import mechanics are too heavy for this card, create a self-contained fixture and document the
  exact package blocker; do not fake package success.
- Add compiler tests and VM tests for exact values.
- Add lock/verify test only if a package manifest is introduced.

## Acceptance

- [x] `Vec3` type and constructors compile.
- [x] `add/sub/scale` execute with exact expected Float values ((5,7,9)/(−3,−3,−3)/(2,4,6)).
- [x] `dot` executes correctly (32.0).
- [x] `cross((1,0,0),(0,1,0)) = (0,0,1)`.
- [x] `norm((3,4,0)) = 5.0` through fast `sqrt`.
- [x] `det_norm((3,4,0)) = 5.0` through `det_sqrt`.
- [x] `distance` executes correctly (5.0).
- [x] A real compiler+VM proof runs the contracts; no string-only proof.
- [x] Packaged: `igc lock` + `igc verify --strict` story tested (CI-trustable).
- [x] No VM builtins, no generic matrix/tensor, no hidden dynamic shape errors.
- [x] Proof doc written: `lab-docs/lang/lab-stdlib-linalg-vec3-package-p2-v0.md`.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-21)

**Built** a Float `Vec3` **local package** — `type Vec3 { x,y,z : Float }` + 9 pure `.ig` helper contracts
(`Vec3Make/Add/Sub/Scale/Dot/Cross/Norm/DetNorm/Distance`) — and a consumer `app` that imports the `Vec3`
type and calls the ops via `call_contract` **through the real workspace resolver**. Fixture:
`tests/fixtures/project_mode/linalg_vec3/{linalg,app}`. **Pure `.ig`, no VM builtins, ZERO shared-source
change** — the first scientific consumer of the completed local package model (wave P1–P16).

**Proof (real compiler + VM, exact values):** resolver-compile `status: ok` (cross-package type import +
`call_contract` resolve); `igniter-vm run` gives `Add=(5,7,9)`, `Sub=(−3,−3,−3)`, `Scale=(2,4,6)`, `Dot=32`,
`Cross=(0,0,1)`, `Norm=5.0` (fast sqrt), `DetNorm=5.0` (det_sqrt), `Distance=5.0`. Package is
**lock/verify-clean**: `igc lock` + `igc verify --strict` pass (CI-trustable). 3 tests (1 VM end-to-end value +
2 compiler resolver/lock), all green; `git diff --check` clean.

**Key decisions:** fixed shape in the type → **no runtime shape checks**; records (not collections/opaque);
**`Norm` forks fast `sqrt` vs replay-safe `DetNorm` (`det_sqrt`)** — the only sqrt site, everything else exact
Float arithmetic. No coercion. Local package (not stdlib canon) — composite types stay out of scalar
`stdlib.Math`; promotion needs a governance PROP.

**Follow-ons:** `LAB-STDLIB-LINALG-MAT3-P3` (Mat3 = 3 Vec3 rows + transpose/mat_vec_mul/rotation, from the
`mat3.ig` governance work); `LAB-STDLIB-LINALG-FIXEDPOINT-VEC3-Pn` (Integer milli-unit base, `isqrt`-norm,
embedded). Generic `Matrix[R,C]` deferred (runtime shape errors).

## Proof doc requirements

The proof doc must include:

- exact package/fixture layout;
- record representation and operations table;
- deterministic vs fast norm policy;
- exact tests and counts;
- package resolver evidence or blocker;
- follow-ons: Mat3 package, fixed-point Vec3, generic matrices deferred.

## Closed scope

- No Mat3 implementation in this card.
- No generic Vector/Matrix/tensor engine.
- No Integer fixed-point Vec3.
- No VM builtins, BLAS, SIMD, GPU.
- No performance benchmark.
- No canon claim.

## Next

After this proof, open `LAB-STDLIB-LINALG-MAT3-P3` or `LAB-STDLIB-LINALG-FIXEDPOINT-VEC3-Pn` depending on
which app pressure wins: transforms/neural dense layer vs embedded fixed-point.
