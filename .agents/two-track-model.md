# Two-Track Development Model

**Adopted:** 2026-06-07
**Scope:** igniter-lang (canon) ↔ igniter-lab (frontier/lab)
**Maintained by:** Portfolio Architect Supervisor

---

## The Model

Canon and lab are two independent implementations of the same language, moving in
parallel and transferring the best solutions between each other through a
bidirectional channel.

```
igniter-lab (frontier impl) ──pressure / R248 evidence──▶ igniter-lang (canon)
igniter-lang (spec / proof) ──recipe / conformance fixtures──▶ igniter-lab
```

Neither track owns the other. Neither track is subordinate.

---

## Why Two Tracks

A single track collapses into implementation inertia. If the Rust compiler in lab
is allowed to define language semantics by precedent, the design pressure loop
stops: there is no reason to write proposals, proofs, or conformance fixtures
because "Rust already does it."

Two tracks kept in healthy tension:

- **Lab goes first** on some features: frontier pressure (R248 fixtures, verify
  scripts, integration tests) surfaces real complexity before canon commits to a
  grammar form.
- **Canon goes first** on some features: a PROP + gate proof locks down the
  semantics, grammar, and OOF diagnostics before lab needs to implement
  conformance.
- **Neither direction is permanent.** The relationship rotates per feature.

The discipline of "canon first" and "lab first" is what makes both tracks
develop independently and then converge on the same correct design.

---

## Final Target State

| Track | Final Role |
|---|---|
| `igniter-lang` | Language standard: proposals, grammar proofs, conformance fixtures, OOF registry, canonical semantics |
| `igniter-lab` | Production runtime: certified conformant against canon; runs under load |

Lab becomes production after passing canon conformance fixtures. Canon provides
the certification surface; lab earns the "certified conformant" status.

---

## Transfer Protocol

### Lab → Canon (pressure)

When lab discovers complexity, edge cases, or real-world usage that should
inform grammar design:

1. Lab produces R248 fixtures, verify scripts, or integration tests.
2. These are accepted as **pressure evidence only** (not canon grammar).
3. Canon opens a PROP to evaluate the evidence and propose a canonical form.
4. If the canonical form differs from the lab form, that is expected — it means
   the design improved.

### Canon → Lab (recipe)

When canon closes a gate (parser proof, TypeChecker proof, etc.):

1. Canon has locked grammar forms, OOF diagnostics, and conformance fixtures.
2. Lab updates its implementation to match canon grammar.
3. Lab runs canon conformance fixtures as integration tests.
4. Delta between lab grammar and canon grammar becomes the conformance gap to close.

---

## Delta Balance Rule

At regular intervals (every major gate closure), compare:

| Dimension | Canon state | Lab state | Action |
|---|---|---|---|
| Grammar forms | Canonical fixture | Lab fixture | Update lab to canon form |
| OOF codes | Canon registry | Lab diagnostics | Map lab codes → canon codes |
| Pipeline stages | Proof closed | Lab impl | Lab implements canon spec |
| Conformance | Canon fixtures exist | Lab passes? | Run canon fixtures in lab |

The goal is not zero delta — delta is normal. The goal is **visible delta** that
is tracked and deliberately closed when the time is right.

---

## Why Boundary Rules Matter

The boundary rules (canon not canon, not authorized, etc.) are not about lab
being inferior. They are about keeping both tracks in motion.

Without boundaries:
- Implementation inertia replaces design authority.
- Lab R248 fixtures become de-facto grammar without governance.
- Canon has nothing to contribute because "Rust already does it."
- Lab has no external conformance target because there are no canon fixtures.

With boundaries:
- Canon produces proposals, proofs, and fixtures at its own pace.
- Lab produces frontier experiments, runtime behavior, and pressure evidence.
- Transfer is deliberate and bidirectional.
- Certification becomes meaningful.

---

## Delta History

### Sync pass: 2026-06-07 (PROP-039 gates 3/4/5 closed)

| Delta | Before | After | Status |
|---|---|---|---|
| D1: BudgetedLocalLoop item variable | `loop Name in source` (implicit) | `loop Name item in source` (explicit) | ✅ closed |
| D2: Source type | `Array[Integer]` | `Collection[Integer]` (canon: OOF-L1 requires Collection[T]) | ✅ closed |
| D3: Recursive form | `def f(...) -> T decreases fuel { ... }` | `fuel_bounded contract` + `recursive contract` | ✅ closed in fixtures |
| D4: Service loop boundary | Mixed in PROP-039 file | Annotated as PROP-037 territory, inline form commented out | ✅ boundary marked |

### Remaining Conformance Gaps (as of 2026-06-08)

| Gap | Description | Action needed |
|---|---|---|
| ~~G1: Rust compiler item-variable~~ | ✅ closed 2026-06-07 — parser.rs/classifier.rs/typechecker.rs/emitter.rs/vm/compiler.rs updated; verify_g1_canon_loop.rb PASS | — |
| ~~G2: Rust compiler modifiers~~ | ✅ closed 2026-06-07 — `recursive`/`fuel_bounded` added to modifier match; `Decreases`/`MaxSteps` BodyDecl variants added; verify_loops.rb PASS | — |
| ~~G3a: OOF-R2/R4 in classifier~~ | ✅ closed 2026-06-08 — classifier.rs adds OOF-R2 (recursive missing decreases) and OOF-R4 (fuel_bounded/decreases-fuel missing max_steps); verify_g3_conformance.rb PASS | — |
| ~~G3b: FiniteLoop parser~~ | ✅ closed 2026-06-08 — `for Name item in source { body }` accepted by parser.rs; max_steps=None → loop_class="finite"; VM executes via u64::MAX fuel sentinel; verify_g3_conformance.rb PASS | — |
| ~~G3c: IR shape kind="loop_node"~~ | ✅ closed 2026-06-08 — emitter.rs emits kind="loop_node" (was "loop") + loop_class, termination, source_ref, max_steps at top level; vm/compiler.rs updated; verify_g3_conformance.rb PASS | — |
| ~~G4: Body semantics~~ | ✅ closed 2026-06-08 — `lead` keyword in parser.rs, OOF-L5/L7/L8 in classifier.rs + typechecker.rs, `body=[lead_node*,compute_node*]` + `item_type` in emitter.rs; two-track `body` (canon) / `body_nodes` (VM exec); verify_g4_body_semantics.rb 18/18 PASS | — |
| ~~G5: recur() primitive~~ | ✅ closed 2026-06-08 — OOF-R1/R5/R6/R7 in typechecker.rs, `recur_call` sub-expr node in emitter.rs; verify_g5_recur.rb 18/18 PASS | — |
| ~~G6: OOF-L1 semantic alignment~~ | ✅ closed 2026-06-08 — TypeChecker now emits OOF-L1 for FiniteLoop source not Collection[T] (canon meaning). Lab parser OOF-L1 ("unbounded loop") remains for `loop` without max_steps — lab-local, acceptable delta. | — |

### Sync pass: 2026-06-08 (String Core track closed)

| Delta | Before | After | Status |
|---|---|---|---|
| D5: String stdlib surface | No text operations in canon typechecker (OOF-TY0 for all calls) | `Text` type + 14 pure ops (concat/trim/predicates/split/replace/lengths/slices); `stdlib.text.*` IR path | ✅ closed |

Canon `TEXT_STDLIB_FNS` registry in `typechecker.rb` — 14 entries, `infer_text_call` method.
String literals (`type_tag="String"`) accepted as `Text` args (v0 compat rule).
`Collection[Text]` return type for `split` proven via parametrised type IR.
SemanticIR: `kind: "call"`, `fn: "stdlib.text.*"` — no new IR kind, consistent with integer ops.

Lab Rust symmetry (`Lab STR-CORE`): **not yet authorized**. Future conformance gate.

**verify_g_string_core status:** ✅ 60/60 PASS — String Core closed 2026-06-08.

---

**All updated fixtures now parse cleanly through canon pipeline:**
`grammar_version="loop-v0" · sir=OK · pass=ok · type_errors=[]`

Files updated:
- `igniter-lab/igniter-compiler/fixtures/loops/loop_accumulator.ig`
- `igniter-lab/igniter-compiler/fixtures/conformance/source/loops_and_recursion.ig`

**verify_g1_canon_loop.rb status:** ✅ PASS — G1 closed 2026-06-07.
**verify_loops.rb status:** ✅ PASS — G2 closed 2026-06-07. Full conformance file compiles and executes.
**verify_g3_conformance.rb status:** ✅ PASS 14/14 — G3 closed 2026-06-08. G3a OOF-R2/R4 + G3b FiniteLoop + G3c IR shape all verified.
**verify_g4_body_semantics.rb status:** ✅ PASS 18/18 — G4 closed 2026-06-08. `lead` keyword, OOF-L5/L7/L8, canon `body` + VM `body_nodes` two-track, `item_type`. Non-literal initial OOF-L5 precision-tested.

---

## Reference

- Portfolio index: `igniter-lab/.agents/portfolio-index.md`
- Canon proposals: `igniter-lang/.agents/work/proposals/`
- PROP-039: `igniter-lang/.agents/work/proposals/PROP-039-managed-local-recursion-and-loop-classes-v0.md`
- PROP-037: `igniter-lang/.agents/work/proposals/PROP-037-external-progression-service-liveness-v0.md`
