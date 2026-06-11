# LAB-FORM-VOCABULARY-P1 — Cross-Module Form Vocabulary Coherence Proof

**Track:** form-vocabulary-cross-module-coherence-and-order-independent-resolution-v0
**Route:** LAB PROOF / DESIGN + FIXTURE / NO CANON IMPLEMENTATION
**Status:** CLOSED — ACCEPT
**Gate result:** PROVED — 61/61 PASS
**Date:** 2026-06-11

---

## Context

LAB-FORM-INVOCATION-P1 (66/66 PASS) proved in-module forms are conservative elaborations
over the typed-ref substrate. TH-2 (Coherence) cross-module was OPEN, gating on the import
mainline + OOF-REF2.

This card proves that a safe vocabulary model exists for cross-module form coherence —
one where multiple modules can expose form words without ambient order-dependent behavior.

## Goal

Prove or reject a proof-local model for form vocabularies/dictionaries. Mechanise:
- V-1 Explicit vocabulary import
- V-2 Owner rule
- V-3 Order independence
- V-4 Ambiguity fails closed
- V-5 No first-wins
- V-6 Typed-ref anchor required
- V-7 Resugaring evidence
- V-8 Authority closed

Minimum 55 checks.

---

## Proof Summary

**Result: PASS (61/61)** — Verdict: **ACCEPT**

| Section | Checks | Subject |
|---------|--------|---------|
| A — INVENTORY | 6/6 | Rust registry reuse; OOF-REF2 gate confirmed |
| B — POSITIVE SINGLE | 8/8 | One vocabulary, one word, resolves |
| C — MULTI-MODULE | 6/6 | Two-module vocabulary import chain |
| D — ORDER INDEPENDENCE | 7/7 | Import permutation → identical receipts / same conflict |
| E — AMBIGUITY | 6/6 | Two vocabularies, same trigger → E-FORM-VOCAB-AMBIG |
| F — OWNER RULE | 6/6 | Contract owner ✓; vocab owner ✓; third-party → E-FORM-V2-OWNER |
| G — TH-2 COHERENCE | 6/6 | Conditional proof; OOF-REF2 gap explicit |
| H — TH-3 SKELETON | 5/5 | Vocabulary adds words, not grammar productions |
| I — AUTHORITY CLOSED | 6/6 | No execute/dispatch/capability/package on any type |
| J — ROUTE | 5/5 | V-1..V-8 all mechanised |

---

## Proof-Local Model

| Class | Purpose |
|-------|---------|
| `ProofLocalContractRef` | Typed ref; `cross_module: true` flags OOF-REF2 proof-local refs |
| `FormWord` | Trigger→target word; validates V-2 + V-6 on construction |
| `FormVocabulary` | Named vocabulary from owner module |
| `FormDictionaryImport` | Explicit import record (V-1); `import_mode: :explicit` required |
| `VocabularyOwner` | Ownership: `owned_contracts` + `owned_vocabularies` |
| `VocabularyRegistry` | Aggregates imports; resolves triggers; V-3/4/5 enforced |
| `FormResolutionReceipt` | Names vocabulary + word (V-7) |
| `VocabularyConflict` | Ambiguity: names both competing vocabularies |

---

## Key Findings

### 1. Vocabulary model is coherent under explicit imports

A module that imports a vocabulary explicitly (`FormDictionaryImport.explicit? == true`)
gets a fully enumerable, decidable set of visible form words. Cross-module coherence
follows: two modules importing the same vocabulary always get the same resolution result
(G-02/05).

### 2. Order independence is proved by permutation (V-3/V-5)

Two import orderings `[Alpha, Beta]` and `[Beta, Alpha]`:
- **Non-conflicting triggers**: identical receipts under both orderings (D-01..03)
- **Conflicting triggers**: identical `E-FORM-VOCAB-AMBIG` diagnostics naming same vocabularies
  under both orderings (D-04..07)

The `VocabularyRegistry#resolve` algorithm is order-independent because it collects ALL
candidates, applies arity filtering, then either picks the unique survivor or fails closed.
No first-wins branch exists.

### 3. Ambiguity fails closed (V-4) — not first-wins (V-5)

When two vocabularies export the same trigger with compatible arity, resolution produces
`E-FORM-VOCAB-AMBIG` with a `VocabularyConflict` naming both vocabularies (E-01..05).
There is no winner. The user must either qualify the call explicitly (`ContractName(args)`)
or remove the conflict.

### 4. Owner rule (V-2) requires explicit ownership record

Ownership is checked against `VocabularyOwner.owned_contracts` or `owned_vocabularies`.
The rule does NOT use "declaring module name matches" as a shortcut — that would grant
any module the ability to register words for contracts it doesn't own. Third-party
modules with empty ownership records receive `E-FORM-V2-OWNER` (F-03/06).

### 5. OOF-REF2 gap is bounded and explicit

Cross-module typed refs are `proof_local_only: true` — the `ProofLocalContractRef.cross_module`
flag makes this gap visible in the proof artefacts (G-04). The vocabulary model is sound
given resolved typed refs; the gap is in the substrate (canon `uses` + cross-module
resolution), not in the vocabulary layer itself.

### 6. In-module forms are a degenerate vocabulary

The in-module model from LAB-FORM-INVOCATION-P1 is consistent: when `declaring_module ==
owner_module`, V-2 is satisfied without a separate vocabulary owner. The vocabulary model
is strictly more general (G-01).

---

## Syntax Evaluation

Three candidate import forms were evaluated:

| Option | Sketch | Assessment |
|--------|--------|------------|
| A | `speaks Query.Forms` | Preferred — new keyword cleanly separates vocabulary import from dependency |
| B | `uses vocabulary Query.Forms` | Acceptable — reuses `uses` keyword |
| C | `form vocabulary Query.Forms { ... }` | Heaviest ceremony; captures ownership but verbose |

The proof is syntax-agnostic. Proposal authoring should commit to one form.

---

## TH Status After This Proof

| TH | Status | Change |
|----|--------|--------|
| TH-1 Conservativity | Partially proved | No change |
| TH-2 Coherence | **Conditionally proved** | New: vocabulary model coherence + order independence |
| TH-3 Skeleton stability | **Confirmed by design** | New: section H (vocabulary adds words, not productions) |
| TH-4 Hygiene | Mechanised | No change |
| TH-5 Resugaring | Demonstrated | No change |
| TH-6 Eliminability | Mechanised | No change |

---

## Open Gaps

1. **OOF-REF2**: Cross-module `uses ContractName` not yet canon; V-6 cross-module proof-local only
2. **TH-2 full canon**: Conditional on PROP-IMPORT-RESOLUTION + OOF-REF2 canon fix
3. **TH-3 parse-time fixture**: Skeleton stability confirmed structurally; no parse test needed
4. **Syntax choice**: Three options evaluated; proposal must commit to one

---

## Closed

Same authority surface as predecessors — nothing opened:
- Canon parser / typechecker / SemanticIR — no changes
- VM / runtime — no changes
- Public vocabulary syntax — not introduced
- `call_contract` — unchanged
- `form_registry` / `form_resolver` (Rust lab) — remain lab-only divergence
- Package / visibility / capability / profile — unchanged

---

## Next Routes

| Task | Gate |
|------|------|
| Proposal authoring for vocabulary import mechanism | PROP-IMPORT-RESOLUTION + OOF-REF2 canon fix |
| LAB-FORM-CONSTRUCTOR-P1 (T1 Gap-I Form Constructor) | Independent clock |

---

## Artefacts

| Artefact | Path |
|----------|------|
| Proof runner | `igniter-lab/igniter-view-engine/proofs/verify_lab_form_vocabulary_p1.rb` |
| Fixtures (3) | `igniter-lab/igniter-view-engine/fixtures/form_vocabulary/` |
| Lab doc | `igniter-lab/lab-docs/governance/lab-form-vocabulary-cross-module-coherence-proof-v0.md` |
| Predecessor (in-module) | `igniter-lab/lab-docs/governance/lab-contract-invocation-forms-in-module-proof-v0.md` |
| Predecessor (theory) | `igniter-lab/lab-docs/governance/lab-form-layer-theory-and-grammar-stratification-v0.md` |
