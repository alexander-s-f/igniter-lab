# LAB-RACK-P10: `call_contract` Output Type Verification — Design Preflight

**Status:** CLOSED / DESIGN-LOCKED
**Track:** lab-rack-call-contract-output-type-verification-preflight-v0
**Date:** 2026-06-09
**Result:** 39/39 PASS (inspection proof)

---

## Summary

Design preflight for moving `call_contract` from `Unknown` return type toward
single-output type verification for literal callee names. No TypeChecker or VM
changes implemented; all findings are structural evidence from SemanticIR
inspection.

Builds on:
- P9: call_contract dispatch + fail-closed v0 policy
- P8: explicit `call_contract` design locked

---

## Design verdicts

| Question | Answer |
|---|---|
| Should output type verification open? | YES — literal callee names in P11 |
| Can literal callee be statically verified? | YES — `Expr::Literal{kind:"literal", type_tag:"String"}` is distinguishable |
| Dynamic callee names remain Unknown? | YES — permanently in v0 |
| Narrow P9's Unknown output compat? | NOT NEEDED — self-selecting for dynamic callees |
| TypeChecker module contract registry needed? | YES — `build_contract_registry()` like T2's `build_size_registry()` |
| Creates ContractRef semantics? | NO — compile-time name lookup, not runtime type |
| Public/stable/runtime authority? | NO |
| Next route | P11: module contract registry + literal callee type resolution in TypeChecker |

---

## Key structural findings (all confirmed by 39/39 proof)

1. **SemanticIR carries complete output type metadata**: Every contract has
   `outputs[].type.name` available at TypeCheck time.

2. **Literal vs. dynamic callee is detectable**: `Expr::Literal{kind:"literal",
   type_tag:"String"}` vs. `Expr::Ref` or computed expr. Distinguishable from
   raw AST.

3. **Module registry pattern already established**: `build_size_registry()` for
   PROP-041 T2 proves the mechanism: build a `HashMap<String, Entry>` from
   `ClassifiedProgram.contracts` before the loop, thread to `typecheck_contract`.

4. **Dynamic callee remains Unknown**: Non-literal first arg (`kind:"ref"`,
   computed string) cannot be statically resolved. VM fail-closed is correct.

5. **Not ContractRef**: Static name lookup in `call_contract("Literal", ...)` 
   does not create a `ContractRef` runtime type; no grammar changes needed.

---

## P11 design (design-locked by this card)

### Mechanism
`build_contract_registry(classified: &ClassifiedProgram) → HashMap<String, ContractRegistryEntry>`

Built from `ClassifiedProgram.contracts` before the contract loop.
Passed to `typecheck_contract()` and `infer_expr()` alongside size_registry.

### ContractRegistryEntry fields
- `modifier: String`
- `input_count: usize`
- `input_types: Vec<serde_json::Value>` (for future arity + type check)
- `single_output_type: Option<serde_json::Value>` — None if >1 outputs
- `contract_name: String`

### Two-tier call_contract policy (P11)

| Tier | First arg | TypeChecker behavior |
|---|---|---|
| Static | Literal `"Name"` | Look up registry; check modifier/arity/self; resolve type |
| Dynamic | Variable/computed | Unknown; no OOF emitted; VM fail-closed |

### Static literal callee behavior

| Registry result | Behavior |
|---|---|
| Not found | OOF-TY0: unknown callee |
| Found + non-pure | OOF-TY0: non-pure callee |
| Found + self-call | OOF-TY0: self-recursion blocked |
| Found + arity mismatch | OOF-TY0: arity mismatch |
| Found + multi-output | Unknown (deferred) |
| Found + single output + ok | Return resolved output type |

### P9 fixture impact
`SelfRecurse` in P9 fixture calls `call_contract("SelfRecurse", n)` — this is
a literal self-call, detectable at compile time in P11. The P9 fixture would
become a compile-time error (OOF-TY0) rather than a VM error. P11 should:
- Keep P9 fixture as reference for VM-level behavior
- Use a new P11 fixture for compile-time verification cases

---

## What was proved (39 checks)

```
P10-SIR    (9)  — output metadata complete; inputs/outputs/modifier in SemanticIR
P10-AST    (8)  — literal vs dynamic first arg detectable; Unknown type today
P10-MULTI  (6)  — module contract list available; registry pattern viable
P10-P9REG  (6)  — P9 unchanged; SelfRecurse literal call detectable for P11
P10-CLOSED (5)  — no sockets, no net I/O, no ContractRef claims
P10-GAP    (5)  — gap packet valid; design matrix locked
```

---

## Still open (post-P11)

- Multi-output callee: returns Unknown; dedicated card if needed
- Non-pure callee: effect/query callee dispatch closed
- ContractRef type semantics: closed; canon governance required

---

## Authority

lab-only — no canon claim, no stable API surface.
`call_contract` remains lab-only. P11 design is not a canon grammar proposal.

---

## Files

- `lab-docs/lang/lab-rack-call-contract-output-type-verification-preflight-v0.md`
- `igniter-view-engine/proofs/verify_p10_call_contract_type_preflight.rb`
- `igniter-view-engine/fixtures/rack_core/call_contract_type_probe.ig`
