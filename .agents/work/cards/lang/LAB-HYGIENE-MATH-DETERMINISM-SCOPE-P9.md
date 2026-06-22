# LAB-HYGIENE-MATH-DETERMINISM-SCOPE-P9 - keep det math claims below physical hardware proof

Status: CLOSED
Lane: workspace hygiene / science claims
Type: documentation cleanup
Delegation code: OPUS-HYGIENE-MATH-DETERMINISM-SCOPE-P9
Date: 2026-06-22
Skill: idd-agent-protocol

## Context

Gemini drift forensics flagged a claim-boundary risk around deterministic Float math. The intended boundary is:

- fast `stdlib.Math.*` Float path is platform/local simulation;
- `det_*` uses a fixed pure-Rust `libm`/IEEE strategy with golden vectors;
- cross-emulation may support a strong lab claim if run;
- physical multi-arch identity on real devices (for example ESP32 swarm) is not yet proven unless a hardware
  proof card says so.

## Goal

Audit high-traffic math determinism docs and patch wording if any line overclaims physical cross-architecture
proof.

## Verify first

Run:

```text
rg -n "deterministic by construction|cross-architecture|physical|ESP32|emulator|qemu|libm|det_sin|det_cos" lab-docs/lang .agents/work/cards/lang
```

Read at least:

- `lab-docs/lang/lab-stdlib-math-determinism-readiness-p3-v0.md`
- `lab-docs/lang/lab-stdlib-math-det-tier1-p5-v0.md`
- any current emergence/Kuramoto doc that cites det math as a substrate.

## Allowed changes

- Patch wording only where a physical-hardware proof is implied but not present.
- Preferred phrasing:

```text
Lab claim: fixed-algorithm/golden-vector deterministic surface; physical multi-arch identity remains pending
until a hardware/swarm proof records it.
```

## Closed surfaces

- No VM/compiler/math implementation.
- No new determinism tests.
- No hardware or emulator runs required.
- No weakening of implemented `det_*` feature claims; only scope wording.

## Acceptance

- [x] Fast Float vs `det_*` vs physical-hardware proof are separated.
- [x] No doc says physical ESP32/multi-device identity is proven unless a live proof exists.
- [x] Golden-vector / fixed-algorithm lab evidence remains credited.
- [x] `git diff --check` clean.

## Closing report

- Verified with the prescribed `rg` over `lab-docs/lang` and `.agents/work/cards/lang`.
- Read the high-traffic determinism docs `lab-stdlib-math-determinism-readiness-p3-v0.md` and
  `lab-stdlib-math-det-tier1-p5-v0.md`, plus current Kuramoto/emergence surfaces that cite `det_*`.
- Patched wording only: fast `stdlib.Math.*` remains platform/local simulation; `det_*` remains credited as a
  fixed-algorithm/golden-vector lab surface; qemu cross-arch and physical ESP32/swarm identity are now named as
  pending proof gates.
- Also aligned the drift-forensics "Live Truth" line so it no longer implies an emulator proof already exists.
- No VM/compiler/math implementation changed; no new tests, hardware, or emulator runs.
