# Lab: Contract Forms Lineage Reconciliation v0

**Track:** contract-invocation-forms-lineage-reconciliation-with-typed-ref-substrate-v0
**Card:** LAB-CONTRACT-FORMS-P2
**Category:** governance / lang
**Date:** 2026-06-11
**Route:** LAB RECONCILIATION / DESIGN + EVIDENCE / NO IMPLEMENTATION
**Status:** CLOSED — lineage reconciled; decision SPLIT+KEEP; next routes named
**Predecessors:**
- LAB-CONTRACT-FORMS-P1 (archaeology + SPLIT verdict; terminology table normative)
- LAB-FORM-LAYER-THEORY-P1 (TH-1..TH-6 acceptance frame; OPEN — theory coherent)
- LAB-TYPED-CONTRACT-REF-P1 (58/58 PASS; ACCEPT — typed-ref substrate validated)
- LANG-TYPED-CONTRACT-REF-PROP-P3 (67/67 PASS; PROVED — `uses ContractName` live in canon)

---

## 1. Authority Boundary

Lab reconciliation only. No implementation authorized.

- No parser, typechecker, SemanticIR, VM, or runtime implementation.
- No canon PROP authored. No grammar adoption.
- No public API, no new form syntax, no call_contract changes.
- No module visibility or import changes.
- No capability or profile authority.
- No Rust lab refactor.
- `form_registry.rs` / `form_resolver.rs` remain lab-only divergence.

This document reconciles the orphaned Contract Invocation Forms lineage against
the typed-ref substrate that is now canon, and against the TH-1..TH-6 acceptance
frame. It makes a governance decision and names next routes.

---

## 2. Archaeology Inventory

Every known form-related artifact, classified.

### 2.1 Specification artifacts

| Artifact | Term / Shape | Category | Status |
|---|---|---|---|
| `igniter-lab/lab-docs/core/PROP-Forms-Enhanced-v0.md` | Contract Invocation Forms; FormKind × 7; F-01..F-06; `no_form`; FormShape inheritance; MultiKeywordForm; AccumulatorRef; `form_resolution_trace`; `form_table.json` | **Contract Invocation Form (T2)** | lab-only (pressure doc; never entered canon governance) |
| `igniter-lab/lab-docs/core/PROP-Forms-v0` | Base Contract Invocation Forms spec | **Contract Invocation Form (T2)** | Agent-C archive; superseded by Enhanced-v0; never in mainline proposals/ |
| `igniter-lang/docs/language-covenant.md:P27-P28` | `form constructors`; "no unnamed semantic structure" | **Gap-I Form Constructor (T1)** | canon (doctrine-only; no parser keyword; no implementation) |
| `igniter-lang/docs/concepts/canonical-semantic-model.md` (Gap-I row) | `form NAME -> TypeTarget` | **Gap-I Form Constructor (T1)** | spec_candidate; all pipeline stages 🔴 |
| `igniter-lang/docs/spec/ch2-appendix-ebnf-grammar.md:51-52` | `ContractShapeDecl` only; no `form` keyword | — | `form` is NOT a canon parser keyword |
| `igniter-lang/.agents/work/proposals/PROP-002-contract-composition-algebra-v0.md` | `>>`, `\|\|`, `branch`, `over`, `embed`; traced symmetric monoidal category | **Composition algebra** | authored, pending proof; rejects dynamic/recursive composition explicitly |
| `igniter-lab/lab-docs/governance/lab-contract-invocation-forms-formalization-v0.md` | LAB-CONTRACT-FORMS-P1 archaeology; 8 terminology meanings disambiguated; SPLIT verdict | **governance index** | CLOSED; terminology §3 normative |
| `igniter-lab/lab-docs/governance/lab-form-layer-theory-and-grammar-stratification-v0.md` | TH-1..TH-6; stratification theory; fixed-skeleton/open-vocabulary; coherence problem | **theory** | CLOSED (OPEN verdict — theory coherent) |

### 2.2 Rust-lab implementation artifacts

| Artifact | Shape | Category | Status |
|---|---|---|---|
| `igniter-lab/igniter-compiler/src/form_registry.rs` | `FormEntry { id, contract, module, trigger, kind, elements, priority, associativity, trust_level, inherited_from }`; `FormRegistry`; trigger index; no_form set; F-01/02/05 structural checks; contract_shape inheritance | **Contract Invocation Form (T2) — Phase 2 registration** | lab-only (implemented, working) |
| `igniter-lab/igniter-compiler/src/form_resolver.rs` | `FormResolver` walks TypedProgram AST; resolves BinaryOp/UnaryOp/FieldAccess → `ResolvedExpr`; `TraceEvent` with candidates/refused/filter_status; `AmbiguityEvent`; E-FORM-AMBIG fail-closed; H2 language-primitive pass-through | **Contract Invocation Form (T2) — Phase 3 resolution** | lab-only (implemented, working) |
| `igniter-lab/igniter-compiler/out/contract_invocation_forms_type_directed_dispatch_proof/` | FTD-1..7 all PASS; type-filtered candidates; refused_candidates with reason/expected/actual; E-FORM-UNRESOLVED; ambiguity fail-closed | **T2 type-directed resolution proof** | lab-local PASS |
| `igniter-lab/igniter-compiler/out/contract_invocation_forms_semanticir_lowering_proof/` | Form lowers to `call` + `lowered_from_form` metadata; `runtime_dispatch_required: false`; `vm_linker_required: false`; `stable_semanticir_node: false`; ambiguity/unresolved/no_form → oof | **T2 SemanticIR lowering proof** | lab-local PASS |

### 2.3 Canon pipeline (post-P3)

| Artifact | Shape | Category | Status |
|---|---|---|---|
| `igniter-lang/lib/igniter_lang/parser.rb` | `parse_uses_decl`: 1-token lookahead → `uses_contract` node with `target` field; dotted names → OOF-REF2 | **Typed contract reference (T6)** | CANON (PROVED P3) |
| `igniter-lang/lib/igniter_lang/classifier.rb` | `when "uses_contract"` → `"metadata"` fragment; `contract_ref_declarations` array; `contract_fragment_for` excludes metadata | **Typed contract reference (T6)** | CANON (PROVED P3) |
| `igniter-lang/lib/igniter_lang/typechecker.rb` | `build_same_module_registry`; `typecheck_uses_contract`; OOF-REF1/2/4 | **Typed contract reference (T6)** | CANON (PROVED P3) |
| `igniter-lang/lib/igniter_lang/semanticir_emitter.rb` | `contract_refs` per-contract field (enters `contract_ref` content hash); `typed_nodes` nil guard | **Typed contract reference (T6)** | CANON (PROVED P3) |
| `igniter-lang/lib/igniter_lang/assembler.rb` | `dependency_edges` flat manifest array: `{from, to, kind: "typed_contract_ref", execution_dependency: false, resolution}` | **Typed contract reference (T6)** | CANON (PROVED P3) |

### 2.4 View and other domain artifacts

| Artifact | Conclusion | Category | Status |
|---|---|---|---|
| `igniter-lab/lab-docs/view/lab-experimental-igniter-html-view-dsl-arbre-like-boundary-v0.md` | `form:todo_card(item)` = "invocation alias resolves to `ContractInvocation`. It should not be a runtime primitive." VDSL-9: `forms_assisted: true` = DX-candidate metadata only | **T3 — view/component form (consumption of T2; not a new semantic)** | CLOSED (VDSL-9 PASS); conclusion: T2 consumed by view, not defined by it |
| `igniter-gov/portfolio/governance/2026-06-10-current-language-surface-map-v0.md` | `form_registry`/`form_resolver` = "Not canon pipeline authority" | **governance boundary** | explicit lab-only ruling; unchanged |
| UI/HTML input forms | user-facing HTML input elements | **T4 — naming collision only** | unrelated; no shared semantics |
| `igniter-lab/igniter-compiler/src/monomorphizer.rs` | Generic specialization `Add[T]`→`Add[Integer]` — PRECONDITION for form registration (forms attach to concrete types) | **prerequisite; not itself a form concept** | lab-only; incidental naming |

### 2.5 Orphaned PROP-Forms lineage — classification

The orphaned implementation (`form_registry.rs` + `form_resolver.rs`) is:
- A **complete lab implementation of Contract Invocation Forms (T2)**.
- Backed by a **complete written spec** (PROP-Forms-v0 archived + PROP-Forms-Enhanced-v0).
- Backed by **two passing proofs** (type-directed dispatch + SemanticIR lowering).
- **Never routed through canon governance**. No PROP number. Never in `igniter-lang/.agents/work/proposals/`.
- Marked lab-only divergence by the 2026-06-10 gov surface map.

This is the governance failure mode LAB-CONTRACT-FORMS-P1 named: the idea was
*built*, not just *discovered and lost*. The reconciliation task is to decide
whether this built thing becomes a substrate for the next proof card, or is
retired.

---

## 3. Current Substrate — Post-LANG-TYPED-CONTRACT-REF-PROP-P3

After P3, the canon Ruby pipeline has:

**`uses ContractName`** (parser → classifier → typechecker → SemanticIR → assembler):
- Parses as `{ kind: "uses_contract", target: "ContractName" }` — 1-token lookahead.
- Classified as `"metadata"` fragment — transparent to `contract_fragment_for` (no fragment class change on declaring contract).
- Typechecked against same-module registry: same-module targets resolve with `resolved_ref { modifier, input_count, input_names, output_names }`. Unknown targets → OOF-REF1. Dotted/cross-module → OOF-REF2. Self → OOF-REF4.
- NOT entered in `symbol_types` — not a local typed binding.
- Emitted to SemanticIR as `contract_refs` per-contract field: `{ contract_name, resolution_status, [modifier, input_count, input_names, output_names] }`. Enters `contract_ref` content hash (structural identity).
- Emitted to manifest as `dependency_edges`: `{ from, to, kind: "typed_contract_ref", execution_dependency: false, resolution }`. Enters `artifact_hash`.

**What this means for Contract Invocation Forms:**

1. The DAG edge that a form implicitly creates is now *declarable* in source. A form that resolves trigger `+` to contract `Add` can anchor to an explicit `uses Add` declaration — the edge is source-visible, statically inspectable, enters the content hash, and appears in the manifest.

2. The `resolved_ref` signature (modifier, input_count, input_names) is exactly the information needed to typecheck form arity and modifier compatibility at the `uses` declaration site — *before* any call site is analyzed.

3. The same-module restriction (v0) mirrors the form scope reality: in-module forms are the natural first step. Cross-module form coherence gates on the same thing cross-module typed refs gate on: the import module table.

4. `execution_dependency: false` in `dependency_edges` correctly represents that a `uses` declaration does not invoke. When a form resolves and lowers to an explicit call, that call site adds the execution-time dependency through the existing `call_contract` mechanism — the two layers compose without confusion.

**Open limits that constrain forms:**
- Same-module only (v0). Cross-module form declarations require cross-module typed refs (OOF-REF2 currently blocks all dotted targets).
- No canon form syntax exists yet. `form` is not a parser keyword.
- No SemanticIR `ContractInvocation` node kind in the Ruby canon pipeline.
- No form-resolution pass in the Ruby canon pipeline.

---

## 4. TH-1..TH-6 Evaluation

Evaluated against the orphaned Contract Invocation Forms lineage.

### TH-1 — Conservativity

**Claim:** Every program using forms elaborates to a kernel program with identical SemanticIR semantics, identical fragment classification, identical effect surface, and identical authority requirements.

**Assessment: PARTIALLY PROVED, condition-bound.**

The lab SemanticIR lowering proof (PASS) demonstrates the path:
- Resolved form → `call` node with `lowered_from_form` metadata.
- `runtime_dispatch_required: false`, `vm_linker_required: false`.
- Fragment class of the *calling* contract is unchanged (the lowering proof confirms the emitter produces the same fragment given the same body nodes).
- Ambiguous/unresolved/no_form forms do NOT produce accepted output (oof) — fail-closed.

What the lab proof does NOT yet demonstrate:
- Fragment classification of the *declaring* contract (the contract with the `form` declaration) is unchanged relative to the form body alone. This mirrors what P3 proved for `uses ContractName`: the "metadata" fragment design keeps declaring contracts clean. A form declaration should follow the same pattern.
- Conservativity over effect surface: a form binding an `effect` contract is currently unblocked in the spec (PROP-Forms-Enhanced §E2 only adds `no_form` for opt-out; it does not say a `pure` contract's fragment changes when its form resolves to an `effect` target). This gap must be explicitly closed.

**Gate for proof card:** demonstrate that a contract declaring `form (x) "op" (y) uses EffectTarget` does not acquire `effect` modifier; and that the `no_form` on effect contracts (§E2) is enforced at the declaring-contract level, not just at the call-site level.

### TH-2 — Order Independence / Coherence

**Claim:** Permuted declaration and import order produces bit-identical resolution; engineered overlap fails closed with both candidates named.

**Assessment: IN-MODULE PROVED, CROSS-MODULE OPEN.**

The lab type-directed dispatch proof (FTD-5/6 PASS) demonstrates:
- Within a module, declaration order does NOT win ambiguous resolution — E-FORM-AMBIG fires for equal surviving candidates regardless of declaration order.
- `candidate_refusal` filters by type facts before ambiguity is checked — type-directed, not declaration-order.

Cross-module coherence is unproven. The `FormRegistry.build_from_program` method works from a single `SourceFile` (one module). Multi-module form registration is not implemented. The coherence problem (two modules declaring forms over overlapping triggers and types) has no enforcement mechanism in the lab.

**Gate for proof card:** mechanize TH-2 with ≥3 modules: (a) two modules declare non-overlapping forms → order-independent; (b) two modules declare overlapping forms → compile-time diagnostic (not first-wins); (c) one module declares a form, another imports and uses it → resolution identical regardless of import order.

**Dependency:** cross-module typed refs (OOF-REF2 gate). TH-2 cross-module proof gates on import-resolution mainline.

### TH-3 — Skeleton Stability

**Claim:** Adding N new forms does not change the parse of any existing program.

**Assessment: CONFIRMED by design, not formally proved.**

The lab resolver is strictly post-parse (it fires after `TypeChecker`, not during lexing/parsing). PROP-Forms-Enhanced §E7 makes the invariant explicit: "the parser MUST NOT attempt to resolve forms — it produces generic operator nodes; form_resolver is CORRECT and type-informed." The `binary_prec` table in the Rust parser provides precedence for parse-time grouping only; form resolution priorities come from the Form Registry after parse.

The FormKind × 7 model occupies pre-allocated syntactic slots:
- `BinaryOp`, `UnaryOp`, `FieldAccess` → already in the grammar as generic productions.
- Forms populate the *meaning* of a trigger inside those productions, not the productions themselves.
- A new form declaration cannot introduce a new production rule — it can only register a new trigger string in an existing slot.

This is Strategy B (fixed skeleton, open vocabulary) as described in LAB-FORM-LAYER-THEORY-P1 §4.

**Gate for proof card:** parse-tree golden equality test over a full fixture corpus before and after registering M new forms. The lab skeleton already enables this; the test just needs to be mechanized.

### TH-4 — Hygiene

**Claim:** Form parameter names cannot capture or shadow call-site bindings.

**Assessment: PARTIALLY ADDRESSED, incomplete.**

Addressed in the lab spec:
- F-02: at most one BinderRef per form — prevents compound capture through multiple binders.
- F-03: KeywordBlockForm literal token must not match a parameter name — prevents the specific case of keyword literals shadowing inputs.
- `AccumulatorRef` scoping is block-local by spec.
- `BinderRef [x]` is visible only inside the block — described in PROP-Forms-v0.

Not demonstrated:
- The resolver currently substitutes form arguments by position (`candidate_refusal` operates on `input_types` count). There is no parameter-name binding hygiene check in `form_resolver.rs` — if a form's parameter name happens to collide with a call-site binding name, the lab does not detect it.
- MultiKeyword arm bindings (PROP-Forms-Enhanced §E5 ArmRef) have no explicit hygiene rule. In `match value { [x] => ... }`, `x` binds inside the arm — but the resolver does not emit arm-binding hygiene evidence.

**Gate for proof card:** fixture matrix across all 7 FormKinds where form-parameter names are engineered to collide with call-site binding names; assert that no capture occurs.

### TH-5 — Resugaring / Debuggability

**Claim:** For every kernel-level diagnostic in a formed region, tooling can present both the surface span and the expanded invocation.

**Assessment: DEMONSTRATED — strongest TH.**

The lab already carries both ends of the resugaring map:
- `ResolvedExpr { original_kind, trigger, resolved_to, form_id, typed_operands, lowering_target }` — the form end.
- SemanticIR lowering proof adds `lowered_from_form { authority, trigger, runtime_dispatch_required, vm_linker_required, stable_semanticir_node }` on the lowered call node — the kernel end.
- `TraceEvent { kind, trigger, expr_kind, candidates, resolved_to, refused_candidates, filter_status }` — full resolution audit trail.
- `form_resolution_trace` (§E4 of PROP-Forms-Enhanced) spec exists; the lab already emits trace events.

The `Pombrio–Krishnamurthi resugaring` property (LAB-FORM-LAYER-THEORY-P1) is structurally satisfied: both surface trigger and expanded call node carry identifying fields, and they point at each other through `form_id` / `lowered_from_form.trigger`.

**Gate for proof card:** for each TraceEvent diagnostic (E-FORM-AMBIG, E-FORM-UNRESOLVED, E-FORM-NOFM-MATCH) confirm that (a) the surface trigger span is included, and (b) the refused/blocked candidates are named with their reasons. This is already true in the lab for positive cases; the negative-case span requirement needs a fixture confirming diagnostics carry both form and kernel information.

### TH-6 — Eliminability

**Claim:** Attempts to express a non-eliminable feature as a form (new effect, recursion, dynamic dispatch) must be structurally impossible or fail closed.

**Assessment: CLOSED BY DESIGN CLAIMS, NOT YET NEGATIVELY PROVED.**

The spec and implementation block several non-eliminable paths:
- `no_form` on effect/privileged/irreversible contracts (§E2): prevents a form from routing to authority-bearing contracts. Implemented in `form_registry.rs` (`no_form_contracts` HashSet) and `form_resolver.rs` (E-FORM-NOFM-MATCH, P7 block).
- One form = one contract invocation: the resolver maps `trigger → ContractInvocation`. Multi-expansion (composition) is not specced or implemented.
- No self-recursive forms: the existing `call_contract` restriction (no self-recursion at Tier 1) applies to the lowered invocation node.
- Dynamic dispatch: `TrustLevel::System/Stdlib/Trusted/User` controls which forms can bind to which triggers; resolution is fully static (no runtime registry lookup). `runtime_dispatch_required: false` in the lowering proof.

What is NOT proved by a dedicated negative fixture:
- A form that attempts to declare two outputs (widening the callee's output surface) is not blocked by F-rules — it would be caught downstream when the lowered invocation's type doesn't match the call site expectation. No explicit E-FORM-MULTI-OUTPUT rule exists.
- A form declared in an `effect` contract but targeting a `pure` callee is not addressed. The spec restricts calling effect callees *from* pure callers (inheriting call_contract §10.4), but does not explicitly address the reverse.

**Gate for proof card:** negative fixture matrix — attempts at non-eliminable forms (effect authority, multi-expansion, dynamic target, output widening) must each produce a compile-time diagnostic rather than silent acceptance or runtime surprise.

---

## 5. Typed-Ref Lowering Target

The canonical lowering path for a Contract Invocation Form, now anchored to the typed-ref substrate:

```
Step 1 — Declaration site:
  Contract C body:
    uses TargetContract           ← canon (P3); makes DAG edge source-visible
    form (x) "trigger" (y)        ← form declaration (lab; future canon candidate)

Step 2 — Resolution gate:
  TypeChecker sees `uses TargetContract`:
    → resolved_ref { modifier, input_count, input_names, output_names }
  Form resolver sees `(x) "trigger" (y)`:
    → candidates = contracts with matching trigger + arity
    → type-filters by typed_operands
    → arity-matches against resolved_ref.input_count
    → survives = TargetContract (or ambiguity = error)

Step 3 — Lowering:
  Resolved form → ContractInvocation node in SemanticIR
  ContractInvocation references the typed-ref edge already in contract_refs
    { lowered_from_form: { trigger, form_id, original_kind } }
  dependency_edges entry for the resolved invocation: execution_dependency: true
    (distinct from the typed-ref edge with execution_dependency: false)

Step 4 — Trace:
  TraceEvent carries: trigger, original_kind, candidates, refused_candidates,
    typed_operands, resolved_to, lowering_target
  Tooling can expand: "trigger resolved to TargetContract via FormKind::Infix"
```

**Key design principle from the substrate:** The `uses TargetContract` declaration acts as an **explicit license** for C to reference T through a form. A form that resolves to a target not declared in `contract_refs` should be an error, not a silent resolution success. This is the typed-ref-anchored version of the Rust orphan rule (LAB-FORM-LAYER-THEORY-P1 §4.2): the contract that declares the `uses` edge is the one authorized to declare forms for that target.

This changes the current lab design slightly: today `form_registry.rs` registers forms by iterating `contract.forms` without checking whether the contract has a typed-ref to the form's callee. With the typed-ref substrate, the check is:

```
  REGISTER: form (trigger) for contract C targeting T
    REQUIRE: C has uses T in contract_refs (resolved)
    ERROR:   E-FORM-NO-REF — "form references target T but no `uses T` declaration found"
```

This makes every form's target edge double-visible: once in `uses` (static declaration) and once in the form trigger mapping (call-shape declaration). The two are separate concerns (presence vs. invocation shape), but they must be consistent.

---

## 6. Risk Table

| Risk | Severity | Lab Evidence | Mitigation / Gap |
|---|---|---|---|
| Hidden runtime dispatch | HIGH | SemanticIR lowering proof: `runtime_dispatch_required: false`; `vm_linker_required: false` | MITIGATED. VM sees ordinary invocations. Forms lower before emit. |
| Macro-like expansion (one form → multiple calls) | HIGH | Spec: one form = one contract invocation; composition stays in PROP-002 | MITIGATED by design. No multi-expansion surface in the lab implementation. |
| Order-dependent overload resolution | HIGH | FTD-5/6: declaration order does not win; E-FORM-AMBIG fires | IN-MODULE MITIGATED. Cross-module: OPEN. Gates on import-resolution mainline. |
| Ambiguous triggers | HIGH | E-FORM-AMBIG: no winner, compilation refused, both candidates named | MITIGATED. Fail-closed, not first-wins. |
| Cross-module coherence (form ownership) | HIGH | Not proved; lab registry is single-module | OPEN RISK. Must be addressed in LAB-FORM-INVOCATION-P1 coherence fixture (TH-2). |
| Authority smuggling via forms | HIGH | `no_form` on effect/privileged/irreversible contracts (§E2, implemented) | PARTIALLY MITIGATED. TH-6 negative proof needed for authority-bearing edge cases. |
| Trace opacity (forms hide real calls) | MEDIUM | `ResolvedExpr` + `TraceEvent` + `lowered_from_form` carry full history | MITIGATED. TH-5 is the strongest TH. Tooling can show expanded view. |
| call_contract backsliding | MEDIUM | Forms lower to explicit call nodes; `call_contract` is not modified | MITIGATED. Typed-ref anchor ensures the DAG edge is declared before any form resolves. |
| Form vocabulary collisions (two packages, same trigger) | HIGH | No cross-module vocabulary ownership enforced | OPEN RISK. `speaks`/dictionary coherence model unimplemented. Gates on import mainline + TH-2. |
| Effect modifier propagation from callee to declaring contract | MEDIUM | Lab spec does not address this case explicitly | OPEN. TH-1 proof card must include fixture: `pure` declaring contract + form → `effect` callee = error. |
| TH-4 hygiene gaps | MEDIUM | F-02/F-03 cover specific cases; MultiKeyword arm capture not proved | OPEN. Fixture matrix needed across all 7 FormKinds. |
| TH-6 output-widening | LOW | Not specced or implemented; downstream type error would catch it | OPEN. Should be closed explicitly with E-FORM-MULTI-OUTPUT or equivalent. |
| control-forms (MultiKeyword / `match`) trust gating | MEDIUM | `trust_level` field exists but no System/Stdlib-only enforcement in lab | LAB-FORM-LAYER-THEORY-P1 §7 flagged this. Decide: MultiKeyword is System/Stdlib-gated or user-accessible. |

---

## 7. Coherence Rules

The following rules are proposed based on the archaeology. They are design candidates
for the next proof card, not yet formally proved.

**Rule C-1 — Typed-ref anchor (new; from P3 substrate):**
A form declaration targeting contract T in contract C requires an explicit
`uses T` declaration in C's body. Resolution that would map to a target not in
`contract_refs` is a compile-time error (E-FORM-NO-REF), not a silent resolution
success. This makes every form's target edge double-visible.

**Rule C-2 — Form ownership (from LAB-FORM-LAYER-THEORY-P1 §4.2):**
A form for contract T may be declared only in:
(a) the module that declares T (callee-side declaration), OR
(b) the module that explicitly `uses T` (caller-side declaration, anchored by C-1).
A module that neither declares T nor declares `uses T` cannot register forms
for T. This is the Rust-shaped orphan rule applied to form declarations.

**Rule C-3 — Ambiguity is diagnostic, not first-wins:**
Already implemented (E-FORM-AMBIG in `form_resolver.rs`; FTD-5/6 proved).
After cross-module forms are introduced, the rule extends: a trigger that would
be ambiguous across module boundaries produces a compile-time error at the
use site. The diagnostic must name all surviving candidates with their declaring
modules.

**Rule C-4 — Import order must not affect form resolution:**
Form resolution results must be bit-identical under permuted import order.
This is TH-2, currently only proved within a module. The rule is stated here
as a design requirement for the next proof card.

**Rule C-5 — no_form propagates through typed-ref:**
If a contract T has `no_form`, then any contract C with `uses T` cannot declare
a form targeting T. The compiler checks this at `uses` declaration time, not only
at call-site resolution time. This closes the gap where a form could be declared
that would silently fail later at call sites.

**Rule C-6 — Fragment class of declaring contract is unchanged by form declaration:**
A `pure` contract that declares `form (x) "trigger" (y)` remains `pure`. The
form declaration is metadata (like `uses ContractName`). The fragment class of
the declaring contract is determined by its behavior declarations only. This
follows the precedent established by the `"metadata"` fragment class in P3.

**Rule C-7 — control-forms (MultiKeyword) are System/Stdlib-gated in v0:**
`MultiKeywordForm` (which allows `match`-like syntax) is restricted to
`trust_level: :system` or `trust_level: :stdlib` in v0. User-level MultiKeyword
is deferred until the eliminability boundary (TH-6) is formally proved. This
avoids the "users define match-like constructs that hide arbitrary dispatch"
risk flagged in LAB-FORM-LAYER-THEORY-P1 §7.

---

## 8. Decision

**SPLIT + KEEP**

The three tracks established in LAB-CONTRACT-FORMS-P1 remain the correct
separation. This card decides the status of each:

**Track A — Contract Invocation Forms (T2): KEEP**

The orphaned lineage is substantial (full spec + full implementation + two
passing proofs). The theoretical foundation is coherent (LAB-FORM-LAYER-THEORY-P1).
The typed-ref substrate is now canon and provides the missing lowering anchor.

TH-1 and TH-3 and TH-5 are in good shape. TH-2 (cross-module coherence),
TH-4 (hygiene), and TH-6 (eliminability) have specific open gaps that are
well-scoped and addressable in a proof card.

The typed-ref anchor (Rule C-1) is a new design element this card adds to
the spec: forms must declare their target via `uses`. This is the right
connection between the two tracks and makes forms source-visible by construction.

The decision to KEEP is conditional:
- The next proof card (LAB-FORM-INVOCATION-P1) must mechanize TH-1, TH-4, TH-6
  for the in-module case.
- TH-2 (cross-module coherence) is deferred to LAB-FORM-VOCABULARY-P1, which
  gates on the import-resolution mainline.
- MultiKeyword / `match` (Rule C-7) is restricted to Stdlib in v0.

**Track B — Gap-I Form Constructor (T1): KEEP (independent clock)**

Covenant P27/P28 commitment unchanged. Completely separate semantics (value
construction, not invocation). No implementation anywhere. LAB-FORM-CONSTRUCTOR-P1
is on an independent clock gated on supervisor prioritization of Gap-I.
This card does not advance or retard that track.

**Track C — View/UI forms (T3/T4): NOT A FORM TRACK**

The view DSL conclusion (VDSL-9: invocation alias = DX-candidate metadata only)
stands. View-domain form invocation is a *consumer* of Track A — the view direction
uses Contract Invocation Forms (T2) but does not define new form semantics. This
is not a separate track; it is an application of Track A when it lands.

**Summary:**

| Track | Decision | Next card |
|---|---|---|
| Contract Invocation Forms (T2) | KEEP — proof-local design + in-module proof | LAB-FORM-INVOCATION-P1 |
| Gap-I Form Constructor (T1) | KEEP — independent clock | LAB-FORM-CONSTRUCTOR-P1 |
| View/component forms (T3) | Not a track — consumes T2 | (deferred) |
| UI/HTML input forms (T4) | Not a form concept — naming collision | (out of scope) |

---

## 9. Next Route

```
LAB-FORM-INVOCATION-P1           (first; gated on nothing except supervisor
                                  authorization)
  Goal: proof-local design card for Contract Invocation Forms in-module case.
        Mechanize:
          - TH-1 (conservativity): compile with forms → SemanticIR₁; hand-expand
            to typed-ref kernel calls → SemanticIR₂; assert semantic equality
            (same nodes, fragment classes, effect surface, contract_refs, receipts).
          - TH-4 (hygiene): fixture matrix across all 7 FormKinds, name-collision
            engineered; assert no capture.
          - TH-6 (eliminability): negative fixture matrix — effect authority,
            multi-expansion, dynamic target, output-widening all fail closed.
        Implement Rules C-1, C-5, C-6, C-7 in proof-local fixtures.
        Define the `form` declaration surface in proof-local syntax only
          (no grammar PROP, no parser implementation).
  Route: LAB / PROOF-LOCAL DESIGN
  Explicitly not: cross-module, canon grammar, parser/typechecker implementation,
    call_contract changes, public API.

LAB-FORM-VOCABULARY-P1           (after LAB-FORM-INVOCATION-P1 + import
                                  resolution mainline lands)
  Goal: proof-local: define 2 small vocabularies over one kernel fixture set;
        mechanize TH-2 (cross-module coherence — permute import order, engineered
        overlap fails closed), TH-3 (skeleton stability).
        Define and test Rules C-2, C-3, C-4.
        Decide `speaks` vocabulary import syntax surface (design-only).
  Route: LAB / PROOF-LOCAL DESIGN
  Gate: PROP-IMPORT-RESOLUTION-P5 (99/99 PASS — already done) +
        cross-module typed refs (OOF-REF2 gate from P3) +
        LAB-FORM-INVOCATION-P1 closed.

LAB-FORM-CONSTRUCTOR-P1          (independent clock; Gap-I)
  Goal: first design boundary for `form NAME -> TypeTarget` value constructors
        per Covenant P27/P28; explicitly separate namespace from invocation
        forms, citing LAB-CONTRACT-FORMS-P1 §3 terminology table.
  Route: LAB / DESIGN BOUNDARY
  Gate: supervisor prioritization of Gap-I
```

---

## 10. Sources

**Canon:**
`igniter-lang/docs/language-covenant.md` (P27:295-315, P28:317-345),
`igniter-lang/docs/concepts/canonical-semantic-model.md` (Gap-I rows),
`igniter-lang/docs/spec/ch2-appendix-ebnf-grammar.md` (no `form` keyword),
`igniter-lang/.agents/work/proposals/PROP-002-contract-composition-algebra-v0.md`
(traced SMC claim; operator algebra; dynamic-selection rejection).

**Proposals:**
`LANG-TYPED-CONTRACT-REF-typed-contract-reference-declaration-v0.md`,
`LANG-TYPED-CONTRACT-REF-P2-implementation-planning-v0.md`,
`LANG-TYPED-CONTRACT-REF-P3-ruby-implementation-proof-v0.md` (67/67 PASS).

**Governance docs (lab):**
`lab-contract-invocation-forms-formalization-v0.md` (LAB-CONTRACT-FORMS-P1),
`lab-form-layer-theory-and-grammar-stratification-v0.md` (LAB-FORM-LAYER-THEORY-P1),
`lab-typed-contract-reference-boundary-proof-v0.md` (LAB-TYPED-CONTRACT-REF-P1).

**Lab implementation:**
`igniter-lab/igniter-compiler/src/form_registry.rs`,
`igniter-lab/igniter-compiler/src/form_resolver.rs`,
`igniter-lab/lab-docs/core/PROP-Forms-Enhanced-v0.md`,
`igniter-lab/igniter-compiler/out/contract_invocation_forms_type_directed_dispatch_proof/`,
`igniter-lab/igniter-compiler/out/contract_invocation_forms_semanticir_lowering_proof/`.

**View:**
`igniter-lab/lab-docs/view/lab-experimental-igniter-html-view-dsl-arbre-like-boundary-v0.md`
(VDSL-9: `forms_assisted: true` = DX-candidate only; invocation alias conclusion).

**Gov boundary:**
`igniter-gov/portfolio/governance/2026-06-10-current-language-surface-map-v0.md`
(`form_registry`/`form_resolver` lab-only ruling).
