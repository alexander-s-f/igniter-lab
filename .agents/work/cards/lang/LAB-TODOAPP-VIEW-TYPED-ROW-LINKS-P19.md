# LAB-TODOAPP-VIEW-TYPED-ROW-LINKS-P19

Status: CLOSED (proven 2026-06-26)
Route: standard / product proof
Skill: idd-agent-protocol

## Closing report (2026-06-26)

Proof doc: `lab-docs/lang/lab-todoapp-view-typed-row-links-p19-v0.md`.

**Verdict: row data drives navigation cleanly** — per-row detail links (`href` from `row.id`, label from
`row.title`) + a KEYSET load-more href (`/todos?after=<last row id>`) built entirely from typed crossed rows,
through the normal `dispatch_with_read` contour. No `rows_json`, no new primitive, no renderer/schema change.

**Files changed (2, additive, fixture+tests only):**
- `server/igniter-web/tests/fixtures/typed_html/typed_html.ig` — `TodoRowDetailLink`, `FetchTodoLinksHtml`,
  `TodoLinksHtmlFromRows` (P18 label flow untouched; both coexist, test picks the entry).
- `server/igniter-web/tests/typed_html_tests.rs` — `load_app_links()` + 2 tests.

**href construction = clean.** `TodoRow.id : String` → `concat("/todos/", row.id)` direct, no coercion;
`row.title` escaped in the link label. **Latent gap named (not hit):** a cursor/href from an *Integer* field
(`rank`) would need `Integer→String` (lang lacks it, P1/P2) — sidestepped because the keyset key `id` is a
String.

**Keyset load-more = no workaround.** `map(rows, r -> r.id)` → `last(ids)` (`Option[T]`, `stdlib_calls.rs:708`)
→ `or_else(_, "")` → `concat("/todos?after=", last_id)`. **`last` exists → NOT pressure.** Minor DX idiom note:
project the key column then `last` (avoids unwrapping `Option[Record]` with an awkward default record).

**Tests:** `typed_html_tests` **6/6** (4 P18 + 2 new, real read contour, fake adapter); `todo_view_app_tests`
**16/16** + `igniter-render-html` **15/15** unchanged. `git diff --check` clean.

**Next product slice:** (a) promote this exact flow to a **real DB-backed** route (opt-in `postgres`; only the
adapter changes — read contour + reconciliation already run); (b) a small **`Integer→String`** stdlib helper
if a numeric cursor/href is needed. Bounded `list`/`item` layout (P26) remains held.

> **Scope note:** working tree also carries the team's data-projection P6/P7 source changes — NOT mine. This
> card's diff is exactly the 2 fixture/test files above.

## Goal

Extend the typed rows -> HTML proof from labels/load-more to real row-driven navigation:

```text
ReadThen typed rows
  -> per-row detail links built from typed row fields
  -> keyset-style load-more href built from a row id/cursor
  -> RenderView text/html
```

This should prove row data can drive navigation, not just text labels.

## Current Authority

Read first:

- `lab-docs/lang/lab-todoapp-view-typed-rows-html-p18-v0.md`
- `lab-docs/lang/lab-igniter-web-viewartifact-link-nav-p27-v0.md`
- `server/igniter-web/tests/fixtures/typed_html/typed_html.ig`
- `server/igniter-web/tests/typed_html_tests.rs`
- `server/igniter-web/examples/todo_view_app/todo_views.ig`
- `server/igniter-web/tests/todo_view_app_tests.rs`
- `frame-ui/igniter-render-html/src/lib.rs`

## Problem

P18 proved typed rows can render escaped labels and a generic `Load more` link from `meta.truncated`.
P27 proved static/authored Todo rows can produce detail links and next-page links.

P19 should join them: typed host rows should produce per-row links and a keyset cursor link using typed row
fields (`id` or equivalent), without falling back to `rows_json`.

## Recommended Shape

Extend the focused DB-free typed HTML fixture:

```ig
pure contract TodoRowDetailLink {
  input row : TodoRow
  compute href : String = concat("/todos/", row.id)
  compute node : HtmlNode = call_contract("MakeLink", row.title, href)
  output node : HtmlNode
}

pure contract TodoRowsHtmlFromRows {
  input rows : Collection[TodoRow]
  ...
  compute links : Collection[HtmlNode] = map(rows, r -> call_contract("TodoRowDetailLink", r))
}
```

For keyset load-more, use the smallest honest route:

- if "last row" helper exists, build `/todos?after=<last.id>`;
- if not, use a carried cursor or fixed fixture cursor and document the missing collection-last helper as
  pressure;
- do not invent a new collection primitive inside this card.

## Boundary

Allowed:

- Update `typed_html` fixture/tests.
- Add app-local helpers only.
- Use fake read host only.
- Proof doc in `lab-docs/lang/`.
- Update this card with closing report.

Closed:

- No live Postgres.
- No new ViewArtifact node kind.
- No renderer change.
- No new stdlib primitive.
- No `rows_json`.
- No route/account/auth product semantics.

## Required Proof Doc

Create:

`lab-docs/lang/lab-todoapp-view-typed-row-links-p19-v0.md`

Include:

- exact helper shape;
- whether href construction from row fields is clean;
- whether keyset next link needed a workaround;
- whether a collection-last helper is now real pressure;
- tests/counts.

## Acceptance

- [x] Typed rows render per-row detail links from `row.id` and `row.title`.
- [x] Link text is escaped.
- [x] Hrefs are safe relative URLs and pass through existing `safe_url`.
- [x] A keyset/load-more link is rendered when `meta.truncated` is true.
- [x] No `rows_json` boundary is used.
- [x] No renderer/schema change.
- [x] `typed_html_tests` green.
- [x] `todo_view_app_tests` green.
- [x] `igniter-render-html cargo test` green.
- [x] `git diff --check` clean.

## Reporting

Close with:

- verdict on row-field-driven navigation;
- exact gap, if any (`last`, `Integer->String`, cursor envelope);
- next product slice: real DB-backed HTML route or small language helper.
