# LAB-IGNITER-WEB-EXAMPLE-APP-P9 — first real IgWeb app example

Status: CLOSED (lab implementation)  
Lane: standard / lab implementation  
Opened: 2026-06-18  
Closed: 2026-06-18  
Delegate label: OPUS-IGNITER-WEB-EXAMPLE-I  
Skill: idd-agent-protocol  

## Why This Card

P8 extracted `build_igweb_app` into the `igniter-web` crate. The next risk is developer experience:

```text
Can a developer write normal files
  routes.igweb + types.ig + handlers.ig + tiny Rust runner
and run a loopback server without domain code in igniter-server?
```

This card builds the first real example app on top of `igniter-web`.

## Authority

Lab implementation. This is an example/DX proof, not canon and not a public framework API.

Allowed:
- Add example app files under the smallest appropriate `igniter-web` example location.
- Add a tiny Rust runner that uses `build_igweb_app`.
- Add tests/proof docs/card closure.
- Add README/example pointers if useful.

Not allowed:
- No `igweb.toml` manifest.
- No CLI/dialect registry.
- No source-map/diagnostics expansion.
- No `igniter-server/src` route table.
- No SparkCRM/domain-specific app.
- No live/public listener; loopback/bounded only.
- No real effect execution; `InvokeEffect` may remain observed `202`.
- No new web framework surface beyond the example.

## Verify First

Read:

- `lab-docs/lang/lab-igniter-web-crate-p8-v0.md`
- `igniter-web/src/lib.rs`
- `igniter-web/tests/builder_tests.rs`
- `igniter-server/examples/server_app_basic.rs`
- `igniter-server/examples/server_app_runner.rs`
- `igniter-server/src/host.rs`
- `igniter-server/src/serving_loop.rs`
- `igniter-server/src/middleware.rs`

Live code wins. Keep the example boring.

## Implementation Target

Create a small, inspectable example app. Suggested shape:

```text
igniter-web/
  examples/
    todo_app/
      web_types.ig
      todo_handlers.ig
      routes.igweb
    todo_server.rs
```

or an equivalent minimal layout if Cargo example conventions require it.

The example should show:

```rust
let app = build_igweb_app(IgWebBuildInput {
    sources: vec![
        "examples/todo_app/web_types.ig",
        "examples/todo_app/todo_handlers.ig",
        "examples/todo_app/routes.igweb",
    ],
    entry: "Serve".into(),
})?;
```

Then either:
- call the app directly and print decisions; and/or
- serve a bounded loopback run through `igniter_server::host::serve_once` / `serve_bounded`.

Prefer a bounded loopback proof because it matches P5/P8 and reveals real DX.

## Required Example Behavior

Use a neutral Todo-ish domain, not SparkCRM.

Routes:

```text
GET  /health             -> 200 "ok"
GET  /todos              -> 200 "[]"
GET  /todos/:id          -> 200 id
POST /todos/:id/done     -> requires idempotency -> InvokeEffect target "todo-done"
GET  /missing            -> 404
POST /health             -> 405
```

This is the same behavioral vocabulary as P5/P8, but now authored as real example files.

## Tests / Proofs

Required:

1. `cargo run --example todo_server` (or exact example name) runs without panic and exits deterministically. If it starts a server, it must be bounded.
2. Example files are actual files on disk, not inline strings in the runner.
3. A real loopback request to `/health` returns 200.
4. `/todos/42` proves path param extraction through generated regexp/capture.
5. Keyless mutating route returns 400.
6. Keyed mutating route yields observed `InvokeEffect` / 202 with logical target and idempotency key, no privileged effect identity.
7. Unknown path/wrong method produce 404/405.
8. Example composes with middleware or explicitly states why middleware is already proven and not repeated.
9. `igniter-server` normal dependency tree remains small.
10. `igniter-web` tests still pass.

Suggested commands:

```bash
cd igniter-web && cargo test
cd igniter-web && cargo run --example todo_server
cd igniter-server && cargo test
cd igniter-server && cargo test --features machine
cd igniter-server && cargo tree -e normal
```

Use the exact example name created.

## Deliverables

- Real example app files.
- Example runner.
- Tests/proof if needed.
- `lab-docs/lang/lab-igniter-web-example-app-p9-v0.md`
- Closing report in this card.
- Thin pointer from P8 proof doc to P9 result.

## Acceptance

1. Example is built from authored `.igweb` + `.ig` files, not inline test strings.
2. Example runner uses `igniter_web::build_igweb_app`.
3. Example can run deterministically from Cargo.
4. Loopback proof covers health, param, keyless/keyed mutation, 404, 405.
5. Server still owns transport only; routes live in `.igweb`.
6. Effect authority remains out of `.igweb`.
7. No manifest/CLI/source-map introduced.
8. Docs state the exact developer command and the current DX pain points.
9. Dependency boundary remains clean.
10. P8/P5/P4 regressions remain green.

## Closing Report Template

Report:

- final example file layout;
- exact command(s) to run;
- request/response traces;
- dependency boundary result;
- what this revealed about DX;
- what remains deferred.

---

## Closing report — 2026-06-18

**Final example layout:** `igniter-web/examples/todo_app/{web_types.ig, todo_handlers.ig, routes.igweb}`
+ `igniter-web/examples/todo_server.rs` (runner) + `igniter-web/tests/example_app_tests.rs` (7 tests).
Authored files on disk, loaded by path (`CARGO_MANIFEST_DIR`) — not inline strings.

**Command:** `cd igniter-web && cargo run --example todo_server` (deterministic, bounded, exits 0).

**Request/response traces:**
```
GET  /health         -> 200 {"body":"ok"}
GET  /todos          -> 200 {"body":"[]"}
GET  /todos/42       -> 200 {"body":"42"}        (path param via generated regexp/capture)
POST /todos/42/done  -> 400 {"body":"missing idempotency-key"}   (keyless)
POST /todos/42/done  -> 202 invoke_effect target "todo-done" idem "evt-1"  (keyed; no capability_id/scope)
GET  /missing        -> 404 ;  POST /health -> 405
```

**Dependency boundary:** `igniter-server` normal tree stays serde-only (`cargo tree -e normal` none);
the example lives in `igniter-web` (which already carries compiler/machine). build via
`igniter_web::build_igweb_app`; server serves via `igniter_server::host::serve_bounded` (machine-free).

**Tests/counts:** igniter-web 12 (5 builder + 7 example_app); igniter-server 49 default / machine 0
failed; igniter-compiler igweb_lowering 2. igniter-web warning-clean (own code).

**What DX revealed:** authored surface is tiny + readable (one `.igweb` block + `pure contract`
handlers + a ~50-line runner); routing reads like routing; path params work via stdlib.regexp (P3) with
no split/nth gymnastics. Pain points (deferred): fixed import-name convention (WebTypes/TodoHandlers);
no `.igweb→.ig` source map; InvokeEffect observed (not executed); Decision/Request authored per app.

**Deferred:** shared Request/Decision prelude; module-name parameterization; source maps; real effect
execution (P3); dialect registry/CLI (P0).

**Acceptance:** all 10 boxes met (see `lab-docs/lang/lab-igniter-web-example-app-p9-v0.md`). Thin
pointer added from the P8 proof doc.

