# LAB-WEB-FRAMEWORK-P2-A

**Card ID:** LAB-WEB-FRAMEWORK-P2-A
**Category:** view
**Track:** lab-igniter-web-framework-siteartifact-jekyll-contract-alignment-v0
**Route:** LAB / VIEW / PROOF-LOCAL / HARDENING
**Date:** 2026-06-07
**Status:** DONE

---

## D — Deliverables

| File | Action |
|---|---|
| `igniter-lab/igniter-view-engine/fixtures/siteartifact_url_contract/igniter_org_v0.json` | Updated — added 5 new route families and upgraded lab sub-pages and tutorial pages to tri-locale |
| `igniter-lab/igniter-view-engine/proofs/siteartifact_url_contract_proof.rb` | Updated — added 4 new checks (checks 11–14), total raised from 22 to 30 |
| `igniter-lab/lab-docs/view/lab-igniter-web-framework-siteartifact-jekyll-contract-alignment-v0.md` | New — hardening pass documentation |
| `igniter-lab/.agents/work/cards/view/LAB-WEB-FRAMEWORK-P2-A.md` | New — this card receipt |

---

## S — Summary

This card is a hardening pass on the P2 SiteArtifact proof. Five route families present in the
`igniter-org-jekyll` candidate's `docs/route-contract.md` and `_data/locale_groups.yml` were
absent from the `igniter_org_v0.json` fixture: `language-covenant`, `language-specification`,
`language-proposals`, `tutorial-vm-candidate-proof`, and `lab-design-system`. These were added
with complete tri-locale coverage (en/ru/uk), correct hreflang maps, and locale_equivalents
entries. Existing lab sub-pages (`lab-compiler`, `lab-vm`, `lab-ide`, `lab-view`, `lab-gui`)
and `tutorial-compiler-first-proof` were upgraded from en-only to tri-locale, reflecting the
localized routes present in the Jekyll candidate. Four new proof checks validate Jekyll-contract
route family coverage, tri-locale hreflang/locale_equivalents completeness, fallback hreflang
hygiene, and tutorial slug localization. All 30 checks pass with exit code 0. The Jekyll
candidate is used as read-only pressure evidence throughout; no generator-specific fields were
introduced into the SiteArtifact model.

---

## T — Tensions / Risks

1. **Fixture drift from Jekyll candidate.** The `locale_groups.yml` and `_pages/` in
   `igniter-org-jekyll` may continue growing (e.g. spec chapter routes). Each new Jekyll
   surface that lacks a fixture counterpart will fail `jekyll_contract_route_families_present`
   only after it is manually added to `JEKYLL_CONTRACT_ROUTES` in the proof runner. There is
   no automated sync; a human must decide when to extend the constant.

2. **`valid_minimal.json` is not exercising the new tri-locale checks.** The minimal fixture
   uses only `en` and `ru`, so check 12 (`locale_equivalent_completeness`) runs but does not
   exercise the three-locale completeness path. A future FAIL-fixture for partial tri-locale
   coverage would improve negative-path coverage for checks 12 and 13.

3. **`canonical_path` key mismatch for home page.** The `home` page has `canonical_path: "/en/"`
   but `locale_equivalents` is keyed by `"/"`. The check 12 lookup was extended to resolve this
   by searching by default-locale value. This works correctly but the data model has a mild
   canonical key inconsistency that a future schema revision should formalize.

---

## R — Recommended Next

**Open P3: Tutorial and Specification Content Compiler Prototype.**

The route contract is mechanically proven across 30 checks. The SiteArtifact fixture provides
a complete routing configuration (canonical paths, hreflang maps, locale equivalents, source
content refs) that a content compiler can consume directly. Another hardening round is not
needed before P3. The one bounded gap — `/spec/` chapter routes — is additive and does not
block P3's core scope of reading markdown and emitting HTML with correct canonical and hreflang
tags. Add spec routes to the fixture when P3's scope expands to cover specification chapters.

---

## Proof Matrix

```
..............................
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
  igniter_org_v0.json                jekyll_contract_route_families_present       PASS
  igniter_org_v0.json                locale_equivalent_completeness               PASS
  igniter_org_v0.json                fallback_pages_have_no_hreflang_for_missing_locales PASS
  igniter_org_v0.json                tutorial_slug_routes_localized               PASS

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
  valid_minimal.json                 jekyll_contract_route_families_present       PASS
  valid_minimal.json                 locale_equivalent_completeness               PASS
  valid_minimal.json                 fallback_pages_have_no_hreflang_for_missing_locales PASS
  valid_minimal.json                 tutorial_slug_routes_localized               PASS

  invalid_forbidden_routes.json      all_forbidden_routes_rejected                PASS
  invalid_forbidden_routes.json      all_forbidden_equiv_violations_caught        PASS
------------------------------------------------------------------------
Total: 30  |  PASS: 30  |  FAIL: 0
========================================================================
Result: ALL CHECKS PASSED
```

Exit code: 0
