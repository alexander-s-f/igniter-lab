# LAB-RACK-P11: `call_contract` TypeChecker Literal Callee Resolution

**Track:** `lab-rack-call-contract-literal-callee-typechecker-resolution-v0`
**Card:** LAB-RACK-P11
**Status:** CLOSED / PROVED
**Date:** 2026-06-09
**Authority:** lab-only — no canon claim, no stable API surface

---

## Background

P9 proved that `call_contract("ContractName", args...)` dispatches to a named
contract at VM runtime with full fail-closed guarantees. The TypeChecker returned
`Unknown` for every `call_contract` compute node — the callee's output type was not
verified at compile time.

P10 proved that the TypeChecker has all the structural prerequisites to resolve
literal callee names at compile time: SemanticIR carries output type metadata,
`Expr::Literal{type_tag:"String"}` is distinguishable from `Expr::Ref`, and the
`build_size_registry` pattern is a ready-made template for a module contract registry.

P11 implements the TypeChecker-level literal callee resolution designed in P10.

---

## What was implemented

### ContractRegistryEntry

```rust
pub struct ContractRegistryEntry {
    pub modifier: String,
    pub input_count: usize,
    pub input_names: Vec<String>,
    pub input_types: Vec<serde_json::Value>,
    pub single_output_type: Option<serde_json::Value>, // None if 0 or >1 outputs
    pub single_output_name: Option<String>,
    pub contract_name: String,
}
```

### build_contract_registry

```rust
fn build_contract_registry(&self, classified: &ClassifiedProgram)
    -> HashMap<String, ContractRegistryEntry>
```

Built from `ClassifiedProgram.contracts` before the contract loop (in `typecheck()`),
mirroring the `build_size_registry()` pattern established for PROP-041 T2. Maps
`contract_name → ContractRegistryEntry`. Order-independent: all contracts are
visible to the registry at loop time regardless of declaration order.

Threaded to `typecheck_contract()` and `infer_expr()` alongside `size_registry`.

### Two-tier call_contract policy

| Tier | First arg form | TypeChecker behavior |
|---|---|---|
| **Tier 1 — static** | Literal `"Name"` | Registry lookup; resolve output type or emit OOF-TY0 |
| **Tier 2 — dynamic** | Variable / computed | `Unknown`; no OOF emitted; VM fail-closed |

### Tier 1 static lookup rules

| Registry result | TypeChecker action |
|---|---|
| Not found | OOF-TY0: "unknown callee '{}' — not found in this module" |
| Found + non-pure modifier | OOF-TY0: "callee '{}' is not pure (modifier: {})" |
| Found + same name as current contract | OOF-TY0: "self-recursion via '{}' is closed in v0" |
| Found + arity mismatch | OOF-TY0: "callee '{}' expects {} input(s), got {}" |
| Found + multi-output | Unknown (deferred; not an error) |
| Found + single output + all checks pass | Return `type_ir(entry.single_output_type)` |

### P9 Unknown output compatibility (preserved)

P9's guard:
```rust
if actual != expected && actual != "Unknown" { OOF-TY0 }
```

This self-selects correctly after P11:
- Tier 1 success → actual is a concrete type (e.g. Integer) → normal check applies
- Tier 2 dynamic → actual stays Unknown → guard skips the check

No narrowing of the Unknown compatibility rule was needed.

---

## Effect on P9 fixture

P9's `multi_contract_caller.ig` contained `SelfRecurse`, which calls
`call_contract("SelfRecurse", n)` — a literal self-call. With P11, this is caught
at compile time (OOF-TY0: self-recursion). The contract was renamed to
`SelfRecurseDyn` and changed to use a dynamic callee:

```igniter
pure contract SelfRecurseDyn {
  input  n : Integer
  compute self_name = "SelfRecurseDyn"
  compute result    = call_contract(self_name, n)  -- Tier 2, VM cycle detection preserved
  output result : Integer
}
```

P9's VM-level self-recursion test is preserved via Tier 2. P11's compile-time
self-recursion test uses a new `SelfRecursive` inline fixture.

---

## What was proved (47 checks)

```
P11-COMPILE  (5)  — call_contract_resolution.ig compiles; 7 contracts; no diagnostics
P11-STATIC   (6)  — literal callee resolves to correct type in semantic IR
                    CallerDouble.doubled → Integer
                    CallerBool.flag → Bool
                    CallerAdder.sum → Integer
P11-TIER2    (4)  — dynamic callee → Unknown; compiles OK; no OOF-TY0
P11-FC      (16)  — 4 cases × 4 checks:
                    FC-01: unknown literal callee → OOF-TY0 at compile time
                    FC-02: effect callee (non-pure) → OOF-TY0 at compile time
                    FC-03: arity mismatch → OOF-TY0 at compile time
                    FC-04: self-recursion → OOF-TY0 at compile time
P11-REG      (6)  — P9 fixture still compiles; CallerDoubler VM result=21;
                    SelfRecurseDyn VM cycle detection preserved
P11-CLOSED   (5)  — no sockets, no ContractRef claims, no canon/production claims
P11-GAP      (5)  — gap packet valid; two-tier policy documented
```

---

## Still open (post-P11)

- **Multi-output callee**: returns Unknown; dedicated card if needed
- **Cross-contract cycle detection at compile time**: A→B→A cycles and depth>8
  remain VM-only; only self-recursion is now compile-time via P11
- **ContractRef type semantics**: closed; canon governance required; P11 is
  compile-time static name lookup, NOT ContractRef

---

## Closed surfaces (carried forward from P9/P10)

```
CLOSED: igniter-lang canon grammar
CLOSED: ContractRef type semantics
CLOSED: multi-output callee dispatch (deferred, not blocked)
CLOSED: non-pure callee dispatch (OOF-TY0 in Tier 1; Tier 2 → VM error)
CLOSED: real TCP/socket usage
CLOSED: ServiceLoop / HTTP server / middleware
CLOSED: stable/public API claims
CLOSED: production runtime, release, certification
NOTE:   call_contract is lab-only; no canon claim, no stable API surface
```

---

## Files

- `igniter-compiler/src/typechecker.rs` — ContractRegistryEntry, build_contract_registry,
  updated typecheck_contract and infer_expr signatures, updated call_contract handler
- `igniter-view-engine/fixtures/rack_core/call_contract_resolution.ig` — P11 fixture
- `igniter-view-engine/fixtures/rack_core/multi_contract_caller.ig` — updated (SelfRecurseDyn)
- `igniter-view-engine/proofs/verify_p11_call_contract_typechecker_resolution.rb` — 47-check proof
- `igniter-view-engine/proofs/verify_p9_user_contract_dispatch.rb` — updated (dynamic callees)
