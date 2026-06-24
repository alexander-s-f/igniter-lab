# LAB-STDLIB-DET-MATH-T2-THIRD-ISA-P4 - third-ISA determinism evidence for det math

Status: CLOSED (PARTIAL T2 — math surface earned via qemu; full VM bundle deferred)
Lane: stdlib science / deterministic math / evidence
Type: proof or refusal packet
Date: 2026-06-24
Skill: idd-agent-protocol

## Context

`LAB-STDLIB-DET-MATH-CANON-PROMOTION-READINESS-P3` says canon promotion should not rely only on lab enthusiasm.
The current evidence tier has real two-ISA proof for the deterministic math surface and emergence bundles.
The recommended next evidence broadening is a third ISA (for example riscv64 via qemu or real hardware).

This card is evidence work, not canon authority. If the environment cannot run a third ISA, produce a precise
refusal/readiness packet instead of faking coverage.

## Goal

Attempt to earn T2 third-ISA evidence for the deterministic math surface:

```text
det_sqrt / det_sin / det_cos / det_ln / det_exp / det_tan
```

against the existing golden-vector set. If practical, also run one minimal deterministic bundle.

## Verify First

Read:

- `lab-docs/lang/lab-stdlib-det-math-canon-promotion-readiness-p3-v0.md`;
- emergence determinism proof docs for T1/T2 wording;
- current det math tests and golden vectors;
- local toolchain support for qemu/riscv64 or another third ISA;
- CI/build constraints.

Do not claim third-ISA evidence unless the bits were actually compared.

## Requirements / Acceptance

- [x] Identify the current golden-vector source and exact functions covered.
- [x] Identify available third-ISA path: qemu, real host, CI, or none.
- [x] If available: run the det math harness on third ISA and compare exact IEEE-754 bits to existing targets.
- [x] If unavailable: write a refusal packet naming the missing toolchain/device and the exact command that would run.
- [x] If practical: run one minimal deterministic bundle on the third ISA and compare receipt/output bits.
- [x] Produce `lab-docs/lang/lab-stdlib-det-math-t2-third-isa-p4-v0.md`.
- [x] Do not change det math implementation unless a real mismatch is found and separately justified.
- [x] `git diff --check` clean.

## Closed Surfaces

- No canon promotion.
- No change to `STDLIB_VERSION` unless implementation actually changes.
- No new math primitive.
- No toolchain-invariance claim.
- No science claim beyond the evidence tier achieved.

## Closing Report

Proof doc: `lab-docs/lang/lab-stdlib-det-math-t2-third-isa-p4-v0.md`.

**Outcome: T2 EARNED for the det math surface (qemu third ISA), not refused.** No native riscv64 silicon in
the lab (inventory: ai-main-lab=x86_64, pi5-lab/pi5-lab2=aarch64 — only the two T1 ISAs as hardware), so the
path was **qemu riscv64**, which the card/readiness §5 explicitly accept.

**Third-ISA path attempted:** built a minimal standalone harness (deps = `libm =0.2.16` only, det_sqrt =
IEEE `f64::sqrt` — identical to the VM's `eval_math_call` dispatch), cross-compiled to a **static
riscv64gc-unknown-linux-musl** binary on `pi5-lab` (aarch64, rustc **1.96.0** = T1 toolchain), ran it under
**qemu-riscv64** registered via `tonistiigi/binfmt`.

**Exact commands:** in proof doc (rustup target add → RUSTFLAGS rust-lld static build → `binfmt --install
riscv64` → run binary → `grep '^V ' | sha256sum`).

**Bit comparison result:** `ALL_MATCH=true`, exit 0, **14/14 golden f64 bit patterns identical** on riscv64.
Cross-ISA evidence digest `1a09885b9dfefb1276106db8e3b16b5e807ed3008deeb256cbc080824b272667` — **identical**
on riscv64(qemu, rustc1.96), aarch64-linux(pi5-lab native, rustc1.96), aarch64-darwin(mac, rustc1.95).

**Minimal VM bundle on third ISA:** DEFERRED. Blocker = lab has no Cargo workspace root and `igniter-vm` uses
`../` cross-crate path-deps → standalone cross-build of the VM is out of proportion. Math-surface bits (the
determinism-bearing core of any bundle) are proven identical; exact next step documented.

**Artifact paths:** `lab-docs/lang/det-math-t2-harness/{Cargo.toml,src/main.rs}`; riscv64 binary sha256
`f305310f4c8591ab1d89c3550851028cd1af448d78bc6c95708a0b281a39bd59` (on pi5-lab).

**Effect on canon-promotion readiness:** P3 §5 `LAB-1` (T2 third ISA) → substantially met for the det math
surface via qemu. Honest residuals kept in wording: **qemu not real silicon**, and **full VM bundle** not yet
run on riscv64. No det-math impl changed; no STDLIB_VERSION bump; no canon/portability/toolchain-invariance
claim. Promotion remains a governance act (GOV-1/GOV-2).
