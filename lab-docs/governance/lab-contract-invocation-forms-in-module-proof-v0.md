# LAB-FORM-INVOCATION-P1: In-Module Contract Invocation Forms Proof

**Track:** contract-invocation-forms-in-module-conservative-elaboration-v0
**Route:** LAB PROOF / DESIGN + FIXTURE / NO CANON IMPLEMENTATION
**Date:** 2026-06-11
**Result:** PASS — 66/66 checks
**Verdict:** ACCEPT

---

## 1. Purpose

This proof establishes that Contract Invocation Forms are **conservative elaborations** over
the typed-ref substrate introduced by LANG-TYPED-CONTRACT-REF-PROP-P3 (`uses ContractName`,
canon, 67/67 PASS). It mechanises TH-1 (Conservativity), TH-4 (Hygiene), and TH-6
(Eliminability) from the TH-1..TH-6 acceptance frame (LAB-FORM-LAYER-THEORY-P1).

The proof is **proof-local only**: it builds a pure Ruby model of the form layer without
touching any canon compiler, typechecker, SemanticIR, VM, or runtime. All proofs run
against the canon `uses ContractName` substrate via the Ruby canon pipeline
(`igniter-lang/lib`).

---

## 2. Authority Surface

**Allowed in this card:**
- Proof runner (`verify_lab_form_invocation_p1.rb`) — reads SIR, does not modify it
- Proof-local model classes (`ProofLocalContractRef`, `FormDeclaration`, `FormRegistry`,
  `FormResolution`, `InvocationIntent`, `LoweringReceipt`, `ResugaringTrace`)
- Lab fixtures (`.ig` files, canon syntax only)
- This lab doc, card, portfolio update

**Closed — not opened by this proof:**
- Canon parser / typechecker / SemanticIR — no changes
- VM / runtime — no changes
- Public form syntax — not introduced
- Macro system — not touched
- `call_contract` behavior — unchanged
- `form_registry` / `form_resolver` (Rust lab) — remain lab-only divergence
- Package / visibility / capability / profile — unchanged

---

## 3. Predecessor Chain

| Card | Result | Key Finding |
|------|--------|-------------|
| LAB-TYPED-CONTRACT-REF-P1 | 58/58 PASS | SIR already carries all data for typed contract refs |
| LANG-TYPED-CONTRACT-REF-PROP-P3 | 67/67 PASS | `uses ContractName` live in canon Ruby pipeline |
| LAB-CONTRACT-FORMS-P2 | RECONCILED — SPLIT+KEEP | Rule C-1 typed-ref anchor; PROP-Forms orphan is NOT retired |

---

## 4. Proof-Local Model

The proof builds six classes that model the form layer without implementing it:

### 4.1 `ProofLocalContractRef`

Built from SIR `contract_refs` (Canon output of `uses ContractName`).

```
ProofLocalContractRef
  module_name       : String
  contract_name     : String
  resolution_status : :pending | :resolved | :failed
  resolved_signature: { modifier, input_count, input_names, output_names } | nil
  no_form           : Bool
  # Absent: execute, runtime_dispatch, capability_grant
```

A ref is `:pending` until `resolve!` is called with canon SIR data. An unresolved ref
blocks form declaration (Rule C-1).

### 4.2 `FormDeclaration`

Metadata-only binding: trigger → target. Validates C-1 and four structural rules on
construction.

```
FormDeclaration
  form_name             : String
  trigger_kind          : :infix | :prefix_call | :postfix_method | :method_call |
                          :block_method | :keyword_block | :multi_keyword
  trigger_token         : String
  target_contract       : String
  required_contract_ref : ProofLocalContractRef  ← C-1 anchor (must be resolved, not no_form)
  input_mapping         : [{ param:, target_input: }]
  output_mapping        : [{ form_output:, target_output: }]
  validation_errors     : [FormStructureError]
  # Absent: execute, runtime_dispatch, capability_grant, macro_expansion,
  #         import_authority, profile_binding
```

Validation rules enforced in `initialize`:
- **C-1**: `required_contract_ref` must be a resolved `ProofLocalContractRef` whose `no_form` is false → `E-FORM-NO-REF`
- **C-5**: `no_form` target → `E-FORM-NO-REF`
- **F-01**: block at position zero → `E-FORM-STRUCT`
- **F-02**: multiple BinderRefs → `E-FORM-BINDER`
- **F-03**: keyword literal shadows param name → `E-FORM-KW-SHADOW`
- **F-05**: alphabetic infix trigger → `E-FORM-KIND`

### 4.3 `FormRegistry`

Trigger-indexed store over valid `FormDeclaration` entries. Only `valid?` forms are registered.

```
FormRegistry
  entries       : [FormDeclaration]
  trigger_index : { trigger_token → [FormDeclaration] }
```

### 4.4 `FormResolution`

Result of type-directed trigger resolution.

```
FormResolution
  trigger_token      : String
  call_site_contract : String
  candidates         : [FormDeclaration]  ← all registered for this trigger
  refused_candidates : [RefusedCandidate]  ← filtered by arity mismatch
  status             : :resolved | :ambiguous | :unresolved | :primitive_pass_through
  resolved_to        : FormDeclaration | nil
  diagnostic_code    : "E-FORM-AMBIG" | "E-FORM-UNRESOLVED" | nil
```

`FormResolver.resolve` is fail-closed on ambiguity (`E-FORM-AMBIG`) and passes language
primitives through (`H2` list: `+`, `-`, `*`, etc.).

### 4.5 `InvocationIntent`

Lowering target. Not execution — declares the invocation shape with static evidence only.

```
InvocationIntent
  target_contract_ref  : ProofLocalContractRef
  argument_mapping     : [{ param:, target_input: }]
  lowered_from_form    : { form_name:, trigger_token:, trigger_kind: } | nil
  execution_dependency : false  (always)
  # to_h includes runtime_dispatch_required: false, vm_linker_required: false,
  #           stable_semanticir_node: false
  # Absent: execute, runtime_dispatch, capability_grant
```

### 4.6 `LoweringReceipt`

TH-1 Conservativity evidence: records fragment class and authority surface before/after
form declaration.

```
LoweringReceipt
  form_decl                : FormDeclaration
  invocation_intent        : InvocationIntent
  fragment_class_before    : String
  fragment_class_after     : String
  authority_surface_before : Array
  authority_surface_after  : Array
  conservative?            : Bool  (before == after for both fields)
```

### 4.7 `ResugaringTrace`

TH-5 debuggability evidence: carries both surface trigger and expanded contract (Pombrio–
Krishnamurthi resugaring).

```
ResugaringTrace
  surface_trigger          : String   ← ".validate"
  surface_kind             : Symbol   ← :postfix_method
  expanded_contract        : String   ← "Validator"
  expanded_contract_ref_id : String
  refused_candidates       : Array
  lowered_from             : Hash     ← from InvocationIntent.lowered_from_form
```

---

## 5. Fixtures

| File | Module | Contracts | Purpose |
|------|--------|-----------|---------|
| `basic_form.ig` | `Lab.FormInvocation.Basic` | Validator, Processor | Primary substrate; `uses Validator` |
| `effect_form.ig` | `Lab.FormInvocation.Effect` | Logger (effect), Analyzer | TH-1 E-02: effect target doesn't change declaring modifier |
| `chain_form.ig` | `Lab.FormInvocation.Chain` | Step1, Step2, Step3 | Chained typed-refs |
| `multi_form.ig` | `Lab.FormInvocation.Multi` | Alpha, Beta, Composer | Two-form Composer (E-06) |
| `no_ref_baseline.ig` | `Lab.FormInvocation.NoRef` | Validator, Consumer | H-01: Consumer has NO `uses Validator` |

All fixtures use canon `uses ContractName` syntax and compile clean through the Ruby
canon pipeline.

---

## 6. Proof Sections

### Section A — SUBSTRATE (8/8)

Verifies that `uses ContractName` produces the expected SIR and manifest output from the
canon Ruby pipeline.

| Check | Evidence |
|-------|----------|
| A-01..02 | `basic_form.ig` has no parse/type errors |
| A-03..05 | Processor has `contract_refs[0]` = `{contract_name: "Validator", resolution_status: "resolved"}` |
| A-06 | Resolved ref carries `modifier` field |
| A-07..08 | Manifest has `dependency_edges`; edge `Processor→Validator` has `execution_dependency: false` |

### Section B — FORM DECLARATION (7/7)

Verifies `FormDeclaration` construction and C-1 anchor validation.

| Check | Evidence |
|-------|----------|
| B-01 | `ProofLocalContractRef` built from SIR is `:resolved` |
| B-02 | `FormDeclaration` with resolved anchor is valid |
| B-03 | `required_contract_ref: nil` → `E-FORM-NO-REF` |
| B-04 | Unresolved ref (`:pending`) → `E-FORM-NO-REF` |
| B-05 | Valid `FormDeclaration` has no `execute`, `runtime_dispatch`, `capability_grant` |
| B-06..07 | `input_mapping` and `output_mapping` are carried verbatim |

### Section C — POSITIVE RESOLUTION (8/8)

Verifies that valid forms resolve correctly and deterministically.

| Check | Evidence |
|-------|----------|
| C-01 | Single candidate → `:resolved` status |
| C-02..04 | Resolved form has correct `target_contract`, `input_mapping`, `output_mapping` |
| C-05 | Identical result on repeated `FormResolver.resolve` call |
| C-06 | Postfix method form (`.validate`) resolves for 1-arg call |
| C-07 | Infix form (`\|>`) resolves for 2-arg call |
| C-08 | Arity mismatch produces `refused_candidates` with `reason: "arity_mismatch"` |

### Section D — LOWERING (7/7)

Verifies that a resolved form lowers to `InvocationIntent` — not to execution.

| Check | Evidence |
|-------|----------|
| D-01 | `lower_to_intent(resolution)` returns `InvocationIntent` |
| D-02 | `target_contract_ref` is `ProofLocalContractRef` for "Validator" |
| D-03 | `lowered_from_form` carries `{form_name:, trigger_token:, trigger_kind:}` |
| D-04 | `execution_dependency == false` |
| D-05 | `to_h` records `runtime_dispatch_required: false` |
| D-06 | No `execute`, `runtime_dispatch`, `capability_grant` on `InvocationIntent` |
| D-07 | `LoweringReceipt.conservative?` is true (fragment class unchanged) |

### Section E — TH-1 Conservativity (6/6)

**Claim:** Form declaration does not change the declaring contract's fragment class,
authority surface, `contract_refs`, or `dependency_edges`.

| Check | Evidence |
|-------|----------|
| E-01 | Processor `fragment_class == "core"` (from SIR; form has no effect) |
| E-02 | Analyzer `modifier == "pure"` even though it targets effect Logger |
| E-03 | `contract_refs` field is identical before/after proof-local registry.register |
| E-04 | Manifest `dependency_edges` identical before/after proof-local registration |
| E-05 | Explicit `InvocationIntent` and form-lowered intent have identical `execution_dependency` and `target_contract_ref` |
| E-06 | Two forms in Composer accumulate no `capability_grant` |

**Gap (known):** TH-1 effect-modifier propagation from callee to declaring contract is not
fully mechanised here — the `modifier` field on `ProofLocalContractRef` is carried
(D-03 `lowered_from_form`), but the rule "a pure contract that uses an effect contract
does not become effect" is only asserted, not derived from a rule in the canon typechecker.
This gap is scoped to TH-1 partial status (LAB-CONTRACT-FORMS-P2 §5).

### Section F — TH-4 Hygiene (7/7)

**Claim:** Structural rules F-01/02/03/05 (from PROP-Forms-Enhanced-v0 §E3) are
enforced at form declaration time.

| Check | Rule | Code |
|-------|------|------|
| F-01 | Block at position zero | `E-FORM-STRUCT` |
| F-02 | Multiple BinderRefs | `E-FORM-BINDER` |
| F-03 | Keyword shadows param | `E-FORM-KW-SHADOW` |
| F-04 | Alphabetic infix trigger | `E-FORM-KIND` |
| F-05 | Symbolic infix is accepted (positive boundary for F-04) | — |
| F-06 | Exactly one binder accepted (positive boundary for F-02) | — |
| F-07 | Block-local binder: `InvocationIntent.argument_mapping` is self-contained | — |

### Section G — TH-6 Eliminability (6/6)

**Claim:** For every form-lowered `InvocationIntent`, there exists an explicit
`InvocationIntent` with the same target contract, same argument mapping, and same
`execution_dependency`. Removing the form leaves the authority surface unchanged.

| Check | Evidence |
|-------|----------|
| G-01..03 | Explicit intent and form-lowered intent match on `target_contract_ref`, `argument_mapping`, `execution_dependency` |
| G-04 | Processor `fragment_class` identical before/after (no form in code) |
| G-05 | `InvocationIntent.to_h` has no `:secondary_target` — one form = one target |
| G-06 | Analyzer `fragment_class == "core"` (effect-target form doesn't smuggle class) |

### Section H — Negative Rules (7/7)

| Check | Rule | Code |
|-------|------|------|
| H-01 | No `uses Target` → `E-FORM-NO-REF` (C-1) | `required_contract_ref: nil` |
| H-02 | Pending/unresolved ref → `E-FORM-NO-REF` | `:pending` status |
| H-03 | Arity mismatch at resolution → `refused_candidates` | — |
| H-04 | Unknown trigger → `:unresolved` or `:primitive_pass_through` | — |
| H-05 | Ambiguous trigger (two same-arity candidates) → `E-FORM-AMBIG` | — |
| H-06 | `no_form` target → `E-FORM-NO-REF` (C-5) | — |
| H-07 | Self-referential `uses SelfRef` → `OOF-REF4` from canon typechecker | Via `compile_inline` |

### Section I — Authority Closed (6/6)

Verifies that neither `InvocationIntent` nor `FormDeclaration` expose authority methods.

| Check | Absent field/method |
|-------|---------------------|
| I-01 | `InvocationIntent#execute` |
| I-02 | `InvocationIntent#runtime_dispatch` / `:runtime_dispatch` key |
| I-03 | `InvocationIntent#capability_grant` / `:capability_grant` key |
| I-04 | `FormDeclaration#macro_expansion` / `#expand` |
| I-05 | `FormDeclaration#import_authority` / `#grant_import` |
| I-06 | `FormDeclaration#profile_binding` / `#bind_profile` |

### Section J — Route (4/4)

Structured recommendation receipt. Confirms that TH-1/4/6 mechanisation is present in
the proof artefacts.

| Check | Evidence |
|-------|----------|
| J-01 | C-1 enforced: all valid forms have resolved typed-ref anchor |
| J-02 | TH-1 mechanised: `LoweringReceipt.conservative? == true` |
| J-03 | TH-4 mechanised: four structural violations each produce a diagnostic |
| J-04 | TH-6 mechanised: explicit intent == form-lowered intent; `ResugaringTrace` has surface trigger + expanded contract + lowering metadata |

---

## 7. TH Status After This Proof

| TH | Name | Status | Evidence |
|----|------|--------|----------|
| TH-1 | Conservativity | **Partially proved** | Fragment class + authority surface unchanged (E-01..06); effect-modifier propagation gap (see §6.E note) |
| TH-2 | Coherence | **In-module proved** (prior: FTD-5/6); cross-module OPEN | Gates on import mainline + OOF-REF2 |
| TH-3 | Skeleton stability | **Confirmed by design** | Strategy B: fixed skeleton + open vocabulary |
| TH-4 | Hygiene | **Mechanised** (F-01/02/03/05) | Section F (7/7); MultiKeyword arm-capture gap remains |
| TH-5 | Resugaring | **Demonstrated** | `ResugaringTrace` in J-04; strongest TH |
| TH-6 | Eliminability | **Mechanised** | Section G (6/6); explicit == lowered |

---

## 8. Rules Enforced in This Proof

| Rule | Source | Enforcement Point |
|------|--------|-------------------|
| C-1 | LAB-CONTRACT-FORMS-P2 | `FormDeclaration` init; `E-FORM-NO-REF` |
| C-5 | LAB-CONTRACT-FORMS-P2 | `FormDeclaration` init when `no_form: true`; `E-FORM-NO-REF` |
| C-6 | PROP-Forms-Enhanced-v0 | Sections E-01/E-02/G-06: fragment class unchanged |
| F-01 | PROP-Forms-Enhanced-v0 §E3 | `E-FORM-STRUCT` |
| F-02 | PROP-Forms-Enhanced-v0 §E3 | `E-FORM-BINDER` |
| F-03 | PROP-Forms-Enhanced-v0 §E3 | `E-FORM-KW-SHADOW` |
| F-05 | PROP-Forms-Enhanced-v0 §E3 | `E-FORM-KIND` (infix alphabetic) |

---

## 9. Open Gaps

1. **TH-2 Cross-module coherence** — gates on import mainline (PROP-IMPORT-RESOLUTION)
   and OOF-REF2 cross-module typed-ref. Deferred to LAB-FORM-VOCABULARY-P1.

2. **TH-3 Skeleton golden-test mechanisation** — Strategy B skeleton stability confirmed
   by design (FormKind ×7, fixed grammar productions). No golden-test fixture yet.
   Low risk given Strategy B precedent.

3. **TH-1 Effect-modifier propagation** — the rule "a pure contract using an effect
   contract stays pure" is enforced by the canon typechecker (not by the proof-local
   model). Asserted in E-02 by reading SIR; no derived proof from a rule.

4. **MultiKeyword arm-capture** — TH-4 partial. MultiKeyword forms are System/Stdlib-gated
   in v0; arm-capture hygiene deferred to vocabulary track.

---

## 10. Recommendation

**ACCEPT.** The in-module proof demonstrates that Contract Invocation Forms are
conservative elaborations over the typed-ref substrate. The proof-local model correctly
enforces C-1 (typed-ref anchor), four structural rules (F-01/02/03/05), fail-closed
ambiguity (E-FORM-AMBIG), and the authority-closed invariant.

**Next route:** LAB-FORM-VOCABULARY-P1 — cross-module form coherence proof (after
OOF-REF2 integration + import mainline).

---

## 11. Artefacts

| Artefact | Path |
|----------|------|
| Proof runner | `igniter-lab/igniter-view-engine/proofs/verify_lab_form_invocation_p1.rb` |
| Fixture: basic | `igniter-lab/igniter-view-engine/fixtures/form_invocation/basic_form.ig` |
| Fixture: effect | `igniter-lab/igniter-view-engine/fixtures/form_invocation/effect_form.ig` |
| Fixture: chain | `igniter-lab/igniter-view-engine/fixtures/form_invocation/chain_form.ig` |
| Fixture: multi | `igniter-lab/igniter-view-engine/fixtures/form_invocation/multi_form.ig` |
| Fixture: no_ref | `igniter-lab/igniter-view-engine/fixtures/form_invocation/no_ref_baseline.ig` |
| Lab doc (this) | `igniter-lab/lab-docs/governance/lab-contract-invocation-forms-in-module-proof-v0.md` |
| Card | `igniter-lab/.agents/work/cards/governance/LAB-FORM-INVOCATION-P1.md` |
| Predecessor (reconciliation) | `igniter-lab/lab-docs/governance/lab-contract-forms-lineage-reconciliation-v0.md` |
| Predecessor (theory) | `igniter-lab/lab-docs/governance/lab-form-layer-theory-and-grammar-stratification-v0.md` |
