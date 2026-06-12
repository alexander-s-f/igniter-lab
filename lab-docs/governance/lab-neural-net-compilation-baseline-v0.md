# Lab: Neural Net Compilation Baseline

**Track:** LAB-NEURAL-NET-BASELINE-P1
**Date:** 2026-06-12
**Proof runner:** `igniter-lab/igniter-view-engine/proofs/verify_lab_neural_net_baseline_p1.rb`
**Result:** 85/85 PASS

---

## Purpose

Freeze `neural_net` as a positive static computational graph baseline. The app implements a
small feed-forward neural network using fixed-point integer arithmetic and statically unrolled
layer equations. It proves that pure multi-contract computational pipelines — including
activation functions, weight records, and chained `call_contract` invocations — compile cleanly
through the full Rust pipeline without capability, tensor, or dynamic layer claims.

This is the third positive Rust multi-file baseline after `vector_math` (37 contracts, pure numeric
geometry) and `dsa` (12 contracts, collection algorithms). Neural net adds: nested `call_contract`
chains, `if/else` conditional activations, multi-field weight records, and integer arithmetic
including division.

---

## App Structure

| File | Module | Contracts | Role |
|------|--------|-----------|------|
| `types.ig` | NeuralNetTypes | 0 | InputVector, OutputVector, Weights2x2, Weights2x1, HiddenState |
| `activations.ig` | NeuralNetActivations | 2 | ReLU, SigmoidApprox |
| `layers.ig` | NeuralNetLayers | 2 | DenseLayer2x2, DenseLayer2x1 |
| `network.ig` | NeuralNetCore | 1 | FeedForwardNN |
| `example.ig` | NeuralNetExample | 1 | RunInference |

**Total:** 5 source units, 6 contracts, 5 named types.

Import graph:
- `activations.ig` → `NeuralNetTypes`
- `layers.ig` → `NeuralNetTypes`, `NeuralNetActivations`
- `network.ig` → `NeuralNetTypes`, `NeuralNetActivations`, `NeuralNetLayers`
- `example.ig` → `NeuralNetTypes`, `NeuralNetCore`

---

## Baseline Numbers (frozen 2026-06-12)

Hashes computed with absolute source paths (as used by the proof runner).

| Metric | Value |
|--------|-------|
| status | ok |
| source units | 5 |
| contracts | 6 |
| stages | parse ok / classify ok / typecheck ok / emit ok / assemble ok |
| diagnostics | 0 |
| warnings | 0 |
| source_hash | `sha256:9a6506e3f42aec717fd3a857ccd1d5b759e158169f4589ffcff4849c4a3368c8` |
| artifact_hash | `sha256:60926a9fcb51a7b814ab4dfd2e1c9c9493414d204c4561e7f1be29be2adad594` |
| liveness: tc_infer | 5 (limit 1000, mode fatal) |
| liveness: fr_walk | 5 (limit 1000, mode fatal) |
| liveness breaches | 0 |

Artifact hash verified stable across two independent compilation runs of identical sources.

**Source hash note:** The registry's hash (`sha256:c4b63d...`) was computed with relative
paths from the `igniter-compiler/` directory. The proof runner uses absolute paths; both are
deterministic within their calling convention. Use the proof runner — not manual cargo
invocations — to verify against the constants above.

---

## Proof Matrix

| Section | Topic | Checks |
|---------|-------|--------|
| A | Preconditions (compiler binary + 5 source files) | 6 |
| B | Compilation status + diagnostics | 4 |
| C | Pipeline stages (all 5 ok) | 6 |
| D | Source units (count, modules, hashes, paths) | 9 |
| E | Contracts (count, names, SIR, manifest, index) | 8 |
| F | Artifact files (manifest, SIR, sourcemap, report, diag) | 8 |
| G | Hash stability (2 runs) | 9 |
| H | Semantic IR integrity | 6 |
| I | Sourcemap | 3 |
| J | Liveness instrumentation (tc_infer=5, fr_walk=5, no breach) | 8 |
| K | Static graph / no dynamic layer/tensor/training/capability claim | 5 |
| L | Unary minus workaround documented (NN-P02) | 3 |
| M | Fixed-point arithmetic documented (NN-P03) | 3 |
| N | Manifest metadata | 7 |
| **Total** | | **85** |

---

## Static Computational Graph (NN-P05 positive)

The full forward pass compiles as a pure DAG of `compute` steps:

```
RunInference
  → FeedForwardNN (call_contract)
    → DenseLayer2x2 (call_contract)
      → ReLU × 2 (call_contract)
    → DenseLayer2x1 (call_contract)
      → SigmoidApprox (call_contract)
```

All 6 contracts are pure: zero `effects`, zero `capabilities`. The SIR contains no
references to `tensor`, `training`, `gradient`, `backprop`, `ml_package`, `tensor_package`,
`capability`, or `profile_binding`. The computational graph is fully static and deterministic.

**Binary operator distribution in SIR:** `+` × 7, `-` × 6, `*` × 6, `/` × 4, `>` × 2, `<` × 1.
All arithmetic is Integer × Integer. No Float, Decimal, or collection operations.

---

## Unary Minus Workaround (NN-P02 pressure)

The Igniter parser does not support the unary minus operator (`-N`). All negative weights
and biases use the `0 - N` pattern, which produces `binary_op {op: "-", left: 0, right: N}`
nodes in the SIR. Examples:

| Weight | Source | SIR |
|--------|--------|-----|
| w12 = -0.5 | `0 - 500` | `binary_op(-,  0, 500)` |
| w21 = -0.4 | `0 - 400` | `binary_op(-,  0, 400)` |
| b2 = -0.2 | `0 - 200` | `binary_op(-,  0, 200)` |
| w2.w21 = -0.8 | `0 - 800` | `binary_op(-,  0, 800)` |
| w2.b1 = -0.1 | `0 - 100` | `binary_op(-,  0, 100)` |
| SigmoidApprox lower | `0 - 2500` | `binary_op(-,  0, 2500)` |

**This is NN-P02 pressure only.** The workaround compiles cleanly. Route:
`LANG-PARSER-UNARY-MINUS-P1` (also VM-P04, ERP-P04 — same root).

---

## Fixed-Point Arithmetic (NN-P03 pressure)

Igniter has no native `Float` or `Decimal` types. The app uses integer milli-units
(scale factor = 1000): `0.8 → 800`, `-0.5 → 0 - 500`, etc.

Multiplying two scale-1000 values yields scale-1,000,000. Layer equations normalize by
dividing post-multiply:

```igniter
compute z1_raw = (x.x1 * w.w11) + (x.x2 * w.w12)
compute z1 = (z1_raw / 1000) + w.b1
```

The SIR contains `/` binary_op nodes (4 total) confirming this pattern compiles cleanly.
The Sigmoid activation uses hardcoded integer threshold boundaries (`x < 0 - 2500`,
`x > 2500`) to approximate the sigmoid curve.

**This is NN-P03 pressure only.** The workaround compiles cleanly. Route:
`LAB-STDLIB-NUMERIC-FIXED-POINT-P1`. Related: VM-P03 (vector_math integer milli-units).

---

## Closed Surfaces

- No numeric type implementation (Float, Decimal, FixedPoint — remain as pressure)
- No tensor package (no `tensor`, `ml_package`, `tensor_package` surface)
- No training, backpropagation, gradient, or optimizer surface
- No dynamic layer algebra (no collection reduce/fold-based layer loops)
- No source edits to the app (all 5 source files read-only for this proof)
- No new stdlib inventory entries
- No new OOF codes

---

## App Pressure Map (frozen with baseline)

| ID | Status | Pressure | Route |
|----|--------|---------|-------|
| NN-P01 | BASELINE | Full Rust multi-file compilation | this card |
| NN-P02 | ACTIVE | Unary minus parser gap — `0-N` workaround | `LANG-PARSER-UNARY-MINUS-P1` (also VM-P04, ERP-P04) |
| NN-P03 | ACTIVE | Fixed-point integer scale — no Float/Decimal | `LAB-STDLIB-NUMERIC-FIXED-POINT-P1` (also VM-P03) |
| NN-P04 | ACTIVE | Collection reduction / dot product — `sum`/`fold` needed for generic layers | fold/sum P4 track |
| NN-P05 | POSITIVE | Static computational graph — pure call_contract chain compiles | preserve |
| NN-P06 | ACTIVE | Activation/math helper surface — Sigmoid is approximated | `LAB-STDLIB-NUMERIC-P1` |

---

## Next Route

This baseline is a freeze, not an implementation milestone. Future regression runners for
multi-file compilation, multi-contract `call_contract` chains, integer arithmetic, or
if/else conditional dispatch should verify against these constants.

Active routes from this baseline:
- `LANG-PARSER-UNARY-MINUS-P1` — unary minus (NN-P02; also VM-P04, ERP-P04 — multi-app)
- `LAB-STDLIB-NUMERIC-FIXED-POINT-P1` — scale/precision convention (NN-P03; also VM-P03)
- `LANG-STDLIB-FOLD-PROP-P4` / `LANG-STDLIB-SUM-PROP-P4` — collection reduction for generic layers (NN-P04)
