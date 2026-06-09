# LAB-RACK-P11: `call_contract` TypeChecker Literal Callee Resolution

**Status:** CLOSED / PROVED
**Track:** lab-rack-call-contract-literal-callee-typechecker-resolution-v0
**Date:** 2026-06-09
**Result:** 47/47 PASS

---

## Summary

Implemented TypeChecker-level resolution for literal `call_contract("ContractName", ...)`
calls. Added a same-module contract registry (`build_contract_registry()`) built from
`ClassifiedProgram.contracts` before the contract loop. Literal callee names are now
resolved to the callee's single output type at compile time, or rejected with OOF-TY0
for invalid cases.

Builds on:
- P9: call_contract dispatch + fail-closed v0 policy
- P10: design preflight — literal callee detection, registry pattern, design matrix

---

## Two-tier policy (P11)

| Tier | First arg | TypeChecker behavior |
|---|---|---|
| Tier 1 — static | Literal `"Name"` | Registry lookup; resolve type or OOF-TY0 |
| Tier 2 — dynamic | Variable/computed | Unknown; VM fail-closed |

### Tier 1 fail-closed cases (all emit OOF-TY0)
- Unknown callee name (not in module)
- Non-pure modifier (effect, etc.)
- Self-recursion (contract calling itself via literal name)
- Arity mismatch

---

## Key implementation details

### New struct
```rust
pub struct ContractRegistryEntry {
    pub modifier: String,
    pub input_count: usize,
    pub single_output_type: Option<serde_json::Value>,
    pub contract_name: String,
    // + input_names, input_types, single_output_name
}
```

### New method
```rust
fn build_contract_registry(&self, classified: &ClassifiedProgram)
    -> HashMap<String, ContractRegistryEntry>
```

Built in `typecheck()` before the contract loop, like `build_size_registry()`.
Threaded to `typecheck_contract()` and `infer_expr()` (all ~29 call sites updated).

### P9 compatibility
- `multi_contract_caller.ig`: SelfRecurse renamed SelfRecurseDyn with dynamic callee
  (literal self-call now OOF-TY0; Tier 2 preserves VM cycle detection)
- P9 inline fixtures (unknown/arity/effect): changed to dynamic callees for Tier 2
- P9 proof: 60/60 PASS unchanged

---

## What was proved (47 checks)

```
P11-COMPILE  (5)  — fixture compiles; all 7 contracts; no diagnostics
P11-STATIC   (6)  — CallerDouble→Integer, CallerBool→Bool, CallerAdder→Integer
P11-TIER2    (4)  — dynamic callee → Unknown; no OOF
P11-FC      (16)  — unknown/effect/arity/self-recursion → OOF-TY0 (compile time)
P11-REG      (6)  — P9 fixture green; CallerDoubler VM=21; SelfRecurseDyn VM cycle
P11-CLOSED   (5)  — no sockets, no ContractRef claims
P11-GAP      (5)  — gap packet valid; two-tier policy documented
```

---

## Authority

lab-only — no canon claim, no stable API surface.
`call_contract` remains lab-only. No grammar changes. No ContractRef semantics.

---

## Files

- `igniter-compiler/src/typechecker.rs`
- `igniter-view-engine/fixtures/rack_core/call_contract_resolution.ig`
- `igniter-view-engine/fixtures/rack_core/multi_contract_caller.ig` (updated)
- `igniter-view-engine/proofs/verify_p11_call_contract_typechecker_resolution.rb`
- `igniter-view-engine/proofs/verify_p9_user_contract_dispatch.rb` (updated)
- `lab-docs/lang/lab-rack-call-contract-typechecker-resolution-v0.md`
