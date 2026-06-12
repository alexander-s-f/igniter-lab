# Igniter Rule Engine

A dynamic Rule Engine / Inference Pipeline implemented in Igniter. The app demonstrates a powerful but safety-sensitive pattern: dynamic `call_contract` over rule names produces `Unknown`, and the current typechecker allows that value to flow through field access and typed output boundaries. It currently achieves **full Rust compilation** with **5 contracts**.

This app is an app-pressure fixture, not a canon claim. Treat the dynamic-dispatch path as `SAFETY-HIGH` until the Unknown-flow semantics are proved and bounded.

## Implementations

### 1. Facts (`RuleEngineTypes`)
The data model consists of `Transaction` facts and `RuleDecision` outputs.

### 2. Rules (`RuleEngineRules`)
A suite of modular contracts (`HighValueRule`, `ForeignCurrencyRule`, `FraudScoreRule`) that implement the `Transaction -> RuleDecision` interface. Each rule is a pure contract representing a predicate and action.

### 3. Inference Engine (`RuleEngineCore`)
A pipeline execution contract (`ExecuteRules`) that dynamically iterates over an array of rule names (`Collection[String]`) using `map` and `call_contract`.

## Dynamic Pressure Found

1. **Dynamic Contract Dispatch**: By passing variables to `call_contract(r_name, t)`, the typechecker defers lookup and emits an `Unknown` type signature.
2. **Field Access via Unknown**: `Unknown` is permissive enough that the pipeline can filter by reading `d.action` from an unknown result.
3. **Typed Output Boundary**: `Collection[Unknown]` can currently flow into an output annotated as `Collection[RuleDecision]`. This is useful pressure, but not yet a proof of safety; it needs a validation/receipt boundary.

## Compilation

```bash
cd igniter-compiler
cargo run -- compile ../igniter-apps/rule_engine/types.ig ../igniter-apps/rule_engine/rules.ig ../igniter-apps/rule_engine/engine.ig ../igniter-apps/rule_engine/example.ig --out /tmp/rule_engine.igapp
```

**Result**: Full compilation — 5 contracts emitted, zero diagnostics.

## Pressure Registry

See [PRESSURE_REGISTRY.md](PRESSURE_REGISTRY.md) for tracked pressure IDs, safety classification, and next routes.
