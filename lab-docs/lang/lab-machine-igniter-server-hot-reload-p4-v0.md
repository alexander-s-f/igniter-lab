# lab-machine-igniter-server-hot-reload-p4-v0 — safe ServerApp swap between requests

**Card:** `LAB-MACHINE-IGNITER-SERVER-HOT-RELOAD-P4`
**Status:** CLOSED (implementation proof) — the host can swap the active `ServerApp` **between**
requests; an in-flight request keeps the instance it started with. **No public listener, no daemon,
no file watcher, no dynamic code loading, no SparkCRM/live, no route-config framework, no middleware,
no `igniter-machine` code change.**
**Authority:** Lab-only. No canon claim. Builds on P1–P3.

## What this card proves

A request takes a SNAPSHOT of the active app at the start of processing and serves that exact
instance. A `swap` replaces the active pointer for LATER requests only:

```text
ReloadableApp = Arc<RwLock<Arc<dyn ServerApp + Send + Sync>>>

serve_once_reloadable:
  accept
  current = app.current()      ← snapshot: clone the inner Arc under a brief read lock, then DROP it
  req     = read(stream)
  decision = current.call(req) ← lock NOT held here; swap may happen concurrently, this keeps `current`
  write(execute(decision))

operator: app.swap(new_app)    ← write lock only for the pointer assignment; affects the NEXT snapshot
```

The read lock is held only long enough to `Arc::clone` the active pointer (`reload.rs::current`); it
is never held across `call` or effect execution. Because the in-flight request owns its own `Arc`
clone, a swap can land at any moment without disturbing it.

## Implementation surface (all lab-only, `igniter-server` crate)

| File | Change |
|---|---|
| `src/reload.rs` (**new, machine-free**) | `ReloadableApp` (`new` / `current` / `swap` / `identity`) over `Arc<RwLock<Arc<dyn ServerApp + Send + Sync>>>`; 2 unit tests |
| `src/protocol.rs` | added `AppIdentity { name, version, digest }` + `ServerApp::identity()` **with a default** (existing apps need no change; `digest` opaque, no scheme mandated) |
| `src/host.rs` | added `serve_once_reloadable` / `serve_bounded_reloadable` (sync, machine-free) — snapshot then serve |
| `src/effect_host.rs` (`#[cfg(feature = "machine")]`) | added `serve_once_effect_reloadable` — snapshot then run the **unchanged P3 `MachineEffectHost`** contour |
| `src/fixture.rs` | `DemoApp` now overrides `identity()` (`demo-app` / `v0`) |
| `tests/reload_tests.rs` (**new, machine-free**) | 4 reload tests |
| `tests/effect_machine_tests.rs` | +1 reloadable-effect test |

### Design decisions

- **Std-library only.** `Arc<RwLock<Arc<…>>>` per the card's hint — no `arc-swap` dependency needed
  for a lab proof. `current()` is a clone-under-read-lock; `swap()` is an assign-under-write-lock.
- **Identity is observation, not authority.** `AppIdentity` is app-supplied and opaque; the host
  never consults it to make routing or execution decisions (proven by
  `app_identity_is_observable_but_not_authority`). It is distinct from the signed recipe / effect
  passport that actually gate execution. Added to the trait with a default so it is opt-in.
- **No new global log authority.** Traceability is via response bodies the fixture app chooses to
  expose (e.g. `app_version`) and the test-local `ReloadableApp::identity()` accessor — no side-log.
- **Middleware untouched** (explicit guardrail). The Gemini wave's middleware/readiness is not
  implemented here; reload is the only mechanic added.
- **Effect path narrow.** `serve_once_effect_reloadable` differs from P3's `serve_once_effect` by one
  line (snapshot the app from `ReloadableApp` instead of taking `&dyn ServerApp`); it forwards to the
  same `dispatch` / `MachineEffectHost` and adds no effect semantics.

## Acceptance — met

- [x] `igniter-server cargo test` (default, machine-free): **15 tests, 0 failed** (4 protocol + 2
      reload-unit + 5 loopback + 4 reload).
- [x] `igniter-server cargo test --features machine`: **22 tests, 0 failed** (above + 7 effect).
- [x] Request 1 sees app v1; after swap, request 2 sees app v2 on the same listener
      (`reloadable_host_routes_v1_then_v2_on_same_listener`).
- [x] In-flight request keeps v1 even if the active app is swapped before it returns
      (`in_flight_request_keeps_original_app_after_swap` — a genuinely concurrent test: the app blocks
      inside `call` on a `Condvar`, the test swaps to v2 mid-flight, releases, and the response is
      still v1 while `host.identity()` is already v2).
- [x] Reloadable effect path still commits through P3 `MachineEffectHost` and performs no second
      effect on replay (`reloadable_effect_path_uses_machine_host`: v1 commits, swap to v2, same-key
      request replays, `exec.attempts() == 1`).
- [x] Host does not inspect `(method,path)` for product routing
      (`reload_does_not_create_host_route_table`: v1 routes `/a`, v2 routes `/b`, same host helper,
      routing changes only by swap).
- [x] App decision still carries no effect identity (`AppIdentity` is app identity, not effect
      identity; the P2/P3 invariant on decisions is unchanged).
- [x] No public listener, no daemon, no file watcher, no dynamic code loading, no SparkCRM, no DB/live.
- [x] Proof doc (this file) + closing report in the card.

## Exact commands + pass counts

```text
$ cd igniter-server && cargo test
  unittests src/lib.rs (protocol + reload)   6 passed; 0 failed
  tests/effect_machine_tests.rs              0 passed (feature-gated off)
  tests/loopback_tests.rs                    5 passed; 0 failed
  tests/reload_tests.rs                      4 passed; 0 failed
  TOTAL                                     15 passed; 0 failed

$ cd igniter-server && cargo test --features machine
  unittests src/lib.rs (protocol + reload)   6 passed; 0 failed
  tests/effect_machine_tests.rs              7 passed; 0 failed
  tests/loopback_tests.rs                    5 passed; 0 failed
  tests/reload_tests.rs                      4 passed; 0 failed
  TOTAL                                     22 passed; 0 failed
```

(`igniter-server` compiles warning-clean in both builds; transitive warnings come from
`igniter_compiler`/`igniter_machine`, pre-existing and unrelated.)

## Closed surfaces (held)

No public bind · no daemon · no file watcher · no dynamic code loading · no SparkCRM/live routes ·
no DB/live · no new effect semantics · no middleware · no canon claim.

## Next

- `LAB-MACHINE-IGNITER-SERVER-SERVING-LOOP-P5` — a bounded serving loop over the reloadable app
  pointer (reuse the machine's `ServingLoop` shape).
- `LAB-MACHINE-IGNITER-SERVER-MIDDLEWARE-P*` — wrapper middleware, only after the reload shape is
  settled (this card deliberately left it out).
- `LAB-MACHINE-SPARKCRM-SERVER-APP-READINESS-P1` — product-shaped app design, readiness-only until the
  local server mechanics are fully proven.
