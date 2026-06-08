# LAB-RACK-P9: Explicit Named User-Contract Dispatch via `call_contract`

**Status:** CLOSED / PROVED
**Track:** lab-rack-explicit-call-contract-user-dispatch-proof-v0
**Date:** 2026-06-08
**Result:** 60/60 PASS

---

## Summary

Implemented and proved explicit named user-contract dispatch via
`call_contract("ContractName", args...)` using a prebuilt dispatch table and
fail-closed v0 policy.

Builds on:
- P7: named entrypoint selector (compile_entry / --entry flag)
- P8: ContractRef dispatch design preflight (Option B selected)

---

## What was built

| Component | Change |
|---|---|
| `vm.rs` | `DispatchEntry` struct, `MAX_CALL_DEPTH=8`, `call_contract` handler |
| `compiler.rs` | `build_dispatch_entry` — extracts input_names/modifier, compiles bytecode |
| `main.rs` | dispatch table built from all contracts; `__call_chain__` seeded |
| `typechecker.rs` | `call_contract` registered; OOF-P1 narrowed; Unknown output allowed |
| Fixture | `multi_contract_caller.ig` — 7 contracts (3 callees + 3 callers + SelfRecurse) |
| Proof | `verify_p9_user_contract_dispatch.rb` — 60/60 |

---

## Fail-closed constraints (all proved)

| Constraint | Error message |
|---|---|
| Unknown callee | `no contract named 'X' in igapp (available: [...])` |
| Arity mismatch | `contract 'X' expects N input(s) [...], got M` |
| Non-string first arg | TypeChecker OOF-TY0 at compile time |
| Effect callee | `callee 'X' is not pure (modifier: effect)` |
| Self-recursion | `dispatch cycle detected (X -> X)` |
| A→B→A cycle | `dispatch cycle detected (X,Y -> X)` |
| Depth > 8 | `max call depth (8) exceeded` |

---

## TypeChecker changes

Two fixes were required beyond just registering `call_contract`:

1. **OOF-P1 narrowed**: Only fires when a symbol is truly absent from
   `symbol_types`. Declared symbols with `Unknown` type (e.g., `call_contract`
   return values) no longer trigger "Unresolved symbol" errors.

2. **Unknown output compatibility**: When a compute node has `Unknown` type,
   it passes the output type check. The VM enforces correctness at runtime;
   the type declaration is trusted.

---

## v0 Policy

- Only `pure` callees may be dispatched
- No self-recursion, no indirect cycles
- Max call depth: 8
- These constraints are enforced at VM runtime, not compile time (except
  non-string first arg, which is caught by TypeChecker)

---

## Still open

- Non-pure callee dispatch (effect/query callees)
- Multi-output callee (named tuple return)
- Compile-time output type verification
- ContractRef type semantics in igniter-lang canon

---

## Authority

lab-only — no canon claim, no stable API surface.
`call_contract` is explicitly lab-only and must not be claimed as canon grammar
or stable dispatch API.

---

## Proof

`igniter-view-engine/proofs/verify_p9_user_contract_dispatch.rb`
`lab-docs/lang/lab-rack-explicit-call-contract-user-dispatch-proof-v0.md`
