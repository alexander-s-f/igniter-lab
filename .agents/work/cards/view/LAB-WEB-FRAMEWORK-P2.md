# LAB-WEB-FRAMEWORK-P2

**Card ID:** LAB-WEB-FRAMEWORK-P2
**Category:** view
**Track:** lab-igniter-web-framework-siteartifact-url-contract-proof-v0
**Route:** LAB / VIEW / PROOF-LOCAL
**Date:** 2026-06-07
**Status:** DONE

---

## D — Deliverables

- `igniter-lab/lab-docs/view/lab-igniter-web-framework-siteartifact-url-contract-proof-v0.md`
  — Research and model document: SiteArtifact JSON schema, URL contract definition (required
  routes, forbidden routes, canonical policy, hreflang policy, locale fallback policy),
  generator neutrality stance, fixture descriptions, full proof matrix, gaps, roadmap position,
  and recommended next card.

- `igniter-lab/igniter-view-engine/fixtures/siteartifact_url_contract/igniter_org_v0.json`
  — Primary fixture modeling the full `igniter-org` site structure with all required routes,
  multi-locale trees (en/ru/uk), translated and fallback pages, hreflang maps, and output policy.

- `igniter-lab/igniter-view-engine/fixtures/siteartifact_url_contract/valid_minimal.json`
  — Minimal valid site fixture (2 locales, 2 pages) demonstrating model is not over-specified.

- `igniter-lab/igniter-view-engine/fixtures/siteartifact_url_contract/invalid_forbidden_routes.json`
  — Forbidden-routes fixture: 6 forbidden route paths covering all 4 forbidden pattern families,
  plus 2 structural violation examples (same-path equivalents, docs-path equivalents). All entries
  must be rejected by the proof runner.

- `igniter-lab/igniter-view-engine/proofs/siteartifact_url_contract_proof.rb`
  — Self-contained Ruby proof runner (no gems beyond stdlib). Loads fixtures, runs 10 PASS
  checks per valid fixture and 2 FAIL checks against the forbidden-routes fixture. Prints a
  pass/fail matrix. Exits 0 on all-pass.

---

## S — Summary

P2 defines a generator-neutral, language-neutral `SiteArtifact` JSON model that encodes the
routing contract for `igniter-org`'s multi-locale static site. The model covers the full route
tree (RouteNode), per-page metadata (PageDescriptor), locale equivalents map, canonical URL
policy, hreflang policy, source content refs, and generated output policy. A self-contained
Ruby proof runner validates three fixture files: two pass fixtures covering all required route
shapes, locale distinctness, hreflang completeness, fallback page marking, output path
separation, and path hygiene; and one fail fixture confirming that all forbidden route shapes
(`/docs/i18n/**`, `/docs/tutorial/en/**`, `/content/**`, `/_site/**`) and structural
violations (same-path locale equivalents, docs-path locale equivalents) are mechanically
rejected. All 22 checks pass with exit code 0. This addresses the igniter-org long-path failure
risk by formalizing the URL contract as a testable artifact, independent of Vite, Jekyll,
or any other generator.

---

## T — Tensions / Risks

1. **Generator coupling pressure** — As the model is used in P3 (content compiler prototype),
   there will be pressure to add Jekyll-specific field names or Vite config conventions directly
   into the `SiteArtifact` schema. This must be resisted. If generator-specific extensions are
   needed, they should live in a separate overlay layer, not in the core model.

2. **Fixture coverage gaps** — The `igniter_org_v0.json` fixture covers tutorial and lab routes
   but does not include `/spec/` pages (e.g. `/ru/spec/ch1-identity/`). A future hardening pass
   should add spec routes before P5 (i18n + sitemap). Under-coverage means the contract does
   not fully exercise the full site surface.

3. **i18n fallback ambiguity at the locale root level** — The model marks `fallback_locale` on
   `PageDescriptor` entries, but the root locale pages (`/ru/`, `/uk/`) are also fallbacks in
   practice. The current fixture marks `root-redirect` as `fallback_locale: "en"` which is
   technically correct, but the semantics of fallback for structural/redirect pages versus
   content pages are not yet fully distinguished. This ambiguity could affect how P3 emits
   canonical tags for locale root pages.

---

## R — Recommended Next

**LAB-WEB-FRAMEWORK-P3 — Tutorial and Specification Content Compiler Prototype**

Rationale: P2 provides the `SiteArtifact` model as a formal routing configuration. P3 should
consume this model as input and prove that a Ruby content compiler can read markdown with YAML
frontmatter, apply all safety guards (no absolute paths, no `file://`, no `javascript:`,
HTML escaping), inject translation banners, and emit canonical tags and hreflang links
derived from the `SiteArtifact` fixture. This makes the P2 model observable as actual HTML
output and gives P5 (i18n + sitemap generation) a stable proof surface to extend.

Alternative: A route-contract hardening rerun to add `/spec/` routes and sitemap fields to the
P2 fixture before proceeding to P3. Recommended only if `igniter-org` spec route coverage
becomes urgent before P3 is started.

---

## Proof Matrix

```
......................
========================================================================
SiteArtifact URL Contract Proof — Results Matrix
========================================================================
  FIXTURE                            CHECK                                        STATUS
------------------------------------------------------------------------
  igniter_org_v0.json                required_routes_present                      PASS
  igniter_org_v0.json                no_forbidden_routes_in_route_tree            PASS
  igniter_org_v0.json                locale_equivalents_are_distinct              PASS
  igniter_org_v0.json                locale_equivalents_no_forbidden_paths        PASS
  igniter_org_v0.json                fallback_locale_set_for_en_only_pages        PASS
  igniter_org_v0.json                hreflang_entries_complete                    PASS
  igniter_org_v0.json                output_paths_separate_from_source            PASS
  igniter_org_v0.json                no_absolute_local_paths                      PASS
  igniter_org_v0.json                no_file_uri                                  PASS
  igniter_org_v0.json                no_javascript_scheme                         PASS

  valid_minimal.json                 required_routes_present                      PASS
  valid_minimal.json                 no_forbidden_routes_in_route_tree            PASS
  valid_minimal.json                 locale_equivalents_are_distinct              PASS
  valid_minimal.json                 locale_equivalents_no_forbidden_paths        PASS
  valid_minimal.json                 fallback_locale_set_for_en_only_pages        PASS
  valid_minimal.json                 hreflang_entries_complete                    PASS
  valid_minimal.json                 output_paths_separate_from_source            PASS
  valid_minimal.json                 no_absolute_local_paths                      PASS
  valid_minimal.json                 no_file_uri                                  PASS
  valid_minimal.json                 no_javascript_scheme                         PASS

  invalid_forbidden_routes.json      all_forbidden_routes_rejected                PASS
  invalid_forbidden_routes.json      all_forbidden_equiv_violations_caught        PASS
------------------------------------------------------------------------
Total: 22  |  PASS: 22  |  FAIL: 0
========================================================================
Result: ALL CHECKS PASSED

Exit code: 0
```
