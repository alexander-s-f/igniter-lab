# LAB-STDLIB-DET-MATH-CANON-PROMOTION-READINESS-P3 - decide lab→canon path for det_* surface

Status: CLOSED (2026-06-24) — readiness packet delivered, NO code changes. Recommendation only; canon promotion stays a governance act.
Lane: stdlib math / governance boundary
Type: readiness packet
Date: 2026-06-24
Skill: idd-agent-protocol

## Context

Lab frontier has `det_sin, det_cos, det_sqrt, det_ln, det_exp, det_tan` with golden vectors and
cross-arch evidence. Emergence depends on this surface for scientific claims, but **lab evidence is not
canon authority**. This packet defines what promotion to stable/canon stdlib requires.

## Goal

Define the requirements + a per-function promote/defer recommendation for moving `det_*` from lab
frontier to a stable/canon stdlib surface. No promotion is performed.

## Verify First (done)

Read: `lang/igniter-stdlib/stdlib/math.ig`, `lang/igniter-vm/src/vm.rs` (`eval_math_call`),
`lang/igniter-vm/tests/stdlib_math_det_tests.rs`, `lang/igniter-vm/Cargo.toml` (libm pin),
`lang/igniter-compiler/src/lib.rs` (STDLIB_VERSION); cards `LAB-STDLIB-MATH-DET-TIER1-P5`,
`…-DET-TIER2-LN-EXP-P1`, `…-DET-TIER2-TAN-P2`, `…-DETERMINISM-READINESS-P3`, `…-TIER2-READINESS-P6`,
`LAB-HYGIENE-MATH-DETERMINISM-SCOPE-P9` + proof docs; emergence determinism docs/experiments/cards
(`determinism-cross-arch-t1`, `…-bundle-cross-arch`, `…-measurement`, claim-wording lock); canon
`igniter-lang/docs/spec/ch8-stdlib.md` + covenant; gov `DELTA-LEDGER.md`,
`authority-and-certification.md`, `private-governance-charter.md`.

## Acceptance

- [x] Clear promote/defer table for each `det_*` — packet §3.
- [x] Explicit authority boundary: evidence vs canon — packet §4.
- [x] Acceptance matrix for implementation/governance follow-up — packet §5.
- [x] No code changes.
- [x] No stronger science claim than evidence supports — claim scoped to **T1** (two real ISAs, fixed toolchain); T2/T3/T4 marked open.

## Closing Report (2026-06-24)

**Deliverable:** `lab-docs/lang/lab-stdlib-det-math-canon-promotion-readiness-p3-v0.md` (full analysis).

**Findings (headline):**
- Surface = 6 fns; libm `0.2.16` pinned; golden vectors = exact-bit literals; locked by `STDLIB_VERSION 0.1.7`.
- Evidence is **T1**: bit-identical on **real x86_64 + aarch64**, fixed `rustc 1.96.0`/`libm 0.2.16`
  (evidence distributed across emergence experiments + lab Tier-2 cards). Open: T2 third ISA (riscv64),
  T3 toolchain variation, T4 embedded/ESP32.
- `det_sqrt` is the strongest (IEEE-754 correctly-rounded — portable by standard); the rest are
  fixed-pure-Rust-libm + no-FMA-contraction (portable by construction + empirically T1).
- Totality is clean: no NaN/Inf escapes — every out-of-domain/non-finite case is a deterministic error.
- Canon today has **no** transcendental math (only integer/float/decimal/numeric, PROP-013/CORE), so this
  is net-new canon surface.

**Recommendation:**
- v1 candidate = all six `det_*` (one coherent surface); defer `det_atan2`, `det_pow`, distributions.
- Promotion is **governance-blocked, not engineering-blocked**: minimum gate = T1 (met) + LAB-1 (T2 third
  ISA) + a canon PROP + gate decision; canon wording must be **STDLIB_VERSION-relative + ISA-scoped**
  (`det_sqrt` IEEE-anchored; others "bit-identical across tested ISAs, not a correct-rounding guarantee").
- Acceptance matrix (GOV-1/2, LAB-1/2/3, EMG-1, DEFER) in packet §5.

**Authority:** lab readiness only. `det_*` stays `lab-ahead`; the route to canon is a PROP in
`igniter-lang` + governance gate — never lab alone.

## Suggested Next

- GOV-1: open the canon `det_*` PROP in `igniter-lang`.
- LAB-1: `LAB-STDLIB-MATH-DET-TIER3-ISA-P*` — qemu/real riscv64 golden-vector + bundle proof.
