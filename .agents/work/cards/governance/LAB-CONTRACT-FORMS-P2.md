# Card: LAB-CONTRACT-FORMS-P2

**Category:** governance / lang / reconciliation
**Track:** contract-invocation-forms-lineage-reconciliation-with-typed-ref-substrate-v0
**Status:** CLOSED — SPLIT + KEEP
**Gate result:** RECONCILED
**Date closed:** 2026-06-11
**Route:** LAB RECONCILIATION / DESIGN + EVIDENCE / NO IMPLEMENTATION
**Predecessors:**
- LAB-CONTRACT-FORMS-P1 (SPLIT verdict; terminology §3 normative)
- LAB-FORM-LAYER-THEORY-P1 (TH-1..TH-6 acceptance frame; OPEN)
- LAB-TYPED-CONTRACT-REF-P1 (58/58 PASS; ACCEPT)
- LANG-TYPED-CONTRACT-REF-PROP-P3 (67/67 PASS; PROVED — `uses ContractName` canon)

---

## Goal

Reconcile the orphaned Contract Invocation Forms lineage (`form_registry.rs` /
`form_resolver.rs` / PROP-Forms-Enhanced-v0) against the now-canon typed-ref
substrate and the TH-1..TH-6 acceptance frame.

---

## Headline

**SPLIT + KEEP. Contract Invocation Forms lineage is viable with the typed-ref
anchor. Two tracks named. Coherence rules proposed. TH gaps scoped.**

The orphaned implementation is not a museum piece. It is a complete lab
implementation (spec + two passing proofs) whose missing piece — a source-visible
lowering substrate — is now canon (`uses ContractName`, P3). The decision is KEEP,
conditional on a proof-local design card that closes TH-1/4/6 in-module.

---

## Archaeology Verdict

| Artifact class | Count | Disposition |
|---|---|---|
| Contract Invocation Form (T2) — spec | 2 (PROP-Forms-v0 + Enhanced-v0) | KEEP as design basis |
| Contract Invocation Form (T2) — implementation | 2 (form_registry.rs + form_resolver.rs) | KEEP as proof substrate |
| Contract Invocation Form (T2) — proofs | 2 (type-directed dispatch + SemanticIR lowering) | KEEP as evidence |
| Gap-I Form Constructor (T1) | Covenant P27/P28 (doctrine-only) | KEEP — independent clock |
| View/component forms (T3) | View DSL conclusion (VDSL-9) | Not a track — T2 consumer |
| Typed contract reference (T6) | `uses ContractName` (P3 canon) | SUBSTRATE — live in canon |
| UI/HTML input forms (T4) | Naming collision only | Out of scope |

---

## TH-1..TH-6 Status

| Theorem | Status | Key gap |
|---|---|---|
| TH-1 Conservativity | Partially proved (lab lowering PASS) | Effect modifier propagation from callee to declaring contract not covered |
| TH-2 Coherence | In-module proved (FTD-5/6); cross-module OPEN | Gates on import-resolution mainline |
| TH-3 Skeleton stability | Confirmed by design (Strategy B) | Needs golden-test mechanization |
| TH-4 Hygiene | Partially addressed (F-02/03) | MultiKeyword arm capture; cross-FormKind coverage |
| TH-5 Resugaring | Demonstrated (ResolvedExpr + lowered_from_form) | Strongest TH; needs negative-case span test |
| TH-6 Eliminability | Closed by design claims | Negative fixture matrix needed |

---

## Typed-Ref Lowering Target (new this card)

The key design addition: **forms must anchor to a `uses` declaration.**

```
Contract C:
  uses TargetContract          ← P3 canon; makes DAG edge source-visible
  form (x) "trigger" (y)      ← form declaration; targets TargetContract implicitly
```

Rule C-1: a form targeting T requires `uses T` in C's `contract_refs`. Forms
that resolve to an undeclared target → E-FORM-NO-REF.

This makes every form's target edge double-visible:
- `uses T` → source-visible dependency (enters `contract_refs`, manifest `dependency_edges`)
- `form ... trigger ...` → call-shape declaration (enters form table)

The two declarations are independent but must be consistent.

---

## Coherence Rules Proposed

| Rule | Statement |
|---|---|
| C-1 | Form declaration requires `uses T` in declaring contract |
| C-2 | Form for T may be declared only by T's module or by a module with `uses T` |
| C-3 | Ambiguity is diagnostic (E-FORM-AMBIG), not first-wins; cross-module same rule |
| C-4 | Import order must not affect form resolution results |
| C-5 | `no_form` on T propagates: `uses T` + form targeting T → E-FORM-NO-REF |
| C-6 | Declaring contract's fragment class unchanged by form declaration (metadata precedent) |
| C-7 | MultiKeyword (control-form) restricted to System/Stdlib trust level in v0 |

---

## Decision

**SPLIT + KEEP**

| Track | Decision | Next card |
|---|---|---|
| Contract Invocation Forms (T2) | **KEEP** | LAB-FORM-INVOCATION-P1 |
| Gap-I Form Constructor (T1) | KEEP (independent clock) | LAB-FORM-CONSTRUCTOR-P1 |
| View/component forms (T3) | Not a track; consumes T2 | — |

---

## Closed Surfaces

- No parser implementation
- No typechecker implementation
- No SemanticIR implementation
- No VM / runtime implementation
- No new form syntax
- No macro system
- No public API
- No call_contract changes
- No package / visibility changes
- No capability / profile authority
- No Rust lab refactor

---

## Next Route

```
LAB-FORM-INVOCATION-P1           — Contract Invocation Forms in-module proof-local
                                   design card. Must mechanize TH-1/4/6; implement
                                   Rules C-1/5/6/7 in proof-local fixtures only.
                                   No canon grammar. Route: LAB / PROOF-LOCAL DESIGN.
                                   Gate: supervisor authorization (no mainline
                                   dependency).

LAB-FORM-VOCABULARY-P1           — Cross-module coherence + vocabulary ownership.
                                   Must mechanize TH-2/3; implement Rules C-2/3/4.
                                   Route: LAB / PROOF-LOCAL DESIGN.
                                   Gate: LAB-FORM-INVOCATION-P1 + OOF-REF2 (cross-
                                   module typed refs) + import-resolution mainline.

LAB-FORM-CONSTRUCTOR-P1          — Gap-I value constructors; independent clock.
                                   Route: LAB / DESIGN BOUNDARY.
                                   Gate: Gap-I supervisor prioritization.
```

---

## Deliverables

| Artifact | Path | Status |
|---|---|---|
| Reconciliation doc | `lab-docs/governance/lab-contract-forms-lineage-reconciliation-v0.md` | ✅ DONE |
| This card | `.agents/work/cards/governance/LAB-CONTRACT-FORMS-P2.md` | ✅ DONE |
| Portfolio update | `.agents/portfolio-index.md` | ✅ DONE |
