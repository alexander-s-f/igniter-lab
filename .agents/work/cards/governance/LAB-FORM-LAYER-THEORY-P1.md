# Card: LAB-FORM-LAYER-THEORY-P1

**Category:** governance / lang / theory
**Track:** contract-invocation-forms-and-form-assisted-composition-v0 (continuation)
**Status:** CLOSED — theoretical foundation authored; verdict OPEN (theory coherent)
**Gate result:** N/A — theory research (no proof runner); no code/canon changes
**Date closed:** 2026-06-11
**Route:** BACKGROUND RESEARCH / THEORY / NO IMPLEMENTATION
**Predecessor:** LAB-CONTRACT-FORMS-P1 (SPLIT verdict; terminology preserved)
**Pin:** Pinned background; mainline (import resolution / entrypoint / module identity) untouched.

---

## Goal

Develop the strong hypothesis that forms are an undervalued *stratification
mechanism* — a fixed verifiable semantic kernel (contracts + PROP-002 algebra +
SemanticIR) plus an open surface vocabulary (forms) — and give it a fundamental
theoretical grounding in grammar transformation.

---

## Headline

The Lego-bricks-with-pictures metaphor has an exact mathematical shape, and
every joint lands on standard, well-studied theory:

| Joint | Theory | Status in repo |
|---|---|---|
| Kernel algebra | traced symmetric monoidal category | **already claimed by PROP-002** (lines 152-154, 453-454) |
| "Pictures" | string diagrams; forms = named derived operations (definitional extension) | new framing |
| Honesty | conservativity theorem: forms add abbreviation power, NOT expressive power (Felleisen eliminability) | converts Covenant Axiom 1/P27 instinct into a provable property |
| Grammar mechanism | fixed skeleton + open vocabulary (Smalltalk/Wyvern lineage) — vocabulary extension preserves skeleton unambiguity; conflicts move from parse time (undecidable) to resolution time (decidable, fail-closed) | **FormKind ×7 already implements exactly this** |
| Execution layer | elaboration to trusted kernel (GHC Core / Lean 4 / Racket precedents) | lab resolver ≈ elaborator |
| Tooling | resugaring (Pombrio–Krishnamurthi) — bidirectional source↔kernel views | `ResolvedExpr` already carries both ends |
| **The one new hard problem** | **coherence/ownership** (type-class coherence; Rust orphan rule) — candidate rule: form declarable only by contract owner or vocabulary owner; order-independent resolution; cross-module priority races forbidden | gates on import-resolution mainline — validates SPLIT sequencing |

Beyond invocation: the right unit is the **form vocabulary** (named, versioned,
`speaks`-imported — no ambient dialects, P28 at language level). The lab has
already invented three proto-vocabularies independently (view, query,
outcome/decision) — one mechanism replaces N ad-hoc DSL temptations, and the
kernel stays still while the language grows.

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Theory doc | `lab-docs/governance/lab-form-layer-theory-and-grammar-stratification-v0.md` | ✅ DONE |
| This card | `.agents/work/cards/governance/LAB-FORM-LAYER-THEORY-P1.md` | ✅ DONE |
| Portfolio update | `.agents/portfolio-index.md` | ✅ DONE |

---

## Proof Obligations Named (for future proof-local cards)

- TH-1 conservativity receipt (forms-IR ≡ hand-expanded-IR, golden equality)
- TH-2 coherence / order independence (permute imports; bit-identical resolution)
- TH-3 skeleton stability (new forms never change existing parses)
- TH-4 hygiene (no capture across all seven FormKinds)
- TH-5 resugaring (diagnostics show surface span + expanded invocation)
- TH-6 eliminability boundary (non-eliminable features structurally inexpressible as forms)

---

## Decision

**OPEN** — theory coherent; undervalued-idea hypothesis confirmed: forms are
the growth mechanism of the language itself, with the kernel held verifiably
still. Single identified cost center: coherence (gates on import mainline).

## Next Route (spine unchanged; one amendment, one addition)

```
LAB-TYPED-CONTRACT-REF-P1   — unchanged, still first
LAB-CONTRACT-FORMS-P2       — AMENDED: adopts TH-1..TH-6 as acceptance frame;
                              decides control-forms (MultiKeyword/trust_level) boundary
LAB-FORM-VOCABULARY-P1      — NEW (after P2 + import mainline): proof-local,
                              2 vocabularies over one kernel fixture set;
                              mechanize TH-1/TH-2/TH-3
LAB-FORM-CONSTRUCTOR-P1     — unchanged (Gap-I, independent clock)
```

## Closed Surfaces

No implementation; no canon PROP; no grammar adoption; no `speaks` syntax
authority (sketch only); no vocabulary-gating-by-profile proposal (flagged
far-future only); no change to SPLIT sequencing; external literature is
grounding, not authority.
