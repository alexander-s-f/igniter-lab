# Card: LAB-TYPED-CONTRACT-REF-P1

**Category:** governance / lang / proof
**Track:** typed-contract-reference-and-stringly-call-contract-replacement-v0
**Status:** CLOSED — proof complete; verdict ACCEPT (58/58 PASS)
**Gate result:** ACCEPT — proof-local model coherent; substrate ready for canon proposal
**Date closed:** 2026-06-11
**Route:** LAB PROOF / DESIGN + FIXTURE PRESSURE / NO CANON IMPLEMENTATION
**Predecessor:** LAB-CONTRACT-FORMS-P1 (SPLIT verdict; this card executes Track 1 of 3)
**Pin:** Pinned background; mainline (import resolution / entrypoint / module identity) untouched.

---

## Goal

Prove the smallest useful typed contract-reference surface that separates:
- contract implementation
- reference to a contract as a typed value/target
- later invocation/composition forms (forms lower **to** this substrate)

This is NOT a form system. This is the substrate that forms elaborate to.

Primary question: can Igniter represent "this contract uses/refers to contract X"
as typed, static, inspectable evidence instead of stringly runtime lookup?

**Answer: yes — all data is already in SemanticIR.**

---

## Headline Finding

**The data was already there.** SemanticIR already emits `contract_name`,
`modifier`, `inputs[]`, `outputs[]`, and `source_hash` (via manifest) for every
contract. The proof-local model (`ContractRef` / `ContractSignature` /
`ContractDependency` / `RefUseReceipt`) is built entirely from existing SIR
data — zero new compiler emission required.

The Rust typechecker already builds `HashMap<String, ContractRegistryEntry>` at
Tier 1 (P11). Typed refs are the same information with an explicit typed wrapper
and an inspectable dependency edge. The gap is not data — it is the **declared
source-level relationship** that source currently hides.

---

## Proof Summary

| Section | Checks | Result | Key claim |
|---------|--------|--------|-----------|
| A Discovery | 6/6 | PASS | All ContractRef fields in SIR; literal/dynamic callee discriminable |
| B Positive ref | 8/8 | PASS | ContractRef resolves; edge inspectable; DAG 2/3 nodes |
| C Negative ref | 8/8 | PASS | Unknown/effect/arity/self-rec → OOF-TY0; unresolved ≠ silent |
| D Authority | 6/6 | PASS | ContractRef has no execute/dispatch/capability method |
| E Composition | 6/6 | PASS | Not a form; not a macro; future lowering target for forms |
| F Import | 6/6 | PASS | Cross-file resolves; order-independent; import ≠ capability |
| G Trace | 6/6 | PASS | Edge label, signature expansion, receipt JSON-serializable |
| H Closed | 6/6 | PASS | No socket/net/canon claim/VM execution/macro impl |
| I Gap packet | 6/6 | PASS | ACCEPT verdict; next route named |
| **Total** | **58/58** | **PASS** | |

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Lab doc | `lab-docs/governance/lab-typed-contract-reference-boundary-proof-v0.md` | ✅ DONE |
| Proof runner | `igniter-view-engine/proofs/verify_lab_typed_contract_ref_p1.rb` | ✅ DONE |
| Fixture: basic | `igniter-view-engine/fixtures/typed_contract_ref/basic_typed_ref.ig` | ✅ DONE |
| Fixture: chain | `igniter-view-engine/fixtures/typed_contract_ref/chain_ref.ig` | ✅ DONE |
| Fixture: multi-callee | `igniter-view-engine/fixtures/typed_contract_ref/multi_callee_ref.ig` | ✅ DONE |
| This card | `.agents/work/cards/governance/LAB-TYPED-CONTRACT-REF-P1.md` | ✅ DONE |
| Portfolio update | `.agents/portfolio-index.md` | ✅ DONE |

---

## Key Findings

| # | Finding |
|---|---------|
| F1 | SemanticIR already carries all fields needed for ContractRef (contract_name, modifier, inputs, outputs, source_hash via manifest) — zero new emission required |
| F2 | Literal callee discriminant is `args[0].kind == "literal" && type_tag == "String"` — same as P10/P11 precedent |
| F3 | ContractRef has no execute/runtime_dispatch/capability_grant — reference is not invocation |
| F4 | Effect modifier is preserved in resolved_signature — future gating on effect-ref remains possible |
| F5 | Dependency graph (ContractDependency list) is DAG-inspectable, serializable to JSON, and produces human-readable edge labels |
| F6 | Cross-file resolution is order-independent (F-04 PASS; callee.ig + caller.ig in both orders → identical contract set) |
| F7 | ContractRef carries all fields LAB-CONTRACT-FORMS-P2 needs for form lowering (module_name, contract_name, contract_ref, modifier, input_count) — it is the substrate for TH-1 conservativity path |
| F8 | Cross-module typed refs are deferred: they require the module table from PROP-IMPORT-RESOLUTION-P3 (same-module case proven here) |

---

## Open Gaps

| Gap | Status | Gate |
|-----|--------|------|
| Cross-module typed refs | Deferred | PROP-IMPORT-RESOLUTION-P3 module table |
| Visibility gating on ref | Deferred | PROP-MODULE-VISIBILITY |
| TH-2 coherence for forms | Deferred | Import mainline (LAB-FORM-LAYER-THEORY-P1) |
| Gap-I Form Constructor | Independent | LAB-FORM-CONSTRUCTOR-P1 |
| `uses Contract` syntax | Successor | LANG-TYPED-CONTRACT-REF-PROP-P1 |

---

## Decision

**ACCEPT** — proof-local typed-ref substrate is coherent, satisfies all required
boundary properties, and is ready to ground a canon proposal. The gap between the
current state and a fully typed-ref language is exactly one syntax declaration +
one compiler pass (replacing the stringly string in `call_contract("Name")` with
a resolved `ContractRef`). No grammar ambiguity introduced; no new IR nodes
required; no VM changes needed.

---

## Next Route

```
LANG-TYPED-CONTRACT-REF-PROP-P1  — canon proposal for `uses Contract` syntax
                                    (or equivalent); must scope against P27/P28
                                    and PROP-002 algebra; predecessor to
                                    LAB-CONTRACT-FORMS-P2 acceptance frame

LAB-CONTRACT-FORMS-P2            — PROP-Forms lineage reconciliation (now has
                                    typed-ref substrate as lowering target +
                                    TH-1..TH-6 as acceptance frame)

LAB-FORM-CONSTRUCTOR-P1          — Gap-I, independent clock (Covenant P27/P28)
```

---

## Closed Surfaces

- No parser changes; no typechecker production changes; no SemanticIR production changes
- No VM/runtime changes; no canonical syntax adopted
- No form vocabulary, no macro system, no composition system
- No package/visibility claims; no public API
- `call_contract` runtime semantics unchanged; no replacement
- Cross-module typed refs deliberately deferred (import mainline gate)
