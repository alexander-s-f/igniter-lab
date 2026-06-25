# lab-todoapp-view-typed-rows-html-p18-v0

Card: `LAB-TODOAPP-VIEW-TYPED-ROWS-HTML-P18`
Route: standard / product proof · Skill: idd-agent-protocol
Status: implemented (typed rows → real text/html through the runner) · zero production-code change · no canon claim
Date: 2026-06-25
Builds on: P7 boot-reconciliation (typed `ReadThen` crossing) · the TodoView HTML helper line (P19–P23 + LINK-NODE)

> **Authority boundary.** Lab product evidence. Joins two already-proven halves with a DB-free fixture + tests;
> **no source change**, no new ViewArtifact schema, no `.igweb`/renderer change, **no canon claim.**

---

## Headline

TodoApp HTML now renders **database-shaped rows** end to end — `ReadThen` typed rows + `DatasetMeta` →
`filter`/`map` into `HtmlNode` helpers → `RenderView` → real escaped `text/html` — through the **normal
`dispatch_with_read` runner contour**, with **no `rows_json : String`, no request-body artifact JSON, no
manual node enumeration, and no JSON parser in `.ig`**. The proof needed **zero production code**: P7 already
crosses typed rows + meta; the TodoView helpers already turn `Collection[HtmlNode]` into escaped HTML. P18 is
the fixture + tests that wire one to the other.

---

## Exact fixture / route

`server/igniter-web/tests/fixtures/typed_html/typed_html.ig` (self-contained, DB-free):

```text
FetchTodoHtml(req)                      -- entry: account_id = req.path; plan = ListTypedTodos(account_id)
  -> ReadThen { plan, then: "TodoHtmlFromRows", carry: "" }
TodoHtmlFromRows(req, rows : Collection[TodoRow], meta : DatasetMeta)
  pending = filter(rows, t -> t.done == false)            -- Bool field, host-typed
  labels  = map(pending, t -> call_contract("TodoRowLabel", t))   -- TodoRow -> HtmlNode (title escapes)
  more    = if meta.truncated { [MakeLink("Load more","/todos")] } else { [] }
  body    = if total == 0 { [MakeLabel("No todos yet")] } else { concat(labels, more) }
  view    = FormView(meta.source, body)                   -- title = meta.source
  d       = RenderView { status: 200, view: view }        -- -> igniter-render-html -> text/html
```

Helpers (`MakeLabel`, `MakeLink`, `FormView`, `TodoRowLabel`) are app-local, the same flat
`HtmlNode`/`ViewArtifact` records `todo_view_app` proved (P19–P23 + LINK-NODE). The host side is the P7 typed
read path verbatim (`StagedReadHost::with_read_policy` + `dispatch_with_read` auto-routing + reconciliation).

## Typed row schema

```text
type TodoRow { id : String  account_id : String  title : String  done : Bool  rank : Integer }
type DatasetMeta { source : String  count : Integer  truncated : Bool }
```

The continuation reads `t.title` (String) and `t.done` (Bool); the host materializes these from the fake
adapter's typed rows (P6/P7). No stringly access, no `map_get_string`.

## How `DatasetMeta` is used

- **`meta.source` → the view title** (`FormView(meta.source, …)` → `<h1>todos</h1>`). Proves meta crosses and
  is read in the rendered view with no extra host work.
- **`meta.truncated` → a "load more" link node** appended when the read was clamped (`if meta.truncated {
  [MakeLink("Load more","/todos")] } else { [] }`). The href routes through the renderer's fail-closed
  `safe_url`; it is a safe relative reference.
- **`meta.count` is intentionally NOT rendered** as text: `.ig` has no Integer→String builtin (verified P6),
  so a numeric count cannot land in an escaped text leaf today. `truncated` (Bool) is the actionable
  pagination signal and is sufficient for the load-more affordance; a count badge waits on a number→text
  builtin (named follow-on). This is the honest answer to "is DatasetMeta enough for pagination UX": **yes for
  a load-more affordance via `truncated`; a numeric page/count badge needs a number→text primitive.**

## Behavior matrix

| Case | Behavior | Test |
| --- | --- | --- |
| **Found** rows | pending rows → escaped `text/html`, in order; done rows filtered out; title `<h1>todos</h1>` | `typed_rows_render_to_escaped_html` |
| **Escaping** | a `"Buy milk <script>"` title renders as `Buy milk &lt;script&gt;`; no raw `<script>` survives | same |
| **Order** | `filter` then `map` preserve order (`Buy milk` before `Pay bills`) | same |
| **Empty** | no rows → app-owned empty-state view (`<…>No todos yet</…>`, **200 text/html**), not a host error | `empty_rows_render_app_owned_empty_state` |
| **Truncated** | clamped read (`cap 1`) → `meta.truncated` → a `Load more` link with `href="/todos"` | `truncated_meta_renders_load_more_link` |
| **Drift** | host `done : Text` vs `TodoRow.done : Bool` → **500 `projection_schema_drift`**, no HTML, adapter never queried | `drift_fails_before_html_continuation` |

Empty is rendered as a **200 empty-state HTML page** (app-owned), not a 404 — a list of zero todos is a valid
list; the empty-state label is the product affordance. (A 404 stays available for single-resource routes; this
is a list.)

## Questions answered

1. **DatasetMeta in the view without host work?** Yes — `meta.source` → title, `meta.truncated` → load-more,
   straight off the crossed record.
2. **Fake `String`/`Bool` rows render through the same helpers as authored rows?** Yes — `TodoRowLabel`
   consumes a host-materialized `TodoRow` exactly as `TodoLabel` consumes an authored `TodoItem`.
3. **`filter` + `map` preserve order + escaping?** Yes — order asserted; escaping is the renderer's
   (`escape`), unchanged.
4. **Empty set → app-owned output?** Yes — 200 empty-state HTML, no host failure.
5. **Drift still fails before the HTML continuation?** Yes — P7 reconcile runs before the read; 500, adapter
   query_count 0, no render.
6. **Old JSON/request-body `Render` path green?** Yes — `todo_view_app_tests` unchanged and green.

## Test matrix

`server/igniter-web/tests/typed_html_tests.rs` (**4**, `--features machine`, DB-free, fake adapter):
`typed_rows_render_to_escaped_html`, `empty_rows_render_app_owned_empty_state`,
`truncated_meta_renders_load_more_link`, `drift_fails_before_html_continuation`.

**Regression (green):** `todo_view_app_tests` (15 — the old `Render`/`RespondView`/request-body paths),
`typed_readthen_tests` (9/10), `typed_row_crossing_tests` (9), `readthen_dispatch_tests` (10),
`boot_diagnostic_tests` (6); full `igniter-web --features machine` green; `igniter-render-html` green;
`git diff --check` clean.

```bash
# from server/igniter-web
cargo test --features machine --test typed_html_tests        # 4 passed
cargo test --features machine --test todo_view_app_tests     # green (old Render path)
cargo test --features machine --test typed_readthen_tests    # green
cargo test --features machine                                # full suite green
# from frame-ui/igniter-render-html
cargo test                                                   # green
```

## Files changed

| File | Change |
| --- | --- |
| `tests/fixtures/typed_html/typed_html.ig` *(new)* | entry `ReadThen` + typed HTML continuation + app-local helpers. |
| `tests/typed_html_tests.rs` *(new)* | 4 tests across found / empty / truncated / drift. |

**No production source changed** — the join reuses P7's typed read path and the existing TodoView helpers /
renderer verbatim.

## Reporting

- **"typed rows → HTML" verdict:** `implemented`. Host DB-shaped rows render to real escaped `text/html`
  through the normal runner, with the host-owned schema gate (drift/mismatch) intact and the app owning the
  view + empty-state. No production code change was needed — the boundary (P6–P8) and the view layer
  (P19–P23/LINK-NODE) already met in the middle.
- **Is `DatasetMeta` enough for pagination/empty-state UX?** For **load-more** (via `meta.truncated`) and an
  **empty state** — yes, today. For a **numeric** page/count badge or keyset "next" cursor link built from a
  row field — not yet, because `.ig` has no Integer→String builtin and no per-row link cursor is threaded.
  Both are small, named follow-ons.
- **Next product slice:** **pagination/detail links from typed rows** — a keyset "next" link built from the
  last row's `id` (needs a row→href helper threading a String field) and per-row detail links
  (`/todos/<id>`), reusing the proven `MakeLink` + `safe_url`. After that, a real DB-backed TodoApp HTML route
  (swap the fake adapter for the `--features postgres` executor; the `.ig` and view layer are unchanged).

## Next cards

- **`LAB-TODOAPP-VIEW-TYPED-ROW-LINKS-P19`** — per-row detail links + a keyset "load more" href built from a
  typed row field (`MakeLink` + `safe_url`), proving row data → navigation, not just labels.
- **`LAB-LANG-NUMBER-TO-TEXT`** (small enabler) — an Integer/Decimal→String builtin so `meta.count` / numeric
  badges can land in escaped text leaves.
- **`LAB-TODOAPP-DB-BACKED-HTML`** — the real-Postgres swap (`--features postgres`) behind the same typed
  read → HTML route, DB-gated/human-run.
