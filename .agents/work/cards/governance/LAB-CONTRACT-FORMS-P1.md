# Card: LAB-CONTRACT-FORMS-P1

**Category:** governance / lang
**Track:** contract-invocation-forms-and-form-assisted-composition-v0
**Status:** CLOSED — archaeology + formalization complete; verdict SPLIT; next routes named
**Gate result:** N/A — background research (no proof runner); no code/canon changes
**Date closed:** 2026-06-11
**Route:** BACKGROUND RESEARCH / FORMALIZATION / NO IMPLEMENTATION
**Pin:** Pinned background direction — intentionally separate from mainline
(import resolution / entrypoint / module identity); must not block or be blocked by it.

---

## Goal

Research and formalize "Contract Invocation Forms" / "form-assisted invocation"
as a possible abstraction layer separating contract implementation, reusable
invocation shape, composition syntax, and higher-level structure — so the
recurring "form" pain stops being rediscovered and lost.

Research question: can `form` be the missing abstraction layer between a
contract and its uses?

---

## Headline Finding

**The idea was already built once and lost.** `form_registry.rs` +
`form_resolver.rs` in the Rust lab compiler are NOT generics machinery — they
are a complete working implementation of Contract Invocation Forms (trigger →
type-directed resolution → `ContractInvocation`, with trace evidence and
F-01..F-06 fail-closed rules), specified in PROP-Forms-v0 (Agent-C archive) and
PROP-Forms-Enhanced-v0 (lab pressure doc). The lineage never entered canon
governance. The failure mode is **orphaning, not absence**.

Independently, the view DSL exploration converged on the same conclusion:
*"invocation alias that resolves to a `ContractInvocation` node. It should not
be a runtime primitive."*

---

## Terminology Verdict (normative disambiguation in report §3)

Eight meanings inventoried. Keep `form` for only two:
- **T1 Form Constructor** (`form NAME -> TypeTarget`, Gap-I, Covenant P27/P28) — value construction
- **T2 Contract Invocation Form** (PROP-Forms lineage) — call-shape declaration

Rename away from "form": typed contract reference (`uses Other`) is a
dependency feature, not a form; component invocation consumes forms; UI input
forms are unrelated; composition macros are **rejected** (macro-system risk +
PROP-002 owns multi-invocation structure).

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Research report | `lab-docs/governance/lab-contract-invocation-forms-formalization-v0.md` | ✅ DONE |
| This card | `.agents/work/cards/governance/LAB-CONTRACT-FORMS-P1.md` | ✅ DONE |
| Portfolio update | `.agents/portfolio-index.md` | ✅ DONE |

---

## Key Findings

| # | Finding |
|---|---------|
| F1 | "form" is overloaded across 8 meanings (report §3 table is the normative disambiguation) |
| F2 | Lab Form System exists and works: FormKind ×7, priority, `no_form`, shape-inherited forms, `form_resolution_trace.json`; lab-only per gov surface map |
| F3 | Gap-I Form Constructor is a canon Covenant commitment (P27/P28) with zero implementation — flagged "single highest-leverage open gap"; separate semantics from invocation forms |
| F4 | `call_contract` is two-tier: Tier 1 literal = static resolution (pure-only, arity, no self-recursion, LAB-RACK-P11 47/47); Tier 2 dynamic = Unknown. DAG compiler-known, source-invisible |
| F5 | Honesty analysis: forms are honesty-POSITIVE iff (1) static resolution, (2) IR-preserved lowering (Path B precedent), (3) trace evidence + tooling expansion view. Without all three — regression |
| F6 | Candidate E (composition macro) rejected: macro-system risk; PROP-002 algebra owns multi-invocation structure and already rejects dynamic selection |
| F7 | Typed contract refs (D) solve the core stringly/DAG pain with less machinery than forms and should be sequenced first |
| F8 | VM impact in v0: none — forms lower at compile time to existing call nodes |

---

## Decision

**SPLIT** — three separate tracks, never one "forms" track:

1. **Typed contract references** (first; smallest; solves stringly pain) — not named "form"
2. **Contract Invocation Forms** (reconcile orphaned PROP-Forms lineage with governance, then proof-local alias lowering if kept)
3. **Form Constructor / Gap-I** (independent clock; canon commitment; own design boundary)

Card's hypothesis confirmed in the narrow sense (compile-time invocation
adapter desugaring to explicit ContractInvocation, DAG kept honest) — but the
deeper finding is governance: the answer existed and was orphaned.

---

## Next Route

```
LAB-TYPED-CONTRACT-REF-P1   — design + proof-local `uses Other` typed refs (first)
LAB-CONTRACT-FORMS-P2       — PROP-Forms lineage reconciliation: keep/reduce/retire,
                              then proof-local invocation-alias lowering card if kept
LAB-FORM-CONSTRUCTOR-P1     — Gap-I design boundary (supervisor-prioritized, independent)
```

---

## Closed Surfaces

- No parser/compiler/VM/view implementation; no canon PROP; no grammar adoption
- No replacement of `call_contract`; no runtime dispatch primitive
- No module visibility/import changes; no package system
- `form_registry`/`form_resolver` remain lab-only (not canon)
- UI input forms (T4) are out of scope and must not share the term
