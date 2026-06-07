# Lab: SiteArtifact URL Contract — Proof (v0)

> **Status:** experimental · lab-only · proof-local · no-canon · no-public-api · no-stable-schema
> **Category:** view
> **Track:** lab-igniter-web-framework-siteartifact-url-contract-proof-v0
> **Card:** LAB-WEB-FRAMEWORK-P2
> **Date:** 2026-06-07
> **Scope:** model design, fixture authoring, and proof runner — no source code outside designated proof.rb

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

## 1. Purpose and Pressure

### Problem this addresses

The `igniter-org` public site for `igniter-lang.org` is hand-authored using Vite and a
custom `scripts/build-docs.js` Node.js pipeline. It has real, active routing, i18n, canonical
URL, and hreflang requirements documented in three policy files:

- `docs/url-routing-policy.md` — clean URL structure, canonical selection, hreflang, robots/sitemap
- `docs/i18n-pipeline.md` — locale storage layout, frontmatter schema, fallback generation rules
- `docs/tutorial-build-pipeline.md` — markdown compilation, safety hygiene, link rules

The existing build pipeline works but has no formal artifact model and no proof runner.
Without a model, the routing contract is implicit: it lives only in the Node.js script
and policy docs. This creates several failure modes:

1. **Long-path failure** — Locale content routed under `/docs/i18n/` or `/docs/tutorial/en/`
   (old legacy path shapes) could silently re-appear as the site grows. The URL policy
   explicitly forbids these shapes, but nothing enforces the prohibition mechanically.
2. **Duplicate-content risk** — Untranslated fallback pages served under `/ru/` or `/uk/`
   routes without correct canonical tags create SEO duplicate-content penalties. The policy
   defines the fix (canonical to English source), but it requires a formal model to test.
3. **Generator coupling** — The current pipeline is tightly coupled to Vite/Node. A clean
   artifact model defines what a correct site looks like independently of how it is built.

P2 formalizes the contract by defining a `SiteArtifact` JSON model, writing three fixture
files that encode the contract, and running a self-contained Ruby proof runner that validates
the contract mechanically.

### Connection to P1 roadmap

The P1 research card (LAB-WEB-FRAMEWORK-P1) identified this work as the natural next step:
> "A formal i18n artifact model is a clear next step after the static site compiler stabilizes."
> "P2 should produce artifacts that `igniter-org` could adopt, not a competing build system."

P2 delivers exactly that: a model and proof, not a competing site generator.

---

## 2. SiteArtifact Model

The `SiteArtifact` JSON model is designed to be **generator-neutral** and **language-neutral**.
It describes what a correctly structured static site looks like — not how it was built,
which tool generated it, or which language the build script was written in.

### 2.1 Top-level fields

| Field | Type | Description |
|---|---|---|
| `site_id` | string | Unique string identifier for the site configuration. |
| `locales` | array of strings | All locale codes supported by the site, e.g. `["en", "ru", "uk"]`. |
| `default_locale` | string | The authoritative default locale, e.g. `"en"`. |
| `route_tree` | RouteNode | Root node of the route tree. Children nest recursively. |
| `pages` | array of PageDescriptor | All pages in the site with full metadata. |
| `locale_equivalents` | map: canonical path → locale→path map | Maps a canonical path key to all locale-specific equivalents for that page. Used by the locale switcher. |
| `canonical_url_policy` | object | Named rule set for selecting canonical URLs. Generator-neutral — describes the rule, not the implementation. |
| `hreflang_policy` | object | Rules for generating hreflang alternate links. Includes x-default handling. |
| `source_content_refs` | map: page slug → source file path (relative) | Maps each page identifier to its source file, using relative paths only. |
| `generated_output_policy` | object | Describes where output paths go. Explicitly separate from source paths. |

### 2.2 RouteNode structure

```
path        — string. The public URL path, e.g. "/en/" or "/ru/tutorial/lab-orientation/"
locale      — string or null. The locale this route is rendered for (null for root).
slug        — string or null. The page slug (null for locale-root nodes).
page_ref    — string or null. The id of the PageDescriptor this route renders.
children    — array of RouteNode. Nested child routes.
```

### 2.3 PageDescriptor structure

```
id              — string. Unique page identifier.
slug            — string. URL slug segment for this page.
title           — map locale→string. Human-readable title per locale.
locales         — array of locale codes this page actively exists in.
fallback_locale — string or null. Which locale to fall back to if a locale variant is missing.
                  Must be set (non-null) for pages that exist in only one locale when the site
                  has multiple locales.
source_ref      — relative path to source markdown or HTML (no absolute paths).
canonical_path  — string. The full clean public canonical path for the default locale version.
hreflang        — map locale→path. All locale paths for this page, including "x-default".
                  Only includes locales where an equivalent page actually exists.
```

### 2.4 canonical_url_policy fields

```
rule            — named rule string, e.g. "translated_canonical_to_self__fallback_canonical_to_default_locale"
default_locale  — string. The locale used for canonical when a page is an untranslated fallback.
description     — human-readable explanation of the rule.
```

### 2.5 hreflang_policy fields

```
emit_x_default                    — boolean. Whether to emit an x-default alternate link.
x_default_locale                  — string. Which locale the x-default link points to.
only_emit_for_existing_equivalents — boolean. If true, only emit hreflang for locales with actual equivalents.
description                       — human-readable explanation.
```

### 2.6 generated_output_policy fields

```
output_root          — string. Root output directory, e.g. "dist/". Relative, not absolute.
pattern              — string. Output path pattern for locale-specific pages.
root_pattern         — string. Output path pattern for the root page.
locale_root_pattern  — string. Output path pattern for locale home pages.
note                 — string. Human-readable note, must explain that output is separate from source.
```

---

## 3. URL Contract

### 3.1 Required Route Shapes

The following routes must exist in any `SiteArtifact` that models `igniter-org`:

```
/
/en/
/ru/
/uk/
/language/
/ru/language/
/uk/language/
/tutorial/
/ru/tutorial/
/uk/tutorial/
/tutorial/<slug>/        (at minimum: lab-orientation, compiler-first-proof)
/ru/tutorial/<slug>/
/uk/tutorial/<slug>/
/lab/
/lab/compiler/
/lab/vm/
/lab/ide/
/lab/view/
/lab/gui/
/status/
```

All paths use clean directory-style URLs (trailing slash). No `.html` extensions in public paths.

### 3.2 Forbidden Route Shapes

The following patterns must never appear as public routes in a valid `SiteArtifact`:

| Pattern | Reason |
|---|---|
| `/docs/i18n/**` | Legacy internal build path. Blocked by `robots.txt`. |
| `/docs/tutorial/en/**` | Legacy path that embeds locale inside a `docs/tutorial/` prefix. |
| `/content/**` | Source directory exposed as a public route. Source and output must be separate. |
| `/_site/**` | Jekyll `_site` output directory exposed as a public route. |

In addition, two structural violations are forbidden:

1. **Same-path locale equivalents**: A page where ALL `locale_equivalents` entries point to
   the identical path is forbidden. The locale dropdown must link to genuinely distinct pages.
   A dropdown that links `/language/` → `/language/` → `/language/` for all three locales
   provides no locale switching value and misleads search engines.

2. **Locale hidden under `/docs/`**: A `locale_equivalents` map that routes any locale
   through a `/docs/i18n/**` or `/docs/tutorial/**` path is forbidden. Locale paths must
   follow the `/<locale>/<surface>/<slug>/` pattern.

### 3.3 Canonical URL Policy

The canonical selection rule is:

- **Translated page** (page exists in the target locale): `canonical` points to the page's
  own locale path.
  - Example: `/ru/tutorial/lab-orientation/` → canonical is `/ru/tutorial/lab-orientation/`
- **Untranslated fallback page** (target locale page doesn't exist, English content is served
  at the locale route): `canonical` points to the default-locale path.
  - Example: `/ru/tutorial/compiler-first-proof/` (serving English) → canonical is
    `/tutorial/compiler-first-proof/`
- **Root page** (`/`): treated as structural; canonical points to the default locale home.

The `SiteArtifact` model records this at the page level via `canonical_path` and at the site
level via `canonical_url_policy.rule`. A generator reads both to emit the correct tag.

### 3.4 hreflang Policy

- Default locale (`en`) page at `/language/` → hreflang `en` href `/language/`
- `ru` variant at `/ru/language/` → hreflang `ru` href `/ru/language/`
- `uk` variant at `/uk/language/` → hreflang `uk` href `/uk/language/`
- `x-default` → points to the default locale path (`/language/`)
- If a page exists only in `en` (not `ru` or `uk`): no hreflang emitted for missing locales.
  `x-default` still emitted. `fallback_locale` must be set on the `PageDescriptor`.
- The `hreflang` map on each `PageDescriptor` is the canonical record of which alternates to emit.
  Generators must not fabricate hreflang entries for locales not present in this map.

### 3.5 Locale Fallback Policy

When a page has no translation for a locale:

- The `PageDescriptor.locales` array contains only the available locales (e.g. `["en"]`).
- `PageDescriptor.fallback_locale` is set to `"en"` (non-null).
- The build pipeline generates a fallback page at the locale route (e.g. `/ru/tutorial/compiler-first-proof/`)
  containing the English source content plus a "Translation Missing (Fallback)" banner.
- The `canonical` tag on the fallback page points to the English source version.
- No hreflang is emitted for the missing locale.

This prevents 404s while being honest with search engines about content duplication.

---

## 4. Generator Neutrality Stance

The `SiteArtifact` model deliberately does not couple to any specific generator:

- No references to Vite config keys, Jekyll `_config.yml`, Hugo front matter, or any
  generator-specific field names.
- No Node.js-specific types or Ruby-specific assumptions in the JSON schema.
- The model describes the contract (what routes exist, what canonical/hreflang rules apply)
  — not the process (how the generator reads markdown, what template engine is used).
- The `generated_output_policy.output_root` is a relative path string, not a filesystem
  object or build graph node.

Jekyll is one candidate implementation target identified in P1 research. The model must
remain compatible with Jekyll's clean URL conventions (`permalink: /<locale>/<slug>/`),
but must not be *defined* in terms of Jekyll. A future card (P3 or later) that prototypes
a content compiler should be able to consume a `SiteArtifact` fixture as its configuration
without knowing whether another generator had previously generated anything from it.

---

## 5. Fixtures

Three fixture files are written under `igniter-view-engine/fixtures/siteartifact_url_contract/`.

### 5.1 `igniter_org_v0.json`

The primary fixture. Models the full `igniter-org` site structure as of 2026-06-07.

Covers:
- All required route shapes from Section 3.1.
- `en`, `ru`, `uk` locales with locale-prefixed trees.
- Translated pages (`lab-orientation`) with distinct locale equivalents.
- English-only fallback pages (`compiler-first-proof`, all `lab/` sub-pages) with `fallback_locale: "en"`.
- Correct hreflang maps per page.
- `generated_output_policy` with `dist/` output root.
- `source_content_refs` using only relative paths.
- No absolute local paths, no `file://` URIs, no `javascript:` schemes.

### 5.2 `valid_minimal.json`

A minimal valid site with 2 locales (`en`, `ru`), a home page, and one content page.
Demonstrates that the model is not over-specified: a small site with a simple structure
passes all proof checks without needing to enumerate 20+ routes.

Covers:
- Root route `/` and locale roots `/en/`, `/ru/`.
- One multi-locale page (`home`) with distinct equivalents.
- One en-only page (`about`) with `fallback_locale: "en"` and no `ru` hreflang entry.

### 5.3 `invalid_forbidden_routes.json`

A fixture containing only forbidden route shapes and structural violations.
This fixture is the input for the FAIL-fixture checks in the proof runner.

Contains:
- 6 forbidden route paths covering all 4 forbidden pattern families:
  `/docs/i18n/**`, `/docs/tutorial/en/**`, `/content/**`, `/_site/**`.
- 2 locale-equivalent violation examples:
  - A same-path violation (all 3 locales point to `/language/`).
  - A docs-path violation (all 3 locales use `/docs/i18n/**` or `/docs/tutorial/**` shapes).

---

## 6. Proof Results

The proof runner `igniter-view-engine/proofs/siteartifact_url_contract_proof.rb` was executed
and all 22 checks passed.

```
........F.................

Corrected and re-run:

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
```

Exit code: 0

---

## 7. Gaps and Open Questions

| Gap | Notes |
|---|---|
| No live canonical tag rendering | The proof validates the model structure, not actual HTML `<link>` tag output. A future P3/P5 card should prove canonical tag emission from a content compiler. |
| Route tree does not include `/spec/` pages | The `igniter-org` site has `/ru/spec/ch1-identity/` routes. These follow the same pattern but were not included in this fixture. A follow-up hardening pass should add spec routes. |
| Sitemap and robots.txt not modeled | The URL policy specifies sitemap.xml and robots.txt generation. The SiteArtifact model has no fields for these outputs. P5 should extend the model or define a companion SitemapArtifact. |
| Locale switcher JavaScript not modeled | The `i18n-pipeline.md` describes a dropdown switcher driven by `assets/site-nav.js`. The `locale_equivalents` map provides the data this script needs, but the connection is not formally proven. |
| `x-default` hreflang vs. canonical for root `/` | The root page (`/`) is structural and not a content page. How root-level canonical and x-default interact with SEO crawlers when the content is served at `/en/` is not formally proven here. |
| No proof for fallback page HTML banner injection | The model marks `fallback_locale` on pages, but the proof does not verify that a compiler would inject a "Translation Pending" banner at HTML generation time. This is P3 scope. |
| Fixture coverage: only 2 tutorial slugs | The required route spec asks for "at least 2 slug examples." Two are provided. Broader slug coverage (specification chapters, proposal pages) is deferred. |

---

## 8. Roadmap Position

This card is P2 in the web framework roadmap established by P1
(`lab-docs/view/lab-igniter-web-framework-research-and-view-engine-roadmap-v0.md`).

The P1 card described P2's scope as:
> "Define a formal static site artifact model: route tree, page descriptor, locale manifest,
> and content pipeline rules. Produce a proof runner that validates a route tree against the
> policy in `igniter-org/docs/url-routing-policy.md`."

P2 is complete. The SiteArtifact model is defined, three fixtures are written, and the
proof runner validates 22 checks with exit code 0.

P3 is the recommended next card: a Ruby proof-local content compiler that reads lab markdown
with YAML frontmatter and emits HTML pages with the safety guards documented in
`igniter-org/docs/tutorial-build-pipeline.md`. P3 would consume the `SiteArtifact` fixture
as its routing configuration and prove canonical tag and hreflang header emission in actual
HTML output.

---

## 9. Recommended Next Card

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

**Why now:** P2 provides the routing model that P3 needs as input. P3 makes the model
observable as actual HTML output. Together, P2+P3 give P5 (i18n + hreflang + sitemap
generation) a stable foundation.

**Alternative:** A route-contract hardening rerun could add `/spec/` pages, sitemap fields,
and spec-specific route shapes to the P2 fixture before proceeding to P3. This is lower
priority than P3 but is a valid precursor if site scope expands rapidly.
