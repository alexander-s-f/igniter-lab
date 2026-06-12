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
| NN-P01 | Static neural-net baseline | Wave recheck: Rust still CLEAN (0 diagnostics, 6 contracts); `LAB-NEURAL-NET-BASELINE-P1` proof frozen at 85/85 PASS | Positive, proof frozen | `LAB-NEURAL-NET-BASELINE-P1` CLOSED |
| NN-P02 | RESOLVED | Unary minus parser gap | LANG-UNARY-OPERATORS-P3 (Ruby) + LANG-UNARY-OPERATORS-P4 (Rust) CLOSED — unary `-` now supported in both toolchains; negative literals `-500` are valid; app source `0 - 500` workaround is stale but no source edits in this wave | `LANG-UNARY-OPERATORS-P3/P4` CLOSED |
| NN-P03 | DOCUMENTED | Fixed-point arithmetic | `LAB-STDLIB-NUMERIC-FIXED-POINT-P1` CLOSED (SPLIT verdict): convention document written; scale=1000 accepted as app convention; no stdlib helpers needed; risks catalogued (R1 silent scale error, R2 overflow, R3 truncation) | `LAB-STDLIB-NUMERIC-FIXED-POINT-P1` CLOSED |
| NN-P04 | Active | Collection reduction / dot product | Generic dense layers need `sum`, `fold`, or `reduce` to collapse product collections | Fold/sum follow-up |
| NN-P05 | Positive | Static computational graph | Explicit equations such as `(x1 * w11) + (x2 * w12) + b1` compile cleanly | `LAB-TENSOR-STATIC-GRAPH-P1` later |
| NN-P06 | Active | Activation/math helper surface | Sigmoid is approximated with hardcoded integer thresholds; richer activation functions need numeric stdlib | `LAB-STDLIB-NUMERIC-P1` |
| NN-P07 | RESOLVED | `<` operator gap (Ruby TC) | LANG-STDLIB-NUMERIC-COMPARISON-P3 CLOSED — `<`, `<=`, `>=` added to Ruby TC; Wave P2 unstripped recheck: 0 `Unsupported operator: <` (12 total diags vs 13 in P1, 1 fewer = this error); SigmoidApprox `x < (0 - 2500)` now compiles in Ruby | `LANG-STDLIB-NUMERIC-COMPARISON-P3` CLOSED |
| NN-P08 | ACTIVE | Ruby call_contract parity | Wave P2 recheck: 12 total (7× `Unknown function: call_contract`, 3× `Output type mismatch`, 2× `Unresolved symbol`); layers.ig / network.ig / example.ig all use `call_contract` form; dominant Ruby blocker | call_contract parity follow-up |

## Interpretation

The bounded claim is: static feed-forward computational graphs compile today. The app does not prove dynamic tensor algebra, generic layers, training, gradient descent, or runtime vectorization.

This pressure should feed numeric and collection-reduction tracks rather than opening an ML package surface immediately.

## Wave Recheck Summary P1 (2026-06-12)

Ruby compile: 13 diagnostics (1× `Unsupported operator: <`, 7× `Unknown function: call_contract`, 3× `Type mismatch`, 2× `Unresolved symbol`). Rust: CLEAN. NN-P01 baseline frozen (LAB-NEURAL-NET-BASELINE-P1 85/85 PASS). NN-P03 documented/closed (LAB-STDLIB-NUMERIC-FIXED-POINT-P1 40/40 PASS, SPLIT verdict). New gaps: NN-P07 (`<` operator Ruby TC) and NN-P08 (call_contract parity).

## Wave P2 Recheck Summary (2026-06-12)

Ruby: 12 diagnostics (7× `Unknown function: call_contract`, 3× `Output type mismatch`, 2× `Unresolved symbol`). Rust: CLEAN (0 diagnostics, source_hash unchanged). NN-P02 RESOLVED — LANG-UNARY-OPERATORS-P3/P4 closed; unary `-` dual-toolchain; app workaround stale. NN-P07 RESOLVED — LANG-STDLIB-NUMERIC-COMPARISON-P3 closed; `<` operator works in Ruby; `Unsupported operator: <` gone. Dominant remaining Ruby blocker: call_contract parity (NN-P08).

## Recommended Route

1. call_contract parity (NN-P08) — cross-app dominant blocker.
2. `fold` / `sum` tracks for dot-product and dense layer support (NN-P04).
3. `LAB-TENSOR-STATIC-GRAPH-P1` only after numeric and reduction surfaces are clearer.

## Non-Goals

- No ML framework or tensor package is authorized by this app.
- No dynamic layer algebra is proven.
- No training, backpropagation, gradient, or optimizer surface is implied.
- No Float/Decimal runtime semantics are inferred from fixed-point integer workarounds.
