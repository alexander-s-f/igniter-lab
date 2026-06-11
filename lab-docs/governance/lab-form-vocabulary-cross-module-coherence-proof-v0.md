# LAB-FORM-VOCABULARY-P1: Cross-Module Form Vocabulary Coherence Proof

**Track:** form-vocabulary-cross-module-coherence-and-order-independent-resolution-v0
**Route:** LAB PROOF / DESIGN + FIXTURE / NO CANON IMPLEMENTATION
**Date:** 2026-06-11
**Result:** PASS — 61/61 checks
**Verdict:** ACCEPT

---

## 1. Purpose

This proof evaluates whether a safe **form vocabulary model** exists for Igniter —
one where multiple modules can expose form words without ambient order-dependent
behavior. It directly addresses TH-2 (Coherence) from the TH-1..TH-6 acceptance
frame (LAB-FORM-LAYER-THEORY-P1).

**Primary question:** Can Igniter support an explicit form vocabulary model where
form words are resolved independently of file/import order and all ambiguity fails
closed?

**Answer: Yes** — under the explicit vocabulary import model proved here (V-1..V-8),
cross-module form vocabularies are coherent, order-independent, and authority-closed.
The remaining gap is OOF-REF2 (cross-module typed-ref resolution), which gates the
canon implementation of cross-module `uses ContractName`, and by extension the
cross-module typed-ref anchor required by V-6.

---

## 2. Authority Surface

**Allowed:**
- Proof runner (`verify_lab_form_vocabulary_p1.rb`) — reads SIR and Rust source; does not modify either
- Proof-local model classes
- Lab fixtures (`.ig` files, canon syntax only)
- This lab doc, card, portfolio update

**Closed — not opened by this proof:**
- Canon parser / typechecker / SemanticIR — no changes
- VM / runtime — no changes
- Public vocabulary syntax — not introduced
- Macro system — not touched
- `call_contract` behavior — unchanged
- `form_registry` / `form_resolver` (Rust lab) — remain lab-only divergence
- Package / visibility / capability / profile — unchanged

---

## 3. Predecessor Chain

| Card | Result | Key Finding |
|------|--------|-------------|
| LAB-FORM-LAYER-THEORY-P1 | OPEN (strong hypothesis) | Forms = stratification; vocabulary = unit; coherence = hard problem |
| LAB-CONTRACT-FORMS-P2 | RECONCILED — SPLIT+KEEP | Rule C-1; TH-2 in-module proved, cross-module OPEN |
| LAB-FORM-INVOCATION-P1 | 66/66 PASS | TH-1/4/6 mechanised; TH-2 cross-module OPEN |

---

## 4. Vocabulary Model Design

### 4.1 Core Principle

A form vocabulary is a **named, owner-declared collection of form words**. Words are
explicitly imported by consuming modules. There are no ambient vocabularies —
a module that doesn't import a vocabulary cannot see its words.

This preserves the key property from LAB-FORM-LAYER-THEORY-P1: "no ambient dialects."

### 4.2 Syntax Evaluation

Three candidate syntax forms were considered (all proof-local; none are canon):

| Option | Sketch | Assessment |
|--------|--------|------------|
| A | `speaks Query.Forms` | Most explicit; new keyword (`speaks`); cleanest separation |
| B | `uses vocabulary Query.Forms` | Reuses `uses` keyword precedent; moderate cognitive load |
| C | `form vocabulary Query.Forms { ... }` | Captures ownership; highest ceremony |

**Decision (proof-local):** The proof uses an abstract `FormDictionaryImport` struct
that is agnostic to syntax. Option A (`speaks`) is the preferred sketch for a future
proposal because it most clearly communicates "this module opts into a surface
vocabulary" without conflating dependency (`uses`) with vocabulary import. Option B
is acceptable if keyword minimalism is a constraint. Proposal authoring is the next
step (after OOF-REF2 canon fix).

### 4.3 Proof-Local Model Classes

| Class | Purpose |
|-------|---------|
| `ProofLocalContractRef` | Typed ref from SIR or proof-local construction; absent: execute/dispatch/capability |
| `FormWord` | Trigger→target word; validates V-2 (owner) + V-6 (typed-ref) on construction |
| `FormVocabulary` | Named vocabulary exported by owner module |
| `FormDictionaryImport` | Explicit import record (V-1); `import_mode: :explicit` required |
| `VocabularyOwner` | Ownership record: `owned_contracts` + `owned_vocabularies` |
| `VocabularyRegistry` | Aggregates imported vocabularies; resolves triggers (V-3/4/5) |
| `FormResolutionReceipt` | Result: names vocabulary + word + target (V-7) |
| `VocabularyConflict` | Ambiguity event: names both competing vocabularies |

---

## 5. Rules Proved

| Rule | Description | Evidence |
|------|-------------|----------|
| V-1 | Explicit vocabulary import required | Section B-04, G-03, J-01 |
| V-2 | Owner rule: contract owner or vocabulary owner only | Section F, J-02 |
| V-3 | Order independence: same result under import permutation | Section D-01..03 |
| V-4 | Ambiguity fails closed: E-FORM-VOCAB-AMBIG | Section E, D-04..06 |
| V-5 | No first-wins: registration order never selects winner | Section D-05/07, E-05 |
| V-6 | Typed-ref anchor required for every vocabulary word | Section B-08, C-05, J-05 |
| V-7 | Receipt names vocabulary + word selected | Section B-06/07, J-05 |
| V-8 | Vocabulary import grants no capability/profile/runtime authority | Section I |

---

## 6. Proof Sections

### Section A — INVENTORY (6/6)

Inspects the existing Rust lab implementation (`form_registry.rs`, `form_resolver.rs`)
for reusable coherence principles, and verifies the OOF-REF2 cross-module gate.

| Check | Finding |
|-------|---------|
| A-01 | `trigger_index: HashMap<String, Vec<usize>>` — reusable pattern for vocabulary word indexing |
| A-02 | `E-FORM-AMBIG` with "NO winner" comment — fail-closed principle already encoded |
| A-03 | `trust_level: TrustLevel` — vocabulary gating hook present |
| A-04 | `inherited_from: Option<String>` — vocabulary provenance hook present |
| A-05 | `alpha_module.ig` compiles clean — substrate for vocabulary model |
| A-06 | Cross-module dotted `uses` → parse/type error (OOF-REF2 gate confirmed) |

**Finding:** The Rust lab implementation already encodes the key coherence principles
(fail-closed ambiguity, trigger indexing, provenance tracking). The vocabulary model
can build on these without diverging from the existing design.

### Section B — POSITIVE SINGLE VOCABULARY (8/8)

Validates that a single vocabulary with one word resolves correctly.

| Check | Evidence |
|-------|----------|
| B-01..02 | `FormVocabulary` and `FormWord` with resolved anchor are valid |
| B-03 | `FormWord` has no `execute`, `runtime_dispatch`, `capability_grant` |
| B-04 | `FormDictionaryImport` is `:explicit` (V-1 enforced) |
| B-05 | Registry resolves `.filter` to `AlphaFilter` in Consumer context |
| B-06 | Receipt names vocabulary `Alpha.Forms` + word `filter` (V-7) |
| B-07 | Receipt has `target_contract_name == "AlphaFilter"` |
| B-08 | Receipt has `has_typed_ref_evidence? == true` (V-6) |

### Section C — MULTI-MODULE POSITIVE (6/6)

Validates a two-vocabulary cross-module scenario.

| Check | Evidence |
|-------|----------|
| C-01 | Alpha module owns AlphaFilter; vocabulary exports filter word |
| C-02 | Consumer imports both Alpha.Forms and Beta.Forms (2 explicit imports) |
| C-03..04 | `.filter` resolves to Alpha.Forms in Consumer context; receipt names vocabulary + word |
| C-05 | Cross-module typed-ref (`BetaFilter`) is proof-local-only; `proof_local_only? == true` |
| C-06 | `to_h` carries full dependency chain: vocabulary_name, word_name, target_contract |

**Note on C-05:** The `beta_filter_ref` is marked `cross_module: true` and
`resolution_status: :resolved` (proof-local). This explicitly flags the OOF-REF2 gap:
in canon, cross-module `uses ContractName` is blocked until the import mainline lands.

### Section D — ORDER INDEPENDENCE (7/7)

Permutation tests for import order.

**Non-conflicting case (D-01..03):**
- `[Alpha.Forms, Beta.Forms]` → `.filter` resolves to `Alpha.Forms`
- `[Beta.Forms, Alpha.Forms]` → `.filter` resolves to `Alpha.Forms`
- Receipts identical under both orderings → V-3 proved

**Conflicting case (D-04..07):**
- `[Alpha.PipeForms, Beta.Forms]` with same trigger `>>` → `E-FORM-VOCAB-AMBIG`
- `[Beta.Forms, Alpha.PipeForms]` → same `E-FORM-VOCAB-AMBIG`
- Both orderings name the same two vocabularies in the conflict
- Registration order never selects the winner → V-5 proved

### Section E — AMBIGUITY (6/6)

| Check | Evidence |
|-------|----------|
| E-01..02 | Two same-arity candidates → `:ambiguous` + `E-FORM-VOCAB-AMBIG` |
| E-03 | Conflict names both vocabularies (`Alpha.PipeForms`, `Beta.Forms`) |
| E-04 | Arity mismatch between candidates → refusal, not ambiguity |
| E-05 | Conflict is symmetric: sorted vocabulary names identical under both orderings |
| E-06 | Non-conflicting triggers from same vocabularies resolve correctly |

**Key design decision:** Unlike the in-module resolver (which uses type-directed
arity filtering then fails on ambiguity), the vocabulary resolver applies the same
fail-closed rule at a higher granularity: two vocabularies with the same trigger
token and compatible arity → `E-FORM-VOCAB-AMBIG` regardless of which vocabulary
was imported first. This is stronger than first-wins and weaker than requiring
globally unique triggers.

### Section F — OWNER RULE (6/6)

V-2: A form word may be declared only by the target contract owner or a declared
vocabulary owner.

| Check | Evidence |
|-------|----------|
| F-01 | Contract owner (`AlphaFilter ∈ owned_contracts`) → valid word |
| F-02 | Vocabulary owner (`AlphaFilter ∈ owned_vocabularies`) → valid word |
| F-03 | Third-party (empty `owned_contracts` + `owned_vocabularies`) → `E-FORM-V2-OWNER` |
| F-04 | `VocabularyOwner.to_h` carries `owned_contracts` + `owned_vocabularies` |
| F-05 | `owns_contract?("BetaFilter")` returns false for `alpha_owner` |
| F-06 | `third_party_word.error_codes == ["E-FORM-V2-OWNER"]` |

**Implementation note:** V-2 checks ownership declaratively via `VocabularyOwner`.
It does NOT use "declaring_module == owner_module" as a shortcut — that would grant
any module the ability to register words for contracts it doesn't own. Ownership must
be explicitly registered in `VocabularyOwner.owned_contracts` or `owned_vocabularies`.

### Section G — TH-2 Coherence (6/6)

| Check | Evidence |
|-------|----------|
| G-01 | In-module forms are a degenerate vocabulary (declaring_module == owner) — consistent with P1 model |
| G-02 | Two consumer modules importing same vocabulary → identical receipts |
| G-03 | Vocabulary not imported → `E-FORM-VOCAB-NO-IMPORT` (no ambient leakage, V-1) |
| G-04 | Cross-module typed ref has `proof_local_only? == true` (OOF-REF2 gap is explicit) |
| G-05 | Identical receipts across two import contexts (G-02 re-verified via to_h) |
| G-06 | Import set is fully enumerable per module → coherence is decidable |

**TH-2 status after this proof:**
- **In-module:** Proved (FTD-5/6 from Rust lab + LAB-FORM-INVOCATION-P1 in-module model)
- **Cross-module (within explicit vocabulary model):** Proved conditionally — coherence holds for any pair of modules that import the same explicitly-declared vocabulary
- **Cross-module (typed-ref substrate):** Conditional on OOF-REF2 + PROP-IMPORT-RESOLUTION. The proof flags this gap explicitly with `proof_local_only?`

### Section H — TH-3 Stable Skeleton (5/5)

| Check | Evidence |
|-------|----------|
| H-01 | All vocabulary words use `trigger_kind ∈ VALID_FORM_KINDS` (7 existing variants) |
| H-02 | Registering a new word does not mutate `VALID_FORM_KINDS` |
| H-03 | Ambiguity is detected at resolution-time, not parse-time |
| H-04 | A word with invalid `trigger_kind` is rejected (no grammar mutation) |
| H-05 | `vocabulary_name` + `owner_module` are metadata only — no parser-visible token |

**TH-3 status:** Confirmed by design. Vocabulary adds words over existing FormKind
productions; it cannot declare new grammar variants.

### Section I — Authority Closed (6/6)

All proof-local vocabulary types are free of authority methods:

| Type | Absent |
|------|--------|
| `FormVocabulary` | `execute`, `runtime_dispatch` |
| `FormWord` | `runtime_dispatch`, `capability_grant` |
| `FormDictionaryImport` | `capability_grant`, `profile_binding` |
| `VocabularyRegistry` | `call_contract`, `execute` |
| `FormResolutionReceipt` | `profile_binding`, `runtime_dispatch`, `capability_grant` |
| `VocabularyOwner` | `package_authority`, `visibility_grant`, `grant_import` |

### Section J — Route (5/5)

| Check | Evidence |
|-------|----------|
| J-01 | V-1 enforced: empty registry → `E-FORM-VOCAB-NO-IMPORT` |
| J-02 | V-2 enforced: third-party word → `E-FORM-V2-OWNER` |
| J-03 | V-3/V-5 enforced: non-conflicting receipts identical under permutation |
| J-04 | V-4 enforced: conflict → `E-FORM-VOCAB-AMBIG`, no winner |
| J-05 | V-6/V-7 enforced: typed-ref required + receipt names vocabulary + word |

---

## 7. TH Status After This Proof

| TH | Name | Status | Evidence |
|----|------|--------|----------|
| TH-1 | Conservativity | Partially proved (effect-modifier gap) | LAB-FORM-INVOCATION-P1 |
| TH-2 | Coherence | **Conditionally proved** | G-01..06; conditional on OOF-REF2 for full cross-module |
| TH-3 | Skeleton stability | **Confirmed by design** | H-01..05; vocabulary adds words, not productions |
| TH-4 | Hygiene | Mechanised (F-01/02/03/05) | LAB-FORM-INVOCATION-P1 |
| TH-5 | Resugaring | Demonstrated | LAB-FORM-INVOCATION-P1 |
| TH-6 | Eliminability | Mechanised (explicit == lowered) | LAB-FORM-INVOCATION-P1 |

---

## 8. Open Gaps

1. **OOF-REF2: Cross-module typed-ref anchor** — `uses ContractName` is same-module
   only in v0. V-6 for cross-module vocabulary words requires the import mainline
   (PROP-IMPORT-RESOLUTION) + OOF-REF2 canon fix. All cross-module typed refs in
   this proof are `proof_local_only: true`.

2. **TH-2 full canon cross-module** — Conditional on OOF-REF2 + PROP-IMPORT-RESOLUTION.
   The vocabulary model is coherent, but the typed-ref substrate underneath it is not
   yet canon for cross-module cases.

3. **TH-3 parse-time golden-test** — FormKind skeleton stability is confirmed by design.
   No parse-time fixture test that a vocabulary word cannot introduce a new grammar
   production. This is structural (FormKind is a closed enum in Rust); no fixture needed.

4. **MultiKeyword arm-capture vocabulary** — Deferred. System/Stdlib-gated in v0.

5. **Syntax form for vocabulary import** — Three candidates evaluated (A/B/C); proof
   is syntax-agnostic. Proposal authoring should pick one and justify.

---

## 9. Recommendation

**ACCEPT.** The explicit vocabulary model is coherent under the proof-local model.

V-1..V-8 are all mechanised:
- V-1 (explicit import) and V-3/V-5 (order independence) are the novel properties proved here
- V-4 (fail-closed ambiguity) reuses the E-FORM-AMBIG principle from the Rust lab
- V-2 (owner rule) is new — requires explicit ownership record, not module-name matching
- V-6 (typed-ref anchor) is carried forward from C-1 in LAB-FORM-INVOCATION-P1
- V-7 (resugaring receipt) extends the ResugaringTrace from P1 to name the vocabulary
- V-8 (authority closed) is consistent across all proof-local types

**Next route:** Proposal authoring for the vocabulary import mechanism — after
PROP-IMPORT-RESOLUTION provides the cross-module module table that V-6 needs for
canon cross-module typed refs.

---

## 10. Artefacts

| Artefact | Path |
|----------|------|
| Proof runner | `igniter-lab/igniter-view-engine/proofs/verify_lab_form_vocabulary_p1.rb` |
| Fixture: alpha_module | `igniter-lab/igniter-view-engine/fixtures/form_vocabulary/alpha_module.ig` |
| Fixture: beta_module | `igniter-lab/igniter-view-engine/fixtures/form_vocabulary/beta_module.ig` |
| Fixture: consumer_module | `igniter-lab/igniter-view-engine/fixtures/form_vocabulary/consumer_module.ig` |
| Lab doc (this) | `igniter-lab/lab-docs/governance/lab-form-vocabulary-cross-module-coherence-proof-v0.md` |
| Card | `igniter-lab/.agents/work/cards/governance/LAB-FORM-VOCABULARY-P1.md` |
| Predecessor (theory) | `igniter-lab/lab-docs/governance/lab-form-layer-theory-and-grammar-stratification-v0.md` |
| Predecessor (reconciliation) | `igniter-lab/lab-docs/governance/lab-contract-forms-lineage-reconciliation-v0.md` |
| Predecessor (in-module proof) | `igniter-lab/lab-docs/governance/lab-contract-invocation-forms-in-module-proof-v0.md` |
