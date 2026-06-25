# LAB-TODOAPP-VIEW-TYPED-ROWS-HTML-P18

Status: CLOSED (2026-06-25) — typed rows → real text/html through the runner; zero production-code change
Route: standard / product proof
Skill: idd-agent-protocol

## Goal

Join the two proven halves of the stack:

```text
ReadThen typed rows + DatasetMeta
  -> Todo view continuation
  -> map/filter app rows into HtmlNode helpers
  -> RenderView
  -> real text/html
```

This should prove that TodoApp HTML can render database-shaped rows without `rows_json : String`, request-body
artifact JSON, or manual node enumeration.

## Current Authority

Read first:

- `lab-docs/lang/lab-igniter-data-projection-boot-reconciliation-p7-v0.md`
- `server/igniter-web/tests/fixtures/typed_readthen/typed_readthen.ig`
- `server/igniter-web/tests/typed_readthen_tests.rs`
- `server/igniter-web/examples/todo_view_app/todo_views.ig`
- `server/igniter-web/examples/todo_view_app/routes.igweb`
- `server/igniter-web/tests/todo_view_app_tests.rs`
- `frame-ui/igniter-render-html/src/lib.rs`
- `frame-ui/igniter-render-html/tests/render_html_tests.rs`

Live code wins over card prose.

## Why This Card Exists

P7 proves typed rows can cross through the normal runner contour into a continuation. The typed fixture already
renders a small `RespondView`/view-like shape, but it is still a proof fixture. TodoView proves app-local
helpers (`MakeLabel`, `MakeButton`, `MakeLink`, `FormView`) can emit real HTML, but its rows are authored
inside the app.

P18 should make the product-shaped bridge explicit: host rows become typed app rows, then app-authored
ViewArtifact becomes HTML.

## Recommended Shape

Use a focused DB-free fixture or extend the smallest existing Todo view fixture. Prefer keeping real Postgres
out of scope; use the fake read host already used by typed `ReadThen` tests.

Example shape:

```ig
type TodoRow {
  id : String
  title : String
  done : Bool
}

pure contract TodoHtmlFromRows {
  input req : Request
  input rows : Collection[TodoRow]
  input meta : DatasetMeta
  input carry : String
  compute pending : Collection[TodoRow] = filter(rows, t -> t.done == false)
  compute body : Collection[HtmlNode] = map(pending, t -> call_contract("TodoLabel", t))
  compute view : ViewArtifact = call_contract("FormView", "Todos", body)
  compute d : Decision = RenderView { status: 200, view: view }
  output d : Decision
}
```

If the exact helper signatures differ, follow live `todo_view_app`.

## Questions To Answer

1. Can the continuation use `DatasetMeta` in the rendered view without extra host work?
2. Can fake rows with `String`/`Bool` fields render through the same helpers as authored domain rows?
3. Can `filter` + `map` over typed host rows preserve order and escaping?
4. Does an empty row set render an app-owned empty state, not a host error?
5. Does a drifted host policy still fail before any HTML continuation dispatch?
6. Does the old JSON/request-body `Render` path remain green?

## Boundary

Allowed:

- Add a focused fixture and tests under `server/igniter-web/tests`.
- Optionally add a small TodoView example route if it stays DB-free and app-local.
- Use fake read host/policy only.
- Proof doc in `lab-docs/lang/`.
- Update this card with closing report.

Closed:

- No live Postgres.
- No new ViewArtifact schema unless proven necessary.
- No JSON parser in `.ig`.
- No `rows_json` fallback in the new proof path.
- No app auth/account semantics.
- No `.igweb` syntax change.

## Required Proof Doc

Create:

`lab-docs/lang/lab-todoapp-view-typed-rows-html-p18-v0.md`

Include:

- exact fixture/app route used;
- typed row schema;
- how `DatasetMeta` is used or intentionally not used;
- behavior for found, empty, drift, and row mismatch;
- exact tests/counts.

## Acceptance

- [x] A `ReadThen` entry reaches a typed HTML continuation through normal `dispatch_with_read`. — `FetchTodoHtml`→`TodoHtmlFromRows`
- [x] Continuation declares `rows : Collection[TodoRow]` and `meta : DatasetMeta`. — fixture
- [x] Handler maps typed rows to `HtmlNode` helpers, not manual HTML strings. — `map(pending, t -> call_contract("TodoRowLabel", t))`
- [x] Response is real `text/html` via `RenderView`. — `typed_rows_render_to_escaped_html` (content-type text/html)
- [x] Escaping still holds for malicious row title. — `Buy milk &lt;script&gt;`, no raw `<script>`
- [x] Empty rows are app-owned output, not host failure. — `empty_rows_render_app_owned_empty_state` (200 "No todos yet")
- [x] Projection drift still fails before continuation dispatch. — `drift_fails_before_html_continuation` (500, query_count 0)
- [x] Existing `todo_view_app_tests` remain green. — 15 passed
- [x] Existing `typed_readthen_tests` remain green. — green
- [x] `igniter-render-html cargo test` remains green. — green
- [x] `git diff --check` clean.

## Closing Report (2026-06-25)

**Files changed (additive only — ZERO production-code change):**
- `tests/fixtures/typed_html/typed_html.ig` *(new)* — entry `ReadThen` + `TodoHtmlFromRows` typed HTML
  continuation + app-local helpers (`MakeLabel`/`MakeLink`/`FormView`/`TodoRowLabel`).
- `tests/typed_html_tests.rs` *(new)* — 4 tests (found/escaping/order, empty-state, truncated→load-more, drift).
- `lab-docs/lang/lab-todoapp-view-typed-rows-html-p18-v0.md` *(new)* — proof doc.

The join reuses P7's typed read path (`StagedReadHost::with_read_policy` + `dispatch_with_read`) and the
existing TodoView helpers + `igniter-render-html` verbatim — no source edits.

**"typed rows → HTML" verdict:** `implemented`. Host DB-shaped rows render to real escaped `text/html` through
the normal runner; host-owned drift gate intact; app owns view + empty-state. Escaping, order, empty, truncated,
drift all proven.

**Is DatasetMeta enough for pagination/empty-state UX?** Load-more (via `meta.truncated`) and empty-state: yes,
today. A numeric count/page badge or a keyset "next" cursor link from a row field: not yet — `.ig` has no
Integer→String builtin and no per-row link cursor is threaded. Small named follow-ons.

**Tests + counts:** `typed_html_tests` **4**; regressions `todo_view_app_tests` **15**, `typed_readthen_tests`
**9**, `typed_row_crossing_tests` **9**, `readthen_dispatch_tests` **10**, `boot_diagnostic_tests` **6**; full
igniter-web `--features machine` green; `igniter-render-html` green; `git diff --check` clean.

**Next product slice:** `LAB-TODOAPP-VIEW-TYPED-ROW-LINKS-P19` (per-row detail links + keyset load-more href
from a typed row field via `MakeLink`+`safe_url`), then `LAB-LANG-NUMBER-TO-TEXT` (small enabler for numeric
badges), then `LAB-TODOAPP-DB-BACKED-HTML` (real-Postgres swap behind the same route, DB-gated/human-run).

## Reporting

Close with:

- "typed rows -> HTML" verdict;
- whether `DatasetMeta` is enough for pagination/empty-state UX;
- next product slice (pagination links, detail links, or real TodoApp DB-backed HTML).
