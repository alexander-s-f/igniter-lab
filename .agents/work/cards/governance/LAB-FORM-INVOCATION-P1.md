# LAB-FORM-INVOCATION-P1 — In-Module Contract Invocation Forms Proof

**Track:** contract-invocation-forms-in-module-conservative-elaboration-v0
**Route:** LAB PROOF / DESIGN + FIXTURE / NO CANON IMPLEMENTATION
**Status:** CLOSED — ACCEPT
**Gate result:** PROVED — 66/66 PASS
**Date:** 2026-06-11

---

## Context

LANG-TYPED-CONTRACT-REF-PROP-P3 (67/67 PASS) established `uses ContractName` as canon
in the Ruby pipeline. LAB-CONTRACT-FORMS-P2 (RECONCILED — SPLIT+KEEP) produced Rule C-1:
a form targeting T requires `uses T` in the declaring contract's `contract_refs`.

This card delivers the in-module proof that Contract Invocation Forms are conservative
elaborations over that substrate.

## Goal

Build a proof-local in-module Contract Invocation Forms model demonstrating conservative
elaboration over the typed-ref substrate. Mechanise TH-1 (Conservativity), TH-4
(Hygiene), TH-6 (Eliminability). Minimum 50 checks.

---

## Proof Summary

**Result: PASS (66/66)**

| Section | Checks | Subject |
|---------|--------|---------|
| A — SUBSTRATE | 8/8 | `uses ContractName` → SIR `contract_refs`; manifest `dependency_edges` |
| B — FORM DECL | 7/7 | `FormDeclaration` construction; C-1 anchor validation |
| C — POSITIVE | 8/8 | Single-candidate resolve; deterministic; infix + method triggers |
| D — LOWERING | 7/7 | Resolved form → `InvocationIntent`; not execution |
| E — TH-1 | 6/6 | Fragment class + authority surface unchanged |
| F — TH-4 | 7/7 | F-01/02/03/05 structural rules enforced |
| G — TH-6 | 6/6 | Explicit intent == form-lowered intent |
| H — NEGATIVE | 7/7 | `E-FORM-NO-REF`, `E-FORM-AMBIG`, arity, `no_form`, self-ref |
| I — AUTHORITY | 6/6 | No execute/dispatch/capability/macro/import/profile |
| J — ROUTE | 4/4 | TH-1/4/6 mechanisation confirmed |

---

## Proof-Local Model

Six classes built in pure Ruby (no canon implementation):

| Class | Purpose |
|-------|---------|
| `ProofLocalContractRef` | Typed ref from SIR `contract_refs`; absent: execute/dispatch/capability |
| `FormDeclaration` | Trigger→target metadata binding; validates C-1 + F-01/02/03/05 |
| `FormRegistry` | Trigger-indexed store; only valid forms registered |
| `FormResolution` | Type-directed resolution; fail-closed on ambiguity |
| `InvocationIntent` | Lowering target; `execution_dependency: false` always |
| `LoweringReceipt` | TH-1 evidence: `conservative? == true` |
| `ResugaringTrace` | TH-5 evidence: surface trigger + expanded contract + metadata |

---

## Rules Enforced

| Rule | Code | Enforcement |
|------|------|-------------|
| C-1 | `E-FORM-NO-REF` | `FormDeclaration` requires resolved `uses T` ref |
| C-5 | `E-FORM-NO-REF` | `no_form` target blocked in `FormDeclaration` |
| C-6 | — | Fragment class of declaring contract unchanged (E-01/02, G-06) |
| F-01 | `E-FORM-STRUCT` | Block at position zero |
| F-02 | `E-FORM-BINDER` | Multiple BinderRefs |
| F-03 | `E-FORM-KW-SHADOW` | Keyword shadows param name |
| F-05 | `E-FORM-KIND` | Alphabetic infix trigger |

---

## TH Status After This Proof

| TH | Status | Change |
|----|--------|--------|
| TH-1 Conservativity | **Partially proved** (gap: effect-modifier propagation) | Mechanised: fragment class + authority |
| TH-2 Coherence | In-module proved (FTD-5/6); cross-module OPEN | No change |
| TH-3 Skeleton stability | Confirmed by design | No change |
| TH-4 Hygiene | **Mechanised** (F-01/02/03/05; MultiKeyword arm-capture deferred) | New: section F |
| TH-5 Resugaring | **Demonstrated** | New: `ResugaringTrace` in J-04 |
| TH-6 Eliminability | **Mechanised** (explicit == lowered) | New: section G |

---

## Key Findings

1. **Conservativity receipt produced:** `LoweringReceipt.conservative? == true` —
   fragment class and authority surface are identical with and without form declaration.

2. **TH-6 mechanised:** For every form `F` targeting contract `T`, there exists an
   explicit `InvocationIntent(target: T, args: F.input_mapping)` with identical
   `execution_dependency: false`. The form is eliminable.

3. **TH-5 demonstrated:** `ResugaringTrace` carries both ends — surface trigger `.validate`
   and expanded contract `Validator`. The debugger can recover the surface expression from
   the lowered intent.

4. **Authority closed:** Neither `InvocationIntent` nor `FormDeclaration` expose
   `execute`, `runtime_dispatch`, `capability_grant`, `macro_expansion`,
   `import_authority`, or `profile_binding`. Confirmed by I-01..06.

5. **C-1 enforced:** Every valid form in the proof has a resolved `ProofLocalContractRef`
   built from canon SIR `contract_refs`. Missing/unresolved/no_form targets → `E-FORM-NO-REF`.

---

## Open Gaps

1. **TH-1 effect-modifier propagation** — Analyzer (pure) targeting Logger (effect)
   stays pure (asserted via SIR read in E-02); not derived from a rule. Low risk — canon
   typechecker enforces this.

2. **TH-2 cross-module coherence** — gates on import mainline and OOF-REF2.

3. **TH-3 skeleton golden-test** — Strategy B stability confirmed by design; no fixture.

4. **MultiKeyword arm-capture** — deferred to vocabulary track.

---

## Closed

The following remain closed by this proof (same surface as predecessors):

- Canon parser, typechecker, SemanticIR — no changes
- VM / runtime — no changes
- Public form syntax — not introduced
- Macro system — not touched
- `call_contract` behavior — unchanged
- `form_registry` / `form_resolver` (Rust lab) — remain lab-only divergence
- Cross-module form vocabulary — deferred
- Package / visibility / capability / profile — unchanged

---

## Next Routes

| Track | Card | Gate |
|-------|------|------|
| T2 cross-module coherence | LAB-FORM-VOCABULARY-P1 | OOF-REF2 + import mainline |
| T1 Gap-I Form Constructor | LAB-FORM-CONSTRUCTOR-P1 | Independent clock |

---

## Artefacts

| Artefact | Path |
|----------|------|
| Proof runner | `igniter-lab/igniter-view-engine/proofs/verify_lab_form_invocation_p1.rb` |
| Fixtures (5) | `igniter-lab/igniter-view-engine/fixtures/form_invocation/` |
| Lab doc | `igniter-lab/lab-docs/governance/lab-contract-invocation-forms-in-module-proof-v0.md` |
| Predecessor (reconciliation) | `igniter-lab/lab-docs/governance/lab-contract-forms-lineage-reconciliation-v0.md` |
| Predecessor (theory) | `igniter-lab/lab-docs/governance/lab-form-layer-theory-and-grammar-stratification-v0.md` |
