# Rule Engine Pressure Report

By building a dynamic Rule / Inference Engine, we discovered a safety-sensitive Unknown-flow path in Igniter's type system. It looks powerful enough to support dynamic dispatch and rule pipelines, but it must be treated as `SAFETY-HIGH` until dynamic calls, Unknown field access, and typed output coercion are bounded by explicit validation semantics.

**Current baseline:** Rust compilation succeeds for the four-source app (`types.ig`, `rules.ig`, `engine.ig`, `example.ig`) with 5 contracts emitted and zero diagnostics. Fresh source hash: `sha256:9aefca5ca90dc3ec11a73ff0bf05036a2eadfa00af9034dd3e017beb371b59e3`.

## 1. Dynamic Dispatch (Tier 2 Evaluation)

Igniter's `call_contract(contract_name, args...)` has two tiers of evaluation:
- **Tier 1 (Static)**: If `contract_name` is a literal string (e.g., `"HighValueRule"`), the compiler checks the registry, verifies inputs, and resolves the output type exactly.
- **Tier 2 (Dynamic)**: If `contract_name` is a variable (e.g., `r_name` from a mapped `Collection[String]`), the compiler *cannot* statically resolve it. Instead of failing, the compiler emits an `Unknown` type and delegates resolution to the VM (which will "fail-closed" at runtime if the contract doesn't exist).

**Impact**: This allows the app to map an array of strings representing rule names and dynamically shape a rule pipeline. This should be interpreted as app pressure, not as an authorized reflection feature.

## 2. Duck Typing via "Permissive Unknown"

Because `call_contract(dynamic_name)` returns `Unknown`, our mapped collection is of type `Collection[Unknown]`.
In most strict typed languages, this would be a dead-end requiring manual type casting or matching. However, Igniter's `Unknown` type acts similarly to `any` in TypeScript.

We proved that you can perform field access on an `Unknown` object without causing a typecheck error:
```igniter
-- `d` is Unknown
compute active = filter(raw_decisions, d ->
  if d.action == "SKIP" { false } else { true }
)
```
The compiler permitted the `d.action` lookup because `Unknown` bypasses field existence checks (`OOF-TY0`). This is useful for exploratory dynamic pipelines, but it also means field access is no longer statically evidenced.

## 3. Coercion Boundaries

We demonstrated that Igniter currently permits `Collection[Unknown]` to flow into a statically defined schema by leveraging the contract `output` boundary.
```igniter
-- raw_decisions is Collection[Unknown]
output active_decisions : Collection[RuleDecision]
```
This must not be treated as proven safe yet. The honest interpretation is: a dynamic result can currently cross into a concrete output annotation without an explicit validation receipt. That is the highest-risk finding in this app.

## Pressure Register

| ID | Pressure | Status | Route |
|---|---|---|---|
| RE-P01 | Rule engine Rust baseline | Positive | `LAB-RULE-ENGINE-BASELINE-P1` |
| RE-P02 | Dynamic `call_contract(variable, ...)` | Active, safety-high | `LAB-DYNAMIC-CONTRACT-DISPATCH-P1` |
| RE-P03 | `Unknown` field access | Active, safety-high | `LAB-UNKNOWN-FIELD-ACCESS-P1` |
| RE-P04 | `Collection[Unknown]` to typed output | Active, safety-high | `LAB-UNKNOWN-OUTPUT-COERCION-P1` |
| RE-P05 | Rule interface convention (`Transaction -> RuleDecision`) | Positive but informal | Typed contract-ref / forms route |
| RE-P06 | Dynamic pipeline / plugin architecture | Promising, blocked on safety | After RE-P02..P04 |

## Summary Table

| Feature | Status | Implication |
|---|---|---|
| Static Call (`call_contract("A")`) | ✅ Strict | Validates inputs/outputs at compile time |
| Dynamic Call (`call_contract(r)`) | ⚠️ Permissive | Evaluates to `Unknown`; needs explicit dispatch receipt semantics |
| Duck Typing (`unknown_obj.field`) | ⚠️ Permissive | Allows reading dynamic data without static field evidence |
| Output Coercion | ⚠️ Safety-high | Concrete output annotation accepts `Unknown` flow without explicit validation receipt |
