# Lab: SiteArtifact — Jekyll Route Contract Alignment (v0)

> **Status:** experimental · lab-only · hardening pass on P2 · no canon claim · no stable schema
> **Card:** LAB-WEB-FRAMEWORK-P2-A
> **Date:** 2026-06-07
> **Extends:** lab-igniter-web-framework-siteartifact-url-contract-proof-v0.md

---

## Pre-v1 Language Note

> We are actively shaping the future of Igniter. The toolchains, compilers, view engine,
> and site-generation ideas featured here represent active, pre-v1 exploration.
>
> APIs and artifacts documented here may change without notice. These materials are
> provided as-is for community learning, experimentation, and design discussion.
> Igniter is not a replacement for Jekyll, Vite, React, or any existing site generator.
> It is an independently motivated, accountability-first language platform whose
> site artifact model is still being shaped. Nothing in this document constitutes
> a public API commitment, a stable schema, or a release target.

---

## 1. Purpose

The P2 proof (`LAB-WEB-FRAMEWORK-P2`) established a `SiteArtifact` JSON model, three fixture
files, and a 22-check proof runner that all passed. However, `igniter_org_v0.json` was
authored before the `igniter-org-jekyll` candidate existed as a source of route evidence.
The Jekyll candidate has since grown its own `docs/route-contract.md` and
`_data/locale_groups.yml`, which enumerate route families not yet reflected in the P2 fixture.

This hardening pass (P2-A) closes that gap. It:

1. Adds five route families to `igniter_org_v0.json` that appeared in the Jekyll candidate but
   were absent from the SiteArtifact fixture.
2. Upgrades several `en`-only lab sub-pages to full three-locale coverage, matching the
   locale_groups.yml evidence.
3. Adds four new proof checks that mechanically validate route family coverage, locale-equivalent
   completeness, fallback hreflang hygiene, and tutorial slug localization.
4. Raises the total proof check count from 22 to 30, all passing.

**Why Jekyll is evidence, not authority.** The Jekyll candidate (`igniter-org-jekyll`) is an
independent implementation experiment. It has no authority over the SiteArtifact model. The
model defines what a correctly structured site artifact looks like; Jekyll demonstrates one
possible implementation. The fixture uses Jekyll route evidence as pressure — a concrete list
of routes a real generator has proven it can produce — not as a schema source or spec reference.

---

## 2. New Route Families Added

| Route Family | Canonical Path | Locales Covered | Fallback Policy | Notes |
|---|---|---|---|---|
| language-covenant | `/language/covenant/` | en, ru, uk | none (tri-locale) | Canon projection page per Jekyll route-contract.md |
| language-specification | `/language/specification/` | en, ru, uk | none (tri-locale) | Language spec index |
| language-proposals | `/language/proposals/` | en, ru, uk | none (tri-locale) | Language proposals index |
| tutorial-vm-candidate-proof | `/tutorial/vm-candidate-proof/` | en, ru, uk | none (tri-locale) | New tutorial slug; all locales present per Jekyll _pages/ |
| lab-design-system | `/lab/design-system/` | en, ru, uk | none (tri-locale) | Lab surface page present in all 3 locales per locale_groups.yml |

### Locale upgrade: existing lab sub-pages

The original P2 fixture modeled `lab-compiler`, `lab-vm`, `lab-ide`, `lab-view`, and `lab-gui`
as `en`-only pages with `fallback_locale: "en"`. The Jekyll candidate (`_pages/ru-lab-compiler.md`,
`_pages/uk-lab-compiler.md`, etc.) shows all these pages have been given localized routes.

These pages have been upgraded to full tri-locale coverage in the fixture. `fallback_locale` is
now `null` for these pages, and `hreflang` maps include `en`, `ru`, `uk`, and `x-default`.

The corresponding `locale_equivalents` entries now map all three locales to distinct paths
(e.g., `/lab/compiler/`, `/ru/lab/compiler/`, `/uk/lab/compiler/`).

Additionally, `tutorial-compiler-first-proof` was upgraded from `en`-only to tri-locale, matching
the Jekyll evidence (`ru-tutorial-compiler-first-proof.md`, `uk-tutorial-compiler-first-proof.md`).

---

## 3. New Proof Checks

Four new checks were added to `siteartifact_url_contract_proof.rb`, bringing the total from 22
to 30 checks.

### Check 11: `jekyll_contract_route_families_present`

**Applies to:** `igniter_org_v0.json` only.

**What it validates:** Collects all paths from the fixture's `route_tree` recursively and verifies
that each of 21 path entries in `JEKYLL_CONTRACT_ROUTES` is present. These 21 entries are derived
directly from the Jekyll candidate's `docs/route-contract.md` Required Public Routes section.

**Why it matters:** Without this check, route families could silently be omitted from the fixture
while the Jekyll candidate has already demonstrated they are necessary. This check closes the
feedback loop between Jekyll evidence and SiteArtifact fixture coverage.

### Check 12: `locale_equivalent_completeness`

**Applies to:** all PASS fixtures.

**What it validates:** For every page whose `locales` array contains all three of `en`, `ru`, `uk`:
- The `hreflang` map must have keys `en`, `ru`, `uk`, and `x-default`.
- There must be a matching entry in `locale_equivalents` (looked up by `canonical_path` or by
  finding an entry whose default-locale value equals the canonical path).
- That entry must have all three locale keys mapping to distinct paths.

**Why it matters:** A three-locale page with an incomplete hreflang map or missing
locale_equivalents entry would silently produce incorrect SEO metadata. The P2 model
specifies these invariants but the original proof runner did not verify tri-locale completeness
as a unified constraint.

### Check 13: `fallback_pages_have_no_hreflang_for_missing_locales`

**Applies to:** all PASS fixtures.

**What it validates:** For every page where `fallback_locale` is set (meaning the page is
intentionally limited to a subset of the site's locales), the `hreflang` map must not contain
keys for locales not listed in the page's own `locales` array. The `x-default` key is
excluded from this constraint.

**Why it matters:** The P2 model states "Generators must not fabricate hreflang entries for
locales not present in this map." This check enforces that the fixture itself does not
accidentally author such entries, which would contradict the policy it encodes.

### Check 14: `tutorial_slug_routes_localized`

**Applies to:** all PASS fixtures.

**What it validates:** For every page whose `id` starts with `tutorial-` (excluding the index
page), if the page's `locales` includes `ru`, then `/ru/tutorial/<slug>/` must exist in the
route_tree. Same for `uk`. This verifies that tutorial content page localizations are
reflected as actual routes, not just locale metadata.

**Why it matters:** The tutorial surface is the primary content surface. A page that declares
`locales: ["en", "ru", "uk"]` but lacks corresponding localized routes in the route_tree
would produce broken locale switcher links and missing pages at build time. This check
catches that class of inconsistency.

---

## 4. Generator Neutrality Preservation

The additions in this pass maintain the model's generator-neutral stance:

**No Jekyll-specific fields.** None of the new `PageDescriptor` or `RouteNode` entries contain
Jekyll frontmatter keys (`layout`, `locale_group`, `nav_group`, `eyebrow`, `permalink`). The
SiteArtifact model records what public routes exist, not how they are generated.

**No Jekyll configuration references.** The `JEKYLL_CONTRACT_ROUTES` constant in the proof
runner is documented as "derived from Jekyll route-contract evidence (read-only pressure source)"
— it is pressure, not authority. A generator other than Jekyll that produces the same public
routes would satisfy the same check.

**Fields intentionally absent from SiteArtifact core schema.** The model deliberately omits:
- `layout` — template selection (generator concern)
- `nav_group` — navigation grouping (theme concern)
- `eyebrow` — display label (content concern)
- `jekyll-sitemap` configuration — build plugin concern
- `bundle` / `Gemfile` dependencies — build toolchain concern
- `_config.yml` fields of any kind

The `source_content_refs` map uses relative paths that are meaningful to any build system
that operates from a content directory — they are not Jekyll-specific.

---

## 5. Proof Results

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

---

## 6. Remaining Gaps

| Gap | Notes |
|---|---|
| No `/spec/` routes | The original P2 doc noted `/ru/spec/ch1-identity/` routes exist in igniter-org. These are not yet in the fixture. A follow-up pass or P3 could add them if the spec surface is in scope. |
| Sitemap and robots.txt not modeled | The URL policy specifies sitemap.xml and robots.txt generation. The SiteArtifact model has no fields for these outputs. Deferred to P5. |
| No proof for canonical tag HTML emission | The proof validates the model structure, not actual `<link rel="canonical">` tag output from a content compiler. This is P3 scope. |
| Locale switcher data-binding not proven | The `locale_equivalents` map provides correct data, but no proof verifies a compiler would emit the correct switcher link markup from it. |
| Root `/` canonical interaction | The root page is structural. Its `hreflang` emits `en` and `x-default` both pointing to `/en/`. The crawl behavior for the structural root versus the locale home is not formally proven here. |
| No `valid_minimal.json` update for new check semantics | The `valid_minimal.json` fixture has only `en` and `ru` locales, so the tri-locale completeness check effectively skips it. A new fixture with all three locales and partial coverage would give better FAIL-coverage for checks 12 and 13. |

---

## 7. P3 Readiness Assessment

**Recommendation: P3 content compiler is ready to open.**

The route contract is now mechanically proven across 30 checks with full fixture coverage of the
Jekyll candidate's documented route families. The SiteArtifact fixture provides:

- A complete tri-locale route tree that a content compiler can use as routing configuration.
- Correct `canonical_path` and `hreflang` maps on every page.
- `locale_equivalents` maps for locale switcher data binding.
- `source_content_refs` pointing to relative content paths a compiler can read.
- A fallback policy that is both modeled and proven.

P3's primary task — read lab markdown, emit HTML with canonical/hreflang tags, accept a
SiteArtifact fixture as routing configuration — has a stable foundation. The fixture does not
need another hardening round before P3 starts.

One bounded gap exists: if P3 needs to cover `/spec/` chapter routes, a minor fixture
extension would be needed before those content pages can be compiled. This is additive, not
blocking.

---

## 8. Recommended Next Card

**Card ID (suggested):** `LAB-WEB-FRAMEWORK-P3`

**Title:** Tutorial and Specification Content Compiler Prototype

**Scope:**
- Read lab markdown files from `lab-docs/tutorial/` or test fixtures.
- Parse YAML frontmatter (source_project, source_path, source_revision, translation_status).
- Emit HTML with: h1–h6, code blocks (escaped), tables, links, bold/italic, translation banner.
- Apply all safety guards: no absolute paths, no `file://`, no `javascript:`, HTML escaping.
- Accept a `SiteArtifact` fixture as routing configuration to emit canonical tags and hreflang.
- Run a safety check suite against test fixtures.

**Authority:** Lab-only. No `igniter-org` edits. No `igniter-lang` changes. No site deployment.

**Why now:** P2-A closes the route contract. P3 makes the model observable as actual HTML
output. Together, P2+P2-A+P3 give P5 (i18n + hreflang + sitemap generation) a stable
foundation.
