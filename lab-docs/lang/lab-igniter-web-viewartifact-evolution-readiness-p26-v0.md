# lab-igniter-web-viewartifact-evolution-readiness-p26-v0

Card: `LAB-IGNITER-WEB-VIEWARTIFACT-EVOLUTION-READINESS-P26`
Route: standard / schema readiness · Skill: idd-agent-protocol
Status: schema readiness packet (no code/schema/renderer change; no Todo HTML impl; no canon claim)
Date: 2026-06-25
Builds on: P24 HTML expression model · P25 template dialect · Data Projection P1-P5.

> **Authority boundary.** Schema readiness only. No renderer/schema/prelude change, no TodoApp HTML, no canon
> claim. Cited against live source + green tests.
>
> **Meta-Architect's red flag (the reason this card matters):** the current `ViewArtifact` is **flat**. The
> next real pain is *vocabulary evolution* (lists, links, sections, repeated items) — **not** a templating
> engine — and it must be done **without recursive mush in the language prematurely.** This packet draws that
> line.

---

## Headline

**Verdict: mostly hold — one minimal, pre-designed extension is warranted now: a `link` node.** Almost every
TodoApp HTML need is met by the current vocabulary + helper contracts (P24 Idiom A). The single genuine
*schema* gap is **links/anchors** — required for pagination ("load more") and index↔detail navigation — and
the safety machinery for it (`safe_url`) is **already built and tested but unused**
(`frame-ui/igniter-render-html/src/lib.rs:76-102,317-341`). A second, *optional* step — a **bounded one-level
`list`/`item` grouping** for richer per-row UI — is recommended only if the flat label list proves too weak,
and must be done as a **distinct non-recursive type** (mirroring the existing 2-level `workbench`), never as a
self-referential `HtmlNode`.

---

## 1. Current node inventory (Q1) — verified

Tests green 2026-06-25: `igniter_render_html` **11/11** (3 lib + 8 integration); `todo_view_app_tests`
**14/14** (drives `render_html` end-to-end incl. the fail-closed path).

| Layer | Vocabulary | Renders to | Where |
| --- | --- | --- | --- |
| Layouts | `form`, `workbench` | `<form class="ig-form">` / `<section class="ig-workbench">` | `render-html:115-121` |
| `form` components | `label` | `<p class="ig-label">` (escaped text) | `render-html:241-244` |
| | `button` | `<button type="submit" id data-action>` (escaped) | `render-html:245-250` |
| | `text` | `<label><input type="text" name required></label>` | `render-html:265-271` |
| | `checkbox` | `<label><input type="checkbox"></label>` | `render-html:272-276` |
| | `select` | `<select>` + `<option>`s from `options[]` | `render-html:277-300` |
| `workbench` | `data.leads` (list) + `regions.main.fields` | `<aside><ul><li>` + form fields | `render-html:192-235` |
| Prelude record | `HtmlNode { kind, id, label, text, required, action, options }` — **flat, all required** | — | `lang/igniter-compiler/src/igweb.rs:53-61` |
| Wrapper | `ViewArtifact { artifact, layout, title, body : Collection[HtmlNode] }` | — | `igweb.rs:63-68` |

**Structural facts (the bound):**
- The body is a **flat array of leaf components** — no nesting, no containers (`render-html:178-180`).
- The only "list" is the hardcoded `workbench` `data.leads` (strings) (`render-html:215-221`).
- **No link/anchor node** — `safe_url` exists, is fail-closed and tested, but *"the v0 ViewArtifact
  vocabulary has none yet, so no URL is emitted today"* (`render-html:76`).
- The canonical schema is *intentionally* this shape: ViewArtifact "COMPILES to the proven Rust kit
  (`Form`/`Workbench`)" (`frame-ui/igniter-ui-kit/src/view_artifact.rs:1-8`) — the flatness is by design,
  not an HTML-renderer shortfall.
- Escaping/fail-closed are projector-owned: every leaf escaped; unknown kind → `UnsupportedNode`; no raw HTML
  (`render-html:9-13,252,301`).

---

## 2. TodoApp HTML need matrix (Q2) — need → covered? → gap type

TodoApp routes (from the live API, P1): index/list, detail, create, done, delete, pagination (`?after=`),
errors/empty.

| Need | Current vocab covers it? | Gap type |
| --- | --- | --- |
| **Create form** (title input + submit) | **Yes** — `form` + `text` + `button` | none (this is exactly what the vocab is for) |
| **Done / delete actions** | **Yes** — `button` (`action`/`id`) per row; `checkbox` available | none |
| **Detail** (one todo) | **Yes** — `label`/`text` nodes | none |
| **Index / list** (todos) | **Partial** — `map(rows → label)` gives a flat label sequence (`todo_views.ig:144`) | flat list ✓; **rich per-item row** (title + state + its own action buttons grouped) → nesting gap |
| **Empty state** ("no todos") | **Yes** — a `label` (helper) | none (helper/convention) |
| **Error view** (vs JSON `RespondError`) | **Yes** — `label` nodes | none (helper); dedicated error styling optional |
| **Pagination "load more"** | **No** — needs an anchor to `?after=<cursor>` | **SCHEMA GAP → `link` node** |
| **Navigation** (index ↔ detail) | **No** — needs an anchor | **SCHEMA GAP → `link` node** |
| **CSS classes** | **Yes** — renderer emits `ig-*` classes (host-owned) | none |
| **Assets (css/js files)** | out of v0 (SSR-only) | deferred (P27) |

**Reading:** the matrix collapses to *two* schema questions — **links** (clear, needed now) and **per-item
grouping** (optional, careful). Everything else is current-vocab + helpers.

---

## 3. Helper/convention vs schema (Q3, Q4, Q5)

| Concern | Solve with… | Why |
| --- | --- | --- |
| flat list of todos, empty state, detail, create form, error-as-labels, `<Row>ToNode` | **app-local helper contracts** (no schema change) | uses existing nodes; the P20-P23 helper pattern + P4 Idiom A already do this |
| **link / anchor** (pagination, navigation) | **schema: a `link` node** (renderer arm + prelude; `safe_url` already built) | no existing node emits a URL; helpers cannot synthesize an `<a href>` the renderer won't produce |
| **rich per-item row** (grouped title+actions) | **schema (optional): a bounded `list`/`item` layout** | the flat `body` cannot nest; a grouped row needs one bounded level — but must avoid recursion (§4) |

Design-bias order honored: **prefer helpers before touching the shared schema** (the card's bias) — only
links cross into schema *necessarily*; grouping is optional.

---

## 4. Minimal v0 extension (Q6) — and the no-recursion discipline

**Recommended now — the `link` node (minimal, pre-designed, fail-closed):**
- Reuse the existing flat `HtmlNode` fields: `kind: "link"`, `text` = link label, `action` = href. **No new
  field** needed (the prelude record already carries `text` + `action`).
- Renderer: a new `render_component` arm emitting `<a href="{safe_url(action)}">{escape(text)}</a>` — routing
  the href through the **already-built, already-tested** `safe_url` (fail-closed on non-`http(s)`/relative,
  `render-html:77-102`).
- This unblocks pagination ("load more" → `?after=<cursor>`) and index↔detail navigation — the two real gaps
  — with the smallest possible surface and **zero new safety code** (the URL allowlist exists).

**Optional next — a bounded `list` layout (only if the flat list proves too weak):**
- A new layout `list` whose artifact is `{ layout: "list", title, items: Collection[ListItem] }` with a
  **distinct, non-recursive** `ListItem { title : String, body : Collection[HtmlNode] }` — exactly ONE level
  of nesting (list → item → flat leaves), mirroring the existing 2-level `workbench`
  (`data.leads` + `fields`, `render-html:192-235`).
- **The discipline (Meta-Architect's red flag):** do **not** add a `children : Collection[HtmlNode]` field to
  `HtmlNode` itself — that is self-referential and would introduce recursive types into `.ig` (which has none,
  `igweb.rs:36`) and unbounded nesting into the renderer. A *separate* `ListItem` type gives the needed one
  level with **no recursion**. If a future view needs deeper nesting, that is a deliberate, named layout
  evolution — never an open-ended recursive node.

**Hold everything else:** no table primitive, no arbitrary nesting/sections, no raw HTML, no asset nodes —
until a concrete view demands them with a bounded shape.

---

## 5. XSS / fail-closed preservation (Q7)

Every extension must keep the projector's invariants (`render-html:9-13`):
- `link` href → **must** go through `safe_url` (fail-closed: `javascript:`/`data:`/`mailto:` → `UnsafeUrl`,
  `render-html:93-97,328-341`); link text escaped.
- unknown `kind` (incl. a not-yet-implemented one) → **`UnsupportedNode`** fail-closed (`render-html:252,301`).
- `list`/`ListItem` → each leaf still escaped; empty `items` → reuse the existing empty-body refusal
  (`render-html:169-173`).
- **No raw-HTML node, ever** — the closed vocabulary is what removes the injection surface.

---

## 6. Tests a future implementation would need

For the `link` node:
- `link` with relative / `http` / `https` href → rendered `<a>` with escaped href + text;
- `link` with `javascript:` / `data:` href → fail-closed `UnsafeUrl` (no `<a>` emitted);
- `link` text containing `<script>` → escaped (no injection);
- pagination view: a `link` to `?after=<id>` renders and round-trips to the keyset route (`?after=` already
  live, P1).

For a bounded `list` (if pursued):
- `list` of N `ListItem`s → N grouped blocks, items + leaves in order, each escaped;
- empty `items` → fail-closed (existing empty-body rule);
- `ListItem.body` with an unknown leaf kind → `UnsupportedNode` (fail-closed propagates through one level);
- byte-identical render to the equivalent hand-authored flat form where structure overlaps (regression).

Cross-cutting: `todo_view_app`-style end-to-end (RenderView → `render_html` → escaped bytes) for each.

---

## Verification

```bash
rg -n "HtmlNode|ViewArtifact|kind|label|button|checkbox|select|options|unsupported_node|RenderView|escape" \
  server/igniter-web server/igniter-render-html lab-docs/lang .agents/work/cards/lang \
  > /tmp/igniter-viewartifact-evolution-grep.txt        # 3231 hits

cargo test --test todo_view_app_tests                    # 14/14 (from server/igniter-web)
cargo test                                               # igniter_render_html 11/11 (from frame-ui/igniter-render-html: 3 lib + 8 integration)
git diff --check                                         # clean
```

(The card's `cargo test -p igniter_render_html` resolved to 0 tests via `-p` in this layout; running plain
`cargo test` inside `frame-ui/igniter-render-html` runs the real 11. Reported honestly.)

---

## Reporting

- **Current vocabulary verdict:** sufficient for create form, actions, detail, empty/error, and a *flat* list
  (helpers + P24 Idiom A) — verified green. **One real schema gap: links/anchors** (pagination + navigation);
  a richer per-item list is an *optional* second step.
- **Recommended evolution / hold:** **add one minimal node — `link`** (reuses `text`/`action` fields; renders
  via the already-built fail-closed `safe_url`). **Hold** everything else; if a grouped list is later needed,
  add a **bounded, non-recursive `list`/`item` layout** (distinct `ListItem` type, one level, mirroring
  `workbench`) — **never** a self-referential `HtmlNode`.
- **Next implementation card:** `LAB-IGNITER-WEB-VIEWARTIFACT-LINK-NODE` (the `link` node + `safe_url` wiring +
  prelude field + the §6 fail-closed tests) — small, unblocks pagination/navigation for the TodoApp HTML
  list. The bounded `list` layout is a held follow-on, pursued only on demonstrated need.
