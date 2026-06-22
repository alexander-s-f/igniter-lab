# lab-stdlib-math-det-tier1-p5-v0 — deterministic Tier-1 math (det_sin/det_cos/det_sqrt)

**Card:** `LAB-STDLIB-MATH-DET-TIER1-P5` · **Delegation:** `OPUS-STDLIB-MATH-DET-TIER1-P5`
**Status:** CLOSED (implementation proof) — a second, **deterministic / replay-safe** Tier-1 surface
(`det_sin`, `det_cos`, `det_sqrt`) sits beside the fast P2 surface. `det_sin/det_cos` use a **vendored
pure-Rust `libm`** (one fixed algorithm on every target); `det_sqrt` uses **IEEE-754-correct std `f64::sqrt`**.
The surface **never emits NaN/Inf** (which would collapse to JSON `null` in the observation stream) — bad
domain / non-finite input is a deterministic runtime error. **The fast P2 surface is untouched and makes no
determinism claim.**

## Surface spelling — decided by live grammar (card's open question)

Verify-first compile, *before* wiring:
- **flat `det_sin(x)`** → `parse: ok`, `typecheck: oof` (OOF-TY0 unknown fn) — **parses**.
- **dotted `det.sin(x)`** → `parse: error` (**OOF-P0**) — a 3-level/dotted call name does **not** parse.

So the v0 surface is the **flat `det_sin` / `det_cos` / `det_sqrt`** — the least-surprising live-grammar
choice, matching the existing bare stdlib idiom (`sin`/`map`/`count`). `stdlib.Math.det.sin` is impossible
in the current grammar; `det_*` is the honest spelling. (The qualified `stdlib.math.det_sin` also dispatches
in the VM, but the bare form is canonical.)

## What changed

- **`lang/igniter-vm/Cargo.toml`** — new **normal dependency `libm = "0.2"`** (pure-Rust, `no_std`, MUSL-port
  soft-float; no system libm, no network — the documented dependency boundary; also embed-friendly for the
  swarm line).
- **`lang/igniter-vm/src/vm.rs`** — `det_sin`/`det_cos` → `libm::sin`/`libm::cos`; `det_sqrt` → `f64::sqrt`.
  Guards: non-finite input → error; `det_sqrt(x<0)` → "domain error". Finite output guaranteed.
- **`lang/igniter-compiler/src/typechecker/stdlib_calls.rs`** — `det_*` share the P2 arm: `(Float)->Float`,
  `OOF-MATH1` arity / `OOF-MATH2` non-Float. (Determinism is a *runtime/algorithm* property, not a type.)
- **`lang/igniter-stdlib/stdlib/math.ig`** — `def det_sin/det_cos/det_sqrt`; fast surface re-labelled "NOT a
  cross-architecture determinism claim".
- **`lang/igniter-stdlib/Cargo.toml` + `lang/igniter-compiler/src/lib.rs`** — stdlib surface version bumped
  **`0.1.0` → `0.1.1`** (`STDLIB_VERSION`) so package locks can detect the new deterministic math surface.

## Semantics settled (card §"Semantics to settle")

- **Return shape:** plain **`Float`** (not `Result`). Determinism lives in the algorithm; the type stays
  simple. Safety is enforced by *refusal*, not by a NaN/Result value.
- **`det_sqrt(negative)`** → deterministic **runtime error** ("domain error"), never `NaN`/`null`.
- **Non-finite input** (`NaN`/`±Inf`) to any `det_*` → deterministic **runtime error** (so the result can
  never be a non-finite `f64` that JSON would silently turn into `null`).
- **No implicit coercion** — `det_*` accept only `Float` (Integer/Decimal → `OOF-MATH2`).
- **Error taxonomy (v0):** VM runtime `Err(String)` (arity / non-Float / non-finite / domain), consistent
  with the existing VM call-error style. A typed `Result[Float, MathError]` is a deferred option.

## Determinism — exactly what is and is not proven locally

**Proven locally (this machine, x86_64):**
- **Golden vectors — exact bit equality.** `det_sin(0.5)=0x3fdeaee8744b05f0`, `det_cos(0.5)=0x3fec1528065b7d50`,
  `det_sin(1.0)=0x3feaed548f090cee`, `det_sqrt(2.0)=0x3ff6a09e667f3bcd` (the canonical √2 double). Independently
  cross-checked against Python's `math` (system libm) — **all four match to the bit**, and the Rust `libm`
  crate reproduces them exactly.
- **Repeatability** — identical bits run-to-run (tested).
- **Finite-only / no silent NaN** — negative `det_sqrt` and non-finite inputs error out (tested).
- **`det_sqrt` is IEEE-mandated** — std `f64::sqrt` is correctly-rounded by IEEE-754, so it is deterministic
  by the standard, not merely by convention.

**NOT proven locally (honest limits):**
- **Actual cross-architecture bit-identity** (aarch64/riscv64). The *claim* rests on: (a) `libm` is a single
  fixed pure-Rust algorithm, (b) Rust does not auto-contract `a*b+c` into FMA (and `f64::mul_add` is itself a
  well-defined single-rounding op on every target), so no platform-dependent rounding creeps in. **Full proof
  needs cross-arch CI** (qemu `aarch64`/`riscv64` running the golden-vector test) — deferred and named below.
- The `libm` crate's internal portability is taken on its design (soft-float, used in embedded Rust), not
  independently audited here.

**Governance:** the golden vectors are the *lock*. This P5 changes the stdlib contract surface, so
`igniter-stdlib` + compiler mirror `STDLIB_VERSION` were bumped **`0.1.0` → `0.1.1`**. A future `libm`
version/algorithm change that flips any bit makes `golden_vectors_exact_bits` fail → forcing another
deliberate, `STDLIB_VERSION`-governed change (package P6 provenance). Per the P3/P5 constraint,
deterministic output is part of stdlib semantics.

## Live end-to-end (real compiler + VM `run`)

```text
det_sin(0.5)              → 0.479425538604203          (the deterministic value = golden vector)
KuramotoRDet(0.0, 0.0)    → 1.0                         (order parameter on the det_* surface, synchronized)
```

Kuramoto is unblocked on the **replay-safe** surface by a one-call swap (`sin`→`det_sin`, `sqrt`→`det_sqrt`):
`igniter-home-lab/.../kuramoto_proof.ig` can move to `det_*` as a swarm-portability candidate with zero
rewrite; physical multi-arch identity remains pending until a hardware/swarm proof records it.

## Tests & commands — exact counts

```text
$ cd lang/igniter-vm && cargo test --test stdlib_math_det_tests       → 6 passed (golden bits, repeatable, correct, neg-sqrt error, non-finite error, arity/type)
$ cd lang/igniter-vm && cargo test --test stdlib_math_tests           → 5 passed (fast P2, unaffected)
$ cd lang/igniter-compiler && cargo test --test stdlib_math_tests     → 5 passed (3 P2 + 1 P4 + 1 NEW P5 det)
$ cd lang/igniter-compiler && cargo test --test package_workspace_tests → 46 passed (STDLIB_VERSION mirror/provenance guard)
$ cd lang/igniter-stdlib && cargo test                                → 11 passed (regexp proof + lib)
$ git diff --check                                                    → clean
```

**Pre-existing unrelated VM failure** (same as P2, re-confirmed): `vm_candidate_proof_tests::
test_proof_vmg13_local_loops_and_service_loops` (`OP_GET_FIELD: expected Record, got Integer(<unix-ts>)`) —
a service-loop/temporal test; fails on clean HEAD (git-stash-proven in P2), unrelated to math. Not introduced.

## Acceptance — mapping

- [x] Surface spelling chosen + justified by live parser (flat `det_*`; dotted = OOF-P0).
- [x] `det_sin/det_cos/det_sqrt` compile cleanly for `Float`.
- [x] Wrong arity/type rejected deterministically (OOF-MATH1/2).
- [x] Negative `det_sqrt` errors — never NaN/null (tested); non-finite input errors.
- [x] Golden-vector VM tests prove exact bit equality (+ repeatability + correctness).
- [x] Fast P2 math tests still pass.
- [x] `igniter-compiler` math tests green; `igniter-vm` math tests green; one full-VM failure isolated precisely.
- [x] `igniter-stdlib` `math.ig` updated; no build break.
- [x] Proof doc states exactly what determinism is / is not proven locally.
- [x] `git diff --check` clean.

## Files changed

- `lang/igniter-vm/Cargo.toml` (+`libm = "0.2"`), `lang/igniter-vm/src/vm.rs` (det arms).
- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs` (det share the Float arm).
- `lang/igniter-stdlib/stdlib/math.ig` (det declarations + fast-surface relabel).
- `lang/igniter-stdlib/Cargo.toml`, `lang/igniter-compiler/src/lib.rs`, and lockfiles (stdlib surface
  version/provenance bump to `0.1.1`).
- `lang/igniter-vm/tests/stdlib_math_det_tests.rs` (new, 6 tests); `lang/igniter-compiler/tests/stdlib_math_tests.rs` (+1 det test).

## Closed scope

No fixed-point integer surface; no Decimal transcendentals; no `tan/exp/ln/pow`; no numeric tower; no sim
benchmark; no `Result`-typed math (runtime-error v0); **no cross-arch CI yet** (the named next step).

## Next

`LAB-STDLIB-MATH-DET-CROSSARCH-CI-P6` — run `golden_vectors_exact_bits` under qemu `aarch64` + `riscv64` to
upgrade the determinism claim from "argued + golden-locked" to "cross-arch confirmed." Then Tier-2
(`tan/pow/exp/ln`) and the full Kuramoto phase-transition sweep on the det surface (swarm-portability
candidate; hardware proof still pending).

---

*Implementation proof. 2026-06-21. A deterministic `det_sin/det_cos/det_sqrt` surface (vendored pure-Rust
`libm` + IEEE `f64::sqrt`, finite-guaranteed, flat spelling) sits beside the fast P2 surface; golden-vector
bit equality + repeatability + no-silent-NaN proven locally; cross-arch identity argued + golden-locked,
qemu CI deferred. Kuramoto is now runnable on a fixed-algorithm/golden-vector surface — the keystone for a
portable-emergence candidate; qemu and physical swarm identity remain pending proof gates. 6 VM + 5 compiler
math tests green; `git diff --check` clean.*
