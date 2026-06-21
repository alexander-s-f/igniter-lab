# lab-stdlib-linalg-vec3-package-p2-v0 — Float Vec3 local package proof

**Card:** `LAB-STDLIB-LINALG-VEC3-PACKAGE-P2` · **Type:** implementation proof
**Status:** CLOSED — a Float `Vec3` **local package** (fixed-shape record + pure `.ig` helper contracts) is
imported by a consumer through the **real workspace resolver**, compiles clean, is **lock/verify-clean**, and
every operation runs to **exact values** through the VM. **Pure `.ig`, no VM builtins, no generic matrix, no
shared-source change** — the first scientific consumer of the completed local package model (wave P1–P16).

## Package / fixture layout

Under the established package-fixture area, a two-package workspace:

```text
lang/igniter-compiler/tests/fixtures/project_mode/linalg_vec3/
  linalg/                       # the package
    igniter.toml                #   source_roots = ["src"]   (no [exports] ⇒ open)
    src/vec3.ig                 #   module Linalg.Vec3 — type Vec3 + 9 pure contracts
  app/                          # the consumer
    igniter.toml                #   source_roots=["src"] ; [dependencies] linalg = { path = "../linalg" }
    src/main.ig                 #   module App.Main ; import Linalg.Vec3.{ Vec3 } ; 8 proof contracts
```

The consumer imports the `Vec3` **type** across the package boundary and calls each op contract via
`call_contract("Add"/…/"Distance", …)` — resolved by the **real `igc compile --project-root`** workspace
resolver (which folds the `linalg` dependency into the same module index).

## Representation & operations

`type Vec3 { x : Float, y : Float, z : Float }` — **fixed shape lives in the type**, so there are **no runtime
shape checks** and no hidden dynamic shape errors. All values Float; **no implicit numeric coercion**. Pure
`.ig` helper contracts (no VM builtins):

| Contract | Definition | Result |
|---|---|---|
| `Vec3Make(x,y,z)` | `{x,y,z}` | `Vec3` |
| `Add(a,b)` | componentwise `a+b` | `Vec3` |
| `Sub(a,b)` | componentwise `a−b` | `Vec3` |
| `Scale(v,k)` | `v*k` | `Vec3` |
| `Dot(a,b)` | `a.x*b.x + a.y*b.y + a.z*b.z` | `Float` |
| `Cross(a,b)` | right-handed vector product | `Vec3` |
| `Norm(v)` | `sqrt(dot(v,v))` — **fast** | `Float` |
| `DetNorm(v)` | `det_sqrt(dot(v,v))` — **replay-safe** | `Float` |
| `Distance(a,b)` | `‖a−b‖` (fast `sqrt`) | `Float` |

`dot`/`norm`/`distance` inline the sum-of-squares (self-contained, no intra-package `call_contract`); the
**consumer** exercises cross-package `call_contract`. (A future refactor could compose `Norm` from `Dot` via
`call_contract`; inlining keeps each contract independently testable.)

## Deterministic vs fast norm policy

`add/sub/scale/dot/cross` are exact Float arithmetic (`+ − ×`) — **deterministic by construction**, no `det`
variant. The **only** sqrt site is the magnitude, so the fork lives there: **`Norm` = fast `sqrt`** (local
sim/visualization), **`DetNorm` = `det_sqrt`** (replay-safe — the emergence/swarm thesis). Both return `5.0`
for `(3,4,0)`; the difference is cross-architecture reproducibility, governed by `STDLIB_VERSION`.

## Exact values (real compiler + VM, no string-only proof)

Compiled via `igc compile --project-root linalg_vec3/app --entry App.Main` (real resolver), run via
`igniter-vm run --contract … --entry … --inputs …`:

| Op | Input | Output |
|---|---|---|
| `Add` | (1,2,3)+(4,5,6) | `(5,7,9)` |
| `Sub` | (1,2,3)−(4,5,6) | `(−3,−3,−3)` |
| `Scale` | (1,2,3)·2 | `(2,4,6)` |
| `Dot` | (1,2,3)·(4,5,6) | `32.0` |
| `Cross` | x̂ × ŷ | `(0,0,1)` |
| `Norm` | ‖(3,4,0)‖ | `5.0` (fast `sqrt`) |
| `DetNorm` | ‖(3,4,0)‖ | `5.0` (`det_sqrt`) |
| `Distance` | (0,0,0)→(3,4,0) | `5.0` |

## Package-resolver evidence

- The consumer compiles **clean through the real workspace resolver** (`status: ok`, 0 error diagnostics) —
  cross-package **type import** (`Vec3`) and cross-package **`call_contract`** both resolve.
- The package workspace is **lock/verify-clean**: `igc lock` writes `igniter.lock`, and `igc verify --strict`
  passes (drift-clean **and** assembly-integrity-clean) → a linalg-consuming workspace is **CI-trustable**.

## Tests & commands — exact counts

```text
$ cd lang/igniter-vm && cargo test --test linalg_vec3_tests          → 1 passed
    (vec3_ops_exact_values_through_package_and_vm — all 8 ops, end-to-end igc-resolver + VM run)
$ cd lang/igniter-compiler && cargo test --test linalg_vec3_tests    → 2 passed
    (vec3_package_compiles_through_resolver ; vec3_package_locks_and_verifies_strict)
$ git diff --check                                                   → clean
```

3 tests total. **No shared compiler/VM source changed** — the package is pure `.ig` + a fixture + tests.

## Acceptance — mapping

- [x] `Vec3` type + `Vec3Make` constructor compile.
- [x] `add/sub/scale` execute with exact Float values ((5,7,9)/(−3,−3,−3)/(2,4,6)).
- [x] `dot` = 32.0.
- [x] `cross((1,0,0),(0,1,0)) = (0,0,1)`.
- [x] `norm((3,4,0)) = 5.0` (fast `sqrt`).
- [x] `det_norm((3,4,0)) = 5.0` (`det_sqrt`).
- [x] `distance((0,0,0),(3,4,0)) = 5.0`.
- [x] Real compiler+VM proof (resolver compile + `igniter-vm run` values); no string-only proof.
- [x] Packaged: `igc lock` + `igc verify --strict` story tested (CI-trustable).
- [x] No VM builtins, no generic matrix/tensor, no runtime shape checks (shape in the type).
- [x] `git diff --check` clean.

## Files

- `tests/fixtures/project_mode/linalg_vec3/linalg/{igniter.toml,src/vec3.ig}` (package).
- `tests/fixtures/project_mode/linalg_vec3/app/{igniter.toml,src/main.ig}` (consumer).
- `lang/igniter-vm/tests/linalg_vec3_tests.rs` (value proof).
- `lang/igniter-compiler/tests/linalg_vec3_tests.rs` (resolver + lock/verify proof).

## Follow-ons (deferred, per scope)

- **`LAB-STDLIB-LINALG-MAT3-P3`** — `Mat3` (3 `Vec3` rows) + `identity/transpose/add/scale/mat_vec_mul/
  rotation`, extracting the `mat3.ig` governance work.
- **`LAB-STDLIB-LINALG-FIXEDPOINT-VEC3-Pn`** — the Integer milli-unit base (`isqrt`-norm, embedded/FPU-free),
  matching the existing `vector_math`/`neural_net` convention; no coercion with the Float Vec3.
- **Generic `Matrix[R,C]`** — deferred indefinitely (runtime shape errors vs the typed model).
- Promotion to stdlib canon — only after the package proves the surface + a governance PROP.

## Closed scope (honored)

No Mat3; no generic Vector/Matrix/tensor; no Integer fixed-point Vec3; no VM builtins/BLAS/SIMD/GPU; no
benchmark; no canon claim.

---

*Lab proof. 2026-06-21. A Float `Vec3` local package — fixed-shape record + pure `.ig` helpers (add/sub/scale/
dot/cross/norm/det_norm/distance) — imported through the real workspace resolver, lock/verify-clean, every op
exact through the VM (cross x̂×ŷ=ẑ, norm/det_norm (3,4,0)=5). Shape in the type (no runtime checks); `norm`
forks fast `sqrt` vs replay-safe `det_norm`. The first science consumer of the local package model.*
