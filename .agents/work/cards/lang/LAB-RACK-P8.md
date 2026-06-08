# LAB-RACK-P8

**Card ID:** LAB-RACK-P8
**Category:** lang / web
**Track:** lab-rack-contractref-user-contract-dispatch-boundary-preflight-v0
**Route:** EXPERIMENTAL / LAB-ONLY / DESIGN-PREFLIGHT
**Date:** 2026-06-08
**Status:** ✅ DONE — design locked (preflight; no implementation)

---

## D — Deliverables

- `lab-docs/lang/lab-rack-contractref-user-contract-dispatch-boundary-preflight-v0.md`
  — **main deliverable: full design + option matrix + risk matrix + P9 scope**
- `.agents/work/cards/lang/LAB-RACK-P8.md` (this receipt)

---

## S — Summary

P8 is a design-preflight card. No Rust or Ruby code was written. The full preflight
document locks the design for ContractRef user-contract dispatch (P9).

**Key decision: Option B — explicit `call_contract` stdlib op.**

### Call site (Igniter source)
```igniter
compute doubled      = call_contract("Double", n)
compute gate_result  = call_contract("RouteGate", method, path)
```

### Why Option B over Option A (implicit OP_CALL extension)

Option A requires the TypeChecker to know which names are contracts (loads the
contracts list at type-check time, validates call targets, checks arg types). That
is substantial TypeChecker grammar surgery.

Option B (`call_contract`) is:
- explicit at the call site — never confused with stdlib
- TypeChecker change: add `call_contract` as known function returning `Unknown` (one registration)
- single failure site: VM OP_CALL handler
- clear error: "call_contract: no contract named '...' in igapp"

### Dispatch mechanism

Pre-built dispatch table at load time:
```rust
HashMap<String, DispatchEntry {
    bytecode: Vec<Instruction>,
    input_names: Vec<String>,  // declaration order
}>
```

The VM struct carries this table. OP_CALL `"call_contract"` case looks up the callee,
maps positional args to input names, runs callee via recursive `execute`, returns result.

### Policy (v0)

| Constraint | Value |
|-----------|-------|
| Callee modifier | `pure` only — effect/privileged callee → fail closed |
| Output | First declared output only (multi-output closed) |
| Input supply | Positional → mapped to declaration order |
| Max call depth | ≤ 8 (named constant) |
| Self-recursion | Blocked (caller-name check) |
| Cycles (A→B→A) | Blocked (call-chain set threaded through execution) |
| TypeChecker return type | `Unknown` (no callee output type verification in v0) |

---

## Design Decisions (answers to preflight questions)

| Question | Answer |
|----------|--------|
| Proceed with P9? | **Yes** |
| Mechanism | **explicit `call_contract` stdlib op** |
| Direct OP_CALL extension? | **No** |
| `call_contract` safer than overloading OP_CALL? | **Yes** |
| Single-output-only v0? | **Yes** |
| Multi-output closed? | **Yes** |
| Self-recursion closed? | **Yes** |
| Cycles closed? | **Yes** |
| Max depth required? | **Yes — depth ≤ 8** |
| TypeChecker minimal change only? | **Yes — one function registration** |
| `ContractRef[A,B]` type_ref path? | **Not in v0 — bypassed by explicit op** |

---

## P9 Implementation Scope (from this preflight)

| File | Change |
|------|--------|
| `igniter-vm/src/vm.rs` | `dispatch_table` field; `"call_contract"` OP_CALL case; depth/chain params |
| `igniter-vm/src/compiler.rs` | `input_names` extraction alongside bytecode compilation |
| `igniter-vm/src/main.rs` | Build dispatch table from igapp; thread into VM |
| `igniter-compiler/src/typechecker.rs` | Register `call_contract` as `(String, ..) -> Unknown` |
| New fixture | `multi_contract_caller.ig` — caller uses `call_contract` to invoke named contracts |
| New proof | `verify_p9_user_contract_dispatch.rb` |

**NOT in P9:** ContractRef type verification, record-form inputs, multi-output,
effect callee, middleware, HTTP server, sockets, canon grammar, stable API, production.

---

## Still Open After P9

| Gap | Path |
|-----|------|
| `ContractRef[A, B]` type annotation → dispatch semantics | TypeChecker alignment card |
| Record-form input supply | v0.1 dispatch extension |
| Multi-output callee | Value::Record output design |
| Effect callee cross-contract dispatch | Capability-grant threading |
| Middleware execution | Deferred (separate PROP) |

---

## Next Route

**LAB-RACK-P9**: User-contract dispatch via `call_contract` — implement the design
from this preflight. Prove: `call_contract("Double", n)` executes Double and returns
its output; depth limit enforced; unknown callee fails closed; pure-only callee
enforced; P7 regression green.
