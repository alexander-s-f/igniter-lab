# LAB-TODOAPP-VIEW-MANIFEST-P2

Status: CLOSED
Route: standard / lab implementation proof
Date: 2026-06-19
Skill: idd-agent-protocol
Delegation: OPUS-TODOAPP-VIEW-MANIFEST-P2

## Goal

Prove the **JSON-first TodoApp view path** end-to-end:

```text
Todo `.igweb` view route
  -> `.ig` handler builds a ViewArtifact-shaped JSON descriptor from fake data
  -> `igweb-serve` returns a clean JSON body
  -> no authored Rust, no DB, no raw HTML, no server-core view knowledge
```

This card is still current after `LAB-IGNITER-WEB-RENDER-MIDDLEWARE-READINESS-P2`:
render middleware / SSR is a parallel research track. This card proves the
smaller app-owned ViewArtifact manifest path first. If later a host projector
turns the same artifact into HTML, it should consume this kind of explicit
artifact shape.

## Current Authority

- `.igweb` owns routing and lowers to inspectable `.ig`.
- `.ig` handlers own app/domain/view descriptor construction.
- `igniter-web` runner owns build/load/loopback and maps IgWeb `Decision` to
  `ServerResponse`.
- `igniter-server` owns transport and JSON wire encoding; it must remain
  route/domain/view free.
- ViewArtifact / frame stack owns the structural view model. This card may use a
  minimal ViewArtifact-shaped fixture but must not redefine the whole view
  system.

## Verify First

Read live code/docs before editing:

- `lab-docs/lang/lab-todoapp-views-assets-readiness-p1-v0.md`
- `.agents/work/cards/lang/LAB-IGNITER-WEB-RENDER-MIDDLEWARE-READINESS-P2.md`
  (if present; treat as parallel SSR research, not a blocker)
- `lang/igniter-compiler/src/igweb.rs`
- `server/igniter-web/src/lib.rs`
- `server/igniter-web/src/runner.rs` or current runner module path
- `server/igniter-web/examples/todo_app/`
- `server/igniter-web/examples/todo_v2_app/`
- relevant ViewArtifact docs/live fixtures (`lab-frame-*ViewArtifact*`,
  `.igv` docs, frame/ui-kit paths after reorg)

Confirm:

- `Decision.Respond` is still `status + body:String`.
- `map_decision` still double-wraps as `{"body": <string>}` and forces JSON.
- `ServerResponse.body` is JSON; raw bytes are still unavailable.
- Existing `igweb-serve` can run an app from `igweb.toml` with no authored Rust.
- Existing ViewArtifact JSON shape is sufficient for a small Todo list page
  descriptor, or document the minimal shape used in the proof.

## Scope

Allowed:

- Add a Todo view example under `server/igniter-web/examples/` (or the current
  post-reorg `igniter-web/examples/` path), e.g. `todo_view_app/`.
- Add `.igweb`, `.ig`, and `igweb.toml` app files.
- Add the smallest IgWeb/runner enhancement needed for **clean structured JSON
  responses** so the ViewArtifact is not returned as an escaped string inside
  `{"body": ...}`.
- Add tests proving build, loopback response body shape, and boundaries.
- Add a proof doc and close this card.

Closed:

- No raw response / bytes / HTML.
- No ViewArtifact -> HTML renderer.
- No `.ig.html`.
- No DB/Postgres/API live data.
- No static file serving.
- No new public listener.
- No server-core route table or view-model dependency.
- No effect-host execution.
- No canon claim.

## Design Constraint

Do **not** solve this by hiding JSON in a string and asking clients to double
parse it. The acceptance target is a wire body whose root is the ViewArtifact
JSON object (or an explicit structured envelope documented as such), not:

```json
{ "body": "{\"type\":\"ViewArtifact\", ...}" }
```

Choose the smallest safe representation. Examples to evaluate:

- additive `Decision` variant such as `RespondJson { status, body }`, if the
  language/runtime can carry the needed structured value;
- a constrained JSON/body helper in the IgWeb runner;
- a deliberately limited ViewArtifact response variant.

If a fully generic JSON type is not available, keep the implementation honest:
prove a limited ViewArtifact path and document the broader JSON-body problem as
the next slice. Do not invent a large JSON type system in this card.

## Suggested App Shape

```text
todo_view_app/
  igweb.toml
  routes.igweb
  todo_views.ig
```

`routes.igweb` should include at least:

```igweb
app TodoViewWeb entry Serve {
  handlers TodoViews

  route GET "/" -> TodoIndexView
  route GET "/todos" -> TodoIndexView
  route GET "/todos/:todo_id" -> TodoDetailView
  scope "/api" {
    -- optional: retain a tiny API route only if useful for contrast
  }
}
```

`todo_views.ig` should use fake/static data. Keep the ViewArtifact small but
real enough to prove nested structure:

- page/title;
- list of two todos;
- one action or link descriptor if existing ViewArtifact conventions support it;
- no DB, no API fetch, no effect execution.

## Verification Requirements

Run and report exact commands/counts:

- `cargo test` in `server/igniter-web` (or current crate path)
- targeted test for the new Todo view app
- `cargo run --bin igweb-serve -- examples/todo_view_app` or equivalent bounded
  runner smoke, if practical
- `cargo test` in `server/igniter-server` if server-facing response mapping is
  touched
- `git diff --check`

Tests must prove:

- app builds from `igweb.toml` with no authored Rust;
- `GET /` returns status 200;
- response body is clean JSON, not a stringified/double-wrapped JSON document;
- body contains recognizable ViewArtifact fields;
- route behavior still returns 404/405 where expected;
- `igniter-server` normal dependency tree remains small if touched;
- no raw HTML/body bytes are introduced.

## Expected Deliverables

- Implementation files for the Todo view manifest example and the smallest
  structured JSON response seam.
- Tests.
- `lab-docs/lang/lab-todoapp-view-manifest-p2-v0.md`
- Closing report in this card, with acceptance checked.

## Acceptance

- [x] Todo view app runs from authored `.igweb` + `.ig` + `igweb.toml`, with no
      app-authored Rust.
- [x] Uses fake/static data only.
- [x] Returns clean structured JSON for the view descriptor.
- [x] Avoids escaped JSON string / double-parse response shape.
- [x] Keeps raw HTML / RAW-RESPONSE out of scope.
- [x] Keeps server core view/domain free.
- [x] Documents how this relates to render middleware readiness P2.
- [x] Tests include loopback/body-shape proof.
- [x] Existing IgWeb runner/routing tests remain green.
- [x] Proof doc and closing report are written.

---

## Closing Report (2026-06-19)

**Outcome:** the JSON-first TodoApp view path is proven end-to-end. A new **domain-free** `RespondView`
decision arm + tiny `View`/`ViewItem` prelude types let `.ig` handlers return a typed view descriptor whose
**JSON object is the wire body root** — no `{"body":"<escaped-json>"}` double-wrap. Proof doc:
`lab-docs/lang/lab-todoapp-view-manifest-p2-v0.md`.

**Seam (additive, no server-core change):**
- `igniter-compiler/src/igweb.rs::PRELUDE_SOURCE` — added `type ViewItem`, `type View { …, items :
  Collection[ViewItem] }`, and `Decision::RespondView { status, view }`.
- `igniter-web/src/lib.rs::map_decision` — `RespondView` lifts the typed `view` record directly as the
  JSON body (plain records carry no `__arm`/`__variant`, so it serializes clean).
- New example `examples/todo_view_app/` (`igweb.toml` + `routes.igweb` + `todo_views.ig`), fake data.

**Verify-first delta:** `.ig` has **no recursive types** (`decision_tree/types.ig`), so the view is a
2-level page→`Collection[ViewItem]` tree (proves nesting without recursion); an arbitrary JSON body type is
a separate named slice. De-risked by a standalone compile before wiring.

**Proof — all green:**
- `igniter-web cargo test` → builder 5 · ctx_accum 1 · ctx_demo 1 · example 7 · runner 17 · todo_postgres 3
  · todo_v2 1 · **todo_view 6** (all pass).
- `igweb-serve check examples/todo_view_app` → builds from `igweb.toml`, zero authored Rust.
- `igniter-compiler` igweb **55 lib + 11 integration** green with the additive prelude (P16–P20 byte-identity
  /compile tests + postgres/v2/ctx apps unaffected).
- `git diff --check` clean. `igniter-server` untouched (stays view-free).

Key test `index_view_body_root_is_the_clean_view_object` asserts the root has `kind`/`title`/`items[]`,
**no `body` key** (not double-wrapped), is a JSON object (not a string), and has **no `__arm`/`__variant`**
leak — exactly the P2 design constraint.

**Relation to render-middleware P2:** parallel SSR track; this `View` descriptor is the explicit artifact a
future host HTML projector would consume (once `RAW-RESPONSE` exists). **Next:** external static-shell +
frame-runtime smoke consuming the View JSON / `LAB-IGNITER-WEB-STRUCTURED-JSON-BODY-P*` to generalize beyond
the fixed `View` shape / SSR or Postgres-API integration later.

## Next

If this succeeds, the next likely route is one of:

- external static shell / frame-runtime smoke consuming the ViewArtifact JSON;
- `LAB-IGNITER-WEB-RENDER-MIDDLEWARE-*` implementation if SSR is preferred;
- TodoApp API + Postgres integration once effect-host execution exists.
