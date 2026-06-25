# LAB-IGNITER-WEB-VIEWARTIFACT-LINK-NAV-P27

Status: CLOSED (proven 2026-06-25)
Route: standard / UI vocabulary proof
Skill: idd-agent-protocol

## Closing report (2026-06-25)

Proof doc: `lab-docs/lang/lab-igniter-web-viewartifact-link-nav-p27-v0.md`.

**Verdict: flat `link` node + helpers ARE enough for v0 nav + pagination — no schema/renderer change.**

**Files changed (3, additive, fixture/tests only):**
- `server/igniter-web/examples/todo_view_app/todo_views.ig` — `TodoDetailLink`, `NextPageLink`, `TodoNavHtml`.
- `server/igniter-web/examples/todo_view_app/routes.igweb` — `/todos/nav-html` route.
- `server/igniter-web/tests/todo_view_app_tests.rs` — `nav_html_renders_detail_links_and_next_page_link`.

**Shape:** `map(todos, t -> TodoDetailLink(t))` → detail links (`/todos/<id>`, label=title), then
`append(detail_links, next)` with `NextPageLink` (`/todos?after=<id>`). All flat `HtmlNode` via `MakeLink`;
hrefs via `concat`.

**href construction = NO DX pressure:** `concat(String,String)` is clean for every href; `append(Collection[T],T)`
(`stdlib_calls.rs:2099`) cleanly adds the trailing affordance (fleet alt `concat(coll,[x])`). The card's
"if concat is awkward" caveat did not trigger.

**Pagination:** needs only links (one `?after=` cursor leaf), no layout node. `{items,next}` envelope is a
data-projection concern, not a view-vocab gap.

**Bounded list/item layout: still HELD, NOT justified by this card.** Nav-as-links needs no grouping; only
per-item *grouping* (multiple controls per row) would justify P26's `list`/`item`. Honest observation: links
render as siblings in the `form` body (no nav/list container) — cosmetic, not a blocker.

**Tests:** `todo_view_app_tests` **16/16** (+1, incl. escaping + authored-order + appended-last); renderer
**15/15 unchanged** (untouched; unsafe-scheme fail-closed already covered by the link-node card). `git diff
--check` clean; no new node kind / nesting / raw HTML / DB / CSS.

**Next UI card:** none now — a `list`/`item` layout card becomes justified only when a real view must group
multiple controls per row.

> **Scope note:** working tree also carries the team's in-flight data-projection P6/P7 changes
> (`server/igniter-web/src/{igweb-serve,lib,read_continuation,runner_diag}.rs`) — NOT mine, left untouched.
> This card's diff is exactly the 3 fixture/test files above.

## Goal

Use the new `link` node in realistic Todo navigation and pagination-like affordances without expanding the
ViewArtifact schema again.

This is a pressure test after `LAB-IGNITER-WEB-VIEWARTIFACT-LINK-NODE`: prove whether `kind:"link"`
plus app-local helpers is enough for index↔detail navigation and simple "next page" links.

## Current Authority

Read first:

- `lab-docs/lang/lab-igniter-web-viewartifact-link-node-v0.md`
- `frame-ui/igniter-render-html/src/lib.rs`
- `frame-ui/igniter-render-html/tests/render_html_tests.rs`
- `server/igniter-web/examples/todo_view_app/todo_views.ig`
- `server/igniter-web/examples/todo_view_app/routes.igweb`
- `server/igniter-web/tests/todo_view_app_tests.rs`
- `lab-docs/lang/lab-igniter-web-viewartifact-evolution-readiness-p26-v0.md`

## Problem

The renderer now supports:

```json
{ "kind": "link", "text": "...", "action": "/safe/path" }
```

But P26 explicitly held richer list/grouping. Before adding layout or nested components, test the small
question: can real app navigation be expressed as flat `HtmlNode` collections plus helpers?

## Recommended Shape

Add app-local helpers only:

```ig
pure contract TodoDetailLink {
  input todo : TodoItem
  compute href : String = ...
  compute node : HtmlNode = call_contract("MakeLink", todo.title, href)
  output node : HtmlNode
}

pure contract NextPageLink {
  input after : String
  compute href : String = ...
  compute node : HtmlNode = call_contract("MakeLink", "Next page", href)
  output node : HtmlNode
}
```

Then add one route/test that renders a flat list containing:

- at least two todo detail links;
- one next-page link using a safe relative URL;
- malicious title text that is escaped;
- a deliberately unsafe URL test in renderer or Todo fixture if not already covered.

If string concatenation for hrefs is awkward or missing, document that as DX pressure and use the smallest
existing helper/form instead of inventing syntax.

## Boundary

Allowed:

- Edits in `todo_view_app` fixture/tests.
- Optional renderer tests only if a gap is found.
- Proof doc in `lab-docs/lang/`.
- Update this card with closing report.

Closed:

- No new renderer node kinds.
- No recursive/nested `children`.
- No layout/table/list schema.
- No raw HTML.
- No live DB.
- No CSS/assets.

## Required Proof Doc

Create:

`lab-docs/lang/lab-igniter-web-viewartifact-link-nav-p27-v0.md`

Include:

- whether link+helpers are enough for index/detail nav;
- exact helper shape;
- href construction limitations, if any;
- whether pagination UX needs only links or a future layout node;
- tests/counts.

## Acceptance

- [x] TodoView renders at least two detail links with safe relative hrefs.
- [x] TodoView renders a next-page or load-more style link.
- [x] Link text is escaped; no raw malicious text.
- [x] `javascript:`/unsafe URL remains fail-closed in renderer tests.
- [x] No new shared ViewArtifact fields or node kinds.
- [x] `todo_view_app_tests` green.
- [x] `igniter-render-html cargo test` green.
- [x] `git diff --check` clean.

## Reporting

Close with:

- whether flat link-node nav is enough for v0;
- whether bounded non-recursive list layout is still held or now justified;
- next UI card only if real pressure remains.
