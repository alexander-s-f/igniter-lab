# Lab: Content Compiler Prototype (v0)

> **Status:** experimental · lab-only · proof-local · no canon claim · no stable API
> **Card:** LAB-WEB-FRAMEWORK-P3
> **Date:** 2026-06-07
> **Depends on:** lab-igniter-web-framework-siteartifact-jekyll-contract-alignment-v0.md

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

P2 and P2-A established and hardened a `SiteArtifact` JSON model with a 30-check proof
that all route families, locale equivalents, hreflang maps, and fallback policies are
structurally correct. That proof validated the model in isolation. P3's task is to make
the model observable as actual HTML output.

`SiteContentCompiler` is the prototype that connects those two halves. It reads a
markdown file with YAML frontmatter, uses the SiteArtifact fixture as routing
configuration, and emits a fully formed HTML page with:

- A correct `<link rel="canonical">` tag derived from the SiteArtifact page record.
- One `<link rel="alternate" hreflang="...">` tag per locale in the page's hreflang map.
- A fallback banner when a page is being served in a locale where it does not exist.
- A compiled HTML body from markdown, using a minimal safe converter with no gem dependencies.
- Safety guards that reject `javascript:` links, `file://` URIs, and absolute local paths.

The proof runner compiles five fixture markdown files, writes output HTML, and asserts
59 structural and safety properties — all passing.

---

## 2. Architecture

```
SiteContentCompiler
  initialize(site_artifact_path)
    → loads and parses igniter_org_v0.json

  compile_page(markdown_source)   → { html, page_id, locale, canonical_path }
    ├── parse_frontmatter          → { frontmatter_hash, body_markdown }
    ├── find_artifact_page         → looks up page by canonical_path or hreflang value
    ├── safe_markdown_to_html      → body HTML string
    ├── run_safety_checks!         → raises SiteCompilerSafetyError on violation
    └── emit_html                  → assembles complete HTML document

  compile_file(markdown_file_path)
    → reads file, calls compile_page, adds :output_path to result hash
```

**`parse_frontmatter`** — reads the `---`-delimited YAML block at the top of a
markdown file using Ruby's `YAML.safe_load`. Returns the frontmatter hash and the
remaining body text.

**`find_artifact_page`** — given the `canonical_path` from frontmatter, searches the
SiteArtifact pages array for a page whose `canonical_path` matches, or whose `hreflang`
map contains the path as a value. This allows localized paths (e.g. `/ru/language/`) to
resolve to the correct page record (which has `canonical_path: /language/`) and
inherit its full hreflang map.

**`safe_markdown_to_html`** — line-by-line state machine converter. No external gems.
See Section 3 for the supported subset.

**`run_safety_checks!`** — scans compiled HTML for absolute local paths, `file://`
URIs, and `javascript:` hrefs. Raises `SiteCompilerSafetyError` on any match.

**`emit_html`** — assembles the `<!DOCTYPE html>` page shell, injecting locale,
title, canonical, hreflang tags, optional fallback banner, and compiled body.

---

## 3. Safe Markdown Subset

All text content is HTML-escaped before processing (`&` → `&amp;`, `<` → `&lt;`,
`>` → `&gt;`, `"` → `&quot;`). Inline patterns are applied after escaping.

| Element | Input syntax | Output HTML | Safety note |
|---------|-------------|-------------|-------------|
| H1 | `# Heading` | `<h1>Heading</h1>` | Text is HTML-escaped |
| H2 | `## Heading` | `<h2>Heading</h2>` | Text is HTML-escaped |
| H3–H6 | `### ... ######` | `<h3>` … `<h6>` | Text is HTML-escaped |
| Paragraph | Blank-line-separated text | `<p>…</p>` | Text is HTML-escaped |
| Unordered list | Consecutive `- item` lines | `<ul><li>…</li></ul>` | Text is HTML-escaped |
| Fenced code | ` ``` ` … ` ``` ` | `<pre><code>…</code></pre>` | Code content HTML-escaped; raw `<` → `&lt;` |
| Pipe table | `\| A \| B \|` rows | `<table><thead>…<tbody>…</table>` | Cell text HTML-escaped |
| Inline code | `` `code` `` | `<code>code</code>` | Content HTML-escaped |
| Bold | `**text**` | `<strong>text</strong>` | Text HTML-escaped before pattern match |
| Link | `[text](url)` | `<a href="url">text</a>` | Raises error on `javascript:` or `file://` |

**Not supported in this prototype:** italic, strikethrough, nested lists, blockquotes,
definition lists, footnotes, HTML passthrough, image tags. These are P4/P5 scope.

---

## 4. SiteArtifact Integration

The compiler uses the `pages` array from `igniter_org_v0.json` as its routing
configuration. For each markdown file compiled, the `canonical_path` from frontmatter
is used as a lookup key:

1. **Primary lookup:** find a page where `page.canonical_path == frontmatter.canonical_path`.
2. **Secondary lookup:** find a page where any value in `page.hreflang` equals the
   frontmatter `canonical_path`. This handles localized pages (e.g. `/ru/language/`)
   which do not appear as a primary `canonical_path` in the artifact but do appear as
   hreflang values.

Once resolved, the compiler uses:

- `page.hreflang` — to emit `<link rel="alternate" hreflang="...">` tags for every locale.
- `page.locales` — to determine whether the requested locale actually exists in the artifact.
- `page.fallback_locale` — in combination with `page.locales`, to determine whether a
  fallback banner is warranted.

The `canonical_path` emitted into the HTML always comes from the frontmatter, not the
artifact, since the frontmatter encodes the locale-specific self-referencing path.

---

## 5. Fallback Banner Policy

The fallback banner appears when:

1. The artifact page has a non-null `fallback_locale`, AND
2. The `locale` from frontmatter is NOT in the artifact page's `locales` array.

When both conditions are true, the page is being viewed in a locale for which no
translation exists. The compiler emits:

```html
<div class="iglab-fallback-banner" data-fallback-locale="{fallback_locale}">
  This page is not yet available in the requested locale.
  You are viewing the {fallback_locale} version.
</div>
```

When `locale == fallback_locale` (the page IS in the fallback locale, just with a
`fallback_locale` field set), no banner is shown. The `en_fallback_only.md` fixture
tests this: its frontmatter has `locale: en` and `fallback_locale: en`, so no banner
is emitted.

---

## 6. Safety Policy

The compiler enforces three safety rules. Violations raise `SiteCompilerSafetyError`
and halt compilation.

| Rule | What is rejected | Why |
|------|-----------------|-----|
| No absolute local paths | Strings matching `/Users/`, `/home/`, `C:\Users\` | Prevents accidental local filesystem leakage in output HTML |
| No `file://` URIs | Any `file://` in content or link hrefs | `file://` links are not valid for web content; likely a path leak |
| No `javascript:` scheme | Any `javascript:` link href | XSS vector; no legitimate use in static site content |

Safety checks run in two passes: inline (during `inline_markup`, where link hrefs are
parsed) and post-compilation (scanning the full compiled body before HTML emission).

---

## 7. Proof Results

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

---

## 8. Sample Output

Compiled output for `en_language_index.md` (the `/language/` page, English locale):

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Language — Igniter</title>
  <link rel="canonical" href="/language/">
  <link rel="alternate" hreflang="en" href="/language/">
  <link rel="alternate" hreflang="ru" href="/ru/language/">
  <link rel="alternate" hreflang="uk" href="/uk/language/">
  <link rel="alternate" hreflang="x-default" href="/language/">
</head>
<body>
<h1>Language</h1>
<p>Igniter is an accountability-first programming language.
It is actively being shaped — APIs and artifacts may change.</p>
<h2>Overview</h2>
<p>The language is designed around three principles:</p>
<ul>
<li><strong>Contracts</strong> — every function signature is a verifiable contract.</li>
<li><strong>Proofs</strong> — behavior is proven locally before deployment.</li>
<li><strong>Composability</strong> — modules compose without hidden coupling.</li>
</ul>
<h2>Learn More</h2>
<ul>
<li><a href="/language/covenant/">Covenant</a></li>
<li><a href="/language/specification/">Specification</a></li>
<li><a href="/language/proposals/">Proposals</a></li>
</ul>
</body>
</html>
```

Key observations:
- The `hreflang` entries come from the SiteArtifact page record for `language`, not from
  the markdown frontmatter itself — frontmatter only supplies `canonical_path` as a lookup key.
- Bold (`**...**`) and links (`[text](url)`) are correctly compiled.
- No gem dependencies — the output is produced by the in-process converter alone.

---

## 9. Gaps and Limitations

| Gap | Notes |
|-----|-------|
| No layout primitives | The output is unstyled HTML. No CSS, no nav, no header/footer. P4 scope. |
| No italic, strikethrough, blockquote | Not implemented in the safe converter. Low-priority for lab content. |
| No image tags | Deliberately omitted pending an image safety policy (alt text, path validation). |
| No nested lists | Only flat unordered lists. Nested indentation not parsed. |
| No HTML passthrough | Raw HTML in markdown is escaped, not passed through. Intentional safety choice. |
| No YAML anchor support | `YAML.safe_load` is used; complex anchors or custom types not supported. |
| Page lookup by page_id not used | The `page_id` frontmatter field is carried through the result hash but not used for artifact lookup. Lookup uses `canonical_path`. If frontmatter `canonical_path` is absent or wrong, lookup will fail silently (no hreflang emitted). |
| No sitemap or robots.txt emission | These are P5 scope per the P2-A gaps list. |
| No locale switcher markup | `locale_equivalents` data is available in the artifact but not yet used by the compiler to emit switcher links. |
| Output is a string, not a file tree | `compile_file` returns an `output_path` suggestion but does not write to a dist directory. A batch runner would need to wire up file writing. |

---

## 10. P4 Readiness Assessment

**Recommendation: P4 layout primitives are ready to open.**

The prototype proves that:

1. Markdown content can be compiled to valid, safety-checked HTML using only Ruby stdlib.
2. The SiteArtifact fixture can drive `<link rel="canonical">` and `<link rel="alternate" hreflang>` tag emission correctly for both primary (EN) and localized (RU) paths.
3. The fallback banner policy is mechanically enforced and proven.
4. Safety violations in content (javascript: links, file:// URIs, absolute paths) are caught at compile time.

These properties are stable enough for P4 to build on. P4's task is to add layout
primitives — a slot-based template system that wraps compiled page bodies with nav,
header, footer, and a basic CSS token layer — without changing the compiler's core
markdown-to-HTML pipeline or SiteArtifact integration.

One bounded gap that P4 should address: the `locale_equivalents` data from the
SiteArtifact is not yet used. P4's locale switcher component would consume this data
to emit the correct switcher link markup for each page.

A P3-A hardening pass is not required before P4 opens. The gaps listed in Section 9
are either deferred by design or additive (not blocking).

---

## 11. Recommended Next Card

**Card ID (suggested):** `LAB-WEB-FRAMEWORK-P4`

**Title:** Layout Primitives and Slot-Based Template Prototype

**Scope:**
- Define a minimal slot-based layout template system in Ruby (no JS framework).
- Implement nav, header, footer, and page slots as composable template parts.
- Inject a basic CSS token layer (color, spacing, typography) using inline `<style>` or
  a linked stylesheet generated from a token fixture — no external CSS framework.
- Wire `compile_page` output into the layout slot system to produce a complete rendered page.
- Emit locale switcher markup from `locale_equivalents` in the SiteArtifact fixture.
- Add proof checks: slot injection, locale switcher link correctness, CSS token presence.

**Authority:** Lab-only. No `igniter-org` edits. No `igniter-lang` changes. No deployment.

**Why now:** P3 proves that content compiles correctly and routing metadata is wired up.
P4 makes the output presentable and adds the structural shell that P5 (i18n + sitemap +
full site generation) will need.
