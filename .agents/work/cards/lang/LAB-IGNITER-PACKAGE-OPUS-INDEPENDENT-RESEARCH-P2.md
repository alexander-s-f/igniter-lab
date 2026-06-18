# Card: LAB-IGNITER-PACKAGE-OPUS-INDEPENDENT-RESEARCH-P2 — independent package-manager thesis, competing with Gemini

**Lane:** standard / independent deep research  
**Status:** CLOSED (independent research)  
**Date opened:** 2026-06-18  
**Date closed:** 2026-06-18  
**Delegate label:** OPUS-PACKAGES-INDEPENDENT-B  
**Skill:** idd-agent-protocol  
**Authority:** Lab research only. No code. No package spec authority. No canon. This card is designed to
compete with, not merely summarize, Gemini's Round 1.

## Why this card exists

Gemini Round 1 converged on a local workspace + content-addressed lock/provenance model. That may be
right, but we want a second Opus agent to think harder and more adversarially:

- Can a simpler model beat it?
- Is "package manager" the wrong abstraction?
- Should Igniter use workspace manifests only and defer packages much longer?
- Are generated artifacts in packages a mistake?
- Is lock/provenance the first slice, or should import ownership come first?

This is not a validation card. It is an independent competing thesis.

## Bias control

To reduce anchoring:

1. First read live Igniter surfaces and the Projection Dialects P0 packet.
2. Form an initial thesis before reading Gemini synthesis.
3. Then read Gemini Round 1 and explicitly compare: where your thesis agrees, diverges, or beats it.

## Read first — Igniter, before Gemini

- `lab-docs/lang/lab-igniter-projection-dialects-p0-v0.md`
- `igniter-compiler/src/project.rs`
- `igniter-compiler/src/main.rs`
- `igniter-compiler/src/igweb.rs`
- `igniter-web/src/lib.rs`
- `igniter-server/src/protocol.rs`
- `igniter-machine/IMPLEMENTED_SURFACE.md` if present in this checkout
- current docs/cards around project mode, overlays, `.igweb`, `.igv`, server runner, and package/web
  packaging if present.

## Then read Gemini Round 1

- `lab-docs/lang/lab-igniter-package-manager-research-round1-v0.md`
- `lab-docs/lang/lab-igniter-package-research-synthesis-gemini-p1-v0.md`
- shard reports only as needed.

## Research stance

You are allowed to propose a different answer from Gemini. Explore at least three alternative models:

1. **Workspace-only, no packages yet** — just local module roots and import ownership.
2. **Source-only package** — no generated/compiled artifacts in package.
3. **Dual package** — source + generated + compiled/provenance.
4. **Lockfile-first** — package manager begins as reproducibility ledger.
5. **Import-ownership-first** — package manager begins by preventing namespace/phantom imports.
6. **Capsule/service recipe package** — packaging starts from deployable service artifacts, not source.

You may reject some of these, but evaluate them.

## Questions to answer

1. What is the smallest concept that deserves the name "package" in Igniter?
2. What problem should be solved first: import ownership, reproducibility, artifact distribution,
   deployable service bundles, or developer ergonomics?
3. Is generated artifact inspection enough reason to include generated artifacts in packages?
4. Should compiled `.igapp` ever be packaged, or only produced as build output?
5. Should v0 have any lockfile, or only a deterministic workspace graph?
6. What does package identity mean before a registry exists?
7. What is the relationship between package identity and module namespace?
8. How do projection dialect lowerers participate without becoming install scripts?
9. How do host capabilities stay out of packages while still being declared?
10. What would make the Gemini direction fail in practice?

## Output contract

Write exactly one report:

`lab-docs/lang/lab-igniter-package-opus-independent-research-p2-v0.md`

Then update only this card with a closing report.

## Required report sections

1. Independent thesis, written before comparing Gemini.
2. Live Igniter surface observations.
3. Alternative model comparison table.
4. What Gemini got right.
5. What Gemini got wrong or overfit.
6. Strongest proposed v0, with rationale.
7. Strongest rejected v0, with rationale.
8. Risk ledger.
9. Next-card recommendations.

## Closed surfaces

- No code.
- No package spec authority.
- No canon claim.
- No edits to Gemini reports.
- No edits to parent package card.
- No CLI/config implementation.
- Do not touch parallel `igniter-web` P12 work.

## Acceptance

- [x] Report states an independent thesis before Gemini comparison (§1; anchoring honestly disclosed).
- [x] Report evaluates all six candidate models (§3).
- [x] Report identifies a smallest v0 (import-ownership workspace) and a rejected tempting alternative (lockfile-first).
- [x] Report explicitly compares against Gemini Round 1 (§4–§5).
- [x] Report names seven risks (§8).
- [x] No code changed.

---

## Closing report — 2026-06-18

**Outcome:** Independent, adversarial thesis delivered — it **diverges** from Gemini on framing + ordering
while **converging** on the first implementation card.

**Deliverable:** `lab-docs/lang/lab-igniter-package-opus-independent-research-p2-v0.md` (9 sections).

**Independent thesis:** "**Package** is the wrong first abstraction. The first problem is **import
ownership across module roots** — not distribution, reproducibility, or artifacts." Grounded in
`project.rs`: it computes the import closure + `OOF-IMP4` but does NOT restrict *which* module may import
*which* → phantom/ownership-free imports are reachable today with zero registry. That is the one real,
compiler-native gap.

**Model verdicts:** WINNER = models 1+5 fused (workspace + import-ownership). REJECTED for v0: model 4
lockfile-first (strongest temptation — but local-path + deterministic lowering + existing `source_hash`
= no reproducibility gap yet), model 3 dual/triple package (packaging generated/compiled invites the very
drift a lockfile must then police), model 6 capsule/ServiceRecipe (a deploy concern the machine already
owns, behind the live-gate).

**Divergence from Gemini (adversarial):** (1) lock/provenance is NOT a v0 pillar — defer harder than the
validation's REVISE; (2) don't call it a "package" — call it a workspace member / module-namespace owner;
(3) never package generated/compiled artifacts; (4) the existing `source_hash`/`blake3` substrate should
be reused if/when a lock arrives. **Agreement:** local-first, no-install-scripts, capabilities-declared,
projection-dialects-pure, registry/version-solving deferred.

**Convergence:** same first card — `LAB-IGNITER-PACKAGE-WORKSPACE-RESOLVER-P3` — but reframed as
**import-ownership** (not "package manager") with the roadmap reorder: ownership FIRST; lockfile only when
remote/mutable inputs exist; generated/compiled NEVER packaged.

**Risks (7):** over-strict ownership breaks existing apps; ownership rule under-specified; deferring lock
risks future drift (gate: mandatory on first remote dep); no committed generated = lost diff-review;
cross-member cycles need a check; roadmap fork between the two package threads (mitigate: converge on one
card); my own anchoring (disclosed).

**No code changed.** No Gemini reports or the parent card edited.
