# lab-machine-igniter-server-effect-p3-v0 — execute InvokeEffect through the machine contour

**Card:** `LAB-MACHINE-IGNITER-SERVER-EFFECT-P3`
**Status:** CLOSED (implementation proof) — the server protocol's `ServerDecision::InvokeEffect`,
decided by a fixture `ServerApp`, now executes end-to-end through the **existing** `igniter-machine`
wire-to-effect path. **No public listener, no daemon, no SparkCRM, no DB/live, no web framework, and
zero `igniter-machine` code changes.**
**Authority:** Lab-only. No canon claim. Builds on P1 readiness + P2 protocol/loopback.

## What this card proves

P2 left `InvokeEffect` as an observed `202 deferred_to_p3`. P3 closes that gap with an **adapter, not
a new effect runner**:

```text
real loopback HTTP POST (127.0.0.1)
  → ServerRequest                                    (host parses; host knows no routes)
  → fixture ServerApp::call                          (routing/product meaning = a Rust match)
  → ServerDecision::InvokeEffect { target, input, correlation_id, idempotency_key }
  → MachineEffectHost maps target → machine ingress route   (INFRA binding, not a product route table)
  → IngressRouter::handle_effect                     (the EXISTING P7/P10/P11 contour, unchanged)
       → duplicate policy → ONE replica (select_replica) → capsule intent
       → run_write_effect_atomic (one SingleFlight) → receipt
  → ServerResponse over the socket
```

The exactly-one guarantees are **inherited verbatim** because execution *is* `handle_effect`; the
adapter adds no effect semantics and the app decision still carries no effect identity.

## Authority split held (P1)

| Authority | Owner | Where |
|---|---|---|
| routing / classification (`(method,path) → InvokeEffect{target}`) | **app** | `fixture::DemoApp::call` |
| `target → machine route/pool`, transport, single-flight | **host** | `MachineEffectHost.target_routes` (infra binding only) |
| `capsule_digest` / `entry_contract` / duplicate policy / effect identity | **signed recipe + host effect passport** | `ServiceRecipe`, `EffectBridgeConfig.effect_passport` |

The app decision never carries `capability_id` / `operation` / `scope` — proven by the P2 protocol
test and structurally (the adapter reads the effect identity from `EffectBridgeConfig`, never from the
decision).

## Implementation surface (all lab-only, `igniter-server` crate)

| File | Role |
|---|---|
| `src/effect_host.rs` (**`#[cfg(feature = "machine")]`**) | `MachineEffectHost` adapter (`target → route`, builds the `IngressRequest`, forwards to `handle_effect`, normalizes `IngressResponse → ServerResponse`) + async `serve_once_effect` (real loopback, routes through `ServerApp` then the machine) + `dispatch` (reuses `host::execute` for `Respond`/`Invoke`) |
| `src/host.rs` | factored `parse_request` / `encode_response` / `find_subslice` / `content_length` / `status_text` to `pub(crate)` so the sync loopback and the async machine path share one wire format. No behavior change. |
| `tests/effect_machine_tests.rs` (**`#![cfg(feature = "machine")]`**) | 6 machine-contour tests (fixture mirrors `service_wire_effect_tests`, neutral `CAP = "IO.Demo"`) |
| `src/protocol.rs`, `src/fixture.rs`, `src/bin/igniter-server.rs` | unchanged from P2 — stay machine-free |

### Dependency boundary (the chosen feature gate)

`igniter-server` adds `igniter_machine` + `tokio` as **optional** deps behind a single `machine`
feature (`Cargo.toml`). The default build is **protocol-only and machine-free** (deps: `serde`,
`serde_json`): `protocol.rs`, `host.rs`, `fixture.rs`, and the loopback binary never touch the kernel,
so protocol consumers don't pull the machine + a tokio runtime. Only `--features machine` compiles
`effect_host.rs` and the effect tests. `igniter_machine`'s own `default = []` (fake-only, DB-free),
so even the gated build pulls no Postgres/TLS.

### Why execution reuses `handle_effect` rather than re-implementing it

`IngressRouter::handle_effect` already performs the entire contour: passport verification → route →
recipe → duplicate policy (`decide_duplicate`) → `select_replica` (one replica) → capsule activation
→ `run_write_effect_atomic` (one effect per `duplicate_key:attempt`, guarded by a host `SingleFlight`)
→ receipt + audit. The adapter's only job is to construct the `IngressRequest` the proven path expects
from `(ServerRequest, decision)` and map the result back. That is the whole point of P3: re-shape WHO
decides routing without re-shaping HOW an effect runs.

## Acceptance — met

- [x] `igniter-server cargo test` passes (default, machine-free): **9 tests, 0 failed**.
- [x] `igniter-server cargo test --features machine` passes: **15 tests, 0 failed** (4 protocol + 6
      effect + 5 loopback).
- [x] Relevant `igniter-machine` regression tests still pass under the canonical command
      (`cargo test --no-default-features`): `service_wire_effect_tests` 5, `serving_loop_concurrency_tests`
      5, `service_bridge_replica_tests` 6 — **16, 0 failed**. (No machine code was changed.)
- [x] A real loopback HTTP request through `igniter-server` executes `InvokeEffect` and returns a
      committed `200` with a receipt-backed body (`server_invoke_effect_commits_via_machine_contour`).
- [x] Duplicate replay through the server path performs no second effect
      (`server_invoke_effect_replay_no_second_effect`: `exec.attempts() == 1`).
- [x] Bounded-fresh duplicate policy through the server path creates distinct effect idempotency keys
      by `attempt_index`, matching direct ingress (`...bounded_fresh_attempts_match_ingress`:
      receipts `IO.Demo:E1:0` … `IO.Demo:E1:2`).
- [x] Same-key concurrent requests through the server path collapse via the existing `SingleFlight`;
      no double effect (`server_concurrent_same_key_exactly_one_effect`: 4 concurrent → `attempts == 1`).
- [x] The app decision carries no effect identity (P2 protocol test + structural).
- [x] The host does not inspect `(method,path)` for product routing; only `ServerApp` does
      (`server_routing_still_lives_in_app`: a different app routes `/effect/record` → 404 with no
      effect, and its own `/different-effect` → committed, on the unchanged host).
- [x] Server-mediated path equals direct ingress, normalized (`server_path_matches_direct_ingress_
      normalized`: identical status **and** body vs a hand-built `handle_effect` call on an identical
      fixture).
- [x] No public listener, no daemon, no SparkCRM live, no DB/live, no web framework.
- [x] Proof doc (this file) + closing report in the card.

### Concurrency proof location

`server_concurrent_same_key_exactly_one_effect` drives four concurrent `InvokeEffect` dispatches at
the adapter level (sharing the host's one `SingleFlight` via `EffectBridgeConfig`). The socket is a
thin transport; dedup/atomicity live in `handle_effect` → `run_write_effect_atomic`, exactly as the
machine's own `serving_loop_concurrency_tests::concurrent_same_key_exactly_one_effect` proves. The
server path inherits the guarantee unchanged.

## Exact commands + pass counts

```text
$ cd igniter-server && cargo test
  unittests src/lib.rs (protocol)     4 passed; 0 failed
  tests/effect_machine_tests.rs       0 passed (feature-gated off)
  tests/loopback_tests.rs             5 passed; 0 failed
  TOTAL                               9 passed; 0 failed

$ cd igniter-server && cargo test --features machine
  unittests src/lib.rs (protocol)     4 passed; 0 failed
  tests/effect_machine_tests.rs       6 passed; 0 failed
  tests/loopback_tests.rs             5 passed; 0 failed
  TOTAL                              15 passed; 0 failed

$ cd igniter-machine && cargo test --no-default-features \
    --test service_wire_effect_tests --test serving_loop_concurrency_tests --test service_bridge_replica_tests
  service_bridge_replica_tests        6 passed; 0 failed
  service_wire_effect_tests           5 passed; 0 failed
  serving_loop_concurrency_tests      5 passed; 0 failed
  TOTAL                              16 passed; 0 failed
```

Live committed effect over a real loopback socket (from
`server_invoke_effect_commits_via_machine_contour`): `POST /effect/record` with
`Authorization: Bearer vtok`, `X-Vendor-Event-Id: E1` → `200` `{"status":"committed", ...}`,
`exec.attempts() == 1`. (The canonical live proof is this integration test rather than a CLI binary,
because a machine-backed binary would have to embed the whole fixture pool/recipe/executor — out of
scope for a small proof. The P2 binary stays machine-free.)

## Closed surfaces (held)

No public bind · no daemon · no SparkCRM business routes/tables/terms (neutral `IO.Demo`) · no real
Postgres/TLS/vendor network · no new effect semantics · no autonomous retry/compensation beyond the
existing orchestrator · no canon claim.

## Next

- `LAB-MACHINE-IGNITER-SERVER-HOT-RELOAD-P4` — app `Arc` swap between requests (P1 Q7), now that the
  effect path is real.
- `LAB-MACHINE-IGNITER-SERVER-SERVING-LOOP-P5` — reuse the machine's `ServingLoop` shape for bounded
  concurrent server-mediated serving.
- `LAB-MACHINE-SPARKCRM-SERVER-APP-P*` — a SparkCRM-shaped app only after this local proof + the
  existing human live-gate packet.
