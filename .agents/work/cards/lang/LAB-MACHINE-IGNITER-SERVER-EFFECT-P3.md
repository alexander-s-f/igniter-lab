# Card: LAB-MACHINE-IGNITER-SERVER-EFFECT-P3 — execute InvokeEffect through machine contour

**Lane:** standard / implementation proof · **Skill:** idd-agent-protocol
**Status:** CLOSED (implementation proof)
**Date opened:** 2026-06-18
**Date closed:** 2026-06-18
**Authority:** Lab-only local proof. No public listener. No SparkCRM-specific app. No live DB/network.

## Why this card exists

P1 decided the Rack-like server protocol: app owns routing/product meaning, server owns transport
and host execution. P2 proved the loopback wire and protocol boundary, but intentionally left
`ServerDecision::InvokeEffect` as an observed `202 deferred_to_p3` decision.

P3 closes that gap: `InvokeEffect` must execute through the **existing** `igniter-machine`
wire-to-effect contour:

```text
HTTP request
  -> ServerRequest
  -> ServerApp::call                         (routing lives in app)
  -> ServerDecision::InvokeEffect { target, input, correlation_id, idempotency_key }
  -> server host maps target -> existing machine ingress route
  -> ingress::handle_effect / serve_once_effect
  -> duplicate policy -> one replica -> capsule intent
  -> run_write_effect_atomic -> receipt
  -> ServerResponse
```

This is not a new effect runner. It is an adapter from the server protocol to the already proven
machine path.

## Read first

- `igniter-server/README.md`
- `igniter-server/src/protocol.rs`
- `igniter-server/src/host.rs`
- `igniter-server/src/fixture.rs`
- `lab-docs/lang/lab-machine-igniter-server-binary-p2-v0.md`
- `igniter-machine/src/ingress.rs`
- `igniter-machine/src/serving_loop.rs`
- `igniter-machine/tests/service_wire_effect_tests.rs`
- `igniter-machine/tests/service_bridge_replica_tests.rs`
- `igniter-machine/tests/serving_loop_concurrency_tests.rs`

## Goal

Execute one `ServerDecision::InvokeEffect` end-to-end through `igniter-machine` using a local
fixture app and fake/local executor, with the same safety invariants as direct `ingress`:

- one selected replica, never fanout;
- one atomic effect per effect idempotency key;
- duplicate policy still controls `attempt_index`;
- receipts/audit produced by the existing capability-IO substrate;
- routing remains in `ServerApp`, not server config.

## Required shape

1. **Keep P2 protocol stable.**
   - Do not change `ServerRequest`, `ServerResponse`, or `ServerDecision` JSON shape unless a test
     proves the P2 shape was impossible.
   - `InvokeEffect` still carries only `target`, `input`, `correlation_id`, `idempotency_key`.
   - Do **not** add `capability_id`, `operation`, or `scope` to app decisions.

2. **Add a host adapter, not a bespoke runner.**
   - Suggested shape: an `EffectHost` / `MachineEffectHost` adapter in `igniter-server` that maps
     `target -> machine route` and calls existing `igniter-machine` APIs.
   - Preferred execution surface: `IngressRouter::handle_effect` or `serve_once_effect` with
     `EffectBridgeConfig`.
   - Reuse `SingleFlight` and `run_write_effect_atomic` only through the existing machine contour.

3. **Keep routing authority in the app.**
   - `ServerApp` decides that a request means `InvokeEffect { target: ... }`.
   - The server may hold infra binding `target -> machine route/pool/effect config`; it must not
     hold product route table `(method,path) -> business action`.
   - Add a test proving the same host with a different `ServerApp` changes routing without host
     changes.

4. **Use local fixture machine state.**
   - Build a fixture `CoordinationHub`, production pool, signed/accepted recipe, vendor token,
     duplicate policy, fake executor, and receipts store inside tests.
   - No SparkCRM names, no real Postgres, no external network.
   - If adding an `igniter-machine` dependency to `igniter-server`, keep it feature-gated if that
     avoids pulling the machine into protocol-only builds. Document the chosen boundary.

5. **Prove equality with the direct machine path.**
   - For the same fixture request, direct `ingress::handle_effect` and server-mediated
     `ServerApp -> InvokeEffect -> host adapter` must produce equivalent status/body and the same
     effect receipt semantics.
   - Exact byte equality is ideal; if transport wrappers differ, document and test the normalized
     equivalence.

## Acceptance

- [ ] `igniter-server cargo test` passes.
- [ ] Relevant `igniter-machine` regression tests still pass under the canonical command for this
      tree.
- [ ] A real loopback HTTP request through `igniter-server` executes `InvokeEffect` and returns
      committed `200` with a receipt-backed response.
- [ ] Duplicate replay through the server path performs **no second effect**.
- [ ] Bounded-fresh duplicate policy through the server path creates distinct effect idempotency
      keys by `attempt_index`, matching direct `ingress` behavior.
- [ ] Same-key concurrent requests through the server path collapse through the existing
      `SingleFlight`/receipt path; no double effect.
- [ ] The app decision still carries no effect identity (`capability_id`/`operation`/`scope` absent).
- [ ] The server host does not inspect `(method,path)` for product routing; only `ServerApp` does.
- [ ] No public listener, no daemon, no SparkCRM live, no DB/live credentials, no web framework.
- [ ] Proof doc written:
      `lab-docs/lang/lab-machine-igniter-server-effect-p3-v0.md`.
- [ ] Closing report added to this card with exact commands and pass counts.

## Closed surfaces

- No public bind.
- No long-running production daemon.
- No SparkCRM business routes or live endpoint.
- No real Postgres/TLS/vendor network.
- No new effect semantics.
- No language canon claim.
- No autonomous compensation/retry policy beyond existing machine orchestrator semantics.

## Suggested tests

- `server_invoke_effect_commits_via_machine_contour`
- `server_invoke_effect_replay_no_second_effect`
- `server_invoke_effect_bounded_fresh_attempts_match_ingress`
- `server_path_matches_direct_ingress_normalized`
- `server_routing_still_lives_in_app`
- `server_concurrent_same_key_exactly_one_effect`

## Next routes

- `LAB-MACHINE-IGNITER-SERVER-HOT-RELOAD-P4` — app `Arc` swap between requests, after the effect path
  is real.
- `LAB-MACHINE-IGNITER-SERVER-SERVING-LOOP-P5` — reuse existing `ServingLoop` shape from
  `igniter-machine` only after P3 proves server-mediated execution.
- `LAB-MACHINE-SPARKCRM-SERVER-APP-P*` — SparkCRM-shaped app only after local server effect proof and
  the existing live-gate packet.

---

## Closing report — 2026-06-18

**Outcome:** `ServerDecision::InvokeEffect`, decided by a fixture `ServerApp`, now executes end-to-end
through the EXISTING `igniter-machine` wire-to-effect contour (`IngressRouter::handle_effect` →
`select_replica` → `run_write_effect_atomic`). An adapter, not a new runner. All guardrails held: no
public listener, no daemon, no SparkCRM, no DB/live, no web framework, **zero `igniter-machine` code
changes**.

**Deliverable:** `lab-docs/lang/lab-machine-igniter-server-effect-p3-v0.md`.

**Implementation (lab-only, `igniter-server`):**
- `src/effect_host.rs` (`#[cfg(feature = "machine")]`) — `MachineEffectHost` adapter (`target → machine
  route` infra binding, builds the `IngressRequest`, forwards to `handle_effect`, normalizes the
  result) + async `serve_once_effect` (real loopback → `ServerApp::call` → machine) + `dispatch`
  (reuses `host::execute` for `Respond`/`Invoke`, which stays observed).
- `src/host.rs` — factored pure wire helpers to `pub(crate)` so sync + async paths share one format;
  no behavior change.
- `tests/effect_machine_tests.rs` (`#![cfg(feature = "machine")]`) — 6 tests, fixture mirrors
  `service_wire_effect_tests`, neutral `CAP = "IO.Demo"`.
- `Cargo.toml` — `igniter_machine` + `tokio` are OPTIONAL deps behind a single `machine` feature.
  **Default build stays protocol-only / machine-free (serde only).** Documented boundary.

**Authority split (P1) held:** routing → app; `target → pool` + transport + single-flight → host;
effect identity (`capability_id`/`operation`/`scope`) → signed recipe + host effect passport, never in
the app decision.

**Exact commands + pass counts:**

```text
$ cd igniter-server && cargo test                      → 9 passed; 0 failed  (4 protocol + 5 loopback; effect gated off)
$ cd igniter-server && cargo test --features machine   → 15 passed; 0 failed (4 protocol + 6 effect + 5 loopback)
$ cd igniter-machine && cargo test --no-default-features \
    --test service_wire_effect_tests --test serving_loop_concurrency_tests --test service_bridge_replica_tests
                                                        → 16 passed; 0 failed (5 + 5 + 6) — regression intact
```

**Tests (effect, `--features machine`):**
`server_invoke_effect_commits_via_machine_contour` (real socket → committed 200, attempts==1),
`server_invoke_effect_replay_no_second_effect` (dedup_strict → attempts==1),
`server_invoke_effect_bounded_fresh_attempts_match_ingress` (distinct keys IO.Demo:E1:0..2),
`server_path_matches_direct_ingress_normalized` (status + body equal vs hand-built `handle_effect`),
`server_routing_still_lives_in_app` (different app → 404 no effect; own route → committed; host
unchanged), `server_concurrent_same_key_exactly_one_effect` (4 concurrent same-key → attempts==1 via
shared `SingleFlight`).

**Acceptance:** all boxes met (see deliverable doc).
