# LAB-STDLIB-LINALG-READINESS-P1 — vectors, matrices, and linear algebra boundary

Status: CLOSED
Lane: standard / stdlib science
Type: readiness / design
Delegation code: OPUS-STDLIB-LINALG-READINESS-P1
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

Igniter already has app-local pressure for vectors and matrices:

- `apps/igniter-apps/vector_math` has `Vec3` and `Mat3`-like structures.
- `apps/igniter-apps/neural_net` hardcodes dense 2x2 layer math.
- N-body, control, pursuit, air-combat, and robotics-style examples need vectors, norms, distances, dot products,
  and small fixed matrix transforms.

The trap is building a generic tensor/NumPy clone too early. We need a small scientific surface that matches
Igniter's typed, explicit, replayable model.

## Goal

Design the first linear algebra surface and decide whether it belongs in stdlib, app-local packages, or a
separate science package.

No production code changes in this card.

## Verify first

- `apps/igniter-apps/vector_math/*`
- `apps/igniter-apps/neural_net/*`
- `lab-docs/governance/lab-vector-math-field-alignment-p1-v0.md`
- N-body / Kuramoto docs
- current record/collection capabilities and numeric math surface
- any matrix/dataframe fixtures referenced by compiler verification scripts

Search live tree for `Vec2`, `Vec3`, `Mat2`, `Mat3`, `matrix`, `dot`, `norm`, `normalize`, `distance`,
`cross`, `determinant`, `transpose`, `dense`, `layer`, `tensor`, and classify real pressure.

## Questions to answer

1. What is the first surface?
   - fixed `Vec2`/`Vec3`
   - fixed `Mat2`/`Mat3`
   - generic `Vector[N]` / `Matrix[R,C]`
   - app-local package only
2. Which operations are first?
   - `dot`, `norm`, `normalize`, `distance`
   - `cross` for Vec3
   - matrix-vector multiply
   - transpose/determinant
3. Should vectors/matrices be records, collections, or opaque stdlib types?
4. How do fixed-point Decimal/integer vectors interact with Float math?
5. Does `norm` use fast `sqrt` or deterministic `det_sqrt`?
6. What shape validation is needed for generic matrices?
7. Can current `.ig` express app-local helpers cleanly, or do we need stdlib/prelude records?
8. What belongs in `stdlib.math` vs a future `igniter-science` / package module?
9. How should performance be measured before adding VM builtins?
10. What is the first implementation card and acceptance matrix?

## Design constraints

- Do not build generic tensors first.
- Prefer fixed-shape typed records if they match pressure.
- Avoid hidden dynamic shape errors in core math.
- No implicit numeric coercion.
- Preserve deterministic/replay story: use `det_sqrt` where scientific replay needs it; state if fast Float is
  chosen for local simulations.
- Keep VM builtins out unless pure `.ig` is too slow or too verbose and pressure proves it.

## Candidate splits to compare

At least compare:

1. `Vec2`/`Vec3` records + pure helper contracts (`dot`, `norm`, `distance`, `cross`).
2. `Mat2`/`Mat3` records + pure helper contracts.
3. Generic `Matrix { rows, cols, values }` with runtime shape validation.
4. Separate `igniter-science` package instead of core stdlib.
5. VM builtins for matrix ops.

Bias: start with fixed Vec3/Mat3 app-pressure extraction, probably as lab/package evidence before stdlib canon.

## Required deliverable

Write `lab-docs/lang/lab-stdlib-linalg-readiness-p1-v0.md` with:

- pressure inventory;
- chosen first linear algebra slice;
- record vs collection vs opaque type decision;
- deterministic sqrt / Float policy;
- package-vs-stdlib boundary;
- next implementation card name + acceptance matrix.

Close this card with a report.

## Acceptance

- [x] Live pressure inventory completed. (vector_math Vec3/Mat3, neural_net unrolled dense, mat3 governance, N-body Float.)
- [x] At least five linalg candidates categorized. (5 in the table.)
- [x] Fixed-shape vs generic matrix tradeoff decided. (**fixed-shape records**; generic Matrix deferred — no runtime shape errors.)
- [x] Representation choice proposed. (**records** + pure `.ig` helpers; not collections/opaque.)
- [x] Deterministic/fast math policy stated. (`add/dot/scale` exact; `norm` fast `sqrt` vs `det_norm` `det_sqrt`.)
- [x] Package-vs-stdlib boundary stated. (**local package first**; stdlib stays scalar; linalg = first package-wave science consumer.)
- [x] First implementation card named with acceptance matrix. (`LAB-STDLIB-LINALG-VEC3-PACKAGE-P2`.)
- [x] No production code changes.

---

## Closing Report (2026-06-21)

**Decision:** linear algebra starts as **fixed `Vec3`/`Mat3` records + pure `.ig` helper contracts in a LOCAL
package** — NOT generic tensors, NOT stdlib canon, NOT VM builtins. The pressure is already proven and
*duplicated app-locally*: `vector_math` (`Vec3{x,y,z}` + `Mat3` of 3 Vec3 rows; add/scale/reflect/matvec/
rotation; Integer milli-units), `neural_net` (unrolled 2×2 dense, fixed-point), and the `mat3.ig` governance
work (6 Mat3 contracts). So the task is **extraction into a shared home**, and the home is a **local package**
— composite types don't belong in scalar `stdlib.Math`, and the **package-manager wave (P1–P16) is now
feature-complete**, making linalg its **first scientific consumer**.

**Key tradeoffs settled:** (1) **fixed-shape records** beat generic `Matrix[R,C]` — shape lives in the type →
no runtime shape validation / no hidden dynamic shape errors (the card's fear). (2) **Records**, not
collections/opaque types — pure `.ig`, already proven (P11). (3) **No VM builtins** — pure `.ig` is expressive
enough; add only if a real sim proves it slow. (4) **det policy:** `add/sub/scale/dot/cross` are exact;
**`norm` forks** fast `sqrt` vs replay-safe **`det_norm` (`det_sqrt`)** — emergence line uses `det_norm`.
(5) **No coercion:** Float `Vec3` leads (sim line, det_sqrt landed); Integer fixed-point `Vec3` (existing apps,
`isqrt` norm, embedded) is a parallel non-coercing track.

**Deliverables:** readiness packet `lab-docs/lang/lab-stdlib-linalg-readiness-p1-v0.md`; first impl card
**`LAB-STDLIB-LINALG-VEC3-PACKAGE-P2`** (Float Vec3 local package: add/sub/scale/dot/cross/norm/det_norm/
distance; fixed shape; pure `.ig`; tests through real compiler+VM) with an acceptance matrix. Follow-ons:
Mat3 package, then the Integer fixed-point base. No production code changed.

**Next:** `LAB-STDLIB-LINALG-VEC3-PACKAGE-P2`.

## Closed scope

- No implementation.
- No generic tensor engine.
- No BLAS/LAPACK/native dependency.
- No performance benchmark except proposed future shape.
- No GPU/SIMD.
- No canon claim.
