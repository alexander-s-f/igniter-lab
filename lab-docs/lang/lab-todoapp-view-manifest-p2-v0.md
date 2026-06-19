# lab-todoapp-view-manifest-p2-v0 — JSON-first Todo view manifest

**Card:** `LAB-TODOAPP-VIEW-MANIFEST-P2` · **Delegation:** `OPUS-TODOAPP-VIEW-MANIFEST-P2`
**Status:** CLOSED (lab implementation proof) — a Todo view app returns a clean, structured JSON view
descriptor through `igweb-serve`, with **zero authored Rust**, fake data only, and no raw HTML / DB /
server-core view knowledge.

## 1. Executive summary

`server/igniter-web/examples/todo_view_app/` proves the app-owned ViewArtifact-style path recommended by
TodoApp views/assets P1. The app is ordinary authored Igniter:

```text
igweb.toml
routes.igweb
todo_views.ig
```

The small enabling seam is additive: IgWeb's shared prelude now includes a tiny domain-free
`ViewItem`/`View` descriptor and a `Decision.RespondView { status, view }`. `igniter-web` maps
`RespondView` to `ServerResponse::json(status, view)`, so the **wire body root is the view object**. It is
not an escaped JSON string inside `{"body": ...}`. Existing `Respond { body:String }` remains unchanged.

This is **not** SSR and not HTML. Render middleware / `ViewArtifact -> HTML` stays a parallel research
track (`LAB-IGNITER-WEB-RENDER-MIDDLEWARE-READINESS-P2`).

## 2. Live facts confirmed

- `Decision.Respond` was still `status + body:String` and still double-wrapped by `map_decision`.
- `ServerResponse.body` is JSON; raw bytes are still unavailable.
- `igweb-serve check examples/todo_view_app` builds from `igweb.toml` with no socket and no authored Rust.
- The view response body is a clean JSON object with fields such as `kind`, `title`, and `items`.

## 3. Files

```text
server/igniter-web/examples/todo_view_app/
  igweb.toml
  routes.igweb
  todo_views.ig
server/igniter-web/tests/todo_view_app_tests.rs
```

Code changes:

- `lang/igniter-compiler/src/igweb.rs` — shared prelude adds `ViewItem`, `View`, and `RespondView`.
- `server/igniter-web/src/lib.rs` — `map_decision` maps `RespondView` to a JSON body root.

No `igniter-server` source change; no raw response; no static serving; no DB.

## 4. Behavior proved

Routes:

```igweb
route GET "/"               -> TodoIndexView
route GET "/todos"          -> TodoIndexView
route GET "/todos/:todo_id" -> TodoDetailView
scope "/api" {
  route GET "/health" -> ApiHealth
}
```

Results:

| Request | Result |
|---|---|
| `GET /` | `200`, body root `{ "kind": "todo_index", "title": "Todos", "items": [...] }` |
| `GET /todos` | same index view |
| `GET /todos/42` | `200`, detail view with item key `"42"` |
| `GET /api/health` | old shape preserved: `{ "body": "ok" }` |
| `GET /missing` | `404` |
| `POST /` | `405` |

The test asserts the view response has no root `body`, no `__arm`, and no `__variant`.

## 5. Verification

```text
$ cd server/igniter-web && cargo test --test todo_view_app_tests
  → 6 passed; 0 failed

$ cd server/igniter-web && cargo run --bin igweb-serve -- check examples/todo_view_app
  → igweb-serve: check ok app_dir=examples/todo_view_app entry=Serve sources=2 (no socket opened)
```

The wider `server/igniter-web cargo test` run also includes the new test target and remained green in the
harvest pass.

## 6. Boundaries

- **No raw HTML / RAW-RESPONSE.** The response is JSON.
- **No ViewArtifact -> HTML renderer.** That belongs to the render middleware track.
- **No DB / API live data.** Fake/static items only.
- **No static file serving.**
- **No server-core view dependency.** `igniter-server` still sees only `ServerResponse::json`.
- **No new canon claim.** This is lab evidence for app-owned view descriptors.

## 7. Next

Two good follow-ups:

1. external static shell / frame-runtime smoke that consumes this JSON and renders it in a browser;
2. `LAB-IGNITER-RENDER-HTML-P3` if we want SSR via a host-side `ViewArtifact -> HTML` projector.

The clean JSON body root established here is useful for both paths.
