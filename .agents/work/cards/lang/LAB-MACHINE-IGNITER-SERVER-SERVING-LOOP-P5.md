# Card: LAB-MACHINE-IGNITER-SERVER-SERVING-LOOP-P5 — bounded serving loop over ReloadableApp

**Lane:** standard / implementation proof · **Skill:** idd-agent-protocol
**Status:** CLOSED (implementation proof)
**Date opened:** 2026-06-18
**Date closed:** 2026-06-18
**Authority:** Lab-only implementation proof. No public listener. No daemon. No SparkCRM/live.

## Why this card exists

P1–P4 closed: protocol (P2), machine effect execution (P3), safe app hot reload (P4). P5 adds the
process-shaped piece: a **bounded serving loop** over the reloadable app pointer — the host owning
transport + cadence — that serves a fixed budget and returns, without becoming a background daemon or
acquiring product-routing knowledge.

Readiness: `lab-docs/lang/lab-machine-igniter-server-serving-loop-readiness-p5-v0.md`
(`igniter-machine/src/serving_loop.rs` consulted as pattern only, not copied).

## Required shape

- bounded loop: `max_requests`, then return; no background daemon; no `tokio::spawn`/detached task.
- the loop itself opens no address — accepts a pre-bound listener (stronger than a public-bind guard).
- per-request app snapshot via `ReloadableApp`; host does not inspect `(method,path)`.
- observation-only report (`requests_served`, app identities seen).
- default path machine-free over `serve_once_reloadable`; machine path optional + narrow over
  `serve_once_effect_reloadable` / `MachineEffectHost`.

## Acceptance

- [x] `cargo test` + `cargo test --features machine` pass.
- [x] loop serves exactly N requests and returns.
- [x] request 1 sees v1; swap; later request sees v2 in the same loop/listener.
- [x] in-flight/request snapshot semantics from P4 preserved.
- [x] no route table in the loop.
- [x] no effect identity in app decision.
- [x] machine path: replay no second effect via the P3 contour.
- [x] proof doc + closing report with exact pass counts.

## Closed surfaces

No public listener · no daemon · no middleware · no SparkCRM/live · no DB/live credentials · no
deployment/systemd/supervisor · no language canon.

---

## Closing report — 2026-06-18

**Outcome:** A bounded serving loop implemented and proven. `serve_loop(&listener, &reloadable_app,
&policy)` runs a fixed `max_requests` budget over a CALLER-bound loopback listener, snapshots the
active app per request (request-start pinning), and returns a `ServingReport`. A loop, not a daemon.
All guardrails held: the loop binds nothing, uses no `tokio::spawn`/detached task, no file watcher, no
middleware, no SparkCRM/live, **zero `igniter-machine` code changes**.

**Deliverable:** `lab-docs/lang/lab-machine-igniter-server-serving-loop-p5-v0.md`.

**Safety invariant (card correction honored):** the strong property is "the loop opens no address" —
`serve_loop` / `serve_loop_effect` only ever `accept()` a pre-bound listener; there is no `bind` in the
loop. The opt-in `ServingPolicy::loopback_only()` guard is OFF by default (no deployment policy) and is
a narrow pure function `enforce_loopback(addr, flag)` unit-tested with a fabricated `0.0.0.0` address —
refusal proven WITHOUT binding any public address.

**Implementation (lab-only, `igniter-server`):**
- `src/serving_loop.rs` (new, machine-free) — `ServingPolicy`, `ServingReport`, `serve_loop`, pure
  `enforce_loopback`.
- `src/host.rs` — `serve_once_reloadable_observed` (snapshot after accept → returns served identity);
  `serve_once_reloadable` delegates to it (P4 unchanged).
- `src/effect_host.rs` (`machine`) — `serve_once_effect_reloadable_observed` + async `serve_loop_effect`
  over the P3 contour, reusing `ServingPolicy`/`ServingReport`.
- `tests/serving_loop_tests.rs` (new) 5 tests + `tests/effect_machine_tests.rs` +1 effect-loop test.

**Exact commands + pass counts:**

```text
$ cd igniter-server && cargo test                    → 21 passed; 0 failed (7 unit + 5 loopback + 4 reload + 5 serving_loop; effect gated off)
$ cd igniter-server && cargo test --features machine → 29 passed; 0 failed (above + 8 effect)
```
`igniter-server` warning-clean in both builds (transitive warnings pre-existing in
`igniter_compiler`/`igniter_machine`).

**Key tests:** `loop_serves_exactly_n_then_returns` (JoinHandle returns → not a daemon);
`loop_swaps_app_between_requests` (`app_versions_seen == ["v1","v2"]`);
`loop_preserves_in_flight_snapshot_during_swap` (gated app, swap mid-flight, response still v1);
`loop_has_no_route_table`; `loopback_guard_is_a_narrow_pure_check` (unit, no bind) +
`loop_loopback_only_opt_in_serves_on_127`; `loop_effect_path_replay_no_second_effect`
(`attempts == 1`).

**Acceptance:** all boxes met. Orchestrator boot/tick cadence and middleware deliberately left out;
named as future routes in the deliverable doc.
