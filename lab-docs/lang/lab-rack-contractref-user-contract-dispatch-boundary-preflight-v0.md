# LAB-RACK-P8: ContractRef User-Contract Dispatch — Boundary Preflight

**Track:** lab-rack-contractref-user-contract-dispatch-boundary-preflight-v0
**Route:** EXPERIMENTAL / LAB-ONLY / DESIGN-PREFLIGHT
**Date:** 2026-06-08
**Status:** PREFLIGHT — design locked, no implementation
**Depends on:** LAB-RACK-P7 (VM named entrypoint selector), LAB-RACK-P3 (gap map),
               LAB-RACK-P6 (TypeChecker == and <)
**Authority:** lab-only — no canon claim, no stable API surface, no production commitment

---

## 1. Purpose

After P7 gave us named entrypoint selection, the remaining gap in the ContractRef
dispatch path is: **a contract cannot call another contract from inside its own
compute expression**. P8 locks the design for closing that gap in P9.

Questions answered here:
- Which dispatch mechanism to use (direct OP_CALL extension / dispatch table /
  explicit stdlib op / hold)?
- How the caller supplies the callee's inputs
- How the callee's output is returned
- Call-frame isolation model
- Recursion, cycle, and depth policy
- TypeChecker surface needed
- VM structural change needed
- Whether to proceed with P9 or hold

---

## 2. Current Architecture (post-P7)

### What exists

| Layer | State |
|-------|-------|
| Parser | `ContractRef[A, B]` accepted; compiles to `type_ref` node |
| TypeChecker | Direct `ContractName(args)` call → OOF-TY0 (unknown function) |
| SemanticIR | `kind:call, fn:ContractName` shape exists via form-dispatch path |
| Compiler | `apply/call` arm → `OP_CALL fn_name N` for any unrecognized name (line 280) |
| VM entrypoint | P7: `--entry <name>` selects from contracts array |
| VM OP_CALL | stdlib/builtin only; fallthrough → "Unknown/unimplemented function" (line 1462) |

### The two blocking layers (after P7)

1. **TypeChecker** — rejects `ContractName(args)` before SemanticIR is emitted
2. **VM OP_CALL** — no user-contract case; unknown name returns runtime error

Both must be unblocked for P9. The question is how.

---

## 3. Option Matrix

### Option A — Direct OP_CALL extension (implicit dispatch)

Extend the VM's OP_CALL `_` arm: when an unknown function name is encountered,
check a dispatch table built from the igapp's contracts array. If found, execute
the callee in a new frame.

**Also requires:** TypeChecker must stop rejecting `ContractName(args)` — it
must recognize contract names from the loaded igapp as valid call targets, check
arg count, and emit `kind:call, fn:ContractName` into SemanticIR.

| Dimension | Assessment |
|-----------|-----------|
| TypeChecker change | Substantial — must load contracts list and validate call targets |
| VM change | Moderate — new OP_CALL case before fallthrough |
| Call-site transparency | Low — `HelloHandler(method, path)` looks like any function call |
| Failure location | Diffuse — TypeChecker rejects if name not in contracts; VM rejects if dispatch table miss |
| Diagnostic surface | Complex — two different rejection sites for the same conceptual error |

**Risk:** "Implicit" means any typo in a contract name looks like an unknown stdlib
function. Diagnostic path is split across TypeChecker and VM. Grammar changes needed
in TypeChecker (must know which names are contracts at type-check time).

---

### Option B — Explicit `call_contract` stdlib op (**preferred**)

Define `call_contract` as a known stdlib function. The TypeChecker registers it as
`(String, ...) -> Unknown` — minimal change, no contract-name-awareness needed.
The compiler already emits `OP_CALL "call_contract" N` for a `call` node with
`fn: "call_contract"`. The VM handles `"call_contract"` as a special case in OP_CALL
before the fallthrough, using a pre-built dispatch table.

**Call site syntax** (Igniter source):
```igniter
-- Single-input callee (positional)
compute doubled = call_contract("Double", n)

-- Two-input callee (positional, declaration order)
compute gate_result = call_contract("RouteGate", method, path)
```

**TypeChecker change:** Add `call_contract` to the known-function registry with
return type `Unknown`. No contract-name validation in TypeChecker (deferred to runtime).

**VM change:** Add `"call_contract"` case in the OP_CALL match before the `_` fallthrough.

| Dimension | Assessment |
|-----------|-----------|
| TypeChecker change | Minimal — one function registration, returns Unknown |
| VM change | Moderate — new OP_CALL case |
| Call-site transparency | High — `call_contract(...)` is visually distinct; never confused with stdlib |
| Failure location | Single — VM OP_CALL; unknown contract name → error at the call site |
| Diagnostic surface | Clean — one error class: "call_contract: no contract named '...' in igapp" |
| Type safety in v0 | Low — return type Unknown; no callee output type verification |

**Risk:** Return type `Unknown` means the TypeChecker cannot verify downstream use
of the return value. This is acceptable in v0 (explicit deferred typing).

---

### Option C — Hold

Keep ContractRef dispatch deferred. P9 closes other gaps (HTTP server shape,
query routing, middleware) without user-contract dispatch.

**Assessment:** Not recommended. P7 closed the entrypoint selector gap precisely so
ContractRef can be explored "without the feeling of building a second floor on a door
that only opens to the first contract." P7 is done; holding now wastes that unblocking.
The risk surface of P9 (Option B) is well-bounded.

---

## 4. Selected Approach: Option B (explicit `call_contract` stdlib op)

**Rationale:**
- Explicit over implicit — `call_contract(...)` is always identifiable at the call site
- TypeChecker surgery deferred — no grammar changes needed for cross-contract call type validation
- Dispatch table is the mechanism; the function name makes the dispatch intent explicit
- Single failure site in the VM makes the error model easier to prove
- Option A requires non-trivial TypeChecker changes (contract-name resolution at type-check time) — deferred to a later card when the type boundary is better understood

---

## 5. Design Detail

### 5.1 Dispatch Table (VM structural change)

The VM struct gains a dispatch table built from the igapp at load time in `main.rs`:

```rust
// Per-contract dispatch entry
struct DispatchEntry {
    bytecode: Vec<Instruction>,
    input_names: Vec<String>,  // in declaration order from SemanticIR
}

// VM field
dispatch_table: HashMap<String, DispatchEntry>
```

Built before `executor.execute(...)` in main.rs:
```rust
// For each contract in contracts_arr:
//   compile_entry(jv, Some(name)) → DispatchEntry { bytecode, input_names }
// Insert into dispatch_table
```

The `VM` struct (`vm.rs`) already has a `backend` field. Adding `dispatch_table`
follows the same pattern. The table is populated once at load time; no runtime
mutation.

**Empty table (no --entry with single contract igapp):** empty HashMap — same behavior
as today. The `call_contract` fallthrough just returns "no contract named '...'".

### 5.2 Input Supply (positional → named mapping)

```
call_contract("ContractName", arg1, arg2, ..., argN)
args[0] = Value::String("ContractName")
args[1..N] = positional input values
```

The dispatch entry stores `input_names: Vec<String>` in declaration order.
Mapping: `inputs["input_names[0]"] = args[1]`, `inputs["input_names[1]"] = args[2]`, etc.

Arg count mismatch → fail closed:
```
call_contract: contract 'RouteGate' expects 2 inputs [method, path], got 1
```

**Why positional and not record?**
`Value::Record` exists but constructing a record literal at call time from named fields
requires syntax support not yet in the parser/TypeChecker. Positional matching against
the declaration order is the minimum viable v0 form. Record-form dispatch can be added
in a later card.

### 5.3 Output (single output only in v0)

The callee's first declared output (same logic as `compiler.rs` line 134-143).
Multi-output callees: only the first output is returned. Multi-output-aware dispatch
is closed in v0.

### 5.4 Frame Isolation

```rust
// Inside OP_CALL "call_contract" handler:
let callee_inputs: HashMap<String, Value> = entry.input_names.iter()
    .zip(positional_args.iter())
    .map(|(name, val)| (name.clone(), val.clone()))
    .collect();

// Recursive execute (no shared mutable state with caller)
let callee_result = Box::pin(
    self.execute(&entry.bytecode, &callee_inputs, temporal_context)
).await?;
```

- Local variables (`registers` HashMap): new instance per callee frame (not shared)
- Stack: not shared (execute creates its own stack)
- Inputs: new HashMap per call (no aliasing)
- temporal_context: read-only pass-through (callee can read time but not set it)
- resolved_grants: NOT passed to callee — callee runs with empty grants (pure in v0)

**Implication:** callee contracts must be `pure` in v0. Calling an `effect` or
`privileged` contract via `call_contract` → fail closed:
```
call_contract: callee 'EffectContract' is not pure (modifier: effect); cross-contract call requires pure callee in v0
```

### 5.5 Recursion, Cycle, and Depth Policy

**Self-call:** blocked at dispatch time:
```
call_contract: contract 'Double' may not call itself (self-recursion closed in v0)
```
Detected by passing caller contract name through execution context.

**Cycles (A → B → A):** blocked via a call-chain set threaded through execution:
```rust
// Each frame receives a call_chain: HashSet<String> from parent
// Before executing callee: if call_chain.contains(callee_name) → error
// Insert callee_name into call_chain for its sub-calls
```

**Max depth:** ≤ 8 calls. Counter threaded through execution. Exceeding → fail closed:
```
call_contract: max call depth (8) exceeded; check for indirect recursion
```

**Why 8?** Sufficient for a dispatcher → handler pattern (depth 1–2 in practice).
Prevents stack exhaustion in lab VM. Adjustable as a named constant.

### 5.6 TypeChecker Change (minimal)

Add `call_contract` to the TypeChecker's function registry:
- Input types: `(String, ...) — first arg must be String (contract name); rest are Unknown`
- Return type: `Unknown` (callee output type not verified in v0)
- Arg count: minimum 1 (the contract name); remaining args are positional inputs
- OOF diagnostic: none (type Unknown flows through)

**No contract-name validation in TypeChecker.** Unknown callee names are caught
at VM runtime with a clear error. This is the explicit trade-off for avoiding
TypeChecker grammar surgery in v0.

---

## 6. Risk Matrix

| Risk | Severity | Mitigation |
|------|----------|-----------|
| Frame isolation breach (shared mutable state) | High | New HashMap per call; execute creates own stack |
| Unbounded recursion / stack overflow | High | Depth ≤ 8 + call-chain set; cycle detection before recursive execute |
| Type mismatch (caller passes wrong type for callee input) | Medium | Runtime error at execute; callee input binding fails with clear message |
| Multi-output callee returns only first output | Low | Documented in v0 constraint; multi-output dispatch → closed |
| Calling non-pure callee (effect/privileged) | Medium | Modifier check at dispatch time; fail closed with clear error |
| Empty dispatch table (single-contract igapp) | Low | Graceful error: "no contract named '...' in igapp" |
| call_contract return type Unknown cascades | Low | Downstream TypeChecker accepts Unknown; explicit in v0 constraint |
| Authority drift (lab dispatch looks like stable dispatch API) | High | `call_contract` is explicitly lab-only; no canon claim; comment in code |

---

## 7. Questions Answered

| Question | Answer |
|----------|--------|
| Should ContractRef dispatch proceed? | **Yes — proceed with P9** |
| Path: OP_CALL extension or explicit stdlib op? | **Explicit `call_contract` stdlib op (Option B)** |
| P9: implement direct OP_CALL user-contract dispatch? | **No — use `call_contract` named op** |
| Is `call_contract` safer than overloading OP_CALL? | **Yes — single failure site, explicit at call-site** |
| Single-output-only v0 required? | **Yes — first declared output** |
| Multi-output callee returns closed? | **Yes — v0 constraint** |
| Self-recursive dispatch closed? | **Yes — blocked by caller-name check** |
| Cyclic dispatch closed? | **Yes — call-chain set** |
| Max call depth required before implementation? | **Yes — depth ≤ 8 as named constant** |
| `ContractRef[A, B]` type_ref shape sufficient? | **Not in v0 path — call_contract bypasses it** |
| TypeChecker work needed before VM? | **Minimal only — register `call_contract` as known function** |
| Callee modifier constraint? | **Pure callee only in v0** |

---

## 8. P9 Implementation Scope (from this preflight)

### Changes required for P9

| File | Change |
|------|--------|
| `igniter-vm/src/vm.rs` | Add `dispatch_table: HashMap<String, DispatchEntry>` to VM struct; add `"call_contract"` case in OP_CALL before `_` fallthrough; add depth + call-chain params to execute internals |
| `igniter-vm/src/compiler.rs` | Add method to extract `input_names` from a contract_obj alongside compiling its bytecode |
| `igniter-vm/src/main.rs` | Build dispatch table from all contracts in igapp before calling execute; thread it into VM |
| `igniter-compiler/src/typechecker.rs` | Add `call_contract` to known-function registry with `(String, ..) -> Unknown` return |
| New fixture | `multi_contract_caller.ig` — one contract calls another via `call_contract` |
| New proof | `verify_p9_user_contract_dispatch.rb` |

### Explicitly NOT in P9 scope

- ContractRef[A, B] type verification (dispatch table + TypeChecker alignment)
- Record-form input supply (positional only in v0)
- Multi-output callee dispatch
- Effect/privileged callee dispatch
- Middleware execution
- HTTP server, sockets, query parsing, glob routing
- Canon grammar changes
- Stable/public runtime API
- Production, release, certification claims

---

## 9. Still Open After P9

| Gap | Path |
|-----|------|
| `ContractRef[A, B]` type annotation attached to dispatch semantics | TypeChecker cross-contract type alignment card |
| Record-form input supply for `call_contract` | v0.1 dispatch extension |
| Multi-output callee dispatch | Value::Record output design card |
| Effect callee cross-contract dispatch | Capability-grant threading design |
| Middleware execution | Deferred (separate PROP) |

---

## 10. Authority

- Lab-only — no canon claim, no stable API surface
- `call_contract` is a lab VM debugging/composition aid; does not constitute a stable
  stdlib function, a public runtime API, or a canon Igniter language feature
- The dispatch table mechanism is a lab internal; no portability or certification claims
- Do not accept lab dispatch behavior as canon Igniter semantics
