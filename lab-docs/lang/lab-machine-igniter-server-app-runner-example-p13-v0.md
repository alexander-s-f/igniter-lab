# lab-machine-igniter-server-app-runner-example-p13-v0 - build_app + thin runner example

**Card:** `LAB-MACHINE-IGNITER-SERVER-APP-RUNNER-EXAMPLE-P13`
**Status:** CLOSED (implementation) - a second machine-free Cargo example teaching the P12 packaging
pattern: `build_app(config) -> Arc<dyn ServerApp + Send + Sync>` + a thin runner over `ReloadableApp`
and a bounded `serve_loop`. **No new crate, no domain module in `src/`, no machine bridge, no live IO,
no `igniter-machine` change.**
**Authority:** Lab-only. No canon claim. Implements the P12 readiness model.

## What this card proves

```text
AppConfig -> build_app(config) -> Arc<dyn ServerApp + Send + Sync>   (composes P8 middleware explicitly)
  -> ReloadableApp::new(stack)
  -> ServingPolicy::new(n).loopback_only()
  -> serve_loop over a caller-bound 127.0.0.1 listener   (the THIN runner)
```

The lesson layered on P10's raw-trait example: **how a packaged app is built and run.** The app owns
routing (`match` in `call`); `build_app` composes middleware from config at the edge
(`BodyLimit -> [Auth] -> Trace -> CoreApp`); the runner owns the listener + serving policy + reload; the
machine/effect bindings stay a separate, optional host concern. No new crate, no framework.

## Deliverables (created)

| File | Role |
|---|---|
| `igniter-server/examples/server_app_runner.rs` | neutral `CoreApp` (`GET /health` -> 200; `POST /echo` with idempotency key -> `InvokeEffect{ target: "echo-record" }`; keyless -> 400; else 404), `pub struct AppConfig { version, auth_token, body_limit }`, `pub fn build_app(&AppConfig) -> Arc<dyn ServerApp + Send + Sync>` (explicit P8 middleware composition), and a `main()` that runs the real bounded `serve_loop` with loopback clients + a hot-reload (swap) demo |
| `igniter-server/tests/app_runner_example_tests.rs` | includes the example via `#[path]`; 7 tests |
| `igniter-server/README.md` | one-line pointer to the runner example |

No `src/` change (no domain module). `build_app` returns one boxed trait object; the optional-auth
branch boxes in each arm so a single return type holds either stack.

## Acceptance - met

- [x] Example demonstrates `build_app(config) -> Arc<dyn ServerApp + Send + Sync>`
      (`build_app_returns_send_sync_and_serves_health` - the type annotation proves `Send + Sync`).
- [x] Thin runner over `ReloadableApp` + bounded `serve_loop` (`bounded_loopback_serves_health_then_
      returns`: serves 1, returns - not a daemon; `main` runs a bounded-2 loop over loopback).
- [x] Middleware composition explicit + config-driven (`config_auth_short_circuits_and_trace_decorates`:
      missing token -> 401 short-circuit, valid -> 200 + `x-correlation-id`; `config_body_limit_rejects_
      oversized_before_app`: oversized body -> 413 before the app).
- [x] App owns routing; runner owns listener/policy/reload (`app_owns_routing_unknown_is_404`; no
      server route table anywhere).
- [x] Whole-stack reload (`reload_swaps_the_whole_stack_over_loopback`: TOKA -> 200 under v1, swap to
      v2/TOKB, TOKA -> 401; `report.app_versions_seen == ["v1","v2"]`).
- [x] Bounded loopback on `127.0.0.1` only (`ServingPolicy::loopback_only()`; report `is_loopback`).
- [x] Serialized decisions carry no `capability_id`/`operation`/`scope`
      (`decision_carries_no_privileged_effect_identity`; target is the logical `"echo-record"`).
- [x] Machine-free (default build/test); `cargo test --features machine` still green.
- [x] `cargo build --examples` + `cargo run --example server_app_runner` succeed; example
      warning-clean.

## Exact commands + output

```text
$ cd igniter-server && cargo build --examples              -> Finished (0 warnings)
$ cd igniter-server && cargo run --example server_app_runner
  runner on http://127.0.0.1:PORT (loopback only, bounded to 2 requests)
  req1 GET /health (TOKA)               -> 200
  req2 GET /health (TOKA, after swap)   -> 401
  served 2 requests; app versions seen: ["v1", "v2"]

$ cd igniter-server && cargo test                    -> 49 passed; 0 failed   (was 42; +7 app_runner_example_tests)
$ cd igniter-server && cargo test --features machine -> 62 passed; 0 failed   (was 55; +7)
```

`igniter-server` warning-clean in both builds (transitive warnings are pre-existing in
`igniter_compiler`/`igniter_machine`).

## Closed surfaces (held)

No new crate; no release packaging; no dynamic plugin loading; no machine/effect host
implementation; no SparkCRM/vendor app; no public listener; no DB; no credentials; no
assets/raw-response protocol; no route-config framework; no canon claim.

## Next

- The two examples (`server_app_basic.rs` = the trait; `server_app_runner.rs` = build_app + runner)
  are the durable "write & run your `ServerApp`" references.
- Graduating a real reusable app into a sibling crate (`igniter-server-sample-app`) remains a *later,
  optional* route, opened only when a real second consumer exists (P12).
- `LAB-MACHINE-IGNITER-SERVER-RAW-RESPONSE-P*` (verbatim non-JSON bytes) remains the named, trigger-
  gated assets route (P11).
