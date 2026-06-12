# Lab: Ruby call_contract Parity — Readiness Proof

**Track:** LAB-RUBY-CALL-CONTRACT-PARITY-P1  
**Date:** 2026-06-12  
**Proof runner:** `igniter-lab/igniter-view-engine/proofs/verify_lab_ruby_call_contract_parity_p1.rb`  
**Result:** 56/56 PASS

---

## Purpose

Establish a grounded readiness baseline for adding `call_contract` dispatch to the Ruby
TypeChecker. `call_contract` is the dominant inter-contract invocation form across all
Igniter apps — 148 total calls across 26 files. Before implementing, this proof:

1. Classifies all call shapes exhaustively
2. Characterizes current Ruby TC and Rust TC behavior head-to-head
3. Identifies what is safe to implement vs what must remain blocked
4. Gates P2 planning on the output assignability dependency

---

## Call Shape Taxonomy

| Shape | Count | Files | Status |
|-------|-------|-------|--------|
| LITERAL_MODULE (PascalCase contract name) | 113 | 25 | SAFE — P2 |
| STDLIB_FORM (`"append"`, `"empty"`) | 34 | 9 | BLOCKED — route via stdlib |
| DYNAMIC (variable, not string literal) | 1 | 1 (rule_engine) | SAFE — Tier 2 Unknown |
| LAMBDA_INTERNAL (inside `->` context) | 8 | 4 | SAFE — subset of above |

**Total:** 148 call_contract calls across 26 source files.

The LAMBDA_INTERNAL category is a sub-classification of LITERAL_MODULE. The rule_engine
dynamic form (`call_contract(r, t)`) also appears inside a lambda body but is classified
DYNAMIC.

---

## Behavior Comparison: Ruby TC vs Rust TC

### Ruby TC (current — before P2)

All `call_contract` calls fall through to the `else` branch of `infer_call`:

```ruby
else
  type_errors << oof("OOF-TY0", "Unknown function: call_contract", node_name)
  typed_expr("call", type_ir("Unknown"), [], ...)
end
```

| Condition | Ruby result |
|-----------|-------------|
| Any call_contract call | OOF-TY0 "Unknown function: call_contract" |
| Concrete output declared | +OOF-TY0 "Type mismatch: expected X, got Unknown" |
| Unknown output declared | Only the "Unknown function" error |
| Contract status | `blocked` |

**No `when "call_contract"` arm exists in Ruby TC.**

### Rust TC (LAB-RACK-P11 — two-tier)

**Tier 1** (literal String callee): static lookup in `contract_registry`

| Condition | Rust result |
|-----------|-------------|
| Known same-module pure contract, arity ok | status ok, output type resolved |
| Unknown callee name | OOF-TY0 "not found in this module" |
| Stdlib name ("append") | OOF-TY0 "not found in this module" |
| Arity mismatch | OOF-TY0 "expects N input(s), got M" |
| Self-recursion | OOF-TY0 (closed in v0) |
| Non-pure callee | OOF-TY0 |

**Tier 2** (dynamic / variable callee): result type = `Unknown`, no error, VM fail-closed.

---

## Safe Subset for P2

### SAFE — implement in P2

**Literal same-module contract name (Tier 1):**  
When the first argument is a String literal (e.g. `call_contract("MakeLeaf", ...)`),
look up the contract in the module registry. Validate:
- Callee exists in module → resolve output type
- Callee not found → OOF-TY0 (matches Rust)
- Arity mismatch → OOF-TY0 (matches Rust)
- Non-pure callee → OOF-TY0 (matches Rust)
- Self-recursion → OOF-TY0 (matches Rust)

**Dynamic callee (Tier 2):**  
When the first argument is a variable or expression, result type = Unknown,
no error. VM fail-closed at runtime. Matches Rust exactly.

### BLOCKED — not in P2

**Stdlib names (`"append"`, `"empty"`, `"concat"`):**  
These 34 calls across 9 files must NOT be treated as missing module contracts (OOF-TY0
"not found"). They refer to stdlib helpers. Two options:
- Route to stdlib dispatch (preferred — avoids spurious OOF-TY0)
- Emit a distinct diagnostic

Either way, they cannot be resolved via the module `contract_registry`. Separate P-track
per stdlib function.

**`call_contract("empty")`:**  
No `stdlib.collection.empty` inventory entry exists. This form is a pre-stdlib bootstrap
pattern used in `igniter_parser`. Blocked until `stdlib.collection.empty` is authorized.

---

## App Blocker Analysis

| App | Ruby call_contract gap | Rust call_contract gap |
|-----|----------------------|----------------------|
| vector_editor | LITERAL_MODULE blocked | `"append"` (stdlib form) blocked |
| decision_tree | LITERAL_MODULE blocked | `"append"` (stdlib form) blocked |
| arch_patterns | LITERAL_MODULE blocked | `"append"` (stdlib form) blocked |
| bloom_filter | LITERAL_MODULE blocked | none for module calls |
| igniter_parser | LITERAL_MODULE + "empty" blocked | "empty" blocked |
| neural_net | LITERAL_MODULE blocked | none (pure module calls only) |
| vector_math | LITERAL_MODULE blocked | none (pure module calls only) |
| rule_engine | DYNAMIC blocked | DYNAMIC ok (Tier 2 Unknown) |
| dataframes | LITERAL_MODULE blocked | none |
| dsa | LITERAL_MODULE blocked | none |

**Key insight:** For apps with only LITERAL_MODULE calls (neural_net, vector_math, bloom_filter,
dataframes, dsa, bookkeeping, erp_logistics, spreadsheet, advanced_logistics), Ruby P2 alone
resolves all `call_contract` blockers. Stdlib-form apps (VE/DT/AP/igniter_parser) need both
P2 and stdlib routing.

---

## Output Assignability Gate

The current Ruby TC returns Unknown for all `call_contract` results. Contracts that declare
a concrete output type currently get OOF-TY0 "Type mismatch". After P2 resolves the callee
output type, the output type check becomes structural:

- **Concrete→Concrete:** direct type name equality (already implemented in Ruby TC)
- **Parametric (Collection[T]→Collection[T]):** requires structural recursive comparison

This intersects with **LANG-OUTPUT-TYPE-ASSIGNABILITY-P1** (authored, not implemented), which
proposes `structurally_assignable?` recursive comparison. P2 must not assume deep structural
matching is available.

**P2 safe boundary:** For single-output pure contracts where output type is a bare named type
(not parametric), direct comparison is safe. For parametric return types, P2 should resolve
to Unknown until LANG-OUTPUT-TYPE-ASSIGNABILITY-P1 is implemented, or add a provisional
shallow check consistent with existing Ruby TC behavior.

**Multi-output contracts** stay Unknown regardless, matching Rust behavior.

---

## Next Routes

**LANG-RUBY-CALL-CONTRACT-PARITY-P2** — bounded Ruby TC implementation.  
Authorized scope:
- `when "call_contract"` arm in Ruby TC `infer_call`
- Tier 1: literal String → contract registry lookup + arity/purity checks
- Tier 2: non-literal → Unknown, no error
- Stdlib aliases blocked (error, not route)  
- Proof matrix ≥ 50 checks

**Blocked until separate tracks:**
- `call_contract("append", ...)` routing → LANG-STDLIB-COLLECTION-APPEND-PROP-P2 or P3
- `call_contract("empty")` → `stdlib.collection.empty` authorization track
