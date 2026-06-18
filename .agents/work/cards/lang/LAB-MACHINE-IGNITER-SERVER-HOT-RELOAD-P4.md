# Card: LAB-MACHINE-IGNITER-SERVER-HOT-RELOAD-P4 - safe ServerApp swap between requests

**Lane:** standard / implementation proof  
**Status:** CLOSED (implementation proof)  
**Date opened:** 2026-06-18  
**Date closed:** 2026-06-18  
**Authority:** Lab-only local proof. No public listener. No daemon. No SparkCRM/live.

## Why this card exists

P1-P3 proved the server protocol and effect execution path:

```text
HTTP -> ServerRequest -> ServerApp::call -> ServerDecision::InvokeEffect
  -> MachineEffectHost -> igniter-machine handle_effect -> receipt-backed response
```

The next process-shaped requirement is hot reload: the host should be able to swap the active
`ServerApp` **between requests** without mutating an app mid-request and without restarting the
loopback listener.

This is still local/lab-only. It is not a daemon, public listener, deployment mechanism, or live
SparkCRM integration.

## Read first

- `igniter-server/src/protocol.rs`
- `igniter-server/src/host.rs`
- `igniter-server/src/effect_host.rs`
- `igniter-server/tests/loopback_tests.rs`
- `igniter-server/tests/effect_machine_tests.rs`
- `lab-docs/lang/lab-machine-igniter-server-effect-p3-v0.md`
- `lab-docs/lang/lab-machine-igniter-server-gemini-wave-a-synthesis-v0.md`

## Goal

Implement a reloadable local host shape where each request clones the currently active
`ServerApp` at the start of processing. A swap affects later requests only; in-flight requests keep
the app instance they started with.

## Required shape

1. **Active app pointer.**
   - Use only standard-library primitives unless a stronger case is documented.
   - Suggested shape: `Arc<RwLock<Arc<dyn ServerApp>>>`.
   - The read lock must be held only long enough to clone the current `Arc`.

2. **App identity.**
   - Add an identity surface only if it stays small and useful for tests/operator visibility.
   - Suggested shape: `AppIdentity { name, version, digest }`.
   - `digest` is an opaque app-supplied string. Do not mandate SHA-256.
   - If changing `ServerApp`, update all fixture apps and tests in the same slice.

3. **Standard loopback path.**
   - Add a reloadable version of `serve_once` / `serve_bounded`.
   - It must use the active app clone selected at request start.
   - It must not add a product route table to the host.

4. **Machine/effect path.**
   - Under the existing `machine` feature, add a reloadable version of the P3 effect path if the
     diff remains narrow.
   - It must still use `MachineEffectHost` and the existing machine contour.
   - It must not add `capability_id`, `operation`, or `scope` to app decisions.

5. **Traceability without side-log authority.**
   - Tests may return app identity from helper functions or inspect response headers/body when the
     fixture app chooses to expose them.
   - Do not add a new global log authority. If a trace sink is introduced, keep it test-local and
     documented as observation only.

## Acceptance

- [ ] `igniter-server cargo test` passes.
- [ ] `igniter-server cargo test --features machine` passes.
- [ ] Request 1 sees app v1; after swap, request 2 sees app v2 on the same listener/host helper.
- [ ] In-flight request keeps app v1 even if the active app is swapped before it returns.
- [ ] Reloadable effect path, if implemented in this slice, still commits through P3
      `MachineEffectHost` and performs no second effect on replay.
- [ ] Host still does not inspect `(method,path)` for product routing.
- [ ] App decision still carries no effect identity.
- [ ] No public listener, no daemon, no SparkCRM code, no live DB/network.
- [ ] Proof doc written:
      `lab-docs/lang/lab-machine-igniter-server-hot-reload-p4-v0.md`.
- [ ] Closing report added to this card with exact commands and pass counts.

## Suggested tests

- `reloadable_host_routes_v1_then_v2_on_same_listener`
- `in_flight_request_keeps_original_app_after_swap`
- `reload_does_not_create_host_route_table`
- `reloadable_effect_path_uses_machine_host`
- `app_identity_is_observable_but_not_authority`

## Closed surfaces

- No public bind.
- No unbounded daemon.
- No file watcher.
- No dynamic code loading.
- No SparkCRM/live routes.
- No DB/live credentials.
- No new effect semantics.
- No language canon claim.

## Next routes

- `LAB-MACHINE-IGNITER-SERVER-SERVING-LOOP-P5` - bounded serving loop over reloadable app pointer.
- `LAB-MACHINE-IGNITER-SERVER-MIDDLEWARE-P*` - implement wrapper middleware only after reload shape
  is settled.
- `LAB-MACHINE-SPARKCRM-SERVER-APP-READINESS-P1` - product-shaped app design remains readiness-only
  until local server mechanics are proven.

---

## Closing report — 2026-06-18

**Outcome:** Safe `ServerApp` hot reload implemented and proven. The host swaps the active app between
requests via `ReloadableApp = Arc<RwLock<Arc<dyn ServerApp + Send + Sync>>>`; each request snapshots
the active app at start (clone the inner `Arc` under a brief read lock, then drop it), so an in-flight
request keeps its instance even when a swap lands mid-flight. All guardrails held: no public listener,
no daemon, no file watcher, no dynamic code loading, no SparkCRM/live, no route-config framework, no
middleware, **zero `igniter-machine` code changes**.

**Deliverable:** `lab-docs/lang/lab-machine-igniter-server-hot-reload-p4-v0.md`.

**Implementation (lab-only, `igniter-server`):**
- `src/reload.rs` (new, machine-free) — `ReloadableApp` (`new`/`current`/`swap`/`identity`); read lock
  held only to `Arc::clone`, never across `call`/effect. 2 unit tests.
- `src/protocol.rs` — `AppIdentity { name, version, digest }` + `ServerApp::identity()` with a default
  (opaque digest, observation only — NOT authority). Existing apps unchanged.
- `src/host.rs` — `serve_once_reloadable` / `serve_bounded_reloadable` (sync, snapshot then serve).
- `src/effect_host.rs` (`machine` feature) — `serve_once_effect_reloadable` (snapshot then the
  unchanged P3 `MachineEffectHost` contour; one-line diff vs `serve_once_effect`).
- `src/fixture.rs` — `DemoApp::identity()` override.
- `tests/reload_tests.rs` (new) 4 tests + `tests/effect_machine_tests.rs` +1 reloadable-effect test.

**Exact commands + pass counts:**

```text
$ cd igniter-server && cargo test                    → 15 passed; 0 failed (4 protocol + 2 reload-unit + 5 loopback + 4 reload; effect gated off)
$ cd igniter-server && cargo test --features machine → 22 passed; 0 failed (above + 7 effect)
```
`igniter-server` warning-clean in both builds (transitive warnings are pre-existing in
`igniter_compiler`/`igniter_machine`).

**Key tests:** `reloadable_host_routes_v1_then_v2_on_same_listener` (swap → next request sees v2);
`in_flight_request_keeps_original_app_after_swap` (genuinely concurrent — app blocks in `call` on a
`Condvar`, test swaps to v2 mid-flight, response still v1 while `host.identity()` is already v2);
`reload_does_not_create_host_route_table` (v1 routes /a, v2 routes /b, same host); 
`app_identity_is_observable_but_not_authority`; `reloadable_effect_path_uses_machine_host` (commit via
P3, swap, same-key replay → `attempts == 1`).

**Acceptance:** all boxes met (see deliverable doc). Middleware deliberately left out per guardrail.

