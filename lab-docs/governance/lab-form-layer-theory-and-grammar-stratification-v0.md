# Lab: The Form Layer — Theory of Grammar Stratification over a Semantic Kernel

**Track:** contract-invocation-forms-and-form-assisted-composition-v0 (continuation)
**Card:** LAB-FORM-LAYER-THEORY-P1
**Category:** governance / lang / theory
**Date:** 2026-06-11
**Route:** BACKGROUND RESEARCH / THEORY / NO IMPLEMENTATION
**Status:** CLOSED — theoretical foundation stated; proof obligations named; verdict OPEN (theory coherent)
**Predecessor:** LAB-CONTRACT-FORMS-P1 (archaeology + SPLIT verdict; terminology table §3 is normative here)
**Pin:** Pinned background direction. Does not block or modify the mainline
(import resolution / entrypoint / module identity) or the SPLIT sequencing
from LAB-CONTRACT-FORMS-P1.

---

## 1. Authority Boundary

Research and theory only. No parser/compiler/VM implementation, no canon PROP,
no grammar adoption, no new runtime primitives, no change to the SPLIT
sequencing (typed contract refs still go first). External literature is cited
as intellectual grounding, not as authority over canon.

---

## 2. The Hypothesis, Restated Precisely

LAB-CONTRACT-FORMS-P1 classified forms (T2) as compile-time invocation
adapters. This document investigates the stronger hypothesis:

> **The form layer is not a convenience feature. It is the mechanism by which
> Igniter becomes a *stratified language*: a fixed, verifiable semantic kernel
> (contracts + composition algebra + SemanticIR), plus an open, growable
> surface vocabulary (forms) whose every sentence provably elaborates into the
> kernel. The "language above the language" intuition is correct and has an
> exact theoretical shape.**

The user-level metaphor — Lego bricks with pictures drawn over them — is not
just an analogy. Each half has a precise mathematical counterpart:

| Metaphor | Igniter artifact | Mathematical object |
|---|---|---|
| Brick (sealed, internal mechanism invisible) | `contract` with `contract_ref` identity | Generator morphism in a colored PROP / typed monoidal category |
| Studs/sockets (the only legal connection points) | Named, typed ports | Objects (typed wires) of the category |
| Snapping bricks together | PROP-002 operators `>>`, `\|\|`, `branch`, `over`, `embed` | Composition and monoidal product of morphisms |
| The assembled structure | Contract DAG / SemanticIR | A morphism term / string diagram |
| **The picture drawn over the assembly** | **A form / a form vocabulary** | **A derived operation: a named composite morphism; a definitional extension of the theory** |

---

## 3. The Kernel Already Exists — and Already Has the Right Theory

This is the load-bearing observation: Igniter does not need to *acquire* a
semantic kernel for stratification to work. It already has one, and PROP-002
already states its mathematical structure:

> "`||` is a **symmetric monoidal product** over contracts … together with `>>`
> [this] gives the structure of a **traced symmetric monoidal category**"
> — PROP-002, lines 152–154, 453–454.

Three consequences follow immediately from that claim:

**3.1 String diagrams are the canonical "picture" language.**
Traced symmetric monoidal categories possess a sound and complete graphical
calculus — string diagrams (Joyal–Street coherence; Selinger's survey of
graphical languages). Boxes are morphisms (contracts), wires are typed ports,
diagram pasting is composition. *The Lego-picture metaphor is literally the
standard mathematics of Igniter's own composition algebra.* A form, in this
picture, is a **named sub-diagram**: a dashed box drawn around a wiring pattern,
given a name and a type signature. The dashed box adds no new physics — it
abbreviates an existing assembly.

**3.2 Contracts are generators; forms are derived operations.**
In algebraic terms the kernel is a presentation: contracts are the *generators*
of the theory, the composition operators are the *operations*, and the
fragment/effect rules are the *equations and typing constraints*. A form is a
**derived operation** — a new named symbol defined by a term over the
generators. In logic this is a **definitional extension**, and definitional
extensions are **conservative**: they prove no new theorems about the original
vocabulary. Translated to Igniter:

> **Honesty theorem (target form).** A form vocabulary is admissible iff the
> extended language is a conservative extension of the kernel: every program
> using forms elaborates to a kernel program with identical SemanticIR
> semantics, identical fragment classification, identical effect surface, and
> identical authority requirements.

This converts the Covenant instinct ("sugar must not hide reality", Axiom 1 /
P27) from a design taste into a **provable property with a name**. The three
honesty gates from LAB-CONTRACT-FORMS-P1 §8 (static resolution, IR-preserved
lowering, trace evidence) are exactly the operational ingredients of a
conservativity proof.

**3.3 Expressive power is deliberately NOT increased.**
Felleisen's framework on the expressive power of programming languages
distinguishes features that are *macro-eliminable* (local, semantics-preserving
expansion exists) from features that genuinely add expressive power. Forms must
sit strictly on the eliminable side — they add **abbreviation power, not
expressive power**. This is a feature, not a limitation: it is precisely why
the kernel's verification story (replay, receipts, content-addressed identity,
fragment classification) survives unlimited surface growth. Anything
non-eliminable (new control flow, new effects, dynamic dispatch) is by
definition not a form and must go through a kernel PROP.

---

## 4. Grammar Transformation: Two Strategies, One Safe

The "grammar of compositions" half of the hypothesis needs the formal-language
side. There are exactly two known ways to let users grow a language's surface:

**Strategy A — open grammar extension.** Users add new productions to the
grammar (Racket readers/macros over s-expressions; SDF/Rascal/Spoofax
composable grammars; camlp4). Theory says this is dangerous in general:
*ambiguity of a context-free grammar is undecidable*, and composition of two
unambiguous CFGs can be ambiguous. Languages that survive this (Racket, Lean 4)
do so by heavy machinery: uniform s-expression skeletons, PEG-style ordered
choice, or full elaborator towers with hygiene (Lean's `notation`/`macro_rules`
elaborating to a small trusted kernel).

**Strategy B — fixed skeleton, open vocabulary.** The grammar's *productions*
are closed; users populate pre-allotted syntactic *slots* with new vocabulary.
Smalltalk is the historical proof (fixed message-send grammar, unlimited
selectors); Wyvern's type-specific languages are the modern type-directed
variant (the *expected type* selects the syntax's meaning).

**The lab Form System already chose Strategy B — correctly.** The seven
FormKinds (Infix, PrefixCall, PostfixMethod, MethodCall, BlockMethod,
KeywordBlock, MultiKeyword) are exactly the fixed slots of the skeleton; a form
declaration adds *vocabulary* (a trigger) to a slot, never a *production* to
the grammar. The decisive formal property:

> **Skeleton stability claim.** Vocabulary extension within fixed productions
> preserves the unambiguity and decidability of the skeleton grammar. Conflicts
> move from parse time (grammar ambiguity — undecidable in general) to
> resolution time (which contract owns this trigger at these types — decidable,
> finite candidate set, and the lab resolver already makes ambiguity a
> fail-closed error with trace evidence).

This is the fundamental reason the form layer can be "a language above the
language" without inheriting the macro-system tarpit: the grammar never
changes; only the dictionary does. F-01..F-06 (structural validity) plus
type-directed resolution plus ambiguity-as-error are the complete safety
discipline, and all three already exist in the lab implementation.

**4.1 The elaboration discipline (what "execution layer" means).**
The precedent stack for surface→kernel elaboration is mature: GHC elaborates
Haskell's enormous surface into Core (System F_C, ~weight of one page of
grammar); Lean 4 elaborates user notation into its kernel calculus; Racket's
"languages as libraries" builds whole languages as macro towers over a common
core. The invariant in all three: **the trusted boundary is the kernel; the
surface is checked by elaboration into it.** Igniter's analogue is sharper than
all three because the kernel is not just typed — it is *effect-classified,
content-addressed, and receipt-bearing*. Required elaboration properties,
restated from the precedents:

| Property | Meaning for forms | Status |
|---|---|---|
| Totality | every accepted form use has an expansion | lab resolver: miss = diagnostic |
| Determinism | one expansion result, independent of declaration/import order | needs **coherence rules** (§4.2) |
| Type-direction | expected/operand types select the candidate | lab resolver does this |
| Hygiene | form parameters cannot capture or shadow call-site names | F-rules partially; must be stated explicitly |
| Conservativity | expansion adds no semantics (Honesty theorem §3.2) | the proof obligation, TH-1 below |
| Resugarability | tooling can map kernel steps back to surface form | theory exists (Pombrio–Krishnamurthi resugaring); lab `ResolvedExpr` keeps both ends |

**4.2 The coherence problem is the real new risk — and it is a known one.**
Type-directed resolution with user-extensible instances is exactly the type
class mechanism, and it imports the type class *coherence problem*: if module A
and module B independently declare forms with the same trigger over overlapping
types, which wins — and does the answer depend on import order? Haskell's
answer (global uniqueness + orphan-instance warnings) and Rust's answer (orphan
rule: you may only declare an impl if you own the trait or the type) are the
two studied disciplines. For Igniter the natural rule is Rust-shaped and
P28-flavored:

> **Form ownership rule (candidate).** A form for contract C may be declared
> only in the module that declares C, or in the module that declares the
> trigger's vocabulary (§5). Resolution must be order-independent; any residual
> ambiguity is an error, never a priority race across module boundaries.

This is also where the form layer genuinely interacts with the packaging
mainline (RES-002): coherence is a property *of the import graph*, so its proof
gates on import resolution — one more reason the SPLIT sequencing (typed refs
and mainline first) was right.

---

## 5. Beyond Invocation: Vocabularies as the Unit of "Language Above the Language"

If §3–§4 hold, the interesting unit is not the single form but the **form
vocabulary**: a named, versioned set of forms shipped together — the user's
"рисунок" (picture) as a first-class artifact.

```text
vocabulary Query.Surface {            -- exploratory sketch, NOT adopted syntax
  form (rows) ".where"  { (pred) }   uses FilterRows
  form (rows) ".select" { (cols) }   uses ProjectRows
  form (a) "++" (b)                  uses ConcatRows
}

module Reports.Monthly
  speaks Query.Surface               -- explicit, named, import-visible
```

Evidence that this is the right unit — the lab has *already* invented three
proto-vocabularies independently, each currently trapped as ad-hoc fixture
conventions:

| Domain | What the lab built | What it actually is |
|---|---|---|
| View (IGV/Tailmix, arbre-like DSL) | `form "todo_card" (item)`; html/div/span builders | a **view vocabulary** over contracts producing HtmlNode |
| Query (LAB-QUERY / EXECUTE-QUERY) | QueryPlan records, filter evaluation conventions | a **query vocabulary** over storage-boundary contracts |
| Outcome/decision (PROP-044/047, FRONTIER-DECISION) | KDR conventions, kind guards, match lowering | a **decision vocabulary** over outcome records (`match` itself is MultiKeywordForm in the lab spec — the precedent that even control surface can be vocabulary) |

One mechanism would replace three (and future N) ad-hoc DSL temptations. The
stratification consequences:

1. **The kernel stays still while the language grows.** New domains mean new
   vocabularies (libraries), not grammar PROPs. Grammar churn — the most
   expensive kind of canon churn — drops toward zero after the slots are fixed.
2. **Vocabularies are honest, named, and importable** — P28 applied at the
   language level: *no ambient dialect*. A module declares what it `speaks`;
   readers see the dictionary at the top of the file. (Contrast: macro systems
   where any import may silently rebind syntax.)
3. **Vocabularies ride the packaging rails.** A package ships contracts + its
   vocabulary; the sealed-claim model (RES-002) extends naturally: the
   vocabulary is part of the package's declared surface, and the conservativity
   receipt (§6 TH-1) is part of its evidence.
4. **Profiles can gate vocabularies** the way they gate authority: a
   `payments_profile` could refuse view vocabulary in payment modules. Policy
   over *language shape*, compile-time, Postulate-10-style. (Flagged as a
   far-future possibility, not proposed.)
5. **The diagrams are renderable.** Because the kernel is a traced SMC, every
   program *is* a string diagram; forms are named boxes within it. The IGV
   direction and any future visual tooling get, for free, a mathematically
   canonical visual form in which sugar can be expanded/collapsed (resugaring,
   §4.1) — the picture metaphor closes into actual pictures.

---

## 6. Proof Obligations (falsifiable claims for future cards)

The theory is only worth keeping if it generates testable obligations. A future
proof-local card should mechanize these:

- **TH-1 (Conservativity receipt).** For a fixture corpus with N form uses:
  compile with forms → SemanticIR₁; hand-expand to kernel calls → SemanticIR₂;
  assert semantic equality (same nodes modulo `original_form` metadata, same
  fragment classes, same effect surface, same `contract_ref`s, same receipts on
  execution). This turns the Honesty theorem into a golden test.
- **TH-2 (Order independence / coherence).** Permute declaration and import
  order of vocabularies across ≥3 modules; resolution results must be
  bit-identical; engineered overlap must fail closed with both candidates named.
- **TH-3 (Skeleton stability).** Adding M new forms must not change the parse
  of any existing program (parse-tree golden equality on the full corpus).
- **TH-4 (Hygiene).** Form parameter names engineered to collide with call-site
  bindings must not capture; fixture matrix over all seven FormKinds.
- **TH-5 (Resugaring).** For every kernel-level diagnostic in a formed region,
  tooling can present both the surface span and the expanded invocation
  (already half-proven by `ResolvedExpr` carrying `original_kind` + spans).
- **TH-6 (Eliminability boundary).** Negative tests: attempts to express a
  *non*-eliminable feature as a form (new effect, recursion, dynamic target)
  must be structurally impossible or fail closed — establishing that the form
  layer cannot smuggle expressive power.

---

## 7. Risk Register (delta over LAB-CONTRACT-FORMS-P1 §13)

| Risk | Severity | Note |
|---|---|---|
| Dialect fragmentation (every team its own vocabulary) | HIGH | Mitigated by `speaks` explicitness + vocabulary as governed package artifact + gov review of published vocabularies; the kernel guarantee bounds the blast radius (any dialect is readable after expansion) |
| Coherence/orphan conflicts across packages | HIGH | §4.2 ownership rule; gates on import-resolution mainline; TH-2 |
| Theory overreach (claiming category theory where v0 needs none) | MEDIUM | PROP-002 already sets the precedent: state the algebra concretely, keep the categorical reading as the explanatory layer; this doc follows that discipline |
| `match`-as-form blurs kernel/surface boundary | MEDIUM | Decide explicitly in LAB-CONTRACT-FORMS-P2 whether control forms (MultiKeyword) are trust-gated (`trust_level` exists in the lab spec) or kernel-only |
| Resolution cost at scale | LOW | finite candidate sets per trigger; index already in lab registry |

---

## 8. Recommendation

**OPEN** — the strong hypothesis is theoretically coherent and lands on
standard, well-studied foundations at every joint:

```text
bricks            = generators of a traced symmetric monoidal theory   (PROP-002, already claimed)
pictures          = string diagrams; forms = named derived operations  (Joyal–Street / Selinger)
"language above"  = conservative / definitional extension              (logic; Felleisen eliminability)
grammar mechanism = fixed skeleton + open vocabulary                   (Smalltalk/Wyvern lineage; FormKind ×7 already built)
execution layer   = elaboration to a trusted kernel                    (GHC Core / Lean 4 / Racket lineage)
tooling           = resugaring                                         (Pombrio–Krishnamurthi)
new hard problem  = coherence/ownership of vocabularies                (type-class coherence; Rust orphan rule)
```

The undervalued part of the idea is confirmed: forms are not sugar for calls —
they are the *growth mechanism of the language itself*, with the kernel held
verifiably still. The cost center is identified and singular: **coherence**,
and it gates on the import-resolution mainline, which validates (does not
disturb) the existing SPLIT sequencing.

## 9. Exact Next Route

Unchanged spine, one addition and one amendment:

```
LAB-TYPED-CONTRACT-REF-P1            (unchanged — still first)

LAB-CONTRACT-FORMS-P2                (amended) — reconciliation of the PROP-Forms
  lineage now ALSO adopts the §6 proof obligations as its acceptance frame:
  keep/reduce/retire each feature against TH-1..TH-6, and decide the
  control-forms (MultiKeyword/trust_level) boundary explicitly.

LAB-FORM-VOCABULARY-P1               (new, after P2 and after import-resolution
  mainline lands) — proof-local: define 2 small vocabularies over one kernel
  fixture set; mechanize TH-1 (conservativity receipt), TH-2 (coherence), TH-3
  (skeleton stability). No grammar adoption; proof-local syntax only.

LAB-FORM-CONSTRUCTOR-P1              (unchanged — Gap-I, independent clock)
```

---

## Sources

Internal: PROP-002 (traced SMC claim, lines 152–154/453–454; operator algebra;
rejected paths), PROP-Forms-Enhanced-v0 (FormKind ×7, F-01..F-06, trust_level,
match-as-MultiKeywordForm), `form_registry.rs`/`form_resolver.rs`
(ResolvedExpr/TraceEvent shapes), PROP-044-path-b (lowering discipline
precedent), Covenant Axiom 1 / P10 / P27 / P28,
LAB-CONTRACT-FORMS-P1 report (terminology §3; honesty gates §8),
RES-002 (sealed-claim packaging), gov surface map 2026-06-10.

External literature (grounding, not authority):
- Joyal & Street, "The geometry of tensor calculus" (string-diagram coherence);
  Selinger, "A survey of graphical languages for monoidal categories".
- Felleisen, "On the expressive power of programming languages" (1991) —
  macro-eliminability vs expressive power.
- Definitional/conservative extension — standard mathematical logic.
- Ullrich & de Moura, "Beyond Notations: Hygienic Macro Expansion for
  Theorem Proving Languages" (Lean 4 elaborator).
- Tobin-Hochstadt et al., "Languages as Libraries" (PLDI 2011, Racket).
- Omar et al., "Safely Composable Type-Specific Languages" (ECOOP 2014, Wyvern).
- Pombrio & Krishnamurthi, "Resugaring: Lifting Evaluation Sequences through
  Syntactic Sugar" (PLDI 2014) and "Hygienic Resugaring of Compositional
  Desugaring" (ICFP 2015).
- Type-class coherence / orphan rules — Haskell (Wadler & Blott lineage) and
  Rust's orphan rule as the two studied ownership disciplines.
