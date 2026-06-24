# lab-stdlib-linalg-mat3-p3-v0 — Float Mat3 local package proof

**Card:** `LAB-STDLIB-LINALG-MAT3-P3` · **Type:** implementation proof
**Status:** CLOSED — a Float `Mat3` (fixed-shape record of three Float `Vec3` rows) is added to the P2 linalg
**local package**, imported by a consumer through the **real workspace resolver**, compiles clean, is
**lock/verify-clean**, and every operation (`identity`, `transpose`, `add`, `scale`, `mat_vec_mul`, `mat_mul`,
`rotationZ`) runs to **exact values** through the VM. **Pure `.ig`, no VM builtins, no generic matrix, no
shared compiler/VM source change** — the second scientific consumer of the completed local package model.

## Verify-first findings

- Read `lab-stdlib-linalg-vec3-package-p2-v0.md` and the live Vec3 fixture (`linalg_vec3/{linalg,app}`) — the
  proven pattern: fixed shape in the type, pure `.ig` helper contracts, cross-package `call_contract`,
  `igc compile --project-root` resolver, `igc lock` + `igc verify --strict`.
- Read the governance/lab `mat3.ig` (`apps/igniter-apps/vector_math/mat3.ig`). **Key boundary:** that file is
  the **Integer milli-unit** convention (`/1000` after every multiply), which the P2 follow-ons name as a
  **separate** track (`LAB-STDLIB-LINALG-FIXEDPOINT-VEC3-Pn`, *no coercion with the Float Vec3*). It is the
  **structural** reference only (3 `Vec3` rows; identity/transpose/mat-vec/add/scale/determinant/rotation),
  **not** the numeric model. This P3 builds Mat3 over the **Float** Vec3, so there is **no `/1000` scale**.
- The governance file has a Z-rotation helper (`MakeRotation2D`) but **no matrix-matrix multiply**. The card
  requires `mat_mul`, so it is implemented here (new vs the governance surface).
- Adopted the governance VM-P10 nested-hint fix: inner row literals are annotated `compute … : Vec3` so the
  Ruby typechecker gets an unambiguous row hint before the `Mat3` is assembled.

## Package / fixture layout

A self-contained two-package workspace (P2's `linalg_vec3` left **untouched** — zero regression surface):

```text
lang/igniter-compiler/tests/fixtures/project_mode/linalg_mat3/
  linalg/                       # the package (Vec3 + Mat3)
    igniter.toml                #   source_roots = ["src"]   (no [exports] ⇒ open)
    src/vec3.ig                 #   module Linalg.Vec3 — the P2 Float Vec3 (verbatim copy)
    src/mat3.ig                 #   module Linalg.Mat3 — type Mat3 + 7 pure contracts over Vec3 rows
  app/                          # the consumer
    igniter.toml                #   source_roots=["src"] ; [dependencies] linalg = { path = "../linalg" }
    src/main.ig                 #   module App.Main ; imports Vec3 + Mat3 ; 10 proof contracts
```

The consumer imports the `Vec3` **and** `Mat3` types across the package boundary and calls each Mat3 op
contract via `call_contract(…)` — resolved by the **real `igc compile --project-root`** workspace resolver,
which folds the `linalg` dependency (now carrying **both** Vec3 and Mat3 modules) into the same module index.

## Representation & operations

`type Mat3 { r0 : Vec3, r1 : Vec3, r2 : Vec3 }` — **fixed shape lives in the type** (three Float `Vec3` rows),
so there are **no runtime shape checks** and **no dynamic dimensions**. All values Float; **no implicit numeric
coercion**. Pure `.ig` helper contracts (no VM builtins):

| Contract | Definition | Result |
|---|---|---|
| `Mat3Identity` | `diag(1,1,1)` | `Mat3` |
| `Mat3Transpose(m)` | rows ↔ columns | `Mat3` |
| `Mat3Add(a,b)` | row/componentwise `a+b` | `Mat3` |
| `Mat3Scale(m,k)` | `m*k` | `Mat3` |
| `Mat3MulVec3(m,v)` | each row · `v` | `Vec3` |
| `Mat3Mul(a,b)` | `(a·b)[i][j] = Σₖ a[i][k]·b[k][j]` | `Mat3` |
| `Mat3MakeRotationZ(cos,sin)` | Z-axis rotation embedded in 3×3 | `Mat3` |

## Determinism / norm policy (unchanged)

`add/scale/mul_vec/mat_mul/transpose/rotation` are exact Float arithmetic (`+ − ×`) — **deterministic by
construction**, no `det` variant needed and no milli-unit divide. **`norm`/`det_norm` policy is unchanged:** the
only `sqrt` site in the whole linalg surface is the Vec3 magnitude, where the **fast `sqrt` vs replay-safe
`det_sqrt`** fork already lives (P2). Mat3 adds **no new sqrt and no trig** — `Mat3MakeRotationZ` takes
**precomputed `cos`/`sin` Float inputs** (mirroring governance `MakeRotation2D`), deliberately keeping trig out
of the package so there is **no fast-vs-det confusion** introduced by this card.

## Exact values (real compiler + VM, no string-only proof)

Compiled via `igc compile --project-root linalg_mat3/app --entry App.Main` (real resolver), run via
`igniter-vm run --contract … --entry … --inputs …`. With `m = [[1,2,3],[4,5,6],[7,8,9]]`:

| Op | Input | Output |
|---|---|---|
| `Identity` | — | `[[1,0,0],[0,1,0],[0,0,1]]` |
| `Identity·v` | `v=(1,2,3)` | `(1,2,3)` |
| `Transpose` | `m` | `[[1,4,7],[2,5,8],[3,6,9]]` |
| `Transpose∘Transpose` | `m` | `[[1,2,3],[4,5,6],[7,8,9]]` (= `m`) |
| `Add` | `m + ones` | `[[2,3,4],[5,6,7],[8,9,10]]` |
| `Scale` | `m · 2` | `[[2,4,6],[8,10,12],[14,16,18]]` |
| `Mat·Vec` | `m·(1,0,0)` | `(1,4,7)` |
| `Mat·Mat` | shearₐ·shear_b | `[[7,2,0],[3,1,0],[0,0,1]]` |
| `RotationZ(90°)·v` | `cos=0,sin=1`, `v=(1,0,0)` | `(0,1,0)` |

`shearₐ = [[1,2,0],[0,1,0],[0,0,1]]`, `shear_b = [[1,0,0],[3,1,0],[0,0,1]]` — hand-verified non-diagonal
product exercising off-diagonal mixing.

## Package-resolver evidence

- The consumer compiles **clean through the real workspace resolver** (`status: ok`, 0 error diagnostics) —
  cross-package **type imports** (`Vec3`, `Mat3`) and cross-package **`call_contract`** all resolve.
- The package workspace (Vec3 + Mat3) is **lock/verify-clean**: `igc lock` writes `igniter.lock`, and
  `igc verify --strict` passes (drift-clean **and** assembly-integrity-clean) → CI-trustable.

## Tests & commands — exact counts

```text
$ cd lang/igniter-compiler && cargo test --test linalg_mat3_tests   → 2 passed
    (mat3_package_compiles_through_resolver ; mat3_package_locks_and_verifies_strict)
$ cd lang/igniter-vm && cargo test --test linalg_mat3_tests          → 1 passed
    (mat3_ops_exact_values_through_package_and_vm — all 9 checks, end-to-end igc-resolver + VM run)
$ cd lang/igniter-compiler && cargo test --test linalg_vec3_tests    → 2 passed   (P2 regression — clean)
$ cd lang/igniter-vm && cargo test --test linalg_vec3_tests          → 1 passed   (P2 regression — clean)
$ git diff --check                                                   → clean
```

3 new tests (+ 3 P2 tests still green). **No shared compiler/VM source changed** — the package is pure `.ig` +
a new fixture + new tests (all additions are untracked new files).

## Acceptance — mapping

- [x] `Mat3` defined as a fixed-shape record of three `Vec3` rows.
- [x] `identity`, `transpose`, `add`, `scale`, `mat_vec_mul`, `mat_mul` provided as pure `.ig` helpers.
- [x] Rotation helper present in governance → added (`Mat3MakeRotationZ`, Float, trig kept outside).
- [x] Exact VM results: identity·v = v; transpose(transpose(m)) = m; scale/add sanity; known mat-vec (1,4,7)
      **and** known mat-mul shear product; rotation 90°·(1,0,0) = (0,1,0).
- [x] Workspace resolver + lock/verify clean for the Vec3 + Mat3 package.
- [x] `norm`/`det_norm` policy unchanged; no fast-vs-det confusion (no new sqrt/trig in Mat3).
- [x] Proof doc added (this file).
- [x] `git diff --check` clean.

## Files

- `tests/fixtures/project_mode/linalg_mat3/linalg/{igniter.toml,src/vec3.ig,src/mat3.ig}` (package).
- `tests/fixtures/project_mode/linalg_mat3/app/{igniter.toml,src/main.ig}` (consumer).
- `lang/igniter-vm/tests/linalg_mat3_tests.rs` (value proof).
- `lang/igniter-compiler/tests/linalg_mat3_tests.rs` (resolver + lock/verify proof).

## Closed surfaces (honored)

No generic `Matrix[R,C]`; no BLAS/SIMD/GPU; no dynamic dimensions; no Complex/qubit surface; no Integer
milli-unit Mat3 (separate fixed-point track); no canon/prelude promotion.

## Follow-ons (deferred, per scope)

- **`Mat3Determinant` / inverse** — the governance Integer mat3 has a determinant; a Float `det` + inverse over
  this package is a natural next proof (left out to keep P3 to the card's named op set).
- **`LAB-STDLIB-LINALG-FIXEDPOINT-VEC3/MAT3-Pn`** — the Integer milli-unit base (embedded/FPU-free), matching
  the `vector_math` convention; **no coercion** with the Float surface.
- **Generic `Matrix[R,C]`** — deferred indefinitely (runtime shape errors vs the typed model).
- Promotion to stdlib canon — only after the package proves the surface + a governance PROP.

---

*Lab proof. 2026-06-24. A Float `Mat3` (three Float `Vec3` rows) added to the P2 linalg local package — pure
`.ig` helpers (identity/transpose/add/scale/mat·vec/mat·mat/rotationZ) — imported through the real workspace
resolver, lock/verify-clean, every op exact through the VM (identity·v=v, transpose²=id, mat·mat shear product,
rotZ(90°)·x̂=ŷ). Shape in the type (no runtime checks, no dynamic dims); Float model only — the Integer
milli-unit Mat3 stays a separate track; `norm`/`det_norm` policy untouched (no new sqrt/trig).*
