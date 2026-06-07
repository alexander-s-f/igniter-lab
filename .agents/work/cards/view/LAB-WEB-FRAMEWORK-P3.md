# LAB-WEB-FRAMEWORK-P3

**Card ID:** LAB-WEB-FRAMEWORK-P3
**Category:** view
**Track:** lab-igniter-web-framework-content-compiler-prototype-v0
**Route:** LAB / VIEW / PROOF-LOCAL
**Date:** 2026-06-07
**Status:** DONE

---

## D — Deliverables

| File | Description |
|------|-------------|
| `igniter-lab/igniter-view-engine/lib/site_content_compiler.rb` | `SiteContentCompiler` class — frontmatter parser, safe markdown converter, SiteArtifact integration, HTML emitter, safety checks |
| `igniter-lab/igniter-view-engine/fixtures/site_content_compiler/en_language_index.md` | Fixture: English language index page |
| `igniter-lab/igniter-view-engine/fixtures/site_content_compiler/ru_language_index.md` | Fixture: Russian language index page (localized path lookup test) |
| `igniter-lab/igniter-view-engine/fixtures/site_content_compiler/en_tutorial_intro.md` | Fixture: Tutorial page with fenced code blocks |
| `igniter-lab/igniter-view-engine/fixtures/site_content_compiler/en_status.md` | Fixture: Status page with a pipe table |
| `igniter-lab/igniter-view-engine/fixtures/site_content_compiler/en_fallback_only.md` | Fixture: English-only page with fallback_locale=en (no banner test) |
| `igniter-lab/igniter-view-engine/fixtures/site_content_compiler/output/` | Compiled HTML output files (5 pages) |
| `igniter-lab/igniter-view-engine/proofs/site_content_compiler_proof.rb` | Proof runner — 59 checks, all passing |
| `igniter-lab/lab-docs/view/lab-igniter-web-framework-content-compiler-prototype-v0.md` | Lab document |
| `igniter-lab/.agents/work/cards/view/LAB-WEB-FRAMEWORK-P3.md` | This card receipt |

---

## S — Summary

P3 delivers a working content compiler prototype (`SiteContentCompiler`) that reads
markdown files with YAML frontmatter and emits fully formed HTML pages with correct
`<link rel="canonical">` and `<link rel="alternate" hreflang>` tags, driven by the
`igniter_org_v0.json` SiteArtifact fixture from P2-A. A minimal safe Markdown-to-HTML
converter is implemented in Ruby stdlib with no gem dependencies, supporting headings,
paragraphs, lists, fenced code blocks, pipe tables, bold, inline code, and links. Safety
guards reject `javascript:` links and `file://` URIs at compile time by raising
`SiteCompilerSafetyError`. The proof runner asserts 59 structural and safety properties
across five fixture files — all pass.

---

## T — Tensions / Risks

1. **Lookup by canonical_path, not page_id.** The `page_id` in frontmatter is carried
   through the result hash but not used for SiteArtifact lookup. If a frontmatter
   `canonical_path` is wrong or missing, the page will compile without hreflang tags
   and no error will be raised. A stricter mode that raises on lookup failure would
   catch content authoring mistakes earlier.

2. **Markdown converter is minimal and non-standard.** The safe converter handles the
   subset needed for proof-local lab content, but it will produce incorrect output for
   edge cases (e.g., inline code inside bold, nested lists, blockquotes, HTML entities
   in code spans). Any expansion of the markdown subset requires careful regression
   testing against the safety invariants.

3. **No layout shell.** The compiler emits unstyled HTML fragments. Without a layout
   primitive (P4), the output is not directly renderable in a browser in a meaningful
   way. Integration with any real site generation pipeline requires P4's slot-based
   template system.

---

## R — Recommended Next

**Open P4: Layout Primitives and Slot-Based Template Prototype.**

P3 proves the content-to-HTML pipeline and SiteArtifact routing integration. P4 should
add the structural shell: a slot-based layout template system in Ruby (no JS framework),
nav/header/footer components, a basic CSS token layer, and locale switcher markup driven
by `locale_equivalents`. A P3-A hardening pass is not required before P4 opens — all
59 proof checks pass and no blocking gaps were identified.

---

## Proof Matrix

```
...........................................................
========================================================================
SiteContentCompiler Proof — Results Matrix
========================================================================
  FIXTURE                    CHECK                                  STATUS
------------------------------------------------------------------------
  en_language_index.md       html_has_doctype                       PASS
  en_language_index.md       html_has_canonical                     PASS
  en_language_index.md       html_has_lang_attribute                PASS
  en_language_index.md       html_has_title                         PASS
  en_language_index.md       html_has_body_content                  PASS
  en_language_index.md       no_absolute_local_paths                PASS
  en_language_index.md       no_file_uri                            PASS
  en_language_index.md       no_javascript_scheme                   PASS
  en_language_index.md       canonical_matches_fixture              PASS
  en_language_index.md       has_hreflang_en                        PASS
  en_language_index.md       has_hreflang_ru                        PASS
  en_language_index.md       has_hreflang_uk                        PASS
  en_language_index.md       has_hreflang_x_default                 PASS

  ru_language_index.md       html_has_doctype                       PASS
  ru_language_index.md       html_has_canonical                     PASS
  ru_language_index.md       html_has_lang_attribute                PASS
  ru_language_index.md       html_has_title                         PASS
  ru_language_index.md       html_has_body_content                  PASS
  ru_language_index.md       no_absolute_local_paths                PASS
  ru_language_index.md       no_file_uri                            PASS
  ru_language_index.md       no_javascript_scheme                   PASS
  ru_language_index.md       canonical_matches_fixture              PASS
  ru_language_index.md       has_lang_ru                            PASS
  ru_language_index.md       has_hreflang_entries                   PASS
  ru_language_index.md       canonical_is_ru_path                   PASS

  en_tutorial_intro.md       html_has_doctype                       PASS
  en_tutorial_intro.md       html_has_canonical                     PASS
  en_tutorial_intro.md       html_has_lang_attribute                PASS
  en_tutorial_intro.md       html_has_title                         PASS
  en_tutorial_intro.md       html_has_body_content                  PASS
  en_tutorial_intro.md       no_absolute_local_paths                PASS
  en_tutorial_intro.md       no_file_uri                            PASS
  en_tutorial_intro.md       no_javascript_scheme                   PASS
  en_tutorial_intro.md       canonical_matches_fixture              PASS
  en_tutorial_intro.md       has_code_block                         PASS
  en_tutorial_intro.md       code_is_escaped                        PASS
  en_tutorial_intro.md       has_heading                            PASS

  en_status.md               html_has_doctype                       PASS
  en_status.md               html_has_canonical                     PASS
  en_status.md               html_has_lang_attribute                PASS
  en_status.md               html_has_title                         PASS
  en_status.md               html_has_body_content                  PASS
  en_status.md               no_absolute_local_paths                PASS
  en_status.md               no_file_uri                            PASS
  en_status.md               no_javascript_scheme                   PASS
  en_status.md               canonical_matches_fixture              PASS
  en_status.md               has_table                              PASS

  en_fallback_only.md        html_has_doctype                       PASS
  en_fallback_only.md        html_has_canonical                     PASS
  en_fallback_only.md        html_has_lang_attribute                PASS
  en_fallback_only.md        html_has_title                         PASS
  en_fallback_only.md        html_has_body_content                  PASS
  en_fallback_only.md        no_absolute_local_paths                PASS
  en_fallback_only.md        no_file_uri                            PASS
  en_fallback_only.md        no_javascript_scheme                   PASS
  en_fallback_only.md        canonical_matches_fixture              PASS
  en_fallback_only.md        no_fallback_banner                     PASS

  safety_rejection           javascript_link_raises_safety_error    PASS
  safety_rejection           file_uri_link_raises_safety_error      PASS
------------------------------------------------------------------------
Total: 59  |  PASS: 59  |  FAIL: 0
========================================================================
Result: ALL CHECKS PASSED
```

Exit code: 0
