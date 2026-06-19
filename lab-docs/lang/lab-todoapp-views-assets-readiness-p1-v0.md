# lab-todoapp-views-assets-readiness-p1-v0 — TodoApp UI / views / assets shape

**Card:** `LAB-TODOAPP-VIEWS-ASSETS-READINESS-P1` · **Delegation:** `OPUS-TODOAPP-VIEWS-ASSETS-P1`
**Status:** READINESS / DESIGN (v0) — how a Todo app serves UI / views / assets **without** turning
`igniter-server` into a web framework. **No code, no assets protocol, no raw-response, no file serving,
no public listener, no DB, no canon claim.**
**Authority:** Lab readiness. Grounded in the live `ServerResponse` + host wire encoder + the IgWeb
runner's `Decision → ServerResponse` mapping. Builds on the **server-side** assets readiness
`lab-machine-igniter-server-assets-readiness-p11-v0.md` (P11); this card is its **app-side** counterpart.

---

## 1. Executive summary

The server-side P11 already settled the protocol: the wire body is **always `serde_json::to_vec(body)`**,
so JSON is first-class and verbatim HTML/binary is not servable until a deliberate `RAW-RESPONSE` gate. This
app-side packet answers *what TodoApp does with that*: **serve UI JSON-first by returning a ViewArtifact
JSON descriptor from `.ig` handlers, rendered by the existing machine-free frame runtime in a static shell
served by an external static server.** This needs **no server-core change and no new dialect** — it reuses
the proven `.igv`→ViewArtifact→frame stack. Raw HTML/CSS/JS bytes stay with an external static server (v0)
or the future `RAW-RESPONSE` gate (only when verbatim bytes are truly needed). API and page routes are
**explicitly namespaced** (`/api/...` data vs view routes), never magic content-negotiation.

Recommended next card: **`LAB-TODOAPP-VIEW-MANIFEST-P2`** (a JSON ViewArtifact page descriptor from fake
data, end-to-end through `igweb-serve`) — §11.

## 2. Verify-first facts (live code wins)

| Fact | Evidence |
|---|---|
| `ServerResponse { status: u16, headers: BTreeMap<String,String>, body: Value }` — body is JSON `Value` | `protocol.rs:32-37` |
| **wire body is always JSON-serialized** | `host.rs` `encode_response`: `let body = serde_json::to_vec(&resp.body)…` then status line + **every header** + `Content-Length` + body |
| headers (incl. `content-type`) **are** written to the wire | `host.rs` `for (k,v) in &resp.headers { … }` |
| **but** the IgWeb `Decision` path is narrower: prelude `variant Decision { Respond { status: Integer, body: String } … }` — only status + a **String** body, no headers | `igweb.rs` `PRELUDE_SOURCE` |
| the runner **double-wraps + forces JSON**: `map_decision` → `ServerResponse::json(status, json!({ "body": get_str("body") }))` (content-type hardcoded `application/json`) | `igniter-web/src/lib.rs:164-170` |
| TodoApp example shape today: `igweb.toml` + `routes.igweb` + `todo_handlers.ig` — **no views/ or assets/** | `examples/todo_app/`, `examples/todo_v2_app/` |
| `lab-todoapp-api-postgres-e2e-readiness-p1-v0.md` now exists and keeps the first API slice no-DB / observed-effects | filesystem check after P1 landed |

**Two distinct gaps, not one:**
1. **Server gap (P11):** the body is JSON-serialized on the wire, so **verbatim HTML/binary is not
   servable**; `Respond` body must be JSON.
2. **IgWeb gap (new here):** even within JSON, the `.igweb`/`Decision` path exposes only `status` + a
   **String** body and **double-wraps** it as `{"body":"…"}` with a forced `application/json` — so a
   handler can't yet return a clean structured JSON descriptor or set `content-type`, even though the
   underlying `ServerResponse` supports both. A TodoApp ViewArtifact would today arrive as a JSON string
   inside `{"body":"<escaped-json>"}` (client double-parses). This is the app-level slice to address, not
   the server raw-bytes gate.

**HTML-carried-in-JSON vs verbatim HTML:** putting `"<html>…"` in the body yields a JSON-quoted, escaped
string on the wire — a browser told `text/html` gets quoted junk. Verbatim HTML is **not** available. Every
recommendation below respects this.

## 3. Desired TodoApp UI / app layout (Q3)

```text
todo_app/
  igweb.toml            # runner config (loaded by igweb-serve)
  routes.igweb          # API + view routes (loaded)
  todo_handlers.ig      # data + view-descriptor handlers (loaded)
  views/                # authored ViewArtifact JSON or .igv (NOT loaded by igweb-serve)
    todo_index.view.json
  assets/               # static shell + frame runtime + css (NOT loaded by igweb-serve)
    index.html
    igniter_frame_bg.wasm
    app.css
```

- **Loaded by `igweb-serve`:** only `*.ig` + `*.igweb` (+ `igweb.toml`) — unchanged runner behavior.
- **App-owned, NOT server-served:** `views/` and `assets/` are build-time / external-static inputs. The
  runner does **not** grow a `views/`/`assets/` serving convention (that would be the framework drift the
  boundary forbids). `views/*.view.json` may be `include`d/compiled into a handler's response at build time
  or fetched by the client; `assets/` is served by an **external static server** in v0.
- Server/runtime files (`igniter-server`, `igniter-web`) stay app-agnostic — no Todo-specific knowledge.

## 4. View-shape options & recommendation (Q4)

| Shape | Verdict |
|---|---|
| pure `.ig` returning `Respond` with a **ViewArtifact JSON** descriptor | **v0 ANSWER** — reuses the proven `.igv`→ViewArtifact→frame runtime; machine-free render; JSON-first, no server change |
| `.igv` lowering to ViewArtifact JSON (authored sugar) | **allowed** — `.igv` is an existing lab Projection Dialect; author views in `.igv`, lower to the JSON the handler returns |
| generated/static HTML returned via `Respond` | **rejected (v0)** — verbatim HTML not servable (§2 gap 1); template engine in core forbidden |
| external frontend bundle (React/etc.) | **out of scope** — if ever, it's an external static app consuming the JSON API |
| a new Todo-specific view dialect (`.igtodo-html`) | **rejected** — violates Projection-Dialect governance (P0): no bespoke per-app dialect with hidden runtime meaning; reuse `.igv`/ViewArtifact |

**Recommendation:** TodoApp views are **ViewArtifact JSON** returned by `.ig` handlers (optionally authored
in `.igv`). The browser shell loads the existing machine-free **frame runtime** (proven in the GUI/3D/forms
waves) and renders the fetched ViewArtifact — no new dialect, no server-core UI dependency, JSON the whole
way.

## 5. Assets classification (Q5)

| Asset | Owner | v0 delivery | Cache/digest |
|---|---|---|---|
| ViewArtifact JSON / view descriptors | **app** | `Respond` (JSON, works today) | app may set headers later |
| JSON data manifests (API) | **app** | `Respond` (JSON) | — |
| HTML shell (`index.html`) | **app** | **external static server** | external |
| frame wasm runtime (`*_bg.wasm`), JS glue | **app** | **external static server** | content-hash filename (external) |
| CSS | **app** | external static server | external |
| images / fonts | **app** | external static server | external |
| source maps | **app, dev-only** | external static server | external |

**Rule:** anything that is **JSON** → app-owned, served via `Respond` today. Anything that is **raw bytes**
(HTML/wasm/CSS/images/fonts) → external static server in v0 (or the future `RAW-RESPONSE` gate). The server
core owns **no** asset pipeline, no content-type negotiation, no ETag/range/caching (P11 §5) — those are an
external static server's job.

## 6. Server protocol gap (Q6)

Exact gaps, in priority order for TodoApp:
1. **IgWeb-level structured JSON body (app gap):** the `.igweb`/`Decision` path returns only a String body,
   double-wrapped as `{"body":"…"}` with forced `application/json`. To return a clean ViewArtifact JSON
   descriptor (and optionally a `content-type`), the IgWeb layer needs a small enhancement — **this is the
   v0 blocker for views**, and it is app-layer, not server-core.
2. **Raw-bytes body (server gap, P11 `RAW-RESPONSE`):** verbatim HTML/CSS/wasm needs the deferred
   `ServerResponse` raw-body variant + wire-encoder branch. **TodoApp does NOT need this for v0** because
   the shell+runtime are served externally and the view payload is JSON.
3. content-type fidelity, file serving, range/cache/etag — all out of v0 (external static server).

**Decision: TodoApp views start JSON-first.** Defer `RAW-RESPONSE` until a concrete need for verbatim
server-emitted bytes appears (it doesn't, given the external-shell architecture).

## 7. Route / API / page strategy (Q7)

**Explicit namespace split — no magic `respond_to`/content negotiation:**

```igweb
app TodoWeb entry Serve {
  handlers TodoHandlers
  -- page/view routes: return a ViewArtifact JSON descriptor
  route GET "/"                       -> TodoIndexView
  route GET "/accounts/:account_id/todos" -> AccountTodosView
  -- API routes: return data JSON
  scope "/api" {
    resource todos "/todos" {
      index  GET           -> TodoIndex
      create POST          -> TodoCreate requires idempotency
      show   GET "/:id"    -> TodoShow
    }
  }
}
```

- **View routes** return a `Respond` whose JSON body is a ViewArtifact; the client renders it.
- **API routes** return data JSON (existing handler shape).
- Both are ordinary `.igweb` routes producing JSON `Decision`s — fully inspectable, no content negotiation,
  no hidden `respond_to`. This composes with the proven `scope`/`resource` sugar (P16–P18).

## 8. Middleware / security boundaries (Q8)

- **P8 wrappers apply uniformly** (`TraceApp`/`AuthTokenApp`/`BodyLimitApp`) to view and API routes alike
  (P11 §6). Trace adds correlation; Auth short-circuits before the app; BodyLimit caps the **request** body.
- **Middleware stays generic — never content-aware:** no content-type routing, no per-asset branches, no
  response transform/compression in app middleware (P11 §6). Public-vs-authenticated views are expressed by
  which routes sit behind `AuthTokenApp`, not by asset-aware middleware.
- **Cache headers / gzip:** out of v0; an app may set its own headers once the IgWeb layer exposes them
  (§6 gap 1); core neither computes nor enforces caching.

## 9. Security gates (Q9 — name only, do not implement)

Relevant **only if** server-side file serving is ever built (deferred, gated; v0 has no filesystem surface —
assets are external). Required checks then (same as P11 §7): canonicalized path within a single configured
root; reject `..` traversal; reject symlink escape; **deny directory listing**; explicit extension→
content-type allowlist; no hidden dotfiles; max file size; **no public listener by default**. None are
implemented or proposed here.

## 10. Relation to TodoApp API / Postgres (Q10)

- The API/Postgres readiness packet now exists and confirms the same sequencing pressure: first prove
  app shape with observed effects and **no DB**; views likewise must not depend on a live DB.
- **First UI proof uses static/fake data:** the existing fixture-style handlers already return fixed
  `Decision`s; a view handler builds a ViewArtifact from that fake data and returns it as JSON. No DB, no
  API round-trip required for the first proof.
- **Later:** view handlers may consume API/domain data once the Postgres read wave (typed reads,
  `…-POSTGRES-TYPED-READ-P10`) and a TodoApp API skeleton land; that binding is **gated** behind those
  cards. Live data, real DSN, and the API-Postgres e2e all wait — this card keeps views DB-free.

## 11. Next-card recommendation (Q11)

**`LAB-TODOAPP-VIEW-MANIFEST-P2`** — prove the JSON-first app-owned view path end-to-end: an `.igweb` view
route + an `.ig` handler that returns a **ViewArtifact JSON** descriptor built from **fake data**, served
through `igweb-serve`, with the body being clean JSON the frame runtime can render. Bounded scope: the one
enabling enhancement is the **IgWeb-level structured-JSON body** (§6 gap 1) so the descriptor isn't
double-wrapped as an escaped string — app-layer only, no server-core change, no raw bytes, no DB.

**Why this sequence:**
1. It unblocks views with the **smallest** slice (app-layer JSON, not the server `RAW-RESPONSE` gate).
2. It reuses the **proven** `.igv`→ViewArtifact→frame runtime — no new dialect, no server UI dependency.
3. It needs **no DB** (fake data), so it is independent of the Postgres wave.
4. `RAW-RESPONSE` and external-static-shell examples are deferred until a real need for verbatim bytes
   appears — which the external-shell + JSON-payload architecture avoids.

**Sequence:** `VIEW-MANIFEST-P2` (JSON ViewArtifact from fake data) → external static-shell example (docs)
→ [Postgres typed-read + TodoApp API for real data] → `RAW-RESPONSE-P*` **only if** verbatim
server-emitted HTML/binary is ever required.

## 12. Closed surfaces

No implementation. No raw response body. No filesystem / static-directory serving. No route table or
template engine in server core. No public listener. No CDN / live network. No auth secrets. No DB. No
`igniter-frame` / `igniter-console` dependency in server core (dependency direction is UI-app → server,
never reverse — P11 §4). No new Projection Dialect. No canon claim.

---

*Readiness/design only. Compiled 2026-06-19; verified against live `protocol.rs`, `host.rs` `encode_response`,
`igniter-web/src/lib.rs` `map_decision`, the example app dirs, and P11. No code, example, dependency, asset,
or DB change.*
