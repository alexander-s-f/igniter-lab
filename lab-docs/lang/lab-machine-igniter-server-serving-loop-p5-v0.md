# lab-machine-igniter-server-serving-loop-p5-v0 — bounded serving loop over ReloadableApp

**Card:** `LAB-MACHINE-IGNITER-SERVER-SERVING-LOOP-P5`
**Status:** CLOSED (implementation proof) — a bounded serving loop that runs a fixed `max_requests`
budget over a pre-bound listener + `ReloadableApp`, then returns. **A loop, not a daemon.** No public
bind, no background thread, no `tokio::spawn`, no file watcher, no middleware, no SparkCRM/live, no
`igniter-machine` code change.
**Authority:** Lab-only. No canon claim. Builds on P2 protocol, P3 effect contour, P4 hot reload.

## What this card proves

```text
caller binds 127.0.0.1:0  ──►  serve_loop(&listener, &reloadable_app, &policy)
                                  while served < policy.max_requests:
                                    accept                              (the loop binds NOTHING)
                                    current = app.current()             (snapshot AFTER accept = pinning)
                                    serve current  →  ServerResponse
                                  return ServingReport                  (observation-only counters)
```

The loop is the host owning transport + cadence; the app owns the decision. It composes the proven
pieces: `ReloadableApp::current` (P4) + `host::serve_once_reloadable_observed` (P4/P2 serve) — and,
under `machine`, `effect_host::serve_once_effect_reloadable_observed` → the P3 `MachineEffectHost`
contour.

## The safety invariant (per the card's correction)

The card asked NOT to bolt on a public-listener guard that turns the loop into deployment policy. The
stronger, structural invariant implemented here is: **the serving loop opens no address.** Both
`serve_loop` and `serve_loop_effect` take a `&TcpListener` the caller already bound and only ever call
`accept()` — there is no `bind` anywhere in the loop. That is what makes it impossible for the loop to
become a deployment mechanism.

An *opt-in* `ServingPolicy::loopback_only()` is offered as a lab convenience: when set, the loop
refuses a non-loopback listener BEFORE accepting. It is **OFF by default** (no imposed policy), and the
check is a narrow pure function `enforce_loopback(addr, flag)` — unit-tested with a fabricated
`0.0.0.0` `SocketAddr` so refusal is proven **without ever binding a public address** (which would
itself violate a closed surface).

## Implementation surface (all lab-only, `igniter-server`)

| File | Change |
|---|---|
| `src/serving_loop.rs` (**new, machine-free**) | `ServingPolicy { max_requests, loopback_only }`, `ServingReport { requests_served, app_versions_seen, bound_addr, is_loopback }`, `serve_loop`, pure `enforce_loopback`; 1 unit test |
| `src/host.rs` | added `serve_once_reloadable_observed` (snapshot after accept, returns the served app's `AppIdentity`); `serve_once_reloadable` now delegates to it — P4 signature/semantics unchanged |
| `src/effect_host.rs` (`machine`) | added `serve_once_effect_reloadable_observed` + `serve_loop_effect` (async bounded loop over the P3 contour, reuses `ServingPolicy`/`ServingReport`/`enforce_loopback`) |
| `tests/serving_loop_tests.rs` (**new, machine-free**) | 5 loop tests |
| `tests/effect_machine_tests.rs` | +1 effect-loop test |

### Design decisions (narrow, per card)

- **Sequential bounded loop, no concurrency primitives.** No `tokio::spawn`, no `FuturesUnordered`, no
  detached task — so there is nothing to leak and nothing to join-or-orphan. The loop returns when the
  budget is hit; a `JoinHandle` test proves it actually returns.
- **No orchestrator boot/tick in this slice.** The readiness sketched orchestrator ticks; that would
  pull `EffectOrchestrator` and a richer cadence. P5 stays narrow — per-request effects already run
  through P3. Ticks/recovery cadence is left to a future slice (named in Next).
- **Report is observation-only.** `app_versions_seen` records the snapshotted app identity version per
  request — the swap-visibility proof. It is not a ledger; receipts/WAL remain the only authority.
- **Std-only default path.** `serve_loop` uses `std::net` (machine-free); the effect loop is the only
  thing behind the `machine` feature.

## Acceptance — met

- [x] `igniter-server cargo test` (default): **21 tests, 0 failed** (7 unit + 5 loopback + 4 reload +
      5 serving_loop).
- [x] `igniter-server cargo test --features machine`: **29 tests, 0 failed** (above + 8 effect).
- [x] Loop serves exactly N requests and returns (`loop_serves_exactly_n_then_returns`: 3 requests,
      `JoinHandle::join` succeeds → not a daemon).
- [x] Request 1 sees v1; swap; later request sees v2 in the same loop/listener
      (`loop_swaps_app_between_requests`: `app_versions_seen == ["v1","v2"]`).
- [x] In-flight/request snapshot semantics preserved (`loop_preserves_in_flight_snapshot_during_swap`:
      gated app blocks in `call`, swap to v2 mid-flight, response still v1, report records v1).
- [x] No route table in the loop (`loop_has_no_route_table`: v1 routes `/a`, v2 routes `/b`; routing
      changes only by swap).
- [x] No effect identity in app decision (unchanged P2/P3 invariant; `AppIdentity` is app identity).
- [x] Machine path: replay performs no second effect via the P3 contour
      (`loop_effect_path_replay_no_second_effect`: loop serves 2 same-key requests, `attempts == 1`).
- [x] No public listener / no daemon / no middleware / no SparkCRM / no DB-live / no deployment policy.
- [x] Proof doc (this file) + closing report in the card.

## Exact commands + pass counts

```text
$ cd igniter-server && cargo test
  unittests src/lib.rs (protocol+reload+serving_loop)  7 passed; 0 failed
  tests/effect_machine_tests.rs                        0 passed (feature-gated off)
  tests/loopback_tests.rs                              5 passed; 0 failed
  tests/reload_tests.rs                                4 passed; 0 failed
  tests/serving_loop_tests.rs                          5 passed; 0 failed
  TOTAL                                               21 passed; 0 failed

$ cd igniter-server && cargo test --features machine
  unittests src/lib.rs                                 7 passed; 0 failed
  tests/effect_machine_tests.rs                        8 passed; 0 failed
  tests/loopback_tests.rs                              5 passed; 0 failed
  tests/reload_tests.rs                                4 passed; 0 failed
  tests/serving_loop_tests.rs                          5 passed; 0 failed
  TOTAL                                               29 passed; 0 failed
```

(`igniter-server` compiles warning-clean in both builds; transitive warnings are pre-existing in
`igniter_compiler`/`igniter_machine`.)

## Closed surfaces (held)

No public listener (the loop binds nothing; caller passes a loopback listener) · no daemon (bounded,
returns) · no `tokio::spawn`/detached task · no file watcher · no middleware · no SparkCRM/live · no
DB/live credentials · no deployment/systemd/supervisor policy · no canon claim.

## Next

- `LAB-MACHINE-IGNITER-SERVER-SERVING-LOOP-CADENCE-P*` — optional orchestrator boot/tick cadence
  (recovery + retry drain) over the loop, if a narrow card justifies pulling `EffectOrchestrator`.
- `LAB-MACHINE-IGNITER-SERVER-MIDDLEWARE-P*` — wrapper middleware, only after the loop shape settles.
- `LAB-MACHINE-SPARKCRM-SERVER-APP-READINESS-P1` — product-shaped app design, readiness-only until the
  local server mechanics are fully proven.
