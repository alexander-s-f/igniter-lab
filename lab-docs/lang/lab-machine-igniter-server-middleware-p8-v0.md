# lab-machine-igniter-server-middleware-p8-v0 — generic wrapper middleware

**Card:** `LAB-MACHINE-IGNITER-SERVER-MIDDLEWARE-P8`
**Status:** CLOSED (implementation proof) — three generic, zero-cost wrapper middlewares that extend
`igniter-server` without becoming routing, app logic, effect authority, or hidden mutable state.
**No domain app, no plugin system, no assets protocol, no route framework, no live IO, no
`igniter-machine` change.**
**Authority:** Lab-only, generic server substrate. Implements the P7 extension model.

## What this card proves

Middleware = an ordinary `ServerApp` that wraps an inner `ServerApp` (Approach 1 from the
middleware-shape design). One stack of plain trait objects:

```text
request -> BodyLimitApp -> AuthTokenApp -> TraceApp -> ServerApp::call -> response
```

- wrappers `impl ServerApp` → compose with no new runtime;
- auth / body-limit **short-circuit** before the inner app;
- `TraceApp` only decorates (correlation id), never changing the decision kind;
- a wrapper can never inject effect identity (`ServerDecision` has no such fields);
- `ReloadableApp` wraps the **outer composed stack** → a swap replaces middleware + core atomically.

## Implementation (`igniter-server/src/middleware.rs`, machine-free)

| Wrapper | Behavior |
|---|---|
| `TraceApp<A>` | ensures a correlation id (deterministically derived from method+path+body if absent — no clock/RNG, replay-safe), propagates it to the inner request, decorates a `Respond` with `x-correlation-id`. Decision kind unchanged; `Invoke`/`InvokeEffect` pass through verbatim. |
| `AuthTokenApp<A>` | static bearer-token gate; on failure returns `401` **without** calling inner; on success injects a generic `x-auth-ok` marker and delegates. |
| `BodyLimitApp<A>` | rejects a serialized body over `max_bytes` with `413` **before** inner; no streaming/parser scope. |

Plus `ServerAppExt` (sugar): `app.with_trace().with_auth(token).with_body_limit(n)` builds
`BodyLimitApp<AuthTokenApp<TraceApp<App>>>` — the card pipeline, read top-down. Every wrapper is
`&self`-pure (no interior mutability), `Send + Sync` when its inner is, and delegates `identity()` to
the inner app (so a composed stack reports the inner app's identity — observation only).

### Invariants held (by construction)

- **No route table:** no wrapper inspects `(method, path)` to dispatch — routing stays in the inner
  `ServerApp::call`. (`rg` over `src/middleware.rs` finds no domain vocabulary.)
- **No effect identity:** wrappers return the inner `ServerDecision` unchanged for `Invoke`/
  `InvokeEffect`; `capability_id`/`operation`/`scope` don't exist on the type.
- **No hidden state:** wrappers hold only `inner` + immutable config; no counters/caches/`Mutex`.

## Tests (`tests/middleware_tests.rs`, 8 — machine-free)

1. `sequential_decoration_preserves_inner_and_decorates` — full stack; inner sees injected
   `x-auth-ok` + deterministic `x-correlation-id`; response decorated; inner called once.
2. `short_circuit_auth_does_not_call_inner` — missing/wrong token → `401`, inner is `PanicApp` (never
   called → no panic).
3. `short_circuit_body_limit_does_not_call_inner` — oversized body → `413`, inner never called.
4. `middleware_is_route_agnostic` — same wrapper around two different inner apps → routing follows the
   inner; the wrapper added no route.
5. `middleware_cannot_inject_effect_identity` — an `InvokeEffect` passes through `Trace`+`Auth`
   unchanged; serialized decision has no `capability_id`/`operation`/`scope`.
6. `reloadable_app_wraps_whole_stack` — `ReloadableApp` over `Auth(TOKA)→RouteApp v1`; a real loopback
   request with `TOKA` → `200`; swap the WHOLE stack to `Auth(TOKB)→RouteApp v2`; next request with
   `TOKA` → `401` (the auth middleware swapped too, not just the inner). Also asserts an in-flight
   snapshot keeps `v1` while the active stack reports `v2`.
7. `composed_stack_is_send_sync` — the stack passes `assert_send_sync` and erases to
   `Arc<dyn ServerApp + Send + Sync>`.
8. `no_hidden_cross_request_state` — valid/invalid/valid through one `Auth` stack → `200/401/200`,
   inner called exactly twice; no leakage between requests.

## Acceptance — met

- [x] Generic middleware wrappers implemented (`TraceApp`/`AuthTokenApp`/`BodyLimitApp` + `ServerAppExt`).
- [x] Wrappers preserve `ServerApp` composition; no special runtime.
- [x] Auth/body-limit short-circuit before inner (tests 2, 3 with `PanicApp`).
- [x] Trace/decorate does not alter routing or effect authority (tests 1, 4, 5).
- [x] `ReloadableApp` wraps the entire composed stack; swap + in-flight covered (test 6).
- [x] No route table in middleware; no domain vocabulary in core (`rg` clean).
- [x] No live network/listener/DB/credentials/vendor API.
- [x] `cargo test` green (**34**); `cargo test --features machine` green (**47**).
- [x] Proof doc + closing report.

## Exact commands + pass counts

```text
$ cd igniter-server && cargo test
  unittests src/lib.rs (protocol+reload+serving_loop)  7 passed
  tests/middleware_tests.rs                            8 passed
  tests/loopback_tests.rs                              5 passed
  tests/reload_tests.rs                                4 passed
  tests/serving_loop_tests.rs                          5 passed
  tests/sparkcrm_app_tests.rs                          5 passed
  (effect_machine + sparkcrm_shadow gated off)         0
  TOTAL                                               34 passed; 0 failed

$ cd igniter-server && cargo test --features machine
  + tests/effect_machine_tests.rs                      8 passed
  + tests/sparkcrm_shadow_tests.rs                     5 passed
  TOTAL                                               47 passed; 0 failed
```
`igniter-server` warning-clean in both builds; `igniter-machine` untouched.

## Closed surfaces (held)

No domain app · no dynamic plugin system · no assets protocol · no public listener · no live
SparkCRM/vendor · no DB · no credentials · no route-config framework · no effect-identity injection ·
no `igniter-machine` change.

## Next

- `LAB-MACHINE-IGNITER-SERVER-EXAMPLE-APP-P*` — a discoverable workspace **example** app implementing
  `ServerApp` (the durable "apps live outside core" demonstration), optionally composing these
  wrappers.
- `LAB-MACHINE-IGNITER-SERVER-ASSETS-READINESS-P*` — assets, only if a real need appears (an app
  returning `Respond` covers the simple case today).
