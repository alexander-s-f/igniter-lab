# Lab: Igniter Web Framework — Layout Primitives (v0)

> **Status:** experimental · lab-only · no-canon · no-public-api · no-stable-schema
> **Category:** view
> **Track:** lab-igniter-web-framework
> **Card:** LAB-WEB-FRAMEWORK-P4
> **Date:** 2026-06-07
> **Scope:** LayoutEngine implementation and proof — layout slots, rendering, inheritance, safety

---

## Pre-v1 Language Note

> We are actively shaping the future of Igniter. The layout primitives defined here
> represent active, pre-v1 exploration. APIs and artifacts may change. These materials
> are provided as-is for community learning, experimentation, and design discussion.

---

## 1. Design Stance — Position in the P1–P7 Roadmap

The P1 roadmap staged the web framework work across seven phases:

- **P1** — Research, inventory, and requirements (done)
- **P2** — Route map and static site artifact model (done)
- **P3** — Tutorial/spec content compiler prototype — `SiteContentCompiler` (done)
- **P4** — Layout and component primitive set — `LayoutEngine` (**this card**)
- **P5** — i18n, hreflang, sitemap generation (next)
- **P6** — Contract schema to forms/view binding
- **P7** — Headless GUI artifact integration (research only)

P4 sits between the content compiler (P3) and the i18n layer (P5). Its responsibility is
narrow: given compiled HTML content fragments, compose them into a complete page structure
using named layout slots and an HTML template. It does not route, emit canonical tags, or
manage locales — those remain P2 and P5 concerns.

The design intention is that `LayoutEngine` is a pure Ruby module with no I/O, no
networking, and no framework dependency. It operates on in-memory strings. The only
external dependency is `SiteContentCompiler` (P3), which provides safety-validated
markdown-to-HTML compilation.

---

## 2. Slot Model

### 2.1 Slot Names

`LayoutEngine::SLOT_NAMES` defines the complete set of named slots a layout may declare:

```
header   nav   content   sidebar   footer
```

These map to the structural regions common in a documentation or marketing page.
No other slot names are accepted — `define_layout` raises `ArgumentError` for unknown names.

### 2.2 Required Slots

`LayoutEngine::REQUIRED_SLOTS = %w[content]`

Only `content` is required. A layout that declares `content` in its `slots` array must
have `content` explicitly filled at render time. All other slots (`header`, `nav`,
`sidebar`, `footer`) are optional and default to an empty string.

### 2.3 Default Values

`LayoutEngine::SLOT_DEFAULTS` provides empty-string defaults for every slot. Optional
slots not explicitly filled at render time produce no output in the template — the
`{{slot_name}}` marker is replaced with `""`. This means the surrounding HTML structure
(e.g., `<nav></nav>`) remains in the template output; it is the template author's
responsibility to omit wrapper elements for unused optional slots if desired.

### 2.4 Layout Descriptor

A layout is a plain Ruby hash with symbol keys:

```ruby
{
  name:          String,       # layout identifier
  slots:         Array<String>, # subset of SLOT_NAMES
  template:      String,       # HTML template with {{slot_name}} markers
  parent_layout: String|nil    # name of parent layout for 2-level inheritance
}
```

`define_layout` constructs and validates the descriptor. `validate_layout` performs
structural checks and returns `{ valid: Boolean, errors: Array<String> }`.

---

## 3. Layout Inheritance — 2-Level Model

`render_inherited(parent_layout, child_layout, child_filled_slots, parent_filled_slots)`
supports exactly one level of inheritance:

1. The child layout is rendered with its own filled slots.
2. The child's rendered HTML string becomes the `content` slot of the parent layout.
3. The parent layout is then rendered with its own slots (including the injected child
   content).

This is the maximum supported depth. There is no recursive nesting. Deep hierarchies
introduce coupling and make slot resolution harder to reason about. Two levels are
sufficient for the primary use case: a per-page content layout (article with sidebar)
wrapped in a site-wide base layout (header, nav, footer).

If the child render fails (e.g., required slot missing), the error is propagated
directly — the parent render is never attempted.

### 3.1 Example — Article inside Base

```ruby
base_layout = LayoutEngine.define_layout(
  'base',
  slots: %w[header nav content footer],
  template: <<~HTML
    <!DOCTYPE html>
    <html><body>
    <header>{{header}}</header>
    <nav>{{nav}}</nav>
    <main>{{content}}</main>
    <footer>{{footer}}</footer>
    </body></html>
  HTML
)

article_layout = LayoutEngine.define_layout(
  'article',
  slots: %w[content sidebar],
  template: '<article><section>{{content}}</section><aside>{{sidebar}}</aside></article>',
  parent_layout: 'base'
)

result = LayoutEngine.render_inherited(
  base_layout,
  article_layout,
  { 'content' => '<p>Article body</p>', 'sidebar' => '<p>See also</p>' },
  { 'nav' => '<ul><li><a href="/">Home</a></li></ul>' }
)
# result[:ok]   => true
# result[:html] => full page HTML with article inside <main>
```

---

## 4. Safety Integration — SiteContentCompiler

`fill_slot` compiles raw content through `SiteContentCompiler.compile` before it enters
the layout system. This ensures:

- `<script>` tags and other raw HTML are escaped (markdown compiler treats them as text)
- `javascript:` scheme links raise `SiteCompilerSafetyError` — the error propagates
  and the slot fill fails
- `file://` URI links are blocked by the same mechanism
- Absolute local paths (`/Users/`, `/home/`) are rejected
- All text content is HTML-escaped before output

The safety boundary is inherited from P3 without duplication. `LayoutEngine` does not
implement its own escaping — it delegates entirely to `SiteContentCompiler`.

`SiteContentCompiler.compile(raw_content)` is a class-level convenience method added
in P4 that accepts plain markdown/HTML content without requiring a site artifact path.
It returns `{ html: String, errors: Array<String> }`. If `errors` is non-empty, `fill_slot`
raises and the layout render cannot proceed with unsafe content.

---

## 5. Verification Results

Proof runner: `igniter-view-engine/proofs/web_framework_p4_proof.rb`

```
Total: 45  |  PASS: 45  |  FAIL: 0
Result: ALL CHECKS PASSED
```

| Group          | Checks | PASS | FAIL |
|:---------------|-------:|-----:|-----:|
| LAYOUT-SCHEMA  |     10 |   10 |    0 |
| LAYOUT-FILL    |      8 |    8 |    0 |
| LAYOUT-RENDER  |     10 |   10 |    0 |
| LAYOUT-INHERIT |      8 |    8 |    0 |
| LAYOUT-SAFETY  |      4 |    4 |    0 |
| LAYOUT-STABLE  |      5 |    5 |    0 |
| **Total**      | **45** | **45** | **0** |

All 45 checks pass. The 45-check count exceeds the 43 target; the extra 2 checks cover
distinct sub-properties of `define_layout` return value (slots and template fields
separated from the name field).

---

## 6. Non-Claims

| Claim | Status |
|:---|:---|
| LayoutEngine is a production layout system | **No** — lab proof only |
| Slot model is a stable or canonical API | **No** — experimental, will evolve |
| LayoutEngine replaces ViewArtifact slot injection | **No** — different level; ViewArtifact covers typed slot-contract binding |
| Deep (3+) layout inheritance is supported | **No** — 2 levels maximum by design |
| LayoutEngine emits CSS or design tokens | **No** — HTML structure only; CSS integration is separate |
| `SiteContentCompiler.compile` is a permanent API | **No** — added as a lab convenience for P4; subject to revision |
| LayoutEngine handles i18n or locale routing | **No** — that is P5 scope |

---

## 7. Recommended Next Card — P5: i18n / hreflang / Sitemap

**Card ID (suggested):** `LAB-WEB-FRAMEWORK-P5`
**Title:** i18n + hreflang + Sitemap Generation
**Scope:** Extend `SiteContentCompiler` to emit canonical tags, hreflang alternates,
and a `sitemap.xml` for a multi-locale route tree. Use the locale manifest and fallback
rules from P2.
**Authority:** Lab-only. No `igniter-org` edits. No `igniter-lang` changes.
**Why now:** P2 established the `SiteArtifact` route model with locale-aware routing.
P3 compiles page content. P4 composes pages into layouts. P5 adds the SEO metadata
layer that makes multi-locale pages machine-readable for search engines — the final
step before the static site artifact is usable end-to-end.
**Prerequisites:** P2 route tree fixture, P3 SiteContentCompiler, P4 LayoutEngine.
