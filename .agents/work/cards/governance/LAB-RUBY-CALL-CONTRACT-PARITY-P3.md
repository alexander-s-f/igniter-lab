# Agent Card: LAB-RUBY-CALL-CONTRACT-PARITY-P3

**Lane:** governance / implementation / Ruby parity  
**Mode:** IMPLEMENTATION PROOF  
**Status:** CLOSED — PROVED 56/56 PASS  
**Date:** 2026-06-12  
**Proof runner:** `igniter-lang/experiments/call_contract_parity_proof/verify_lab_ruby_call_contract_parity_p3.rb`  
**Grounding:**
- LAB-RUBY-CALL-CONTRACT-PARITY-P1 (56/56) — shape census + safe subset
- LAB-RUBY-CALL-CONTRACT-PARITY-P2 (planning) — insertion points + registry plan
- LANG-OUTPUT-TYPE-ASSIGNABILITY-P3 (70/70) — `structurally_assignable?` available; parametric outputs resolved fully
- LAB-RACK-P9 (60/60) — VM fail-closed for Tier 2
- LAB-RACK-P11 (47/47) — Rust TC reference for message parity

---

## Goal

Implement `when "call_contract"` in the Ruby TypeChecker `infer_call` switch.
Tier 1 literal same-module dispatch: registry lookup, purity/arity/self-recursion checks,
output type resolution. Tier 2 dynamic callee: Unknown, no error.

---

## Scope

- `igniter-lang/lib/igniter_lang/typechecker.rb` — four additions
- `igniter-lang/experiments/call_contract_parity_proof/verify_lab_ruby_call_contract_parity_p3.rb` — 56-check proof runner
- Ruby only. No Rust, parser, VM, or runtime changes.

---

## Changes

### 1. `typecheck` — build `@call_contract_registry` (after `@same_module_registry` line)

```ruby
# LAB-RUBY-CALL-CONTRACT-PARITY-P3: build call_contract dispatch registry
@call_contract_registry = build_call_contract_registry(classified_program)
```

### 2. `typecheck_contract` — set `@current_contract_name` (after `contract_name_str =`)

```ruby
@current_contract_name = contract_name_str  # LAB-RUBY-CALL-CONTRACT-PARITY-P3: self-recursion guard
```

### 3. `infer_call` — new `when "call_contract"` arm (before `else`)

```ruby
when "call_contract"
  # LAB-RUBY-CALL-CONTRACT-PARITY-P3: Tier 1 literal same-module + Tier 2 dynamic
  infer_call_contract(expr, symbol_types, type_errors, type_warnings, node_name)
```

### 4. New methods: `build_call_contract_registry` + `infer_call_contract`

`build_call_contract_registry` — maps contract_name → `{modifier, input_count, input_names,
single_output_type, single_output_name, contract_name}`. Mirrors Rust `build_contract_registry`
(typechecker.rs:1372–1413). Placed after `build_same_module_registry`.

`infer_call_contract` — two-tier dispatch:
- **Guards:** empty args → OOF-TY0; first arg not String/Unknown → OOF-TY0
- **Tier 1** (literal String first arg): unknown callee → OOF-TY0; non-pure → OOF-TY0;
  self-recursion → OOF-TY0; arity mismatch → OOF-TY0; success → resolve `single_output_type`
- **Tier 2** (non-literal first arg): Unknown, no error

**Output resolution:** `LANG-OUTPUT-TYPE-ASSIGNABILITY-P3` is closed (70/70);
`structurally_assignable?` is implemented. Parametric types (`Collection[T]`, `Map[K,V]`, nested)
are fully resolved — no Unknown deferral needed. The output boundary check handles assignability.

---

## Proof

| Section | Topic | Checks |
|---------|-------|--------|
| A | Empty args → OOF-TY0 | 2 |
| B | First arg not String → OOF-TY0 | 3 |
| C | Unknown callee → OOF-TY0 | 4 |
| D | Non-pure callee → OOF-TY0 | 3 |
| E | Self-recursion → OOF-TY0 | 2 |
| F | Arity mismatch → OOF-TY0 | 4 |
| G | Tier 1 success — bare output types | 6 |
| H | Tier 1 success — parametric output types (P3 available) | 4 |
| I | Tier 2 dynamic callee → Unknown, no OOF-TY0 | 4 |
| J | Stdlib string names → OOF-TY0 not-found | 4 |
| K | OOF message text parity with Rust | 6 |
| L | Multi-contract module — registry isolation | 4 |
| M | No spurious OOF-TY0 on valid Tier 1 calls | 4 |
| N | OOF-TY0 NOT fired for Tier 2 | 3 |
| O | Regression — stdlib/recur unaffected | 3 |
| **Total** | | **56** |

---

## Output Assignability Gate — Resolved

P2 plan deferred parametric outputs to Unknown pending `LANG-OUTPUT-TYPE-ASSIGNABILITY-P3`.
P3 is closed (70/70) as of 2026-06-12. Parametric outputs are fully resolved in this
implementation. Sections H-01 through H-04 prove it.

---

## Closed

- No dynamic dispatch acceptance (Tier 2 stays Unknown)
- No stdlib call_contract special-case routing (stdlib names → OOF-TY0 not-found, correct)
- No plugin model
- No VM/runtime changes
- No cross-module resolution (same-module only, v0)
- No Rust TC changes

---

## Next Route

LANG-OUTPUT-TYPE-ASSIGNABILITY-P4 (Rust parity for structural output check) — independent track.  
Dynamic call_contract acceptance is deferred to a future card pending output assignability validation receipts.
