# Igniter Neural Network

A prototype Feed-Forward Neural Network demonstrating fixed-point arithmetic and statically unrolled computation graphs in Igniter. It currently achieves **full Rust compilation** with **6 contracts**.

This app is an app-pressure fixture, not a canon claim. It shows that static feed-forward computational graphs fit Igniter today, while dynamic tensor/layer algebra remains blocked on numeric and collection-reduction work.

## Implementations

### 1. Types (`NeuralNetTypes`)
Because Igniter lacks Floats, we use **Fixed-Point Arithmetic** (scale: 1000). So $0.5$ is `500`.
Because Igniter lacks `reduce()` or `sum()` over collections, we cannot implement generic $N \times M$ dense layers dynamically. We must use **Statically Unrolled Nodes**, defining struct weights explicitly (`w11`, `w12`, etc.) and processing them as scalar equations.

### 2. Activations (`NeuralNetActivations`)
- `ReLU`: Standard max(0, x)
- `SigmoidApprox`: Since we can't compute $e^{-x}$, we implement a hard sigmoid approximation using fixed-point integer thresholds.

### 3. Layers (`NeuralNetLayers`)
- `DenseLayer2x2`: Hardcoded matrix multiplication $Wx + b$ mapping 2 inputs to 2 hidden neurons. Division by 1000 is applied post-multiplication to normalize the fixed-point scale.
- `DenseLayer2x1`: Hardcoded mapping from 2 hidden neurons to 1 output neuron.

### 4. Network (`NeuralNetCore` & `NeuralNetExample`)
Orchestrates the layers, providing pre-trained weights for an XOR-like gate, and runs inference.

## Compilation

```bash
cd igniter-compiler
cargo run -- compile ../igniter-apps/neural_net/types.ig ../igniter-apps/neural_net/activations.ig ../igniter-apps/neural_net/layers.ig ../igniter-apps/neural_net/network.ig ../igniter-apps/neural_net/example.ig --out /tmp/neural_net.igapp
```

**Result**: Full compilation — 6 contracts emitted, zero diagnostics.

## Pressure Registry

See [PRESSURE_REGISTRY.md](PRESSURE_REGISTRY.md) for tracked pressure IDs, current evidence, and next routes.
