# Neural Net Pressure Registry

This registry tracks language and stdlib pressure from the `neural_net` app. The app implements a small feed-forward network using fixed-point integers and statically unrolled layer equations.

## Baseline

Rust compilation currently succeeds for:

```bash
cd igniter-compiler
cargo run -- compile ../igniter-apps/neural_net/types.ig ../igniter-apps/neural_net/activations.ig ../igniter-apps/neural_net/layers.ig ../igniter-apps/neural_net/network.ig ../igniter-apps/neural_net/example.ig --out /tmp/neural_net.igapp
```

Fresh observed result: all stages complete, 6 contracts emit, and diagnostics are empty. Current source hash: `sha256:c4b63d2ccbf220bf8b1b65a331680edad57b1d8db6dbda42f17c8684b66e7890`. Liveness counters are small (`typechecker.infer_expr.max_depth=5`, `form_resolver.walk_expr.max_depth=5`).

## Pressures

| ID | Name | Evidence | Status | Next route |
|---|---|---|---|---|
| NN-P01 | Static neural-net baseline | Five-source app compiles through Rust with 6 contracts and no diagnostics | Positive, needs frozen proof | `LAB-NEURAL-NET-BASELINE-P1` |
| NN-P02 | Unary minus parser gap | Negative weights cannot be written as `-500`; workaround is `0 - 500` | Active, repeated from vector/math pressure | `LAB-UNARY-MINUS-P1` |
| NN-P03 | Fixed-point arithmetic | Weights and activations use integer milli-units because Float/Decimal ergonomics are not ready | Active numeric pressure | `LAB-STDLIB-NUMERIC-FIXED-POINT-P1` |
| NN-P04 | Collection reduction / dot product | Generic dense layers need `sum`, `fold`, or `reduce` to collapse product collections | Active, already on stdlib route | Fold/sum follow-up after current P3/P4 work |
| NN-P05 | Static computational graph | Explicit equations such as `(x1 * w11) + (x2 * w12) + b1` compile cleanly | Positive | `LAB-TENSOR-STATIC-GRAPH-P1` later |
| NN-P06 | Activation/math helper surface | Sigmoid is approximated with hardcoded integer thresholds; richer activation functions need numeric stdlib | Active numeric pressure | `LAB-STDLIB-NUMERIC-P1` |

## Interpretation

The bounded claim is: static feed-forward computational graphs compile today. The app does not prove dynamic tensor algebra, generic layers, training, gradient descent, or runtime vectorization.

This pressure should feed numeric and collection-reduction tracks rather than opening an ML package surface immediately.

## Recommended Route

1. `LAB-NEURAL-NET-BASELINE-P1` to freeze the positive static-graph baseline.
2. `LAB-UNARY-MINUS-P1` because unary minus has now appeared in multiple app pressures.
3. `LAB-STDLIB-NUMERIC-FIXED-POINT-P1` to decide whether integer scale patterns need helper conventions.
4. Continue `fold` / `sum` tracks before attempting generic layer algebra.
5. `LAB-TENSOR-STATIC-GRAPH-P1` only after the numeric and reduction surfaces are clearer.

## Non-Goals

- No ML framework or tensor package is authorized by this app.
- No dynamic layer algebra is proven.
- No training, backpropagation, gradient, or optimizer surface is implied.
- No Float/Decimal runtime semantics are inferred from fixed-point integer workarounds.
