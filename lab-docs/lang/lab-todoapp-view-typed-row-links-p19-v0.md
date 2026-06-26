# lab-todoapp-view-typed-row-links-p19-v0

Card: `LAB-TODOAPP-VIEW-TYPED-ROW-LINKS-P19`
Route: standard / product proof · Skill: idd-agent-protocol
Status: PROVEN (2026-06-26)
Builds on: P18 typed-rows→HTML (`lab-todoapp-view-typed-rows-html-p18-v0`) · P27 link-nav · link-node.

> Joins the two proven halves into row-data-driven navigation: **typed host rows → per-row detail links
> built from typed row fields → keyset "load more" href from the last row's id → escaped `text/html`**,
> through the normal `dispatch_with_read` contour. No `rows_json`, no new node kind, no renderer change.

---

## Verdict

**Row data drives navigation cleanly.** Per-row detail links (`href` from `row.id`, label from `row.title`)
and a **keyset** load-more href (`/todos?after=<last row id>`) are built entirely from typed crossed rows,
using only proven helpers (`map`, `last`, `or_else`, `concat`, `MakeLink`). **No workaround was needed** and
**no new primitive** was invented. The collection-`last` helper already exists — it is **not** pressure.

---

## 1. Exact helper shape (app-local only, in the `typed_html` fixture)

```ig
-- a typed crossed row → a detail link; href from row.id (String → clean concat), label from row.title
pure contract TodoRowDetailLink {
  input row : TodoRow
  compute href : String = concat("/todos/", row.id)
  compute node : HtmlNode = call_contract("MakeLink", row.title, href)
  output node : HtmlNode
}

pure contract FetchTodoLinksHtml {              -- entry → ReadThen → links continuation
  input req : Request
  compute account_id : String = req.path
  compute plan = call_contract("ListTypedTodos", account_id)
  compute d : Decision = ReadThen { plan: plan, then: "TodoLinksHtmlFromRows", carry: "" }
  output d : Decision
}

pure contract TodoLinksHtmlFromRows {
  input req  : Request
  input rows : Collection[TodoRow]              -- typed crossing (P7), NOT rows_json
  input meta : DatasetMeta
  compute total : Integer = count(rows)
  compute links : Collection[HtmlNode] = map(rows, r -> call_contract("TodoRowDetailLink", r))
  -- keyset cursor = the LAST crossed row's id (next page starts after it)
  compute ids : Collection[String] = map(rows, r -> r.id)
  compute last_id : String = or_else(last(ids), "")
  compute more_href : String = concat("/todos?after=", last_id)
  compute more_link : HtmlNode = call_contract("MakeLink", "Load more", more_href)
  compute more : Collection[HtmlNode] = if meta.truncated { [more_link] } else { [] }
  compute empty_node : HtmlNode = call_contract("MakeLabel", "No todos yet")
  compute body : Collection[HtmlNode] = if total == 0 { [empty_node] } else { concat(links, more) }
  compute view : ViewArtifact = call_contract("FormView", meta.source, body)
  compute d : Decision = RenderView { status: 200, view: view }
  output d : Decision
}
```

The P18 `FetchTodoHtml`/`TodoHtmlFromRows` (label flow) is **untouched** — both flows coexist in one fixture;
the test selects the entry.

---

## 2. href construction from row fields — clean (with one named latent gap)

`TodoRow.id : String` (fixture `typed_html.ig:27`), so `concat("/todos/", row.id)` is a direct
`String × String → String` — **clean, no coercion**. The malicious `row.title` flows into the link label and
is escaped by the projector (`Buy milk &lt;script&gt;`), proving the href/label come from **row data**, not a
literal.

**Latent gap (named, not hit):** the row also has `rank : Integer`. A cursor or href built from an *Integer*
field would need `Integer → String`, which the language lacks (P1/P2: no `to_string`/numeric→text coercion,
only `stdlib.math.to_float`). This card sidesteps it because the cursor id is a **String** (`id`), which is
also the natural keyset key. If a future view needs a numeric cursor/href, that is the `Integer→String`
pressure — a small stdlib helper, not a structural problem.

---

## 3. Keyset "load more" — no workaround; `last` exists

The keyset cursor is built from the **last crossed row's id**, the correct keyset semantics (the next page
begins after the last row of the current page):

```ig
compute ids : Collection[String] = map(rows, r -> r.id)   -- project the key column
compute last_id : String = or_else(last(ids), "")          -- last : Collection[T] -> Option[T]
compute more_href : String = concat("/todos?after=", last_id)
```

`last` is a live stdlib collection op (`lang/igniter-compiler/src/typechecker/stdlib_calls.rs:708`, returns
`Option[T]`); `or_else(Option[String], "")` unwraps it (the same idiom as `or_else(map_get_string(...), "")`).
**No workaround, no fixed/fabricated cursor, no new primitive.**

**Minor DX note (not pressure):** `last(rows)` returns `Option[TodoRow]`; reading a field off an
`Option[Record]` would need an unwrap with a *default record* (awkward — no natural default). Projecting the
key first (`map(rows, r -> r.id)` then `last`) avoids that and reads cleanly. So the idiom is "project the key
column, then `last`," which is natural and worth noting as the recommended pattern.

---

## 4. Is a collection-`last` helper real pressure? — No

`first`/`last` already exist (`stdlib_calls.rs:708`, `-> Option[T]`). Combined with `map` + `or_else` they
build the keyset cursor with zero new surface. The card's "if not, document the missing collection-last
helper as pressure" branch did **not** trigger. (The only adjacent ergonomic note is §3's "project the key
then `last`" idiom, which is a convention, not a missing primitive.)

---

## 5. Tests / counts (green, 2026-06-26)

**`server/igniter-web` — `cargo test --features machine --test typed_html_tests`: 6 passed** (4 P18 + 2 new),
all through the real `dispatch_with_read` contour with the fake Postgres adapter (no DB):
- `typed_rows_render_per_row_detail_links` — detail links `/todos/t1`, `/todos/t3` (label = title) in row
  order; `row.title` `<script>` escaped inside the link; no load-more when not truncated; `query_count == 1`.
- `truncated_meta_renders_keyset_load_more_from_last_row_id` — cap 1 clamps → one row + `meta.truncated`;
  load-more href is `/todos?after=t1` (**the last crossed row's id**, not a generic `/todos`).

Unchanged (verified green, not modified by this card):
- `todo_view_app_tests` **16/16**; `igniter-render-html` `cargo test` **15/15**.

`git diff --check` clean. Card diff: **2 files** (`tests/fixtures/typed_html/typed_html.ig`,
`tests/typed_html_tests.rs`), additive only. No renderer/schema/prelude change; no new node kind; no
`rows_json`; no live DB.

---

## Reporting

- **Row-field-driven navigation: works, clean.** Typed crossed rows drive both per-row detail links
  (`row.id` → href, `row.title` → escaped label) and a keyset load-more cursor (`last(ids)` → `?after=`),
  through the normal runner contour — no `rows_json`, no new primitive, no renderer change.
- **Exact gap:** none hit. The only **latent** pressure is `Integer→String` (named, §2) — sidestepped because
  the keyset key `id` is a `String`. `last` exists (no `last`-helper pressure); `Integer→String` would be a
  small stdlib helper if a numeric cursor/href is ever required.
- **Next product slice:** (a) a **real DB-backed** HTML route — promote this exact flow from the fake adapter
  to the opt-in `postgres` feature (the read contour + reconciliation already run; only the adapter changes);
  and/or (b) a small **`Integer→String`** stdlib helper if a numeric cursor/href is needed. The per-item
  *grouping* layout (P26 bounded `list`/`item`) remains held — links-as-flat-list still suffices.
