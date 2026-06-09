# LAB-RACK-P10: `call_contract` Output Type Verification — Design Preflight

**Track:** `lab-rack-call-contract-output-type-verification-preflight-v0`
**Card:** LAB-RACK-P10
**Status:** DESIGN-LOCKED
**Date:** 2026-06-09
**Authority:** lab-only — no canon claim, no stable API surface

---

## Background

P9 proved that `call_contract("ContractName", args...)` dispatches to a named
contract at VM runtime, with all fail-closed constraints enforced. Every
`call_contract` compute node is typed `Unknown` by the TypeChecker — the callee
output type is not verified at compile time, and the VM enforces dispatch
correctness at runtime.

This preflight designs the smallest safe path from `Unknown` toward
**single-output type verification for literal callee names**, without
implementing ContractRef semantics, multi-output returns, non-pure callee
dispatch, middleware, HTTP server, sockets, or any stable/public API authority.

---

## Evidence collected

### 1. SemanticIR carries full output type metadata

Every contract in `semantic_ir_program.json` has:

```json
{
  "contract_name": "Adder",
  "modifier": "pure",
  "inputs": [{"name": "a", "type": {"name": "Integer", "params": []}}, ...],
  "outputs": [{"name": "result", "type": {"name": "Integer", "params": []}}]
}
```

Output type is fully specified in the `outputs` array at the time the TypeChecker
runs. This information is **available** in `ClassifiedProgram.contracts` — the
outer `typecheck()` function sees the full program, not just one contract.

### 2. Literal vs. dynamic callee is detectable from the AST

Inspecting `call_contract` nodes in SemanticIR:

| Call form | First arg `kind` | `type_tag` | Detectable at compile time? |
|---|---|---|---|
| `call_contract("Adder", x, y)` | `literal` | `String` | YES |
| `call_contract("IsPositive", n)` | `literal` | `String` | YES |
| `call_contract(name, n)` | `ref` | (none) | NO — dynamic |
| `call_contract("Prefix" ++ suffix, n)` | `binary_op` | (none) | NO — computed |

The TypeChecker's `infer_expr` has access to the raw `Expr` AST (not just typed
results), so `Expr::Literal { type_tag: "String", value: callee_name }` can be
detected in the `call_contract` handler.

### 3. TypeChecker already has cross-contract access via `ClassifiedProgram`

The outer `typecheck()` function receives `&ClassifiedProgram` (all contracts).
The `build_size_registry(classified: &ClassifiedProgram)` pattern (PROP-041 T2)
already demonstrates the mechanism for building a shared registry before the
contract loop. The same pattern can build a **module contract registry**:
`HashMap<String, ContractRegistryEntry>` from all contracts' output/input
metadata.

### 4. `typecheck_contract` currently receives only one contract

`typecheck_contract(&ClassifiedContract, ...)` operates on a single contract.
To enable cross-contract lookup, a `contract_registry` parameter must be added.
This is a wider change than one line, but it is **contained within** the
TypeChecker and follows the established size_registry pattern exactly.

---

## Design questions — answered

### Q1: Where should callee output type metadata live?

**Answer: TypeChecker module contract registry + optional DispatchEntry extension**

- **Primary (P11):** A `HashMap<String, ContractRegistryEntry>` built in
  `typecheck()` from `ClassifiedProgram.contracts` before the contract loop.
  Passed to `typecheck_contract()` alongside the size registry. Used during
  `infer_expr` for `call_contract` when first arg is a string literal.

- **Secondary (post-P11, if needed):** `DispatchEntry` can be extended with
  `output_type: Option<String>` for runtime-side type labeling, but this is
  not required for compile-time verification.

- **NOT in:** sidecar receipts, SemanticIR patching, or grammar extensions.

### Q2: Can `call_contract("KnownName", ...)` be type-checked at compile time?

**Answer: YES — for pure literal string first args.**

The TypeChecker's `call_contract` handler sees `Expr::Call { fn_name, args }`.
When `args[0]` is `Expr::Literal { type_tag: "String", value: name }`, the
callee name is statically known. The TypeChecker can:
1. Look up `name` in the module contract registry
2. Check modifier == "pure" (else OOF-TY0)
3. Check arity == `entry.input_count` (else OOF-TY0)
4. Detect self-call (else OOF-TY0)
5. If single output: return `entry.single_output_type` instead of Unknown

### Q3: What happens when first arg is not a literal but has type `String`?

**Answer: Remain `Unknown`. VM-checked only.**

A runtime `String` variable (e.g., `compute result = call_contract(name, n)`)
cannot be statically verified. The TypeChecker emits Unknown and the VM
enforces correctness. This is the same behavior as P9.

### Q4: Can single-output callee type be resolved without changing grammar?

**Answer: YES — no grammar changes needed.**

The module contract registry is built purely from existing SemanticIR data.
No new syntax, keywords, or grammar nodes required. `call_contract` stays as
a stdlib-style function call.

### Q5: Should TypeChecker reject (for literal callees):
- Unknown callee → **YES** (OOF-TY0)
- Non-pure callee → **YES** (OOF-TY0)
- Arity mismatch → **YES** (OOF-TY0)
- Output type mismatch → **YES** (OOF-TY0, via normal output type check since type is now resolved)

### Q6: Should dynamic string callee remain VM-checked only?

**Answer: YES, permanently for v0. May revisit in later card if bounded static registry becomes viable.**

### Q7: Is a two-tier policy needed?

**Answer: YES — the natural design is two-tier:**

| Tier | Callee name form | Compile-time behavior | VM behavior |
|---|---|---|---|
| Tier 1 (static) | Literal `"Name"` | Full type/arity/modifier/existence check | Trust TypeChecker |
| Tier 2 (dynamic) | Variable / computed | Unknown (emit no OOF) | Fail-closed as today |

The two tiers are distinguishable from the AST. No runtime flag or special form needed.

### Q8: Does P11 require changing `call_contract` from stdlib-style function to typed intrinsic?

**Answer: NO.** The `call_contract` handler in `infer_expr` can be extended in-place.
The function remains a stdlib-style `OP_CALL` at the IR level. The TypeChecker
adds semantic context without changing the IR shape.

### Q9: Can P9's `Unknown output compatibility` be narrowed?

**Answer: Not necessary — leave it as-is for safety.**

After P11:
- Literal callee → TypeChecker resolves to concrete type → output check works
  normally (concrete == declared) → Unknown-compat rule NOT triggered
- Dynamic callee → Unknown → Unknown-compat rule IS triggered → correct

The Unknown output compatibility rule is self-selecting: it only fires when the
actual type IS Unknown, which only happens for dynamic callees after P11. No
narrowing required; it becomes a no-op for the static case.

### Q10: Does this create ContractRef semantics?

**Answer: NO — explicitly not ContractRef semantics.**

ContractRef (from igniter-lang canon and LAB-LANG-HTTP-TYPES-P1) is a
**runtime type** that holds a contract reference as a first-class value:
`handler: ContractRef`, passable as arguments, storable in variables, and
dispatched at runtime with the type system tracking what the reference points to.

What P11 proposes is **compile-time static name lookup** — the callee name must
be a string literal in the source. The contract reference is never a value
that flows through the type system. This is equivalent to how `recur()` uses
the current contract name at compile time without creating a "ContractRef to
the recursive contract."

The distinction:
- ContractRef: `let h: ContractRef = MyContract` — runtime reference type
- P11: `call_contract("MyContract", ...)` — literal name resolved at compile time

P11 does NOT open ContractRef type semantics, does NOT require grammar changes,
and does NOT create first-class contract values.

### Q11: Is any public/stable/runtime authority created?

**Answer: NO.**

- `call_contract` remains lab-only
- TypeChecker changes are lab-implementation changes, not canon grammar
- No stable API surface, no public runtime, no production claims
- All P9 closed-surface constraints carry forward unchanged

---

## Design matrix

Full behavior table for P11 (with module contract registry):

| First arg | Registry lookup | Modifier | Arity | Outputs | P11 TypeChecker | VM |
|---|---|---|---|---|---|---|
| Literal "Known" | Found | pure | Correct | 1 | Return output type | Execute |
| Literal "Known" | Found | pure | Correct | >1 | Unknown (multi-output deferred) | Execute |
| Literal "Known" | Found | pure | Mismatch | 1 | OOF-TY0 (arity) | Blocked by typecheck |
| Literal "Known" | Found | effect/other | Any | Any | OOF-TY0 (non-pure) | Blocked by typecheck |
| Literal "Self" | Found (self) | pure | Correct | 1 | OOF-TY0 (self-recursion) | Blocked by typecheck |
| Literal "Unknown" | Not found | — | — | — | OOF-TY0 (unknown callee) | Blocked by typecheck |
| Dynamic String | N/A | — | — | — | Unknown | VM fail-closed |
| Non-String | N/A | — | — | — | OOF-TY0 (P9 behavior) | Blocked by typecheck |

---

## P11 implementation plan

### Scope

TypeChecker only. No VM changes. No grammar changes. No DispatchEntry changes
(though DispatchEntry may optionally be extended post-P11).

### Step 1 — Add `ContractRegistryEntry` struct

```rust
// In typechecker.rs
pub struct ContractRegistryEntry {
    pub modifier: String,
    pub input_count: usize,
    pub input_names: Vec<String>,
    pub input_types: Vec<serde_json::Value>,        // type IR values
    pub single_output_type: Option<serde_json::Value>, // None if 0 or >1 outputs
    pub single_output_name: Option<String>,
    pub contract_name: String,
}
```

### Step 2 — Add `build_contract_registry()` method

```rust
fn build_contract_registry(
    &self,
    classified: &ClassifiedProgram,
) -> HashMap<String, ContractRegistryEntry> {
    // Iterate classified.contracts
    // For each contract: extract modifier, inputs, outputs from declarations
    // If exactly 1 output → Some(output_type), else None
}
```

The data source is `ClassifiedContract.declarations` (kind == "input" / "output")
plus `ClassifiedContract.modifier`. Both are already available.

### Step 3 — Thread registry to `typecheck_contract()`

Add `contract_registry: &HashMap<String, ContractRegistryEntry>` parameter to
`typecheck_contract()` and `infer_expr()`.

### Step 4 — Update `call_contract` handler

In the `"call_contract"` arm of `infer_expr`, after the existing arg count
and first-arg-type checks, add:

```rust
// Tier 1: literal callee → static lookup
if let Some(Expr::Literal { type_tag, value: callee_name }) = raw_args.get(0) {
    if type_tag == "String" {
        match contract_registry.get(callee_name.as_str()) {
            None =>
                OOF-TY0 "call_contract: unknown callee '{}' in this module"
            Some(e) if e.modifier != "pure" =>
                OOF-TY0 "call_contract: callee '{}' is not pure (modifier: {})"
            Some(e) if e.contract_name == current_contract_name =>
                OOF-TY0 "call_contract: self-recursion is closed in v0"
            Some(e) if positional_count != e.input_count =>
                OOF-TY0 "call_contract: callee '{}' expects {} inputs, got {}"
            Some(e) if e.single_output_type.is_none() =>
                Unknown  // multi-output callee — deferred
            Some(e) =>
                return TypedExpression { resolved_type: e.single_output_type, ... }
        }
        // Tier 2: dynamic callee → Unknown (fall through)
    }
}
```

### Step 5 — Proof

Write `verify_p11_call_contract_type_verification.rb` covering:
- Literal known callee → resolved to correct output type
- Literal unknown callee → OOF-TY0 at compile time
- Literal non-pure callee → OOF-TY0 at compile time
- Literal arity mismatch → OOF-TY0 at compile time
- Literal self-recursion → OOF-TY0 at compile time
- Dynamic callee → still compiles; Unknown type retained
- P9 regression green

---

## Risks and mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Registry build before loop may miss forward references | Low | Single-pass over all contracts is order-independent (only reads declarations, not computed types) |
| Adding `contract_registry` parameter to `infer_expr` widens the change surface | Medium | Follows size_registry precedent; thread carefully; compile confirms scope |
| TypeChecker rejects a valid contract that was accepted in P9 | Medium | P9 regression check is required; only NEW diagnostics (OOF-TY0) should be added for previously-ok cases that are now statically knowable |
| Multi-output callee silently returns Unknown | Low | Document and emit a note; may add warning diagnostic later |
| Self-recursion check in TypeChecker duplicates VM check | Low | Belt-and-suspenders: compile-time catch is strictly earlier; no behavior divergence |

---

## P9 compatibility

P9's `multi_contract_caller.ig` fixture includes `SelfRecurse` — a contract that
calls `call_contract("SelfRecurse", n)`. In P11, this would be caught at
**compile time** (OOF-TY0: self-recursion) rather than VM runtime. The P9 fixture
would need to be updated OR a new fixture used to prove both behaviors separately.

**Decision**: The P9 proof and fixture are reference artifacts. P11 introduces a
stricter compile-time gate — this is a compile-time behavior change. The P9
fixture will need to be split:
- Static fail-closed cases → new P11 fixture (compile-time errors)
- Dynamic/runtime cases → remain in P9 fixture

---

## Verdict

| Question | Answer |
|---|---|
| Should output type verification open next? | YES — for literal callee names in P11 |
| Can literal callee names be statically verified? | YES — via module contract registry |
| Dynamic callee names remain Unknown? | YES — permanently in v0 |
| Narrow P9's Unknown output compatibility? | NOT NEEDED — remains correct as-is |
| TypeChecker should learn same-module contract registry? | YES — `build_contract_registry()` like size_registry |
| Does this create ContractRef semantics? | NO — explicitly not ContractRef |
| Any public/stable/runtime authority created? | NO |
| Exact next route recommendation | P11: implement module contract registry + literal callee type resolution in TypeChecker |

---

## Closed surfaces (carried forward from P9)

```
CLOSED: igniter-lang canon grammar
CLOSED: ContractRef type semantics
CLOSED: multi-output callee dispatch
CLOSED: non-pure callee dispatch
CLOSED: real TCP/socket usage
CLOSED: ServiceLoop / HTTP server / middleware
CLOSED: stable/public API claims
CLOSED: production runtime, release, certification
NOTE:   call_contract is lab-only; no canon claim, no stable API surface
```
