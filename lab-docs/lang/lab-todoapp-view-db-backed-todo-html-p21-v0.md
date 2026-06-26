# lab-todoapp-view-db-backed-todo-html-p21-v0

Card: `LAB-TODOAPP-VIEW-DB-BACKED-TODO-HTML-P21`
Route: standard / product HTML payoff · Skill: idd-agent-protocol
Status: implemented (one HTML route in the real `todo_postgres_app`, typed `ReadThen` → `RenderView` → text/html) · JSON API untouched · no canon claim
Date: 2026-06-26
Builds on: P7 typed `ReadThen` runner crossing · P18/P19 typed-rows→HTML · the TodoView HTML helpers

> **Authority boundary.** Lab product evidence. Adds one HTML route + product-local `.ig` helpers to the
> example app; no DB schema / host-policy / renderer / server change, **no canon claim.**

---

## Headline

The **real `examples/todo_postgres_app`** now serves a DB-backed Todo HTML page:

```text
GET /accounts/:account_id/todos.html
  -> AccountTodoHtml            -- builds the SAME ListTodosByAccount QueryPlan the JSON index uses
  -> ReadThen { plan, then: "AccountTodoHtmlFromRows", carry: "" }
  -> host materializes rows : Collection[TodoHtmlRow] + meta : DatasetMeta  (P7 auto-routing + reconciliation)
  -> map(rows, r -> TodoHtmlRowLink(r))  +  keyset "Load more" when meta.truncated
  -> RenderView -> igniter-render-html -> escaped text/html
```

Through the **same async machine runner** path as the JSON API, with **no `rows_json`, no request-body
artifact JSON, no manual HTML strings**. The JSON list/show/create/done/delete routes are untouched.

## Exact route added

`server/igniter-web/examples/todo_postgres_app/routes.igweb`:

```igweb
route GET "/accounts/:account_id/todos.html" -> AccountTodoHtml
```

A **top-level** route (the `:account_id` capture crosses as `input account_id : Option[String]`, the proven
param-capture shape). The `.html` suffix makes the path **distinct** from the resource's `/todos` (index) and
`/todos/:todo_id` (show), so there is **no authored-order shadowing** — verified by the existing JSON smoke
tests staying green with the route added.

## Row type — and why it matches the host policy exactly

`host.example.toml` declares the read source as a **bare field allowlist**:

```toml
[postgres.read]
source = "todos"
fields = "id,account_id,title,done"   # no per-field kinds → ALL decode as Text
```

A bare `fields` list maps to `PostgresReadPolicy::allow_source` (the smoke test mirrors this:
`allow_source("todos", &["id","account_id","title","done"])`), so **every field decodes as `Text`** and there
is **no `rank`**. The HTML row type therefore declares `done : String` — **not `Bool`** — and omits `rank`:

```text
type TodoHtmlRow { id : String  account_id : String  title : String  done : String }
```

This is the card's explicit warning honored: the route does **not** pretend `done` is `Bool`. The page renders
a per-row link and does not branch on `done`, so the Text decode is sufficient (a typed-`Bool` projection is a
separate host-policy lane). The P7 reconciler confirms host `Text` is assignable to app `String` (the §3
matrix), so the typed crossing is sound; a host that decoded `done` as `Boolean` would fail closed as drift
(tested).

## Rendered HTML strings proven

| Case | Proven |
| --- | --- |
| Found rows | `<h1>Todos</h1>`; per-row detail links `href="/accounts/acct-7/todos/t1"` + `/t2` (built from String fields); title escaped `Buy milk &lt;script&gt;`, no raw `<script>` |
| Empty | app-owned `No todos yet`, **200 text/html** (not a host error) |
| Truncated (`cap 1`) | keyset `href="?after=t1"` + `Load more` from the last crossed row's id |
| Drift (`done:Boolean` host vs `String` app) | **500 `projection_schema_drift`**, no HTML, adapter never queried |

## Behavior / error ownership

- **Empty** is a 200 empty-state page (a list of zero todos is a valid list; app-owned), not a 404 — the HTML
  route is single-stage list (it does not run the JSON index's two-stage account-existence 404, which is a
  separate product concern). 
- **Drift** is caught by the P7 first-dispatch reconciler **before** the read/continuation (500, query_count
  0) — no partial HTML.
- Denial/transient stay host-owned (403/503) exactly as the JSON path; the HTML route adds no new error class.

## Files changed

| File | Change |
| --- | --- |
| `examples/todo_postgres_app/routes.igweb` | `+ route GET "/accounts/:account_id/todos.html" -> AccountTodoHtml`. |
| `examples/todo_postgres_app/todo_handlers.ig` | `+ type DatasetMeta`, `type TodoHtmlRow`, `MakeHtmlLabel`/`MakeHtmlLink`/`MakeHtmlFormView`, `TodoHtmlRowLink`, `AccountTodoHtml`, `AccountTodoHtmlFromRows`. |
| `tests/todo_postgres_html_tests.rs` *(new, 4)* | product HTML route tests over the real example, fake adapter. |

No renderer/server/runner/DB change; reuses the IgWebPrelude `HtmlNode`/`ViewArtifact` records and the `P7`
typed read path verbatim.

## Tests / counts

`tests/todo_postgres_html_tests.rs` (**4**, `--features machine`, DB-free): `db_backed_todos_render_escaped_html_with_links`,
`db_backed_empty_renders_app_owned_empty_state`, `db_backed_truncated_renders_keyset_load_more`,
`db_backed_drift_fails_before_render`. Each loads the **real** example via `build_loaded_app_from_dir` and
dispatches through `dispatch_with_read` with a fake read host on the product policy.

**Regression (green):** the JSON API smoke tests (`todo_postgres_async_runner_smoke_tests`) +
`todo_postgres_read_host_tests` + `readthen_dispatch_tests` + `typed_html_tests` + `boot_diagnostic_tests` —
all green (the new typed continuation `AccountTodoHtmlFromRows` is structurally sound, so the P8 boot scan does
not flag it). Full `igniter-web --features machine` green (40 ok-blocks). **`igniter-render-html` UNTOUCHED**.
`git diff --check` clean.

```bash
# from server/igniter-web
cargo test --features machine --test todo_postgres_html_tests              # 4 passed
cargo test --features machine --test todo_postgres_async_runner_smoke_tests # JSON API unchanged, green
cargo test --features machine                                              # full suite green
```

## Reporting

- **Route added:** `GET /accounts/:account_id/todos.html -> AccountTodoHtml`.
- **Row type:** `TodoHtmlRow { id, account_id, title, done : String }` — all `String` because the product host
  policy allowlists `todos` fields untyped (all Text); `done` is Text not Bool, no `rank`.
- **Rendered strings:** `<h1>Todos</h1>`, per-row `href="/accounts/acct-7/todos/<id>"`, escaped
  `Buy milk &lt;script&gt;`, empty-state `No todos yet`, keyset `href="?after=t1"`.
- **Counts:** product HTML 4; JSON API smoke + full igniter-web `--features machine` green; render-html
  untouched; diff clean.
- **JSON API behavior:** unchanged — the `.html` route is distinct and additive; the smoke tests pass with it.
- **Next route:** migrate the JSON list route from legacy `rows_json` to a typed `{items, next}` envelope
  (P49) — the typed read path is now the product default for HTML; the JSON lane can follow.

## Next cards

- **`LAB-TODOAPP-API-TYPED-LIST-ENVELOPE-P49`** — JSON list `{items, next}` over the typed read (drop
  `rows_json`), reusing the keyset `?after=` already proven here.
- **`LAB-TODOAPP-VIEW-TYPED-BOOL-PROJECTION`** (optional) — a typed-`Bool` `done` lane (host `allow_source_typed`
  + a `done`-aware HTML view: pending/done sections), if the product wants to branch on completion in HTML.
