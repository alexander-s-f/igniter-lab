# lab-igniter-web-example-app-p9-v0 — first real IgWeb app example

**Card:** `LAB-IGNITER-WEB-EXAMPLE-APP-P9` · **Delegation:** `OPUS-IGNITER-WEB-EXAMPLE-I`
**Status:** CLOSED (lab implementation) — the first real IgWeb app, authored as **plain files on disk**
(`routes.igweb` + support `.ig`) and run by a tiny Rust runner via `igniter_web::build_igweb_app`. A
developer writes files and gets a loopback server with **zero domain code in `igniter-server`**.
**No manifest, no CLI, no source-map, no server route table, no SparkCRM, no live/public listener.**
**Authority:** Lab DX proof. Not canon, not a public framework API.

## What a developer writes

```text
igniter-web/examples/
  todo_app/
    web_types.ig        # module WebTypes   — Request type + Decision variant
    todo_handlers.ig    # module TodoHandlers — pure Health/TodoIndex/TodoShow/TodoDone contracts
    routes.igweb        # app TodoWeb entry Serve { route ... }   (the Projection Dialect)
  todo_server.rs        # ~50-line Rust runner: build_igweb_app(...) + bounded loopback serve
```

```rust
let app = build_igweb_app(IgWebBuildInput {
    sources: vec![src("web_types.ig"), src("todo_handlers.ig"), src("routes.igweb")],
    entry: "Serve".into(),
})?;
igniter_server::host::serve_bounded(&listener, &*app, n)?;   // server owns transport only
```

## Run it

```text
$ cd igniter-web && cargo run --example todo_server
todo_server on http://127.0.0.1:PORT (loopback, bounded; built from examples/todo_app/*.ig + routes.igweb)
GET  /health              -> 200  {"body":"ok"}
GET  /todos               -> 200  {"body":"[]"}
GET  /todos/42            -> 200  {"body":"42"}            ← path param via generated regexp/capture
POST /todos/42/done       -> 400  {"body":"missing idempotency-key"}
POST /todos/42/done       -> 202  {"decision":"invoke_effect","target":"todo-done","idempotency_key":"evt-1",...}
GET  /missing             -> 404  {"body":"not found"}
POST /health              -> 405  {"body":"method not allowed"}
served 7 bounded requests; exiting
```
Deterministic, bounded, exits 0. The runner builds from the authored files (not inline strings), serves
a real `127.0.0.1` loopback run, and prints every route's outcome.

## Acceptance — met

1. ✓ Built from authored `.igweb` + `.ig` files on disk, not inline strings (`example_files_exist_on_disk`
   asserts the files; the runner + tests load them by path).
2. ✓ Runner uses `igniter_web::build_igweb_app`.
3. ✓ Runs deterministically from Cargo (`cargo run --example todo_server`, bounded, exits 0).
4. ✓ Loopback proof covers health, param (id=42), keyless 400, keyed InvokeEffect, 404, 405
   (`tests/example_app_tests.rs`, 7 tests, over real `host::serve_once`).
5. ✓ Server owns transport only; routes live in `routes.igweb` (no `igniter-server/src` route table).
6. ✓ Effect authority stays out of `.igweb` — `TodoDone` emits a logical `InvokeEffect{ target:
   "todo-done" }`; no `capability_id`/`operation`/`scope`.
7. ✓ No manifest/CLI/source-map introduced.
8. ✓ Docs state the exact command + DX pain points (below).
9. ✓ Dependency boundary clean — `igniter-server` normal tree stays serde-only (verified
   `cargo tree -e normal`); the example lives in `igniter-web` (which already carries the
   compiler/machine weight).
10. ✓ P8/P5/P4 regressions green.

## Test commands + pass counts

```text
$ cd igniter-web && cargo run --example todo_server   → 7 routes printed, exit 0
$ cd igniter-web && cargo test                        → 12 passed; 0 failed (5 builder + 7 example_app)
$ cd igniter-server && cargo test                     → 49 passed; 0 failed
$ cd igniter-server && cargo test --features machine  → 0 failed (igweb_adapter 6 + igweb_builder 3 + …)
$ cd igniter-server && cargo tree -e normal | grep web|machine|compiler|regex|tokio → (none) serde-only
$ cd igniter-compiler && cargo test --test igweb_lowering_tests → 2 passed (P4 intact)
```
`example_app_tests` (7): files-exist · health+index · route-param (id=42) · keyless-400 · keyed-
InvokeEffect (no identity) · unknown-404 + method-405 · composes-with-middleware. `igniter-web`
warning-clean in its own code.

## What this revealed about DX (honest)

Good: the authored surface is tiny and readable — one `.igweb` route block, plain `pure contract`
handlers, a Request type + Decision variant, and a ~50-line runner. Routing reads like routing; the
server stays generic. Path params work via `stdlib.regexp` (P3) with no `split`/`nth` gymnastics.

Pain points (deferred, named):
- **Two import-name conventions are fixed** in the lowering (`WebTypes`, `TodoHandlers`) — the example
  must name its modules to match. A real tool would parameterize or infer these (P6/P7 noted this).
- **No `.igweb → .ig` source map** — a compile error in generated `.ig` points at the generated file,
  not the `.igweb` line. Fine for a small app; matters at scale.
- **`InvokeEffect` is observed `202`**, not executed — real commit is the host-side P3 path.
- **`Decision`/`Request` are hand-authored** per app — a future shared `igniter-web` prelude could
  provide them, but v0 keeps them visible/authored on purpose.

## Closed surfaces (held)

No `igweb.toml`/CLI/source-map · no `igniter-server/src` route table · no SparkCRM/domain app · no
live/public listener (loopback + bounded only) · no real effect execution · no new framework surface.

## Deferred / next

A shared `Request`/`Decision` prelude in `igniter-web`; module-name parameterization in the lowering;
`.igweb→.ig` source maps; real effect execution wiring (P3); dialect registry/CLI (P0). None block the
example.

---

*Lab implementation. Compiled 2026-06-18; `cargo run --example todo_server` deterministic; igniter-web
12 tests green; `igniter-server` normal tree serde-only. The first real IgWeb app, authored as files.*
