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

## Current Delta (as of 2026-06-07)

| Feature area | Canon state | Lab state | Gap |
|---|---|---|---|
| Loop grammar (BudgetedLocalLoop) | `loop Name item in source max_steps: N` | `loop Name in source max_steps: N` (no item var) | Lab missing item variable |
| Recursive forms | `recursive contract R { decreases ... }` | `def f(...) -> T decreases fuel { ... }` (function style) | Completely different syntax |
| Service loop | PROP-037 territory (not in loop grammar) | Conflated with local loop grammar | Lab conflates service liveness with local loops |
| Loop TypeChecker | Gate 4 (OOF-L1/R2/R4) | Lab implements own diagnostics | Canon recipe available after gate 4 |
| Loop SemanticIR | Gate 5 (not yet) | Lab Rust impl | No conformance target yet |

**Next sync point:** after PROP-039 gate 4 closes, lab should update loop grammar
fixtures to match canon item-variable form and map its diagnostics to OOF-L1/R2/R4.

---

## Reference

- Portfolio index: `igniter-lab/.agents/portfolio-index.md`
- Canon proposals: `igniter-lang/.agents/work/proposals/`
- PROP-039: `igniter-lang/.agents/work/proposals/PROP-039-managed-local-recursion-and-loop-classes-v0.md`
- PROP-037: `igniter-lang/.agents/work/proposals/PROP-037-external-progression-service-liveness-v0.md`
