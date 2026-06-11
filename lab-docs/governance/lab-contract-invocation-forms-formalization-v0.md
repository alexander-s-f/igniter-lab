# Lab: Contract Invocation Forms — Formalization and Archaeology

**Track:** contract-invocation-forms-and-form-assisted-composition-v0
**Card:** LAB-CONTRACT-FORMS-P1
**Category:** governance / lang
**Date:** 2026-06-11
**Route:** BACKGROUND RESEARCH / FORMALIZATION / NO IMPLEMENTATION
**Status:** CLOSED — archaeology complete; terminology disambiguated; verdict SPLIT; next routes named
**Pin:** This is a pinned background research direction. It is intentionally
separate from the current mainline (import resolution / entrypoint / module
identity) and must not block or be blocked by it.

---

## 1. Authority Boundary

This document is lab/background research only.

- No parser, compiler, VM, or view-framework implementation authorized.
- No canon PROP authored. No grammar adoption.
- No public API. No replacement of `call_contract`.
- No module visibility or import changes.
- No runtime dispatch authority created.
- `form_registry` / `form_resolver` (Rust lab) are NOT claimed as canon —
  they remain lab-only divergence per the gov surface map (2026-06-10).
- UI forms (HTML input forms) are explicitly NOT the subject of this document.

The purpose of this document is archival: the "form" idea has been repeatedly
rediscovered and lost. This report fixes the terminology, formalizes the pain,
compares candidate semantics, and names the next routes — so the idea has a
stable home.

---

## 2. Evidence Inventory

Every meaningful occurrence of "form"-family concepts found across the three
repositories:

| Source path | Term used | Exact shape/syntax | Status category | Problem it addressed | Why it did / did not land |
|---|---|---|---|---|---|
| `igniter-lang/docs/concepts/canonical-semantic-model.md:107-108,148` | Form Constructor | `form NAME -> TypeTarget` | **spec_candidate (Gap-I)** | Named domain-specific constructors; "no unnamed semantic structure" | No PROP authored; no parser keyword; no fragment class. Waiting on strategic prioritization |
| `igniter-lang/docs/language-covenant.md:310` (P27 table) | `form` constructors | "Named domain constructor — no unnamed semantic structure" | **canon (doctrine-only)** | Accountability: every primitive exists to make accountability legible | Covenant commitment exists; enforcement is `doctrine-only` (PROP Governance Filter, not compiler) |
| `igniter-lang/docs/language-covenant.md:317-345` (P28) | unnamed blocks | "No unnamed block may carry semantic identity" | **canon (partial enforcement)** | Audit/linkage/replay require names | `invariant` blocks enforced by parser; other surfaces partial |
| `igniter-lang/.agents/docs/semantic-governance-heat-map.md:145` | `form NAME -> TypeTarget` | all stages 🔴 | **research/tracking** | "The single highest-leverage open gap in the language" | Tracked as `sem` debt: concept named in Covenant/spec, no PROP, no grammar |
| `igniter-lab/lab-docs/core/PROP-Forms-Enhanced-v0.md` | Form System / Contract Invocation Forms | `form (collection) ".map" { (selector) }`, FormKind ×7, priority, `no_form` | **lab-only (pressure doc)** | Compact, typed, reusable invocation shapes for contracts (operators, methods, keyword blocks) | Full spec exists (E1–E7, F-01..F-06 rules); base PROP-Forms-v0 is Agent-C archive; never routed through canon governance |
| `igniter-lab/igniter-compiler/src/form_registry.rs` | `form_registry` | `FormEntry { trigger, kind, contract, priority, inherited_from, elements }`; trigger index; F-01..F-06 validation | **lab-only (implemented)** | Phase 2: register declared invocation forms at compile time | Working code, golden artifacts (`form_table.json`); marked lab-only divergence by gov surface map |
| `igniter-lab/igniter-compiler/src/form_resolver.rs` | `form_resolver` | walks typed AST; resolves BinaryOp/UnaryOp/FieldAccess → ContractInvocation; emits `form_resolution_trace.json` | **lab-only (implemented)** | Phase 3: type-directed resolution of triggers to contracts, with trace/ambiguity/diagnostic evidence | Same as above; called after typecheck, before emit (`main.rs:252-253`) |
| `igniter-lab/igniter-compiler/src/monomorphizer.rs` | monomorphizer | `Add[T]` → `Add[Integer]` | **lab-only** | Generic specialization — PRECONDITION for form registration (forms attach to concrete types) | Related to forms only as a pipeline prerequisite; NOT itself a form concept |
| `igniter-lab/lab-docs/view/lab-experimental-igniter-html-view-dsl-arbre-like-boundary-v0.md:102-149` | Contract Invocation Forms; `form:` prefix | `form "todo_card" (item)` inside contract; usage `todo_card item`; `form:todo_card(item)` | **view-only exploration (DX candidate)** | Compact component invocation in view DSL | Conclusion locked: "invocation alias that resolves to a `ContractInvocation` node. It should not be a runtime primitive." VDSL-9 marks `forms_assisted: true` as DX-candidate metadata only |
| `igniter-gov/portfolio/governance/2026-06-10-current-language-surface-map-v0.md` | `form_registry` / `form_resolver` | — | **gov boundary note** | Mark Rust pipeline stages as divergence | "Not canon pipeline authority" — explicit lab-only ruling |
| `igniter-lab/lab-docs/governance/igniter-application-structure-and-module-form-proposal-readiness-v0.md:40-44,98-101` | `call_contract`; typed contract-ref; `uses Other` | `call_contract("Name", args)`; proposed `uses Other` | **research (readiness)** | Stringly composition; DAG compiler-known but source-invisible | Typed contract-refs flagged "for a later route; not required for the first structural step" |
| `igniter-lab/igniter-view-engine/fixtures/rack_core/call_contract_resolution.ig` + `typechecker.rs:3350-3445` | `call_contract` two-tier | Tier 1: literal name → static resolution (pure-only, arity, no self-recursion); Tier 2: dynamic name → `Unknown` | **lab-only (proven, LAB-RACK-P11 47/47)** | Inter-contract invocation | Works; is the thing whose ergonomics/honesty the form idea wants to improve |
| `igniter-lang/docs/spec/ch2-appendix-ebnf-grammar.md:51-52` | `contract_shape` | `ContractShapeDecl ::= "contract_shape" Name ...` | **canon (grammar; semantics parsed-only per PROP-016)** | Trait-like structural interfaces | In grammar; PROP-Forms-Enhanced E1 proposes forms-on-shapes (inheritance) |
| `igniter-lang/.agents/work/proposals/PROP-002-contract-composition-algebra-v0.md` | composition operators | `>>`, `\|\|`, `branch`, `over`, `embed` | **authored, pending proof** | Composition altitude above single invocation | Only `embed` expressible; dynamic contract selection explicitly out-of-fragment |
| EBNF grammar (canon) | `form` keyword | — | **not found** | — | `form` is not a canon parser keyword anywhere |
| canon Ruby compiler (`igniter-lang/lib/`) | form pipeline | — | **not found** | — | No Ruby equivalent of form_registry/form_resolver; explicit parity gap |
| `igniter-lang/.agents/work/proposals/` | PROP-Forms | — | **not found in mainline** | — | PROP-Forms-v0 lives only in Agent-C archive lineage; never entered mainline proposals/ |

---

## 3. Terminology Cleanup

The word "form" currently carries **eight distinct meanings**. This section is
the normative disambiguation; future documents should cite it.

| # | Term | What it actually is | Where it lives | Must not be confused with |
|---|---|---|---|---|
| T1 | **Form Constructor** (`form NAME -> TypeTarget`) | A *value-construction* primitive: named domain constructor producing a typed value. Covenant P27/P28 commitment. Gap-I | Canon concepts doc + Covenant; no implementation | T2 — it constructs values, it does not invoke contracts |
| T2 | **Contract Invocation Form** | A *call-shape declaration*: binds a syntactic trigger (`+`, `.map`, keyword block) to a contract, resolved type-directionally to a `ContractInvocation` | Lab: PROP-Forms-v0/Enhanced + form_registry/form_resolver | T1; also not a macro — it cannot compute, only map a trigger to one contract |
| T3 | **`form:` prefix** | DX sugar candidate marking an invocation-alias call site explicitly (`form:todo_card(item)`) | View DSL boundary doc; DX-candidate only | A new semantic construct — it is surface marking over T2 |
| T4 | **UI/HTML form** | User-input form in a view (input fields, submit) | View/Tailmix territory | Everything else here. Naming collision is accidental |
| T5 | **Rust `form_registry` / `form_resolver`** | Lab compiler stages implementing T2 (Phase 2 registration, Phase 3 resolution) | `igniter-lab/igniter-compiler/src/` | Canon pipeline (gov ruled lab-only); also not generics machinery |
| T6 | **Typed contract reference** (`uses Other`) | A *dependency declaration*: makes the contract→contract DAG edge explicit, named, refactor-safe in source | Proposed in application-structure readiness doc; not implemented | T2 — a ref declares an edge; a form declares a call *shape*. Orthogonal |
| T7 | **Component / view invocation** | A contract whose output is a view node, invoked from a view tree | IGV/Tailmix + view DSL exploration | A separate subsystem; components are contracts, their invocation could *use* T2/T6 but is not itself a form concept |
| T8 | **`call_contract("Name", args)`** | The current invocation mechanism: two-tier (literal=static, dynamic=Unknown), pure-only callees, VM dispatch table | Lab compiler/VM, proven LAB-RACK-P11 | The *baseline*, not a form. T2/T6 both desugar toward what call_contract already does at Tier 1 |
| — | **monomorphizer** | Generic specialization (`Add[T]`→`Add[Integer]`). Only relation to forms: runs first so forms attach to concrete types | Lab only | Any "form" meaning — the name proximity in `main.rs` is incidental |

**The card's working hypothesis was partially wrong in an instructive way:**
`form_registry`/`form_resolver` are not type-form/generics machinery — they are
a *complete lab implementation of Contract Invocation Forms (T2)*, with a full
written spec (PROP-Forms-Enhanced-v0) that never entered canon governance. The
idea was not merely "repeatedly searched for" — it was *built*, then orphaned
in the Agent-C archive lineage. That is the strongest single finding of this
archaeology.

---

## 4. Pain Statement

Formalized from the corpus evidence:

1. **Stringly invocation.** `call_contract("Name", args)` couples an invocation
   to a string literal. Renaming a contract silently breaks every caller
   (application-structure readiness doc §1: "rename a contract → silently break
   every string caller").
2. **DAG honesty gap.** The TypeChecker resolves Tier-1 callees and the VM
   builds a dispatch table — the dependency DAG is *compiler-known* but
   *source-invisible*. Covenant-wise this is a structural honesty gap: a real,
   load-bearing fact (the edge) has no declared name in source (P28 pressure).
3. **Implementation/invocation coupling.** A contract's only invocation surface
   is its implementation name + positional args. There is no way to declare a
   reusable, typed *shape* of invocation (operator, method-style, keyword
   block) without changing the contract itself.
4. **Verbose common compositions.** Every composition is spelled as explicit
   compute nodes; PROP-002's operators (`>>`, `||`, `branch`, `over`) have no
   source syntax, so recurring patterns are re-typed long-hand.
5. **Component invocation wants compactness.** The view DSL exploration found
   that `TodoCard(item: item)` vs `todo_card item` is exactly the T2 question
   re-arising in a new domain — evidence the pain recurs across domains.
6. **Abstraction without opacity.** Large programs need a layer between
   "contract implementation" and "uses of that contract" — but any such layer
   must keep edges visible (Axiom 1/P28), or it is a regression.

---

## 5. Candidate Semantics

| Candidate | Description | Assessment |
|---|---|---|
| **A. Invocation alias** | `form` declares a named call shape; desugars at compile time to an explicit `ContractInvocation`; no runtime primitive | **Strongest evidence base.** This is what PROP-Forms-v0/Enhanced + form_resolver already implement and what the view DSL exploration independently concluded ("invocation alias that resolves to a ContractInvocation. It should not be a runtime primitive"). Type-directed, priority-disambiguated, fail-closed with trace evidence. Risk: trigger-based resolution (`+` could mean many contracts) is genuinely macro-adjacent and needs strict bounds (F-rules, `no_form`, ambiguity = error) |
| **B. Value constructor** | `form NAME -> TypeTarget` creates a typed domain value | **Different feature entirely (T1, Gap-I).** It belongs to the Covenant accountability story (named constructors, no anonymous semantic structure), not to invocation. Must be its own track; folding it into A would re-create the overload this document exists to dissolve |
| **C. Component adapter** | `form` binds a contract to view/component syntax | **Special case of A in the view domain.** The view DSL doc treats `form "todo_card" (item)` as exactly an invocation alias. No separate semantics needed; the view direction consumes A, it does not define a new meaning |
| **D. Typed contract reference** | replaces stringly `call_contract`; makes the DAG edge refactor-safe (`uses Other`) | **Solves pains 1–2 directly and is *smaller* than A.** A declared dependency edge + non-stringly call site. Note: D is not a "form" at all — it is a dependency/visibility feature. Mislabeling D as a form is how the term got overloaded. D should proceed under its own name |
| **E. Composition macro** | a form expands to multiple contract invocations | **Reject for v0.** This is a macro system: it computes structure, can hide arbitrary call graphs, and collides with PROP-002's algebra (which is the sanctioned multi-invocation layer). PROP-002's explicit rejection of dynamic/recursive composition signals the project's stance. If common compositions need names, the right home is source syntax for PROP-002 operators, not form-expansion |
| **F. Rename/split** | the term is too overloaded | **Partially adopt.** Keep `form` for A (it has a written spec and an implementation using that name) and for B (Covenant already says "form constructors" — canon text owns the word). Do NOT use "form" for D (call it *typed contract reference*), C (call it *component invocation*, consumes A), or E (rejected) |

---

## 6. Separation Model

Six layers that must remain distinct:

| Layer | What it is | Owner today |
|---|---|---|
| **Contract implementation** | The body: inputs, computes, outputs, effects. The unit of behavior and identity (`contract_ref`) | Canon (Ch1/Ch6) |
| **Invocation form (T2/A)** | A declared, typed, named *shape* by which a contract may be called (operator/method/keyword trigger). Compile-time mapping → `ContractInvocation`. Many forms may point at one contract | Lab only (PROP-Forms lineage) |
| **Composition form** | Structure *between* contracts: `>>`, `||`, `branch`, `over`, `embed`. An algebra over ports, not a call shape | PROP-002 (authored, pending) |
| **Value constructor (T1/B)** | `form NAME -> TypeTarget`: produces a typed value; carries no invocation semantics | Gap-I (spec_candidate) |
| **Component/view form (T7/C)** | A contract producing view nodes, invoked from a view tree; consumes invocation forms, adds no new semantics | IGV/Tailmix direction (lab) |
| **Runtime dispatch** | Name→bytecode table, call depth, cycle guards in the VM | Lab VM; unchanged by any of the above in v0 — all form resolution happens at compile time |

Rules: an invocation form may never *be* an implementation (no body); a
composition form may never be hidden inside an invocation form (that would be
candidate E); constructors never invoke; runtime dispatch never widens because
a form exists (forms lower before emit).

---

## 7. Relationship to Current Mainline

This track is **pinned background**; dependency directions:

- **Import resolution / module identity (LANG-MODULE-IDENTITY-P1 → LAB-MULTIFILE-COMPILATION-P1):** forms resolve against a contract registry; today that registry is single-file. Cross-file forms inherit whatever import resolution delivers. *Forms must not block or precede this work.*
- **Entrypoint (PROP-029 / RES-003):** orthogonal. An entrypoint selects a contract; a form shapes a call. No interaction in v0.
- **Future visibility:** a form is part of a contract's public surface. When visibility lands, form declarations must be covered by the same export rules. Design note for later, not a dependency now.
- **Typed contract refs (D):** *closest neighbor.* D solves stringly-ness; A solves shape reuse. D should go first — it is smaller, it makes every edge named, and forms can then resolve against declared refs instead of a global registry. Sequencing D → A reduces A's risk substantially.
- **App assembly / component direction (RES-003 A3/A4, IGV/Tailmix):** consumers of A, not definers. The view DSL's `form "todo_card"` shape should be re-derived from whatever A becomes, not frozen now.

---

## 8. Honesty / DAG Visibility Analysis

Does a form layer improve or harm honesty? Assessed per the card's questions:

- **Does the form make the DAG more visible?** A *declared* form (in the callee
  or a shape) plus a resolved trace makes today's invisible edges *more*
  visible than `call_contract` strings — provided resolution is static and
  ambiguity is an error. The lab implementation already emits
  `form_resolution_trace.json` with candidates, refused candidates, and the
  final selection: this is the honest pattern (resolution as evidence).
- **Does it hide contract calls?** Risk exists at the call *site*: `a + b`
  resolving to `contract Add` is less explicit than `call_contract("Add", a, b)`.
  Mitigations that must be mandatory: (1) resolution is fully static; (2) every
  resolved site is recorded in IR with the lowered invocation; (3) tooling can
  flip any call site between sugared and expanded views; (4) `no_form` opt-out
  exists (already in PROP-Forms-Enhanced E2).
- **Can SemanticIR preserve expanded edges?** Yes — the Path B lowering
  discipline (PROP-044-P8) is the established precedent: source form is
  human-facing, the compiler lowers to explicit nodes, and the IR keeps both
  the original reference and the lowered result. Forms must follow it.
- **Can tooling show both?** Yes if the IR carries `original_kind` + trigger +
  `resolved_to` (the lab `ResolvedExpr` already has exactly these fields).
- **Can errors point at both the form and the contract?** Diagnostics already
  carry `line`/`node`/`path`; form diagnostics (F-01..F-06 + resolution misses)
  must carry the form declaration span *and* the call-site span.

**Net assessment:** with static resolution + IR-preserved lowering + trace
evidence, forms are honesty-*positive* (they name and record edges that today
hide inside strings). Without those three properties they are honesty-negative.
The properties are non-negotiable gates for any future proof card.

---

## 9. Syntax Sketches (exploratory, NOT adopted)

All sketches are non-authoritative illustrations for a future design card.

**Style 1 — standalone alias declaration (caller-side, near T6):**
```igniter
form todo_card(item: TodoItem) -> HtmlNode uses TodoCard(item)
```

**Style 2 — form declared inside the contract (PROP-Forms lineage, callee-side):**
```igniter
pure contract TodoCard {
  form "todo_card" (item)
  input  item: TodoItem
  output node: HtmlNode
}
```

**Style 3 — explicit `form:` marker at the call site (DX prefix from the view DSL doc):**
```igniter
compute node = form:todo_card(item)
```

**Style 4 — typed-ref import-alias hybrid (closest to candidate D):**
```igniter
uses TodoCard as todo_card(item)
compute node = todo_card(item)
```

**Style 5 — trigger form (what the lab implements today; shown for completeness):**
```igniter
contract_shape Mappable[T, R] {
  form (collection) ".map" { (selector) }
}
```

Observations: Styles 1/4 keep the declaration at the *consumer* (good for
visibility of edges in the using module); Styles 2/5 keep it at the *provider*
(good for reuse, riskier for "who decided this call shape"); Style 3 is
orthogonal surface marking applicable to any of them.

---

## 10. Typechecking Requirements (if ever promoted)

A future proof card must demonstrate, fail-closed:

1. **Arity** — form parameter count matches callee inputs (lab already errors on mismatch for call_contract Tier 1).
2. **Name/type binding** — each form parameter maps to a named input with compatible type; no positional ambiguity.
3. **Output type** — form's declared result type equals callee's (single) output type; multi-output callees rejected in v0.
4. **Effect/fragment compatibility** — v0: pure callees only (inherits the call_contract rule); the form may never widen authority (a form on an `effect` contract is OOF until a separate decision).
5. **Visibility** — the callee must be import-visible at the form's use site (gates on import resolution mainline).
6. **No dynamic lookup** — the trigger→contract mapping is closed at compile time; ambiguity (two candidates survive type filtering) is an error, not a priority silently winning across modules.
7. **Cycle/self-call** — same rules as call_contract (no self-recursion in v0; managed recursion stays in `recur`).
8. **Error locations** — every form diagnostic carries both the form declaration span and the call-site span.

## 11. SemanticIR Requirements

The IR must show, per resolved site: the original form reference (trigger or
alias name + source span), the lowered `ContractInvocation` (or existing call
node) with `contract_ref`, the argument mapping (form param → contract input),
and the dependency edge made explicit in the contract's dependency graph. The
lab `ResolvedExpr`/`TraceEvent` shapes are an adequate starting schema.

## 12. Runtime / VM Requirements

**None in v0.** Forms lower at compile time; the VM sees ordinary contract
invocations through the existing dispatch table (depth/cycle guards unchanged).
No new runtime dispatch primitive unless a later proof demonstrates a need —
and any such proposal must clear PROP-002's standing rejection of dynamic
contract selection.

## 13. Risk Register

| Risk | Severity | Mitigation |
|---|---|---|
| Hides real calls behind sugar | HIGH | Mandatory static resolution + IR-preserved lowering + tooling expansion view (§8 gates) |
| Becomes a macro system (candidate E creep) | HIGH | One form = one contract invocation; no multi-expansion; composition stays in PROP-002 |
| Becomes view-only feature | MEDIUM | Keep the design domain-neutral; view direction consumes, never defines |
| Collides with UI input forms (T4) | MEDIUM | Terminology table (§3) is normative; view docs must say "input form" for T4 |
| Conflicts with Gap-I Form Constructor (T1) | HIGH | SPLIT verdict: T1 and T2 are separate tracks; canon text owns "form constructors" for T1 — any T2 PROP must cite the disambiguation |
| Duplicates typed contract-ref work (D) | MEDIUM | Sequence D first; A builds on declared refs |
| Opens dynamic dispatch | HIGH | Closed by requirement §10.6 + PROP-002 rejection; Tier-2 call_contract stays the only dynamic surface |
| Bad interaction with import/visibility | MEDIUM | Pin: forms gate on mainline import resolution; visibility must cover form exports when it lands |
| Too much syntax too early | MEDIUM | This track stays pinned-background; nothing enters grammar without a proof-local card and governance route |
| Orphaned-spec confusion (PROP-Forms lineage) | MEDIUM | This document is now the index entry; PROP-Forms-v0/Enhanced are inventoried as lab-only with no canon authority |

## 14. Recommendation

**SPLIT** — the term "form" is overloaded across at least three genuinely
different features, and the evidence says they need separate tracks:

1. **Typed contract references (D)** — *not a form*; the smallest fix for the
   stringly/DAG-honesty pain (pains 1–2). Should be first. Name: typed
   contract-ref, never "form".
2. **Contract Invocation Forms (A/T2)** — coherent, already specced and
   lab-implemented (PROP-Forms lineage, form_registry/form_resolver), but
   orphaned outside governance. Needs a reconciliation/readiness pass before
   any new design work: decide whether the existing lab Form System is the
   basis or a museum piece. Sequenced after D.
3. **Form Constructor (B/T1, Gap-I)** — canon Covenant commitment (P27/P28),
   completely separate semantics (value construction). Its own track, on its
   own clock; flagged by the heat map as the highest-leverage `sem` gap.

Within track 2 the hypothesis from the card is **confirmed in the narrow
sense**: a form is correctly a compile-time invocation adapter desugaring to an
explicit `ContractInvocation` with the dependency graph kept honest — both the
lab implementation and the independent view-DSL exploration converged on
exactly that conclusion. What the card's hypothesis missed is that this answer
was already built once and lost; the governance failure mode is orphaning, not
absence.

## 15. Exact Next Route

```
LAB-TYPED-CONTRACT-REF-P1            (recommended first; after — not blocking —
                                      LANG-MODULE-IDENTITY-P2 mainline)
  Goal: design + proof-local study of `uses Other` typed contract references
        replacing stringly call_contract at Tier 1: declared edge, named call
        site, refactor-safe, IR-explicit dependency edges
  Route: LAB / PROOF-LOCAL DESIGN
  Explicitly not: visibility, import changes, forms

LAB-CONTRACT-FORMS-P2                (after LAB-TYPED-CONTRACT-REF-P1)
  Goal: reconcile the orphaned PROP-Forms-v0/Enhanced lineage with current
        governance: inventory what form_registry/form_resolver prove, decide
        keep/reduce/retire per feature (FormKind set, priority, no_form,
        shape-inherited forms), and define the proof-local invocation-alias
        lowering card if kept
  Route: LAB / GOVERNANCE RECONCILIATION + PROOF-LOCAL DESIGN

LAB-FORM-CONSTRUCTOR-P1              (independent clock; gated on supervisor
                                      prioritization of Gap-I)
  Goal: first design boundary for `form NAME -> TypeTarget` value constructors
        per Covenant P27/P28; explicitly separate namespace from invocation
        forms, citing §3 of this document
  Route: LAB / DESIGN BOUNDARY
```

No implementation is recommended directly; every route above is design/readiness
or proof-local with its own card and gate.

---

## Sources

Canon: `igniter-lang/docs/concepts/canonical-semantic-model.md` (Gap-I rows),
`igniter-lang/docs/language-covenant.md` (P27:295-315, P28:317-345, enforcement
registry), `igniter-lang/docs/spec/ch2-appendix-ebnf-grammar.md`
(ContractShapeDecl; no `form` keyword), `igniter-lang/docs/spec/ch6-semanticir.md`
(no invocation node kind; contract_ref as identity),
`igniter-lang/.agents/docs/semantic-governance-heat-map.md:145`.
Proposals: PROP-002 (operators + verbatim rejection of dynamic selection),
PROP-016 (monomorphization/erasure), PROP-044-path-b (lowering discipline
precedent).
Lab: `igniter-lab/lab-docs/core/PROP-Forms-Enhanced-v0.md` (E1–E7),
`igniter-lab/igniter-compiler/src/form_registry.rs` / `form_resolver.rs` /
`monomorphizer.rs` / `typechecker.rs:3350-3445` (call_contract two-tier),
`igniter-lab/igniter-view-engine/fixtures/rack_core/call_contract_resolution.ig`
(LAB-RACK-P11 47/47),
`igniter-lab/lab-docs/view/lab-experimental-igniter-html-view-dsl-arbre-like-boundary-v0.md`
(§3.1-3.2 form: prefix conclusion),
`igniter-lab/lab-docs/governance/igniter-application-structure-and-module-form-proposal-readiness-v0.md`
(stringly pain; typed refs deferred).
Gov: `igniter-gov/portfolio/governance/2026-06-10-current-language-surface-map-v0.md`
(form_registry/form_resolver lab-only ruling).
