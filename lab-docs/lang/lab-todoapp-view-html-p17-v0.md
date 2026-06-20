# lab-todoapp-view-html-p17-v0 — Todo view HTML over the IgWeb `Render` seam

**Card:** `LAB-TODOAPP-VIEW-HTML-P17` · **Delegation:** `OPUS-TODOAPP-VIEW-HTML-P17`
**Status:** CLOSED (lab implementation-pressure) — the Todo view app now serves **real `text/html`
bytes** for a ViewArtifact via the P16 `Render` decision, alongside its unchanged JSON-first
`RespondView` routes. **No `.ig.html`, no template language, no `.ig`-authored JSON/HTML strings, no
prelude schema growth, no `igniter-server` renderer/view dependency, no static serving, no DB.**
**Authority:** Lab tooling. Applies P16 (`Render → igniter-render-html → ServerResponse::raw`) to the
TodoApp pressure case; smallest honest diff (one route + one contract + tests, zero authored Rust).

## Verify-first (confirmed live)

- `todo_view_app` returns a small `View { kind, title, items }` descriptor via `RespondView` (JSON) — **not**
  the full ViewArtifact schema `igniter-render-html` accepts.
- `Decision.Render { status, artifact_json : String }` exists in the IgWeb prelude (P16).
- **`.ig` string literals cannot contain `"`** (`lexer.rs:508` `read_string`, no escapes) → an inline JSON
  literal in `.ig` is impossible; the descriptor must arrive as data.
- `testkit::roundtrip_raw` can inspect `text/html` bodies.
- `igniter-render-html::render_html` validates + escapes + fails closed.

## What changed (todo_view_app + its test only)

1. **`routes.igweb`** — one route: `route POST "/todos/html-preview" -> TodoHtmlPreview`, authored
   **before** `route GET "/todos/:todo_id"` (see route-priority note below).
2. **`todo_views.ig`** — one contract:
   ```ig
   pure contract TodoHtmlPreview {
     input req : Request
     compute d : Decision = Render { status: 200, artifact_json: req.body }
     output d : Decision
   }
   ```
3. **`tests/todo_view_app_tests.rs`** — 2 new tests (HTML verbatim + escaping; invalid→JSON 500) and a
   Todo-shaped ViewArtifact const; the 6 existing JSON tests are untouched.

No Rust authored in the app; no prelude change; no `igniter-web`/server change (the P16 seam already
exists). The Todo ViewArtifact JSON is **request-sourced** (`req.body`) — P17 adds TodoApp pressure on the
proven generic seam; it does **not** pretend Todo can author a full ViewArtifact in `.ig`.

## Route-priority pressure (a real P18 demonstration)

`/todos/html-preview` collides with the param pattern `/todos/:todo_id` (`^/todos/([^/]+)$` matches
`html-preview`). Because IgWeb matches in **authored order** and does **not** auto-rank static over param
suffixes (P18 policy), authoring the static route **after** the param route shadowed it — a POST to
`/todos/html-preview` hit the GET-only `:todo_id` group and returned **405**. Authoring the static route
**before** `/todos/:todo_id` makes it reachable while `/todos/42` still routes to the detail view. This is
the P18 policy working exactly as documented — captured here as a live test, not a surprise.

## End-to-end shape (proven)

```text
POST /todos/html-preview  body = {"artifact":"view","layout":"form","title":"Todos","body":[…]}
  → .ig TodoHtmlPreview returns Render { status: 200, artifact_json: req.body }
  → igniter-web map_decision → igniter_render_html::render_html(...)   (escapes, fails closed)
  → ServerResponse::raw(200, html_bytes, "text/html; charset=utf-8")    (P15 raw seam)
  → wire body = verbatim <!DOCTYPE html>…  (Todo content, ESCAPED; no {"body":…} wrap)
```

## Tests & commands — exact counts

```text
$ cd server/igniter-web && cargo test --test todo_view_app_tests
  → 8 passed  (6 existing JSON: index/detail/alias/api/404+405; + 2 new HTML: verbatim+escaped, invalid→500)
$ cd server/igniter-web && cargo test --test render_html_app_tests   → 3 passed (P16, untouched)
$ cd server/igniter-web && cargo test                                → all suites green
$ cd frame-ui/igniter-render-html && cargo test                      → 11 passed
$ cd server/igniter-server && cargo test                             → all green (14 binaries)
$ cd server/igniter-server && cargo tree -e normal | rg 'render_html|igniter_frame|igniter_ui_kit|xlsx|pdf|export'  → (none)
$ cd server/igniter-web && cargo tree -e normal | rg render_html     → igniter_render_html present (intentional)
$ git diff --check                                                   → clean
```

## Acceptance — mapping

- [x] Existing `todo_view_app` JSON tests still pass: index/detail/API/404/405 (6 green).
- [x] New Todo HTML route builds through `igweb.toml` with no authored Rust (`build_igweb_app` + `check_app_dir`).
- [x] New route returns `Content-Type: text/html; charset=utf-8`.
- [x] New route wire body starts with `<!DOCTYPE html>`, not JSON-quoted/wrapped.
- [x] Returned HTML contains Todo content (`<title>Todos</title>`, `Write the spec`, `data-action="submit"`).
- [x] Malicious Todo text `<script>` is escaped (`Buy milk &lt;script&gt;`; no raw `<script>`).
- [x] Invalid artifact body → JSON 500 (`render failed`), not HTML, not a panic.
- [x] `render_html_app_tests` remain green (3).
- [x] `igniter-render-html` tests remain green (11).
- [x] `igniter-server` normal deps gain no renderer/frame/ui-kit/export/xlsx/pdf crate.
- [x] `igniter-web` normal deps intentionally include `igniter_render_html`.
- [x] `git diff --check` clean.

## Reported facts (per the card)

- The Todo HTML route used **request-sourced ViewArtifact JSON** (`req.body`), **not** a new typed
  authoring path — consistent with the `.ig` no-string-escape constraint.
- Existing `RespondView` routes **stayed JSON** (the JSON tests assert the clean view-object body root).
- Dependency boundary: `igniter-server` renderer-free; `igniter-web` intentionally carries `igniter_render_html`.

## Closed scope (honored)

No `.ig.html`, template language, `.ig`-authored raw HTML or JSON strings, manual JSON concatenation, large
prelude schema, `igniter-server` renderer/view dep, static asset serving, CSS/JS bundling, DB/effect-host,
file export / send-file / streaming, source-map, or canon claim.

## Next

1. **`LAB-IGNITER-WEB-VIEWARTIFACT-AUTHORING-P18`** — a real authoring form for full ViewArtifact in
   Igniter **without inline JSON strings** (the `.ig` no-string-escape constraint forces a typed/records or
   external-source path). This is the gap P17 deliberately did not close.
2. Later: assets/static shell readiness; `LAB-IGNITER-WEB-FILE-EXPORT-READINESS-P*` (descriptor→bytes
   export over the same `Render`/raw pattern).

---

*Lab implementation-pressure. Compiled 2026-06-20; todo_view_app 8 green (6 JSON unchanged + 2 new HTML),
render_html_app 3, igniter-render-html 11, igniter-server green + renderer-free, igniter-web intentionally
carries the renderer, `git diff --check` clean. A TodoApp route now returns real escaped HTML over the wire
via the generic `Render` seam — no render logic in server core, no `.ig.html`.*
