# Lab Governance Doc: Application Structure & Module Form — Proposal Readiness

**Track:** lab-application-structure-and-module-form-proposal-readiness-v0 (out-of-track research)
**Card:** LAB-LANGFORM-RESEARCH-P1 (doc 3 of 3)
**Date:** 2026-06-10
**Category:** governance / lang
**Route:** PROPOSAL READINESS / RESEARCH / LAB-ONLY / NO CANON PROP AUTHORED
**Status:** CLOSED — pain confirmed with evidence; three orthogonal needs separated; route recommended

---

## Scope note

Proposal-readiness research (not a canon PROP). Doc 3 of 3 (stdlib / packaging / application-form).
The within-module complement to doc 2's cross-module work; shares the visibility concern.

---

## 1. Headline — the pain is real and structural: the program is a **flat plane**

The user's report — *"a typical Igniter program is all on one flat plane: unclear entrypoint, no
hierarchy, what's internal vs public API, how modules compose"* — is confirmed by the grammar and by
every real fixture. The only structural levels are **module → contract → input/compute/output**.
Everything above `contract` is a flat sibling list; everything that *looks* like structure is
comments.

Three concrete pains, with evidence:

- **No entrypoint (in the language).** `entrypoint`/`section` are explicitly *not* reserved
  (Ch2 §2.2.1: "not part of Grammar Kernel v0… not parser-supported"). Selection is a **CLI
  concern only**: `--entry <Name>`, else the VM defaults to `contracts[0]` (main.rs). So which
  contract is "the program" is decided outside the source.
- **No hierarchy.** `SourceFile := ModuleDecl? ImportDecl* TopDecl*`; contracts are a flat
  `TopDecl` array. In `pursuit_guidance.ig` (8 contracts) nothing marks `ZemGuidance` as the
  surface and `KalmanPredict`/`ObservationInspector` as helpers — only `-- ──` comment banners.
  In `outcome_variant.ig`, 1 router + 10 `Build*` contracts are flat siblings; the *naming
  convention* `Build*` is the only signal that they're helpers.
- **No public/internal.** There is **zero** visibility mechanism — no `public`/`private`/`internal`/
  `export`. Any contract can `call_contract("AnyOther", …)`. (`affects external|internal` in Ch12 is
  effect-*target*, not visibility; PROP-045 `intent` is *purpose*, not visibility.)
- **Composition is stringly-typed.** One contract uses another via `call_contract("Name", args)`
  — a string literal. The TypeChecker *can* resolve literal names to return types, and the VM builds
  a name→bytecode dispatch table, so the DAG is **known to the compiler** — but it is **invisible
  and unrefactorable in the source** (rename a contract → silently break every string caller).

---

## 2. The deep diagnosis — the DAG is real but author-invisible

Ch1 declares Igniter "a language in which every computation is a **declared, observable, time-aware
dependency graph**." Yet the SemanticIR stores contracts as a **flat array** with no program-level
graph, and the source gives the author **no syntax to express the graph's shape or boundaries**.
The dependency graph is *real in the compiler and invisible in the source.* The structure problem
is, precisely: **make the implicit DAG and its boundaries author-visible.**

This is not mere ergonomics — it is a **Covenant-honesty** gap. The Covenant's whole thesis is that
load-bearing facts must be *declared*, not hidden in bodies/config/heuristics. A module's public
surface, its entrypoint, and its internal-vs-exposed split are exactly such load-bearing facts.
An **undeclared public API is a hidden assumption** — the same category the language refuses
elsewhere. So `public`/`internal`/`entrypoint` are not foreign bolt-ons; they are the missing
*structural* honesty axis, alongside the epistemic/effect/constraint/audit axes.

---

## 3. Three orthogonal needs — do not conflate

| Need | Question it answers | Smallest form | Depends on |
|------|--------------------|---------------|-----------|
| **Entrypoint** | which contract is the program's evaluation target / surface? | a source marker (e.g. `entry contract …` or a module `entry:` field) | nothing — standalone |
| **Visibility** | which contracts/types are public vs internal? | `public`/`internal` modifier on contracts/types | import resolution (doc 2) for *cross-file* meaning |
| **Grouping / hierarchy** | how to organize 20–100 contracts into legible units? | sub-modules / `section` / nested namespaces | larger; defer |

Conflating these is the failure mode the spec already worries about (Ch2 §2.2.1 warns `section`
must not "accidentally become module, namespace, visibility, lifecycle, dependency, or
evaluation-order syntax"). Keep them separate.

---

## 4. Proposed shapes (designed, not adopted)

**Entrypoint (smallest, highest leverage).** A source-level way to name the program's surface
contract(s), replacing "CLI `--entry` or `contracts[0]`". Two candidate forms:
- a contract modifier: `entry pure contract FlyIntercept { … }`; or
- a module header field: `module Lab.Pursuit { entry: FlyIntercept }`.
Value: tooling (and the **debugger-textbook**, LAB-DEBUGGER-FEASIBILITY-P1) no longer has to *guess*
the entry; an `.igapp` manifest gains a real `entrypoint` field; multi-entry programs declare intent.

**Visibility.** `public` / `internal` on contracts and types. Default **internal** (honest: you opt
*in* to a public surface). Cross-module, an `import` (doc 2) may only bind `public` symbols; within
a module everything is callable. The module's public set *is* its content-addressed interface
(doc 2 §4). This single modifier simultaneously: (a) documents the API, (b) gives `call_contract`
an enforceable boundary, (c) feeds the packaging interface.

**Grouping (deferred).** For large programs, sub-modules / `section`. Explicitly out of scope for
the first route — naming conventions + comments suffice until programs are large; getting
entrypoint + visibility right first is more valuable.

**Make composition first-class (optional, later).** A `uses Other` / typed contract-reference could
replace stringly-typed `call_contract("Other")`, making the DAG edge refactor-safe and tool-
visible. The compiler already resolves literal names, so this is surfacing existing knowledge, not
new analysis. Flag for a later route; not required for the first structural step.

---

## 5. Forbidden / closed surfaces

- No grouping/`section`/nested-module grammar in the first route (deferred).
- `entrypoint`/`section` remain *non-canon* until a real PROP — this doc designs, does not reserve.
- No change to `call_contract` semantics in the first route (typed contract-refs are a later option).
- Visibility's *cross-file* enforcement depends on import resolution (doc 2) — within-file
  visibility can be specified first, cross-file meaning lands with the keystone.
- No canon PROP authored; no stable API; no compiler/parser changes.

---

## 6. Recommended route

1. **PROP-ENTRYPOINT (standalone, smallest)** — a source-level entrypoint marker + `.igapp`
   `entrypoint` field. Independent of everything; immediately helps tooling, the debugger-textbook,
   and program legibility. *Recommended first structural step.*
2. **PROP-MODULE-VISIBILITY** — `public`/`internal` (default internal) on contracts/types. Shared
   with doc 2 step 2; within-file specifiable now, cross-file enforcement lands with import
   resolution. Frame it as the **structural honesty axis** (declared public surface).
3. **(later) typed contract-references** — replace stringly `call_contract` for refactor-safety.
4. **(deferred) sub-module / section grouping** — only when program sizes demand it.

Cross-doc: entrypoint is fully standalone and is the cleanest **first concrete win** of the whole
triad; visibility is shared with packaging (doc 2) and only reaches full power once import
resolution (doc 2 keystone) lands.

---

## Gap Packet

```
doc:       igniter-application-structure-and-module-form-proposal-readiness / v0  (3 of 3)
status:    CLOSED — readiness; pain confirmed; no canon PROP authored
authority: governance / lang / lab_only
date:      2026-06-10

pain_confirmed: flat plane — only module→contract→io; contracts are flat siblings
  entrypoint: LANGUAGE-ABSENT (Ch2 §2.2.1 not reserved); CLI-only (--entry / contracts[0] default)
  hierarchy:  none beyond module name; pursuit_guidance 8 contracts, no main/helper marking (comments only);
              outcome_variant 1 router + 10 Build* = naming-convention only
  visibility: ZERO public/private/internal/export; any contract calls any (affects=effect-target, intent=purpose)
  composition: stringly-typed call_contract("Name") — compiler knows the DAG, source hides it, rename breaks callers
diagnosis: Ch1 says "computation is a dependency graph" but the DAG is compiler-real / source-invisible;
           undeclared public surface = a hidden assumption → STRUCTURAL HONESTY gap (Covenant-aligned)
three_needs (don't conflate): entrypoint | visibility | grouping
proposed:  entry marker (modifier or module field) + .igapp entrypoint | public/internal (default internal,
           = content-addressed module interface) | grouping DEFERRED | typed contract-refs LATER
route:     PROP-ENTRYPOINT (standalone, first win, helps debugger-textbook) → PROP-MODULE-VISIBILITY
           (shared w/ doc 2) → (later) typed contract-refs → (deferred) section/sub-module grouping
closed:    section/nesting grammar (deferred) | call_contract change (route 1) | canon PROP authoring
canon_changed: NO   implementation_authorized: NO
```

---

## Authority

lab-only — proposal-readiness research; no canon claim, no stable surface, no PROP authored, no
compiler/parser changes. `entrypoint`/`section` remain non-canon (designed, not reserved); Ch2 §2.2.1
referenced as-is. Lab behavior not accepted as canon. Informs future gate decisions; does not make
them.
