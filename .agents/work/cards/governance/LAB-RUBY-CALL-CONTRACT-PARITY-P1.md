# Agent Card: LAB-RUBY-CALL-CONTRACT-PARITY-P1

**Lane:** governance / readiness / Ruby parity  
**Mode:** READINESS PROOF ONLY — no implementation  
**Status:** CLOSED — PROVED 56/56 PASS  
**Date closed:** 2026-06-12  
**Proof runner:** `igniter-lab/igniter-view-engine/proofs/verify_lab_ruby_call_contract_parity_p1.rb`  
**Lab doc:** `igniter-lab/lab-docs/governance/lab-ruby-call-contract-parity-readiness-v0.md`

---

## Goal

Establish readiness baseline for Ruby `call_contract` parity:
classify all call shapes, compare Ruby vs Rust behavior, identify safe/blocked subsets,
and gate P2 on the output assignability dependency.

---

## Shape Census

| Shape | Count | Files | P2 verdict |
|-------|-------|-------|------------|
| LITERAL_MODULE (PascalCase) | 113 | 25 | SAFE — Tier 1 registry lookup |
| STDLIB_FORM ("append"/"empty") | 34 | 9 | BLOCKED — needs stdlib route |
| DYNAMIC (variable first arg) | 1 | 1 | SAFE — Tier 2 Unknown |
| LAMBDA_INTERNAL (inside `->`) | 8 | 4 | SAFE — subset of above |

---

## Ruby TC vs Rust TC Behavioral Delta

| Situation | Ruby TC (before P2) | Rust TC (LAB-RACK-P11) |
|-----------|--------------------|-----------------------|
| Any call_contract | OOF-TY0 "Unknown function" | (see below) |
| Literal same-module, ok | OOF-TY0 | status ok, type resolved |
| Literal unknown callee | OOF-TY0 | OOF-TY0 "not found in this module" |
| Stdlib name ("append") | OOF-TY0 | OOF-TY0 "not found in this module" |
| Dynamic variable | OOF-TY0 | ok, Unknown (Tier 2) |
| Arity mismatch | OOF-TY0 | OOF-TY0 |

---

## Safe Subset (P2 scope)

**Authorized for P2:**
1. `when "call_contract"` arm in Ruby TC `infer_call`
2. Tier 1: literal String → lookup `contract_registry`, resolve output, validate arity/purity
3. Tier 2: non-literal → Unknown, no error (matches Rust)
4. OOF-TY0 messages parity with Rust (same conditions, same structure)

**Not authorized for P2:**
- Stdlib names ("append", "empty") → separate stdlib routing tracks
- `call_contract("empty")` → `stdlib.collection.empty` not in inventory
- Dynamic Unknown → output type acceptance (Tier 2 stays VM fail-closed)

---

## Output Assignability Gate

P2 is explicitly conditional on **LANG-OUTPUT-TYPE-ASSIGNABILITY-P1** state:
- After P2 resolves callee types, output check becomes structural
- Parametric types (Collection[T]) need `structurally_assignable?`
- Safe path: bare named types use existing equality check; parametric → Unknown until P1

---

## Closed Surfaces

- No Ruby TC changes
- No Rust TC changes
- No VM/runtime changes
- No dynamic dispatch acceptance
- No Unknown typed output escape

---

## Next Route

**LANG-RUBY-CALL-CONTRACT-PARITY-P2** — bounded Ruby TC implementation.  
`when "call_contract"` arm + Tier 1/Tier 2 dispatch + arity/purity checks.  
Proof matrix ≥ 50 checks. Explicitly conditional on output assignability state.
