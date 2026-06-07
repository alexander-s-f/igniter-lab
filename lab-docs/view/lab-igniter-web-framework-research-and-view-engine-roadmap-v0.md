# Lab: Igniter Web Framework — Research and View Engine Roadmap (v0)

> **Status:** experimental · lab-only · no-canon · no-public-api · no-stable-schema
> **Category:** view
> **Track:** lab-igniter-web-framework-research-and-view-engine-roadmap-v0
> **Card:** LAB-WEB-FRAMEWORK-P1
> **Date:** 2026-06-07
> **Scope:** research and inventory only — no source code written in this card

---

## Pre-v1 Language Note

> We are actively shaping the future of Igniter. The toolchains, compilers, view engine,
> and site-generation ideas featured here represent active, pre-v1 exploration.
>
> APIs and artifacts may change. These materials are provided as-is for community learning,
> experimentation, and design discussion. Igniter is not a replacement for React, Svelte,
> Vite, or any existing web framework — it is an independently motivated, accountability-first
> language platform whose view and site artifacts are still being shaped.

---

## 1. What Should "Igniter Web Framework" Mean?

This is the core framing question for the web framework track. The answer is intentionally
layered — different meanings become appropriate at different stages of lab maturity.

### 1.1 What it is NOT (at this stage)

- Not a React/Svelte/Vue competitor shipping JS components to browsers.
- Not an HTMX or LiveView equivalent with a production-ready server protocol.
- Not a static site generator with a stable CLI and published plugin ecosystem.
- Not a public framework with a stable API, versioned releases, or compatibility guarantees.

These are closed claims at the current lab stage. Claiming any of them before the
underlying grammar, runtime, and artifact formats are stable would be misleading and
harmful to the project's credibility.

### 1.2 What it could be — staged meaning

**Stage 1 (now): View artifact compiler and safe renderer.**
The lab already proves this lane. The `.igv` DSL compiles to a content-addressed
`ViewArtifact` JSON. The `SSRRenderer` emits static HTML. The vanilla JS micro-runtime
hydrates it. This is a view artifact compiler, not a framework — and that is the honest
description at this stage.

**Stage 2 (near): Static site artifact model.**
The `igniter-org` site already has a hand-authored `build-docs.js` that compiles markdown
to HTML with i18n, canonical tags, hreflang, and sitemap support. Formalizing this into
a reproducible, testable artifact model — with routing policy, locale manifest, and content
pipeline rules — is a natural next step that the existing site pressure already motivates.

**Stage 3 (medium): Tutorial/spec/docs content compiler prototype.**
`igniter-lab` has `lab-docs/tutorial/` markdown content and `igniter-org` has a
tutorial build pipeline. A compiler that reads lab markdown with YAML frontmatter and
emits structured HTML pages with safety guards is achievable without depending on any
unstable language feature.

**Stage 4 (medium): Layout and component primitive set.**
The view engine's `ViewArtifact`, slot injection, and collection rendering proofs define
a component model. Extending this into a reusable layout/component primitive set for
docs pages (nav, header, content section, code block, table) would make the static site
compiler more capable without needing a JS framework.

**Stage 5 (later): i18n, hreflang, sitemap generation.**
The `igniter-org` site already has locale routing policy (`/en/`, `/ru/`, `/uk/`) and
an i18n fallback pipeline. These patterns are documentable and testable. A formal i18n
artifact model is a clear next step after the static site compiler stabilizes.

**Stage 6 (later): Contract schema to forms/view binding.**
The lab has proven slot-contract type linkage (P6/P7/P8/P9 proofs). Lowering this into
HTML input forms that bind changes back to UIState — without arbitrary DOM event listeners —
is a natural extension of the safe view model. This is where "web framework" behavior in
the traditional sense begins.

**Stage 7 (optional/research): Headless GUI artifact integration.**
The `igniter-gui-engine` has a headless scene/layout/constraint solver, slot binding,
vector renderer, and reactive recalculation loop. Whether and how this integrates with
web rendering (SVG export, canvas, or Tauri-native) remains a research question. This
stage is not on the critical path for static site or tutorial content delivery.

---

## 2. Current Inventory

The following table captures what has been inspected in this research card and what
evidence exists today.

| Component | Files / Docs Inspected | Current Capability | Evidence Maturity | Gaps | Roadmap Relevance |
|:---|:---|:---|:---|:---|:---|
| **View DSL parser / renderer** (`igniter-view-engine`) | `lib/igv_compiler.rb`, `lib/ssr_renderer.rb`, `docs/igv-grammar-sketch-v0.ebnf`, P1–P9 proof runners | Ruby DSL compiles `.igv` to `ViewArtifact` JSON. SSR emits HTML. EBNF grammar sketch exists. | Proven-Lab — 405/405 assertions across P1–P9. Grammar sketch is Draft-Lab (no parser implementation). | No grammar-based parser. No source maps. Ruby `instance_eval` is not sandboxed for untrusted input. | Critical foundation. View DSL is the entry point for any component model. |
| **ViewArtifact / view_tree** (`view_artifact.rb`) | `lib/view_artifact.rb`, layer consolidation readiness map v0 | Content-addressed JSON artifact. UIState, read-only SlotValues, elements, collections, opcode whitelist. | Proven-Lab — 100% test coverage per readiness map. | No routing or page-level composition model. One view per artifact. | Core target format. Any web framework needs this as its compile output. |
| **Safe renderer policy** (`ssr_renderer.rb`, `igniter_view_runtime.js`) | P1 proof, view layer consolidation doc | SSR emits HTML with `data-ig-*` attributes. Vanilla JS hydrates. No `eval`, no `innerHTML`, no `fetch`. | Proven-Lab | No progressive enhancement model. No form-field event delegation. | Safety boundary must be preserved in any web expansion. |
| **Slot / value injection** (`slot_type_linker.rb`, `contract_schema_supplement.rb`) | P6/P7/P8/P9 proof docs, readiness map | Slot-to-contract type linkage. Supplement overlay for collection item fields. Linkage diagnostic report. | Proven-Lab — 55/57/66/58 assertions across P6–P9. | No live contract execution. Linkage is static analysis only at compile time. | Enables typed data-binding for view components driven by contract output schemas. |
| **Contract schema extraction** (`compiled_contract_extractor.rb`) | P7 proof doc, view layer consolidation | Reads compiled contract JSON from `.igapp/contracts/`. Normalizes output ports to schema types. | Proven-Lab — 57 assertions. | Requires compiled contract artifacts to be present. Cannot introspect un-compiled sources. | Bridges compiler output to view binding. Essential for forms/view integration. |
| **GUI scene / layout / headless renderer** (`igniter-gui-engine`) | `gui-engine/README.md`, `lab-docs/gui/README.md`, selected gui lab docs | Headless JSON scene tree. Constraint solver, hit tester, slot binder, vector renderer, timeline resolver. | Proven-Lab — 11-phase proof suite (NGUI-P1..P11). | No browser rendering target (SVG, canvas). No web layout mapping. Tauri/native only path explored. | Optional/research relevance to web — headless layout could inform component sizing but is not required. |
| **IDE preview / introspection viewer** (`igniter-ide`, Tauri IVF track) | `ide/README.md`, `lab-docs/ide/README.md`, Tauri IVF card series (P2–P20) | SvelteKit/Tauri shell. Monaco editor. Contract browser, trace viewer, view preview panel. HMAC-authenticated trace sessions. | Active frontier — Tauri IVF track is mature in lab terms. Svelte is a build dependency. | Tauri/desktop only — no web-hosted preview. Relies on `node_modules` and Svelte toolchain. | Preview/debug tooling. Not a web delivery surface; informs component authoring UX. |
| **Design system tokens** (`igniter-design-system`) | `design-system/README.md`, `assets/ig-brand.css`, `assets/ig-mark.js` | HSL color tokens, typography primitives, SVG mark renderer, dependency-free. Mockup HTML snapshots exist. | Lab snapshot — design-canvas and brand system are inspectable; not a published npm package. | No CSS component library. No token-to-artifact compiler. Mockups are HTML files, not a component system. | Visual consistency signal. Token CSS can be imported by any static site compiler output. |
| **i18n / tutorial / site pressure** (`igniter-org`) | `igniter-org/README.md`, `docs/url-routing-policy.md`, `docs/i18n-pipeline.md`, `docs/tutorial-build-pipeline.md` | Vite-based static multi-page site. `build-docs.js` compiles markdown to HTML. Locale routing (en/ru/uk). hreflang, canonical tags, sitemap.xml, robots.txt designed. | Active site — `igniter-org` is deployed or being prepared for `igniter-lang.org`. Build pipeline is hand-authored Node.js. | Build pipeline is not a reusable library. No CI proof runner. No formal content schema. Tutorial content is sparse (2 pages). Sitemap and robots.txt are specified but generation is manual-or-scripted. | Strong real-world pressure. `igniter-org` is the most immediate consumer of any web framework artifact. |

---

## 3. Requirement Map

The following requirements are derived from current lab evidence and site pressure.
Each requirement is classified by source and priority stage.

### Routing

- Clean directory-style URLs (`/en/tutorial/name/index.html`).
- Locale-prefixed route tree (`/<locale>/<surface>/<name>/`).
- Fallback page generation for missing translations.
- `robots.txt` and `sitemap.xml` emission.
- Source: `igniter-org/docs/url-routing-policy.md` — active site pressure.
- Priority: P2 (route map and static site artifact model).

### Layout / Components

- Reusable page layout primitives: nav, header, content section, footer.
- Code block rendering with semantic coloring.
- Table rendering with responsive wrapper.
- Alert/banner component (translation pending, pre-v1 notice).
- Source: `igniter-org/docs/tutorial-build-pipeline.md`, design system.
- Priority: P4 (layout and component primitive set).

### i18n

- Locale manifest (`locales.json`) driving route tree.
- YAML frontmatter schema with `source_project`, `source_path`, `source_revision`,
  `translation_status`, `non_authority_disclaimer`.
- Translation freshness classification (`declared_only`).
- Locale switcher navigation.
- Source: `igniter-org/docs/i18n-pipeline.md`.
- Priority: P5 (i18n + hreflang + sitemap).

### Markdown / Docs / Tutorial Generation

- Markdown to HTML with header, bold, italic, code block, table, link support.
- Safety guards: no absolute paths, no `file://` URIs, no `javascript:` links, HTML escaping.
- Translation banner injection from frontmatter.
- Source: `igniter-org/docs/tutorial-build-pipeline.md`, `content/test-fixtures/`.
- Priority: P3 (tutorial and spec content compiler prototype).

### SEO / Sitemap / hreflang

- `<link rel="canonical">` selection logic (translated vs fallback).
- `<link rel="alternate" hreflang="...">` per locale on every page.
- `sitemap.xml` with `xhtml:link` entries.
- Source: `igniter-org/docs/url-routing-policy.md`.
- Priority: P5.

### Design System

- HSL color token CSS importable by generated pages.
- SVG mark renderer (dependency-free JS).
- Typography primitives.
- Source: `igniter-design-system/assets/`.
- Priority: P4 (when component set is built).

### Safe HTML Rendering

- No `innerHTML` dynamic injection.
- No `eval`.
- No `fetch` from view runtime.
- Opcode whitelist for UIState mutation (`set_ui_state`, `toggle_ui_state`, `clear_ui_state`).
- Source: `igniter-view-engine` P1–P9 proofs.
- Priority: P1 (already proven); carry the policy forward into every new surface.

### State / Slots

- UIState as mutable tab/accordion/toggle state. Read-only SlotValues from contract output.
- Slot-contract type linkage at compile time.
- Collection rendering with per-item params.
- Source: `igniter-view-engine` P2/P5/P6 proofs.
- Priority: P4 (component primitive set); P6 (forms/view binding).

### Forms

- HTML input elements (text, checkbox) that write changes back to UIState.
- Safe bidirectional binding without DOM event listener leak hazards.
- Source: view layer consolidation Option C recommendation; `lab-docs/core/` forms pressure.
- Priority: P6.

### Contract Execution Integration

- Static slot-contract type linkage is proven (P6–P9).
- Live contract invocation from view is out of scope for the web framework at this stage.
- Forms integration (P6) bridges compiled contract schema to input form generation.
- Source: `lab-docs/ide/lab-contract-schema-to-input-form-generator-v0.md`.
- Priority: P6.

### Preview / Debug Tooling

- Tauri IVF IDE shell covers developer preview today.
- A browser-hosted preview (iframe-based or web-hosted) is not yet scoped.
- LinkageReport JSON is IDE-parseable for inline editor diagnostics.
- Source: view layer consolidation section 5/6; `lab-docs/ide/`.
- Priority: deferred — current Tauri IDE is sufficient for lab phase.

---

## 4. Risk Map

### Framework Drift

**Risk:** Scope grows from "view artifact compiler" to "full-stack web framework" before
the underlying grammar, runtime, and routing model are stable. Each addition couples the
lab to more unstable surfaces.

**Mitigation:** Gate each stage behind an explicit proof or artifact goal. Require a
P-numbered card for each stage. Do not proceed to P4+ until P3 evidence is clean.

### Overbuilding

**Risk:** The lab builds a bespoke content compiler, markdown parser, routing engine, and
component system in parallel, duplicating existing work in `igniter-org` without returning
clean pressure.

**Mitigation:** Treat `igniter-org` as the consumer and evidence source, not as something
to replace. P2–P3 should produce artifacts that `igniter-org` could adopt, not a competing
build system.

### JS Framework Dependency Creep

**Risk:** The IDE shell uses Svelte/Tauri. The site uses Vite. New web work reaches for
React or another JS framework because it is familiar, introducing runtime dependencies that
conflict with the zero-dependency philosophy of the view engine.

**Mitigation:** The view engine's vanilla JS micro-runtime is the reference. Any new
browser-facing runtime should be zero-dependency or explicitly scoped to a dev-only tool.
Production-facing HTML must not require a JS framework to render.

### Unstable Grammar

**Risk:** The `.igv` grammar sketch (EBNF, Draft-Lab) is iterated into a public-facing DSL
before the underlying Igniter-Lang grammar is stable, creating a divergence between the
lab DSL and the eventual canonical syntax.

**Mitigation:** Keep the grammar a design sketch. The Ruby DSL is Tier 0 — lab authoring
only. No public syntax claims. Any grammar hardening requires an explicit canonical route
through `igniter-lang`.

### Public/Canon Claim Drift

**Risk:** Lab docs and site copy begin claiming "Igniter Web Framework" as a stable product,
creating expectations the lab cannot satisfy and undermining trust in the language project.

**Mitigation:** All lab-facing and site-facing copy uses the pre-v1 feedback language from
`lab-docs/tutorial/site-projection-excerpts.md`. No claim of framework readiness, stable
API, or production suitability.

### SEO / Public Indexing Before Route Maturity

**Risk:** `igniter-org` is indexed by search engines before the routing policy, canonical
tags, and hreflang headers are fully implemented. Fallback pages (English content served
at `/ru/` routes) get indexed without canonical redirects, creating duplicate content penalties.

**Mitigation:** The `url-routing-policy.md` and `i18n-pipeline.md` designs address this.
P5 of the web framework roadmap should verify that canonical + hreflang + sitemap generation
is complete and tested before additional locales or pages are added.

---

## 5. Staged Roadmap

### P1 — Research, Inventory, and Requirements (this card)

**Goal:** Understand what exists across all lab components relevant to a web framework.
Map requirements from real site pressure. Produce a stable research document and card receipt.

**Read scope:** All of `igniter-view-engine`, `igniter-gui-engine`, `igniter-ide`,
`igniter-design-system`, `lab-docs/view/`, `lab-docs/gui/`, `lab-docs/ide/`,
`igniter-org/docs/`, `igniter-org/README.md`, `igniter-lang/docs/language-covenant.md`.

**Write scope:** Two markdown files: this roadmap document and the card receipt.
No source code written.

**Proof / Verification:** `git -C igniter-lab diff --check` passes. No absolute paths or
`file://` links in output files.

**Expected artifact:** `lab-docs/view/lab-igniter-web-framework-research-and-view-engine-roadmap-v0.md`
and `.agents/work/cards/view/LAB-WEB-FRAMEWORK-P1.md`.

**Non-goals:** No source code. No routing implementation. No site generator. No framework claim.

---

### P2 — Route Map and Static Site Artifact Model

**Goal:** Define a formal static site artifact model: route tree, page descriptor, locale
manifest, and content pipeline rules. Produce a proof runner that validates a route tree
against the policy in `igniter-org/docs/url-routing-policy.md`.

**Read scope:** `igniter-org/docs/url-routing-policy.md`, `igniter-org/vite.config.js`,
`igniter-org/scripts/build-docs.js` (structure only), `igniter-org/content/i18n/locales.json`
(if it exists).

**Write scope:** A `SiteArtifact` model document in `lab-docs/view/` and a proof runner
(Ruby) that validates a route tree fixture against the policy. One route tree fixture.

**Proof / Verification:** `ruby run_site_artifact_proof.rb` passes with all routes in the
test fixture correctly classified (canonical, fallback, localized).

**Expected artifact:** Route tree fixture, `SiteArtifact` model spec, proof runner.

**Non-goals:** No Vite/build system changes. No `igniter-org` edits. No live site deployment.
No router implementation for browser navigation.

---

### P3 — Tutorial / Spec Content Compiler Prototype

**Goal:** Build a Ruby proof-local compiler that reads lab markdown (with YAML frontmatter)
and emits HTML pages with the safety guards from `igniter-org/docs/tutorial-build-pipeline.md`.
Cover: headers, code blocks, tables, links, translation banner injection. Run the safety
check suite against `content/test-fixtures/`.

**Read scope:** `igniter-org/docs/tutorial-build-pipeline.md`, `igniter-org/content/test-fixtures/`,
`lab-docs/tutorial/*.md` (for test input).

**Write scope:** `igniter-view-engine/lib/` or a new `igniter-site/lib/` directory — a
Ruby content compiler class. Proof runner. Fixture pages.

**Proof / Verification:** Proof runner compiles test markdown fixtures and verifies:
absolute path rejection, `file://` rejection, `javascript:` rejection, HTML escaping,
frontmatter translation banner injection. All safety fixture tests pass.

**Expected artifact:** Content compiler class, proof runner, pass/fail matrix.

**Non-goals:** No Vite or Node.js build system changes. No i18n locale routing yet (P5).
No live publishing. No CSS/design system integration yet (P4).

---

### P4 — Layout / Component Primitive Set

**Goal:** Define a set of reusable page layout primitives — nav, header, content section,
footer, code block, table, alert/banner — as `ViewArtifact`-compatible templates or HTML
partials. Verify they compose with the P3 content compiler output and use design system tokens.

**Read scope:** `igniter-design-system/assets/ig-brand.css`, `igniter-view-engine/lib/`,
P3 output artifacts.

**Write scope:** Layout primitives (HTML templates or `ViewArtifact` fixtures), updated
content compiler to apply them. Proof runner verifying composed page output.

**Proof / Verification:** Proof runner generates a sample docs page from markdown using the
layout primitives and verifies: correct nav, footer, and content section structure; design
token CSS applied; no arbitrary inline styles.

**Expected artifact:** Layout primitive library (HTML or ViewArtifact-based), composition proof.

**Non-goals:** No JS framework. No SSR server process. No dynamic routing.

---

### P5 — i18n + hreflang + Sitemap Generation

**Goal:** Extend the P3 content compiler to emit canonical tags, hreflang alternates, and
a `sitemap.xml` for a multi-locale route tree. Use the locale manifest and fallback rules
from `igniter-org/docs/i18n-pipeline.md`.

**Read scope:** `igniter-org/docs/i18n-pipeline.md`, P2 route map artifact, P3 compiler.

**Write scope:** Locale-aware compiler extension, sitemap emitter, hreflang injector. Proof runner.

**Proof / Verification:** Proof runner verifies: each page has canonical tag, all locale
alternates present, `sitemap.xml` contains all routes, fallback pages canonical to English
source, translated pages canonical to self.

**Expected artifact:** i18n-capable content compiler, sitemap emitter, proof runner.

**Non-goals:** No live deployment. No runtime locale switching (build-time only).
No new locale additions beyond en/ru/uk.

---

### P6 — Contract Schema to Forms / View Binding

**Goal:** Lower basic HTML input elements (text fields, checkboxes) into the view model
so that input changes write back to UIState. Use the compiled contract schema extraction
(P7/P8 proofs) to generate input forms from contract output port definitions.

**Read scope:** `igniter-view-engine/lib/compiled_contract_extractor.rb`,
`igniter-view-engine/lib/slot_type_linker.rb`, `lab-docs/ide/lab-contract-schema-to-input-form-generator-v0.md`,
`lab-docs/core/` forms pressure docs.

**Write scope:** `igniter-view-engine/lib/` — a form lowering module. Proof runner.
ViewArtifact schema extension for input elements (if needed).

**Proof / Verification:** Proof runner generates an input form from a compiled contract
schema fixture and verifies: correct input types, UIState write-back wiring, no arbitrary
DOM event listener registration.

**Expected artifact:** Form lowering module, proof runner, schema extension (if any).

**Non-goals:** No live contract execution from the browser. No network requests from the
view runtime. No server-side form submission handler.

---

### P7 — Optional: Headless GUI Artifact Integration

**Goal:** Research whether the `igniter-gui-engine` headless scene/layout solver can emit
SVG or canvas-renderable artifacts suitable for a browser context (docs diagrams, interactive
layout illustrations).

**Read scope:** `igniter-gui-engine/lib/vector_renderer.rb`, `lab-docs/gui/` headless
vector renderer and composition preflight docs.

**Write scope:** Research document only. No source code unless a minimal proof is warranted.

**Proof / Verification:** Research document concludes with a clear go/no-go recommendation
for SVG emission and a rationale.

**Expected artifact:** Research doc in `lab-docs/view/` or `lab-docs/gui/`.

**Non-goals:** No production SVG rendering. No browser canvas API integration. No Tauri
window management.

---

## 6. Recommended Immediate Next Card: P2

**Card ID (suggested):** `LAB-WEB-FRAMEWORK-P2`
**Title:** Route Map and Static Site Artifact Model
**Scope:** Read `igniter-org` routing policy and content pipeline. Define `SiteArtifact`
JSON model. Proof-run route tree validation.
**Authority:** Lab-only. No `igniter-org` edits. No `igniter-lang` changes. No site deployment.
**Why now:** The `igniter-org` site has real routing, locale, canonical, and sitemap
requirements that are not yet formally modeled. A clean artifact model for P2 gives P3–P5
a stable foundation to build on, and it feeds pressure back to `igniter-org` without
requiring any code to be merged there.

---

## 7. Non-Claims

| Claim | Status |
|:---|:---|
| Igniter is a production web framework | **No** — lab research only |
| Igniter replaces React, Svelte, or Vite | **No** — different motivation and scope |
| `.igv` syntax is stable or canonical | **No** — draft sketch, may change entirely |
| `ViewArtifact` schema is a public API | **No** — internal proof format |
| `igniter-org` is published or production-ready | **Status from igniter-org README** — pre-v1, actively developed |
| GUI engine has a browser rendering path | **No** — headless only at this stage |
| Forms lowering is implemented | **No** — P6 is future work |
| i18n pipeline generates sitemap automatically | **Specified, not yet proved in lab** — P5 work |
