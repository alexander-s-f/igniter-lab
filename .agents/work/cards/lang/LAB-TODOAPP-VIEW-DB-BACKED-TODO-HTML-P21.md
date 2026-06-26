# LAB-TODOAPP-VIEW-DB-BACKED-TODO-HTML-P21

Status: CLOSED (2026-06-26) — one HTML route in the real todo_postgres_app (typed ReadThen → RenderView → text/html); JSON API untouched
Route: standard / product HTML payoff
Skill: idd-agent-protocol

## Goal

Move the typed-row HTML proof from a standalone fixture into the real
`todo_postgres_app` product example, without changing the existing JSON API.

Add one HTML route that reads Todo rows through the existing host `ReadThen`
path and renders escaped HTML through `RenderView`.

The purpose is product payoff: a real Todo page, authored in `.igweb` + `.ig`,
served by the same async machine runner, with no JSON artifact request body and
no manual HTML strings.

## Current Authority

Read first:

- `server/igniter-web/IMPLEMENTED_SURFACE.md`
- `server/igniter-web/examples/todo_postgres_app/routes.igweb`
- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`
- `server/igniter-web/tests/fixtures/typed_html/typed_html.ig`
- `server/igniter-web/tests/typed_html_tests.rs`
- `server/igniter-web/tests/todo_postgres_async_runner_smoke_tests.rs`
- `server/igniter-web/examples/todo_view_app/` for ViewArtifact helper style

Live source wins. The `typed_html` fixture is a pattern, not authority over the
product route.

## Task

Add a minimal HTML route to `examples/todo_postgres_app`, for example:

```igweb
route GET "/accounts/:account_id/todos.html" -> AccountTodoHtml
```

or an equally non-conflicting path. Preserve authored-order route behavior:
avoid placing a static path after a parameterized route if it can be shadowed.

Implement product-local `.ig` helpers if needed:

- `HtmlNode` helpers should reuse the existing IgWeb prelude records;
- use a typed continuation with `rows : Collection[TodoHtmlRow]` and
  `meta : DatasetMeta`;
- row type should match the current host policy exactly. If `done` is currently
  crossed as Text in the product host policy, do not pretend it is Bool.
- render:
  - account/todos title;
  - per-row todo links using row `id`;
  - escaped row `title`;
  - optional "Load more" link when `meta.truncated`.

Keep the existing JSON routes untouched.

## Closed Surfaces

- No DB schema changes.
- No host policy broadening unless the current route cannot work without a
  documented field already present in `host.example.toml`.
- No new ViewArtifact node kinds.
- No raw HTML strings.
- No request-body artifact JSON.
- No migration of JSON list/show routes in this card.
- No currency/money report in this card.

## Acceptance

- [x] Product app has one HTML route under `examples/todo_postgres_app`. — `GET /accounts/:account_id/todos.html`
- [x] The route emits `ReadThen` and receives typed rows. — `AccountTodoHtml`→`AccountTodoHtmlFromRows(rows : Collection[TodoHtmlRow])`
- [x] The continuation returns `RenderView` and produces `text/html`. — `db_backed_todos_render_escaped_html_with_links`
- [x] Found rows render escaped HTML with per-row links. — `href="/accounts/acct-7/todos/t1"`, `Buy milk &lt;script&gt;`
- [x] Empty rows render app-owned empty state, not host error. — `db_backed_empty_renders_app_owned_empty_state` (200 "No todos yet")
- [x] Truncated meta renders load-more `?after=<last_id>`. — `db_backed_truncated_renders_keyset_load_more` (`?after=t1`)
- [x] Projection drift fails before HTML rendering. — `db_backed_drift_fails_before_render` (500, query_count 0)
- [x] Existing JSON API tests still pass unchanged. — smoke + read_host suites green
- [x] `todo_postgres_async_runner_smoke_tests` / narrower product HTML test passes. — new `todo_postgres_html_tests` 4 + smoke green
- [x] `typed_html_tests` remains green. — 7 green
- [x] `git diff --check` clean.

## Closing Report (2026-06-26)

**Route added:** `GET /accounts/:account_id/todos.html -> AccountTodoHtml` (top-level, `.html` suffix distinct
from `/todos` index + `/todos/:todo_id` show → no shadowing). The `:account_id` capture crosses as
`input account_id : Option[String]`.

**Row type — matches host policy:** `TodoHtmlRow { id, account_id, title, done : String }` — ALL String
because `host.example.toml [postgres.read] fields = "id,account_id,title,done"` is a bare allowlist →
`allow_source` → every field Text (smoke test mirrors this). `done` is Text NOT Bool, no `rank`. The card's
warning honored — the page renders a per-row link and does not branch on `done`, so Text suffices; P7
reconciler confirms Text→String assignable (a host `Boolean` `done` fails closed as drift — tested).

**Files:** `examples/todo_postgres_app/routes.igweb` (+route), `examples/todo_postgres_app/todo_handlers.ig`
(+`DatasetMeta`/`TodoHtmlRow` types + `MakeHtmlLabel`/`MakeHtmlLink`/`MakeHtmlFormView`/`TodoHtmlRowLink`/
`AccountTodoHtml`/`AccountTodoHtmlFromRows`); `tests/todo_postgres_html_tests.rs` (new, 4);
`lab-docs/lang/lab-todoapp-view-db-backed-todo-html-p21-v0.md`. No renderer/server/runner/DB change.

**Rendered strings:** `<h1>Todos</h1>`, per-row `href="/accounts/acct-7/todos/<id>"`, escaped
`Buy milk &lt;script&gt;`, empty-state `No todos yet`, keyset `href="?after=t1"`.

**Counts:** product HTML 4; full igniter-web `--features machine` green (40 ok-blocks); JSON API smoke +
read_host + typed_html + boot_diagnostic green; render-html untouched; `git diff --check` clean.

**JSON API:** unchanged — additive distinct route; smoke tests pass with it.

**Next route:** `LAB-TODOAPP-API-TYPED-LIST-ENVELOPE-P49` — migrate the JSON list from `rows_json` to a typed
`{items, next}` envelope over the same typed read (reuse the keyset `?after=` proven here). Optional:
typed-`Bool` `done` projection lane for a pending/done HTML split.

## Reporting

Close with:

- exact route added;
- row type and why it matches host policy;
- rendered HTML strings proven;
- tests/counts;
- confirmation JSON API behavior did not change.

## Next Route

If this lands cleanly, the next product slice can migrate the JSON list route
from legacy `rows_json` to a typed `{items,next}` envelope (see P49).

