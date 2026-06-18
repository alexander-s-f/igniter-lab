# lab-machine-igniter-server-example-app-p10-v0 — first external ServerApp example

**Card:** `LAB-MACHINE-IGNITER-SERVER-EXAMPLE-APP-P10`
**Status:** CLOSED (implementation) — the first discoverable **external** `ServerApp`, implemented as a
standalone Cargo example + a verifying test. **Machine-free, no domain module in core, no route table,
no machine bridge, no live IO, no `igniter-machine` change.**
**Authority:** Lab-only. No canon claim. Implements the P9 readiness shape.

## What this card proves

A third-party developer's smallest teaching artifact:

```text
external app code (examples/) -> impl ServerApp -> host observes Respond / InvokeEffect
```

- the app lives in `examples/`, **never `src/`** — it `use`s the published `igniter_server` crate, so
  the dependency direction is app → server (the P6/P7 boundary, demonstrated);
- routing is a plain `match (method, path)` **inside `ServerApp::call`** — never server config;
- an effect is a LOGICAL `InvokeEffect { target, input, correlation_id, idempotency_key }` decision;
  the app names a `target`, never `capability_id`/`operation`/`scope`;
- it is machine-free: builds, runs, and tests with no `--features machine`.

Neutral domain `ticket-intake` (a generic illustrative noun, not a product ontology):
`GET /health` → `Respond(200)`; `POST /tickets` with an idempotency key → `InvokeEffect { target:
"ticket-create" }`; keyless `POST /tickets` → `Respond(400)`; anything else → `Respond(404)`.

## Deliverables (created)

| File | Role |
|---|---|
| `igniter-server/examples/server_app_basic.rs` | `pub struct ExampleApp` + `impl ServerApp` (`call` match, `identity()` = `ticket-intake-example` / `v0`) + sanitizing `normalize_ticket` + a machine-free `main()` that prints sample decisions and a P8-middleware-composed demo |
| `igniter-server/tests/example_app_tests.rs` | includes the example via `#[path = "../examples/server_app_basic.rs"] mod example_app;` (compiles it exactly as a consumer would) and verifies routes, effect shape, no-privileged-identity, identity, middleware composition, and a real loopback round-trip |
| `igniter-server/README.md` | one-line pointer to the runnable example (no architecture rewrite) |

No `src/` change (no `pub mod` domain module added). The example reads the canonical
`req.idempotency_key` field (which the host parser promotes from the `idempotency-key` header).

## Acceptance — met

- [x] Example lives under `examples/`, not `src/`; no `pub mod` domain module in core.
- [x] Compiles with default features; **no `igniter-machine` dependency** (`cargo build --examples`
      green; `cargo run --example server_app_basic` prints decisions and exits 0).
- [x] Tests prove route behavior + effect decision shape (`health_returns_respond_200`,
      `post_tickets_with_key_is_invoke_effect` — `target == "ticket-create"`, `idempotency_key ==
      Some("tkt-1001")`, correlation propagated, sanitized input; `keyless_post_tickets_is_400_no_effect`;
      `unknown_route_is_404`).
- [x] Tests prove no privileged effect identity (`decision_carries_no_privileged_effect_identity`: no
      `capability_id`/`operation`/`scope`).
- [x] `identity().name == "ticket-intake-example"`.
- [x] Composes with P8 middleware (`composes_with_p8_middleware`:
      `ExampleApp.with_trace().with_auth("demo-secret")` → 401 without token (Auth short-circuits, app
      never reached), 200 + `x-correlation-id` with token).
- [x] Optional real loopback round-trip (`health_over_real_loopback_host`:
      `host::serve_once` → `GET /health` → 200, body names the example).
- [x] `cargo test` green; `cargo test --features machine` green; example warning-clean.

## Exact commands + pass counts

```text
$ cd igniter-server && cargo build --examples            → Finished (warning-clean)
$ cd igniter-server && cargo run --example server_app_basic
  == ticket-intake-example v0 ==
  GET /health   -> {"kind":"respond", … status 200 …}
  POST /tickets -> {"kind":"invoke_effect","target":"ticket-create","input":{"priority":"high","title":"printer jam"},"correlation_id":"corr-1","idempotency_key":"tkt-1001"}
  POST /tickets -> {"kind":"respond", … status 400 "missing idempotency-key" …}
  DELETE /unknown -> {"kind":"respond", … status 404 …}
  middleware (no auth)   -> {"kind":"respond", … status 401 …}
  middleware (with auth) -> {"kind":"respond", … status 200, x-correlation-id … }

$ cd igniter-server && cargo test                    → 42 passed; 0 failed   (was 34; +8 example_app_tests)
$ cd igniter-server && cargo test --features machine → 55 passed; 0 failed   (was 47; +8)
```

`tests/example_app_tests.rs` = 8 tests; `igniter-server` warning-clean in both builds (transitive
warnings are pre-existing in `igniter_compiler`/`igniter_machine`).

## Closed surfaces (held)

No domain module in `src/` · no server route table · no machine bridge implementation · no live
network/public listener · no DB · no credentials · no SparkCRM/vendor vocabulary (neutral
`ticket-intake`) · no dynamic plugin system · no assets protocol · no canon claim.

## Next

- The example is the durable "write your first `ServerApp`" reference. A future card could add a
  second example (e.g. a middleware-composed stack run over the bounded serving loop) or graduate a
  real reusable app into a sibling crate — neither is required now.
- `LAB-MACHINE-IGNITER-SERVER-ASSETS-READINESS-P*` remains the open readiness route for non-API apps.
