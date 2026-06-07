# LAB-WEB-FRAMEWORK-P1

**Card ID:** LAB-WEB-FRAMEWORK-P1
**Category:** view
**Track:** lab-igniter-web-framework-research-and-view-engine-roadmap-v0
**Route:** research-only · no source code · no site edits · no lang changes
**Date:** 2026-06-07
**Status:** DONE

---

## D — Deliverables

- `lab-docs/view/lab-igniter-web-framework-research-and-view-engine-roadmap-v0.md`
  (roadmap document — inventory, requirement map, risk map, staged roadmap P1–P7)
- `.agents/work/cards/view/LAB-WEB-FRAMEWORK-P1.md` (this receipt)

---

## S — Summary

The lab currently has a mature view artifact pipeline (405/405 proofs across P1–P9 in `igniter-view-engine`) covering DSL compilation, SSR, JS hydration, slot-contract linkage, and diagnostic reporting. The `igniter-org` site has active i18n, routing, and tutorial content pipeline pressure that is not yet formally modeled as lab artifacts. The term "Igniter Web Framework" is most honestly described in stages: view artifact compiler (proven), static site artifact model (P2 target), content compiler with safety guards (P3), layout primitives (P4), i18n/hreflang/sitemap (P5), and forms/view binding (P6). The GUI engine and IDE preview are relevant as design signals but are not on the critical path for static site or tutorial delivery.

---

## T — Tensions / Risks Identified

1. **Framework drift** — Scope pressure to declare "Igniter Web Framework" as a product before grammar, routing, and artifact formats are stable. Mitigated by staged card gates and explicit non-claim boundaries.
2. **Public/canon claim drift** — Site copy and lab docs could begin overstating readiness. Mitigated by the pre-v1 language policy from `lab-docs/tutorial/site-projection-excerpts.md`, which must be applied to all new surfaces.
3. **Build pipeline divergence** — `igniter-org`'s hand-authored `build-docs.js` is not a reusable lab artifact. If P3 produces a competing compiler without feeding back to `igniter-org`, the two pipelines diverge. Mitigated by treating `igniter-org` as the consumer and pressure source, not as something to replace.

---

## R — Recommended Next

**LAB-WEB-FRAMEWORK-P2** — Route Map and Static Site Artifact Model.
Read the `igniter-org` routing policy and i18n pipeline design. Define a `SiteArtifact`
JSON model (route tree, page descriptor, locale manifest). Write a Ruby proof runner
that validates a route tree fixture against the routing policy. No edits to `igniter-org`,
`igniter-lang`, or any source package.
