# LAB-NEURAL-NET-BASELINE-P1 — Neural Net Regression Baseline

**Track:** lab / regression baseline
**Route:** BASELINE PROOF ONLY / NO IMPLEMENTATION
**Status:** CLOSED — PROVED 85/85 PASS
**Date:** 2026-06-12

---

## Decision: PROVED — Baseline Frozen

`neural_net` is frozen as a positive static computational graph baseline. Third Rust multi-file
positive baseline after `vector_math` (37 contracts) and `dsa` (12 contracts).

---

## Proof Result

| Metric | Baseline Value |
|--------|---------------|
| status | ok |
| source units | 5 |
| contracts | 6 |
| stages | parse ok / classify ok / typecheck ok / emit ok / assemble ok |
| diagnostics | 0 |
| source_hash | `sha256:9a6506e3f42aec717fd3a857ccd1d5b759e158169f4589ffcff4849c4a3368c8` |
| artifact_hash | `sha256:60926a9fcb51a7b814ab4dfd2e1c9c9493414d204c4561e7f1be29be2adad594` |
| liveness tc_infer | 5 (limit 1000) |
| liveness fr_walk | 5 (limit 1000) |
| liveness breaches | 0 |
| proof checks | 85/85 PASS |

---

## Proof Matrix

| Section | Topic | Checks |
|---------|-------|--------|
| A | Preconditions | 6 |
| B | Compilation status | 4 |
| C | Pipeline stages | 6 |
| D | Source units | 9 |
| E | Contracts | 8 |
| F | Artifact files | 8 |
| G | Hash stability (2 runs) | 9 |
| H | Semantic IR integrity | 6 |
| I | Sourcemap | 3 |
| J | Liveness (tc_infer=5, fr_walk=5, no breach) | 8 |
| K | Static graph / no dynamic claims | 5 |
| L | Unary minus workaround documented (NN-P02) | 3 |
| M | Fixed-point arithmetic documented (NN-P03) | 3 |
| N | Manifest metadata | 7 |
| **Total** | | **85** |

---

## Key Findings

### Static Computational Graph Proved (NN-P05)

Full forward pass compiles as a pure DAG:
`RunInference → FeedForwardNN → DenseLayer2x2 → ReLU; DenseLayer2x1 → SigmoidApprox`

All 6 contracts have zero effects and zero capabilities. SIR contains no
`tensor`, `training`, `gradient`, `backprop`, `ml_package`, `capability`, or
`profile_binding` references.

### Liveness Minimal (tc_infer=5, fr_walk=5)

Lowest liveness depth across all three baselines. Neural net pure arithmetic
has shallower expression nesting than collection HOF lambdas (DSA/vector_math).
Both fatal counters at 5 / 1000 — 200× headroom.

### Unary Minus Workaround Documented (NN-P02)

6 `binary_op {op: "-", left: 0}` nodes in SIR from negative weights/biases.
Parser does not support `-N` syntax. Workaround compiles cleanly. Documented as
pressure only → `LANG-PARSER-UNARY-MINUS-P1`.

### Fixed-Point Arithmetic Documented (NN-P03)

Scale factor 1000: 4 `/` binary_op nodes for post-multiply normalization.
SigmoidApprox uses integer threshold boundaries. No Float/Decimal in SIR.
Documented as pressure only → `LAB-STDLIB-NUMERIC-FIXED-POINT-P1`.

---

## Deliverables

| Artifact | Location |
|----------|----------|
| Proof runner | `igniter-lab/igniter-view-engine/proofs/verify_lab_neural_net_baseline_p1.rb` |
| Lab doc | `igniter-lab/lab-docs/governance/lab-neural-net-compilation-baseline-v0.md` |
| Agent card | this file |
| Portfolio entry | `igniter-lab/.agents/portfolio-index.md` |

---

## Closed Surfaces

- No numeric type implementation (Float, Decimal, FixedPoint)
- No tensor package
- No training, backpropagation, gradient, or optimizer surface
- No dynamic layer algebra
- No source edits (all app files read-only)
- No new stdlib inventory entries

---

## Next Routes

- `LANG-PARSER-UNARY-MINUS-P1` — unary minus (NN-P02; also VM-P04, ERP-P04)
- `LAB-STDLIB-NUMERIC-FIXED-POINT-P1` — scale/precision convention (NN-P03; also VM-P03)
- `LANG-STDLIB-FOLD-PROP-P4` / `LANG-STDLIB-SUM-PROP-P4` — collection reduction for generic layers (NN-P04)
