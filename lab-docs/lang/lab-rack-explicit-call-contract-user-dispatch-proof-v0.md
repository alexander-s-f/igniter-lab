# LAB-RACK-P9: Explicit Named User-Contract Dispatch via `call_contract`

**Track:** `lab-rack-explicit-call-contract-user-dispatch-proof-v0`
**Card:** LAB-RACK-P9
**Status:** PROVED — 60/60 PASS
**Date:** 2026-06-08
**Authority:** lab-only — no canon claim, no stable API surface

---

## What was proved

`call_contract("ContractName", args...)` dispatches to a named contract inside
the same `.igapp` at VM runtime. Every fail-closed constraint fires as specified.
The TypeChecker accepts `call_contract` as a known function and flows `Unknown`
type through downstream expressions correctly.

---

## Design summary (from P8 preflight)

**Option B selected:** explicit `call_contract` stdlib op over implicit OP_CALL
extension. This keeps the dispatch surface visible, named, and auditable. The
dispatch table is prebuilt at igapp load time — no lazy resolution, no implicit
wiring.

---

## Implementation

### `igniter-vm/src/vm.rs`

- `DispatchEntry` struct: `bytecode`, `input_names`, `modifier`, `contract_name`
- `MAX_CALL_DEPTH: i64 = 8` constant
- `VM.dispatch_table: HashMap<String, DispatchEntry>` field
- `"call_contract"` arm in `execute_with_grants`:
  1. Depth check: `current_depth >= MAX_CALL_DEPTH` → error
  2. First arg type check: must be `Value::String` → error on other types
  3. Cycle detection: `__call_chain__` split by `,` → error if callee already in chain
  4. Dispatch table lookup → error if callee not found (lists available)
  5. Modifier guard: callee must be `"pure"` → error if `effect` / other
  6. Arity check: `positional_args.len() != entry.input_names.len()` → error
  7. Build callee inputs (positional → named mapping)
  8. Update `__call_depth__` and `__call_chain__` in callee's temporal context
  9. Execute callee in isolated frame via `Box::pin(self.execute(...))`

### `igniter-vm/src/compiler.rs`

- `build_dispatch_entry(contract_jv, contract_name)`:
  - Extracts `input_names` from SemanticIR `inputs` array (top-level `{name, type}` objects)
  - Reads `modifier` field (defaults `"pure"`)
  - Compiles bytecode via `compile_entry(contract_jv, None)`
  - Returns `DispatchEntry { bytecode, input_names, modifier, contract_name }`

### `igniter-vm/src/main.rs`

- Iterates `contracts` array in SemanticIR, calls `build_dispatch_entry` for each
- Sets `vm.dispatch_table` before first execution
- Seeds `__call_chain__` in `temporal_context` with the root contract name

### `igniter-compiler/src/typechecker.rs`

Two fixes required for `call_contract` to pass typecheck:

**Fix 1 — `Expr::Ref` OOF-P1 suppression:**
The original handler emitted OOF-P1 for any symbol whose type resolved to
`Unknown`. This incorrectly flagged declared compute nodes (e.g., the result of
`call_contract`) as "Unresolved symbol". Fixed: OOF-P1 fires only when the
symbol is NOT in `symbol_types` at all (truly undeclared), not when it exists
with `Unknown` type.

**Fix 2 — Output type Unknown compatibility:**
The output type check rejected `Unknown` actual vs declared type. Fixed: when
the actual type is `Unknown`, the output check is skipped (the VM enforces
type correctness at runtime; the declaration is trusted at compile time).

**`call_contract` registration:**
- Registered as known function in the stdlib match block
- First arg type check: must be `String` or `Unknown` → OOF-TY0 on other types
- `resolved_type` stays `Unknown` (callee output type not verifiable at compile time in v0)

---

## Fixture

`igniter-view-engine/fixtures/rack_core/multi_contract_caller.ig`

Seven contracts:

| Contract | Role | Proves |
|---|---|---|
| `Double` | pure callee | Integer → Integer callee |
| `IsSmall` | pure callee | Bool-returning callee |
| `GateCheck` | pure callee | 2-input callee |
| `CallerDoubler` | caller | happy path (n=10 → 21) |
| `CallerSmall` | caller | Bool output passthrough |
| `CallerGate` | caller | 2-arg positional dispatch |
| `SelfRecurse` | caller | self-recursion blocked |

---

## Proof results — 60/60 PASS

```
P9-COMPILE  (7 checks)   — fixture compiles, 7 contracts, all stages ok
P9-SOURCE  (10 checks)   — DispatchEntry, call_contract, __call_chain__, annotations
P9-HAPPY    (7 checks)   — CallerDoubler/CallerSmall/CallerGate correct outputs
P9-FAIL-CLOSED (21 checks):
  FC-01 (3)  unknown callee → "no contract named" error listing available
  FC-02 (3)  arity mismatch → "expects N input(s) [...], got M" error
  FC-03 (3)  non-string first arg → OOF-TY0 at compile time
  FC-04 (3)  effect callee blocked → "not pure (modifier: effect)" error
  FC-05 (3)  self-recursion blocked → "dispatch cycle detected" error
  FC-06 (3)  A→B→A cycle blocked → "dispatch cycle detected" error
  FC-07 (3)  depth > 8 blocked → "max call depth (8) exceeded" error
P9-REG      (6 checks)   — P7 regression green (multi_contract_entrypoints.ig)
P9-CLOSED   (5 checks)   — no sockets, no net I/O, no stable API claims
P9-GAP      (4 checks)   — gap packet fields valid
```

---

## v0 Policy (enforced)

| Constraint | Mechanism | Status |
|---|---|---|
| Pure callee only | `entry.modifier != "pure"` → error | Enforced |
| No self-recursion | `__call_chain__` split by `,` → contains check | Enforced |
| No cycles (A→B→A) | Same chain check covers multi-hop | Enforced |
| Max depth 8 | `MAX_CALL_DEPTH` constant + depth counter | Enforced |
| Arity must match | `positional_args.len() != entry.input_names.len()` | Enforced |
| String first arg | TypeChecker OOF-TY0 + VM runtime check | Enforced |

---

## Still open (v0 deferred)

| Surface | Detail |
|---|---|
| Non-pure callee dispatch | Effect/query/trusted callee not in v0 scope |
| Multi-output callee | VM returns single result value; named-tuple output deferred |
| Output type verification | `call_contract` returns `Unknown` at compile time; declared type is trusted |
| ContractRef type semantics | Canon type system annotation out of scope for lab |

---

## Authority boundary

```
CLOSED: igniter-lang canon grammar
CLOSED: ContractRef type semantics in igniter-org
CLOSED: real TCP/socket usage
CLOSED: ServiceLoop / HTTP server / middleware
CLOSED: stable/public API claims
CLOSED: production runtime, release, certification, portability gates
NOTE:   call_contract is lab-only; no canon claim, no stable API surface
```

---

## Files changed

| File | Change |
|---|---|
| `igniter-vm/src/vm.rs` | DispatchEntry, MAX_CALL_DEPTH, call_contract handler |
| `igniter-vm/src/compiler.rs` | build_dispatch_entry |
| `igniter-vm/src/main.rs` | dispatch table build + __call_chain__ seed |
| `igniter-compiler/src/typechecker.rs` | call_contract registration, OOF-P1 fix, Unknown output fix |
| `igniter-view-engine/fixtures/rack_core/multi_contract_caller.ig` | P9 fixture (7 contracts) |
| `igniter-view-engine/proofs/verify_p9_user_contract_dispatch.rb` | Proof (60/60) |
