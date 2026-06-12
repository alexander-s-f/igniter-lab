# Lab: Stringly Stdlib call_contract — Classification and Routing
## LAB-STDLIB-STRINGLY-CALL-CONTRACT-P1

**Status:** PROVED — 37/37 PASS  
**Date:** 2026-06-12  
**Grounding:** LAB-RUBY-CALL-CONTRACT-PARITY-P1 (56/56), APP-RECHECK-WAVE-P2  
**Route:** RESEARCH / PROOF ONLY — no implementation, no source rewrites

---

## Summary

34 calls in the app corpus use `call_contract("append", ...)` or `call_contract("empty")` —
string-literal callees that name stdlib functions rather than module contracts. Both Ruby and
Rust TCs block these today with OOF-TY0 "not found in this module". This document classifies
the three distinct shapes, proves why they must NOT be special-cased inside `call_contract`
dispatch, and decides the routing for each.

---

## Census

| Callee | Count | Files | Apps |
|--------|-------|-------|------|
| `"append"` | 31 | 8 | arch_patterns, decision_tree, bloom_filter, igniter_parser, vector_editor |
| `"empty"` | 3 | 2 | igniter_parser |
| **Total** | **34** | **9** | 5 apps |

No other stdlib-form callees exist. `call_contract("is_empty"...)`, `("concat"...)`, `("map"...)` etc. are absent — apps use the direct stdlib form for those.

---

## Shape Classification

### SHAPE-1: ACCUMULATING (25 calls)

```
call_contract("append", existing_collection, new_element)
```

First argument is an already-Collection-typed value (field access or chained variable).
Second argument is an element of the collection's element type.

**Examples:**
- `call_contract("append", ctx.audit_trail, "mw:validate_amount")` — `Collection[String]` + `String`
- `call_contract("append", tree.nodes, node)` — `Collection[TreeNode]` + `TreeNode`
- `call_contract("append", state.tokens, new_token)` — `Collection[Token]` + `Token`
- `call_contract("append", b0, s2)` → chained from bootstrap seed — `Collection[Slot]` + `Slot`

**Files:** arch_patterns/pipeline.ig (3), arch_patterns/example.ig (4), decision_tree/builder.ig (1), igniter_parser/parser.ig (1), igniter_parser/lexer.ig (1), vector_editor/document.ig (1), bloom_filter/example.ig (14)

**Route: direct migration today** — `call_contract("append", coll, elem)` → `append(coll, elem)` is a 1:1 mechanical source rewrite. `stdlib.collection.append` is dual-toolchain and works in both Ruby and Rust today.

---

### SHAPE-2: BOOTSTRAP (6 calls)

```
call_contract("append", bare_element_1, bare_element_2)
```

Both arguments are bare elements (not Collection-typed). This is a workaround for the absence
of `stdlib.collection.empty`: the two-element seed collection cannot be constructed any other way.

**Examples:**
- `call_contract("append", t0, t1)` — two `Transition` records → seed `Collection[Transition]`
- `call_contract("append", "pipeline:start", "pipeline:init")` — two `String` literals
- `call_contract("append", decision_income, decision_credit)` — two `TreeNode` records
- `call_contract("append", feat_income_high, feat_credit_good)` — two `Feature` records
- `call_contract("append", s0, s1)` — two `Slot` records (bloom filter seed)

**Files:** arch_patterns/example.ig (2), decision_tree/example.ig (3), bloom_filter/example.ig (1)

**Why `append(t1, t2)` doesn't work directly:** `stdlib.collection.append` has canonical
signature `Collection[T] × T → Collection[T]`. Passing two bare `T` values fires
`OOF-COL2: first argument must be Collection[T]`.

**Route: gated on LANG-STDLIB-COLLECTION-EMPTY-P1.** Once `empty()` exists:
```
# Before (call_contract workaround)
compute c0 = call_contract("append", t1, t2)

# After
compute c0 = append(append(empty(), t1), t2)
```

---

### SHAPE-3: EMPTY_CONSTRUCTOR (3 calls)

```
call_contract("empty")
```

Zero positional arguments. Constructs an empty collection whose element type is inferred
from the output type annotation.

**Examples:**
- `compute initial_tokens = call_contract("empty")` → `output initial_tokens : Collection[AstNode]`
- `compute initial_nodes = call_contract("empty")` → same pattern
- `compute empty_children = call_contract("empty")` → `output : Collection[AstNode]`

**Files:** igniter_parser/api.ig (2), igniter_parser/parser.ig (1)

**Route: gated on LANG-STDLIB-COLLECTION-EMPTY-P1.** Once `empty()` exists:
```
compute empty_children = empty()
```

---

## Why NOT to Special-Case Stdlib Names in `call_contract`

Five invariants make stdlib-name hijacking inside `call_contract` the wrong approach:

### I-1: Registry contract (call_contract is inter-contract dispatch)

`call_contract` dispatches to a *declared module contract* by name. Its registry is built
exclusively from `classified_program.contracts` — PascalCase module declarations. "append" is
not a contract; it is never in the registry. This is correct by definition. Adding an
allowlist of stdlib names would conflate two orthogonal language constructs.

### I-2: Bootstrap arity mismatch

If "append" were special-cased, the call_contract handler would need to distinguish:
- `call_contract("append", coll, elem)` → route to `Collection[T] × T → Collection[T]`
- `call_contract("append", t1, t2)` → route to `T × T → Collection[T]` (bootstrap)

`stdlib.collection.append` only has the first signature. A special-case would need
its own bootstrap detection logic — a sub-language inside call_contract. This complexity
has no canon authority.

### I-3: Double-dispatch (stdlib already handled upstream)

`append(coll, elem)` is already handled at the `when "append"` arm in `infer_call` — *before*
the `when "call_contract"` arm. The correct fix is to call `append(...)` directly. Routing
`call_contract("append", ...)` → `infer_append_call` would create a second dispatch path for
the same semantic operation with no added value.

### I-4: SIR structural mismatch

The SIR node for `call_contract("append", ...)` has `fn: "call_contract"`. The stdlib route
requires `fn: "stdlib.collection.append"` (qualified). Rewriting the fn key inside the type
checker is a lowering concern, not type inference — it violates the layer boundary between TC
and SIR emitter.

### I-5: Callee invariant

The error message "not found in this module" is *semantically correct*. A stdlib name is not
"in this module" — it's not a module contract at all. Silently accepting it would weaken the
callee invariant that every `call_contract` callee is a verified, purity-checked, arity-checked
contract in scope.

---

## Blocking Behavior (Proven in Both TCs)

| Form | Ruby TC | Rust TC |
|------|---------|---------|
| `call_contract("append", coll, elem)` | OOF-TY0 "unknown callee 'append' — not found in this module" | OOF-TY0 same |
| `call_contract("append", T, T)` | OOF-TY0 same | OOF-TY0 same |
| `call_contract("empty")` | OOF-TY0 same | OOF-TY0 same |
| `append(coll, elem)` direct | **ok** (stdlib.collection.append) | **ok** |
| `append(T, T)` bootstrap | OOF-COL2 (wrong first-arg type) | OOF-COL2 |
| `empty()` direct | OOF-TY0 "Unknown function: empty" | OOF-TY0 |

---

## Route Map

| Shape | Count | Route | Blocker |
|-------|-------|-------|---------|
| ACCUMULATING | 25 | Mechanical source rewrite: `call_contract("append", c, e)` → `append(c, e)` | **None** — works today |
| BOOTSTRAP | 6 | Rewrite after `empty()` available: `append(append(empty(), t1), t2)` | **LANG-STDLIB-COLLECTION-EMPTY-P1** |
| EMPTY_CONSTRUCTOR | 3 | Rewrite: `call_contract("empty")` → `empty()` | **LANG-STDLIB-COLLECTION-EMPTY-P1** |

**Total migration: 34 calls.** 25 unblocked today; 9 gated on empty().

---

## Next Cards

| Card | Scope | Status |
|------|-------|--------|
| **LANG-STDLIB-COLLECTION-EMPTY-P1** | Proposal + readiness for `empty(): → Collection[T]`; no predecessors; parallel to append arc | **RECOMMENDED NEXT** |
| **LANG-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1** | Source rewrite card — 34 call sites; gates on LANG-STDLIB-COLLECTION-EMPTY-P1 for bootstrap/empty shapes | After LANG-STDLIB-COLLECTION-EMPTY-P1 |

The `LAB-FORM-INVOCATION` arc (if opened) does NOT affect this routing — these are plain
function calls in the Igniter grammar, not form invocations.

---

## Closed Surfaces

- No source rewrites in this card
- No stdlib implementation (`append` and `empty`)
- No dynamic `call_contract` (r, t) — that's Tier 2, handled separately
- No VM changes
- No new OOF codes
- No `call_contract` dispatch changes
