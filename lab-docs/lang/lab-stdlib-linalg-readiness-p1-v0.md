# lab-stdlib-linalg-readiness-p1-v0 — vectors, matrices, linear algebra boundary

**Card:** `LAB-STDLIB-LINALG-READINESS-P1` · **Type:** readiness / design (NO code)
**Status:** CLOSED (readiness) — picks the first linear-algebra slice and its home (package vs stdlib), ranked
by live app-pressure. Authority: lab readiness; stdlib canon is governance-owned (this feeds it).

## Verify-first pressure inventory (live)

The pressure already exists and is **fixed-shape small vectors/matrices**, not generic tensors:

- **`apps/igniter-apps/vector_math`** — `Vec3 { x, y, z }` records + a `Mat3` built from **three `Vec3` rows**.
  Ops in use (via `call_contract`): `Add`, `Scale`, `Reflect`, matrix-vector multiply (`Mul`), `MakeRotation2D`,
  `MakeScale3D`, squared-distance. Numeric base = **Integer milli-units (scale 1000)** (the fixed-point app
  convention, `lab-stdlib-numeric-fixed-point-readiness-v0`).
- **`apps/igniter-apps/neural_net`** — a dense 2×2 layer written **unrolled**: `z1 = (x.x1*w.w11)+(x.x2*w.w12)+b1`,
  fixed-point scale 1000 (divide by 1000 after multiply). A hand-unrolled matrix-vector product.
- **`lab-vector-math-field-alignment-p1-v0`** (governance) — `mat3.ig` has 6 contracts constructing `Mat3`
  from inner `Vec3` row literals: `Mat3Identity / Mat3Transpose / Mat3Add / Mat3Scale / MakeRotation2D /
  MakeScale3D`. Rust typecheck ok throughout.
- N-body / Kuramoto (this line) work in **Float** (`Collection[Float]`, `det_sqrt`) — the *scientific* base.
- Substrate today: **records with named fields work** (proven in the P11 N-body proof), scalar numeric basics
  **landed** (`abs/min/max/clamp/sign`, P7), `sqrt`/`det_sqrt` landed (P2/P5). So vectors are **already
  expressible as pure `.ig` records + helper contracts** — both apps do exactly this. **No VM builtin is
  required to start.**

**Verdict:** the proven pressure is **fixed `Vec3` + `Mat3` records + pure helper contracts** — and it is
*already implemented app-locally and duplicated* (vector_math + neural_net + the mat3 governance work). The
real question is therefore not "can we" but **"extract the duplicated fixed-shape pattern into a shared home,
and which home."**

## The fixed-shape vs generic decision (Q6, design constraint)

**Fixed-shape typed records win for v0.** A `Vec3 { x, y, z }` / `Mat3 { r0, r1, r2 }` carries its shape **in
the type** → shape mismatches are **compile-time / impossible**, no runtime shape validation, no hidden
dynamic shape errors (the card's explicit fear). A generic `Matrix { rows, cols, values: Collection }` needs
**runtime shape checks** (multiply requires `a.cols == b.rows`, etc.) — dynamic errors that fight Igniter's
typed/explicit/replayable model. **Generic `Matrix[R,C]` is deferred** until fixed shapes prove insufficient.

## Representation (Q3)

**Records, not collections, not opaque stdlib types.**
- *Records* (`Vec3{x,y,z}`) — named-field access, fixed arity in the type, ergonomic, already proven; pure
  `.ig`.
- *Collections* (`Collection[Float]`) — lose the fixed shape and field ergonomics; fine for N-vectors later,
  wrong for Vec3.
- *Opaque stdlib types* — would need VM builtins; rejected (pure `.ig` records are expressive enough now).

## Package vs stdlib (Q8) — the headline boundary

**A local `.ig` package first, NOT stdlib canon.** Vectors/matrices are *composite* types with many helper
contracts; `stdlib.Math` stays **scalar** (`abs/min/max/sin/sqrt/...`). The **LOCAL package model is now
feature-complete** (package-manager wave P1–P16: workspace resolver, content+toolchain lock, import scoping,
exports), so a shared `linalg` package is exactly what it was built for — **linalg is the first real
scientific consumer of the package wave.** Extract the duplicated `Vec3`/`Mat3` pattern from
vector_math/neural_net into one package; promote to stdlib canon only after the package proves the surface and
a governance PROP. (Authority boundary: lab/package evidence first, canon later.)

## Deterministic / fast math policy (Q5, constraint)

- `add/sub/scale/dot` are pure arithmetic → **deterministic by construction** (exact on Integer; exact on
  Float for `+ − ×`). No det variant needed.
- **`norm` is the only sqrt site.** Mirror the math fork: ship **`norm`** (fast `sqrt`, local sim) and
  **`det_norm`** (`det_sqrt`, replay-safe) — `det_norm(v) = det_sqrt(dot(v,v))`. The emergence/replay line uses
  `det_norm`; local visualization may use `norm`. `distance(a,b) = norm(sub(a,b))` inherits the same fork.

## Numeric base (Q4) — no implicit coercion

Two **parallel, non-coercing** instantiations, picked by consumer:
- **Float `Vec3`** — the *scientific* base (Kuramoto/N-body/control sim), with `det_norm` for replay. **Lead
  with this** (det_sqrt just landed; the active emergence pressure is Float).
- **Integer fixed-point `Vec3`** (milli-units) — the *existing* `vector_math`/`neural_net`/embedded base;
  deterministic by construction, FPU-free. A **documented parallel** to reconcile/extract next, **not** mixed
  with Float (no implicit coercion — the constraint).

`norm` on the Integer base needs **`isqrt`** (P8 integer roots) — already the proven "lifts sqrt-free" win;
on the Float base it needs `det_sqrt` (landed). Both deterministic.

## Candidate splits compared (≥5)

| # | Split | Verdict |
|---|---|---|
| 1 | **`Vec2`/`Vec3` records + pure helpers** (`dot/norm/distance/scale/add/sub/cross`) | **RECOMMENDED — first slice** (proven pressure, pure `.ig`) |
| 2 | **`Mat2`/`Mat3` records + pure helpers** (`identity/transpose/add/scale/mat_vec_mul/rotation`) | **RECOMMENDED — second slice** (after vectors; mat3 governance work exists) |
| 3 | Generic `Matrix{rows,cols,values}` + runtime shape validation | **DEFERRED** — runtime shape errors, against the typed model |
| 4 | Separate `linalg` **local package** vs core stdlib | **RECOMMENDED: local package** (composite types; package model complete; stdlib stays scalar) |
| 5 | VM builtins for matrix ops | **DEFERRED** — pure `.ig` is expressive enough; add only if a real sim proves it slow (Q9) |

## Performance (Q9)

Pure `.ig` records + helper contracts; the P11 N-body order parameter ran instantly. **No benchmark now.**
Future measurement shape (only if pressure appears): time a bounded N-body or `Mat3·Vec3`-heavy step; if pure
`.ig` is too slow, *then* consider a VM builtin for the hot op — pressure-proven, not speculative.

## First implementation card + acceptance matrix (Q10)

**`LAB-STDLIB-LINALG-VEC3-PACKAGE-P2` — Float `Vec3` local package.**

| Acceptance dimension | Target |
|---|---|
| Home | a **local `.ig` package** (`linalg`/`vec3`), consumed via the package-manager workspace model — NOT stdlib |
| Type | `Vec3 { x: Float, y: Float, z: Float }` (fixed shape; shape in the type) |
| Ops | `add`, `sub`, `scale`, `dot`, `cross`, `norm` (fast), `det_norm` (`det_sqrt`), `distance`/`det_distance` |
| Determinism | `add/sub/scale/dot/cross` exact; `det_norm` replay-safe via `det_sqrt`; documented |
| Representation | pure `.ig` helper contracts over the record — **no VM builtin** |
| Shape safety | fixed-shape in the type — **no runtime shape validation** |
| Coercion | Float-only; no Integer/Decimal mixing (Integer fixed-point Vec3 is a parallel card) |
| Tests | compile + VM-value (e.g. `dot([1,0,0],[1,0,0])=1`, `det_norm([3,4,0])=5`, `cross(x̂,ŷ)=ẑ`) through real compiler+VM |
| Scope | no Mat3 (next card), no generic Matrix, no VM builtins, no Integer base |

Follow-ons: `LAB-STDLIB-LINALG-MAT3-PACKAGE-P3` (Mat3 + transpose/mat_vec_mul/rotation, extracting the mat3
governance work); `LAB-STDLIB-LINALG-FIXEDPOINT-VEC3-Pn` (the Integer milli-unit base, `isqrt` norm, embedded).

## Acceptance (this card) — mapping

- [x] Live pressure inventory completed (vector_math Vec3/Mat3, neural_net unrolled dense, mat3 governance, N-body Float).
- [x] ≥5 linalg candidates categorized (table).
- [x] Fixed-shape vs generic decided (**fixed-shape records**; generic Matrix deferred — no runtime shape errors).
- [x] Representation proposed (**records**, pure `.ig` helpers; not collections/opaque).
- [x] Deterministic/fast math policy stated (`add/dot/scale` exact; `norm` fast vs `det_norm` replay-safe).
- [x] Package-vs-stdlib boundary stated (**local package first**; stdlib stays scalar; linalg = first package-wave science consumer).
- [x] First impl card named with acceptance matrix (`LAB-STDLIB-LINALG-VEC3-PACKAGE-P2`).
- [x] No production code changes.

## Closed scope

No implementation; no generic tensor engine; no BLAS/LAPACK/native dep; no benchmark (future shape only); no
GPU/SIMD; no canon claim.

## Next

`LAB-STDLIB-LINALG-VEC3-PACKAGE-P2` (Float Vec3 local package), then Mat3, then the Integer fixed-point base.
This is also the **first scientific consumer of the completed local package model** — extracting the
vector_math/neural_net duplication into one shared, version-pinned package.

---

*Lab readiness. 2026-06-21. Linear algebra starts as **fixed `Vec3`/`Mat3` records + pure `.ig` helper
contracts in a LOCAL package** (not generic tensors, not stdlib canon, not VM builtins) — the pattern already
implemented and duplicated across vector_math/neural_net. Shape lives in the type (no runtime shape errors);
`add/dot/scale` are exact; `norm` forks fast `sqrt` vs replay-safe `det_norm`; Float base leads (sim line),
Integer fixed-point is a parallel. First impl card: `LAB-STDLIB-LINALG-VEC3-PACKAGE-P2`.*
