# Neural Network Pressure Report

Attempting to implement a Machine Learning / Matrix Multiplication model in Igniter exposed key gaps in mathematical expressiveness, while also proving that static feed-forward computational graphs are already viable.

**Current baseline:** Rust compilation succeeds for the five-source app (`types.ig`, `activations.ig`, `layers.ig`, `network.ig`, `example.ig`) with 6 contracts emitted and zero diagnostics. Fresh source hash: `sha256:c4b63d2ccbf220bf8b1b65a331680edad57b1d8db6dbda42f17c8684b66e7890`.

## 1. Static Unrolling (The Missing `reduce`)

In Python or Rust, a Dense Layer is implemented dynamically: $Y = Act(W \times X + b)$, relying on nested loops or vector dot products.
In Igniter, we CANNOT aggregate a `Collection`. Even if we `map` over matrices to multiply weights by inputs, we are left with a `Collection[Integer]` representing the products. **Without a `reduce` or `sum` operation, we cannot collapse that collection into a single sum.**

**Workaround**: We must statically unroll the neural network. A 2x2 layer must explicitly declare `w11, w12, w21, w22` and perform the scalar math:
```igniter
compute z1 = (x1 * w11) + (x2 * w12) + b1
```
This restricts Igniter ML models to tiny, hardcoded topologies (e.g., small decision models) rather than large, scalable layers.

## 2. No Unary Minus (Parser Discovery)

During implementation, we encountered a parsing failure: `Unexpected token in expression: Op` when trying to declare negative weights like `-500`.
- The Igniter parser **does not support the Unary Minus (`-`) operator**.
- You cannot write `compute x = -10`.
- You must write `compute x = 0 - 10`.

This is a critical edge-case discovery that affects how negative thresholds, biases, and weights are written across the language.

## 3. Fixed-Point Integers vs Floats

Igniter has no native floating-point types (`Float` or `Double`). Neural Networks are extremely sensitive to fractional weights (e.g., $0.05, -0.8$).
We successfully bypassed this by introducing **Fixed-Point Arithmetic**.
- We scale everything by a chosen factor (e.g., $1000$).
- $0.5 \rightarrow 500$, $-0.2 \rightarrow 0 - 200$.
- When multiplying two scaled numbers, the scale squares ($1000 \times 1000 = 1,000,000$). We simply divide by the scale factor post-multiplication to normalize: `(x * w) / 1000`.
- We approximated the Sigmoid activation using hardcoded integer threshold boundaries.

## Summary Table

## Pressure Register

| ID | Pressure | Status | Route |
|---|---|---|---|
| NN-P01 | Static neural-net Rust baseline | Positive | `LAB-NEURAL-NET-BASELINE-P1` |
| NN-P02 | Unary minus parser gap | Active, repeated pressure | `LAB-UNARY-MINUS-P1` |
| NN-P03 | Fixed-point arithmetic workaround | Active numeric pressure | `LAB-STDLIB-NUMERIC-FIXED-POINT-P1` |
| NN-P04 | Collection reduction / dot product | Active, already aligned with fold/sum route | `LANG-STDLIB-FOLD/SUM` follow-up |
| NN-P05 | Static computational graph form | Positive | `LAB-TENSOR-STATIC-GRAPH-P1` later |
| NN-P06 | Activation/math helper surface | Active, numeric stdlib | `LAB-STDLIB-NUMERIC-P1` |

## Summary Table

| Feature | Status | Implication |
|---|---|---|
| Unary Minus (`-`) | ❌ Missing | Must use `0 - X` for negative numbers |
| Collection `sum` | ❌ Missing | Blocks dynamic dot products / Generic Layers |
| Floats | ❌ Missing | Requires Fixed-Point Integer scaling (`value / 1000`) |
| Neural Nets | ⚠️ Limited | Possible only via static computation graphs |
