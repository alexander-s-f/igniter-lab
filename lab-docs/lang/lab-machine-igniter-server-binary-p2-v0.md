# lab-machine-igniter-server-binary-p2-v0 — local-loopback binary over the ServerApp protocol

**Card:** `LAB-MACHINE-IGNITER-SERVER-BINARY-P2`
**Status:** CLOSED (implementation proof) — first executable proof of the Rack-like `igniter-server`
protocol. **No public listener, no daemon, no web framework, no SparkCRM, no DB/live, no
`igniter-machine` code change.**
**Authority:** Lab-only implementation proof. No canon claim. Builds on the P1 readiness decision
(`lab-machine-igniter-server-protocol-readiness-p1-v0.md`).

## What this card proves

A real loopback HTTP request flows through the protocol boundary and the **app owns routing**, the
**host owns transport only**:

```text
loopback HTTP/1.1 (127.0.0.1)
  → host parses → ServerRequest            (durable envelope; host knows no routes)
  → fixture ServerApp::call                 (routing/product meaning = a Rust match)
  → ServerDecision                          (Respond | Invoke | InvokeEffect — protocol data)
  → host executes the decision
        Respond      → response over the socket (fully executed)
        Invoke /
        InvokeEffect → 202 OBSERVED decision (execution = P3 slice)
  → ServerResponse over the socket
```

The host (`host.rs`) never inspects `(method, path)`; it has no route table. Swap the `ServerApp`
and routing changes entirely with the host unchanged — that is the whole point (test
`routing_lives_in_app_not_server_config`).

## P1 protocol delta — APPLIED (`igniter-server/src/protocol.rs`)

1. `ServerDecision::Invoke { contract, .. }` → **`Invoke { target, .. }`** (delta #1). The app names a
   logical `target`; the host maps `target → pool` (infra) and the signed recipe pins the entry
   contract.
2. Added **`ServerDecision::InvokeEffect { target, input, correlation_id, idempotency_key }`**
   (delta #2) — the named third shape for the proven wire-to-effect path.
3. **No `capability_id` / `operation` / `scope`** on any app decision (delta #3). The effect identity
   comes from the signed `ServiceRecipe` + host effect passport at execution time, never from app
   code. Asserted by `invoke_effect_round_trips_and_carries_no_effect_identity` and the loopback
   effect test (no such key in the 202 body).

`ServerRequest` / `ServerResponse` are unchanged from the seed (P1 Q1): JSON-stable `BTreeMap`
headers, `correlation_id` / `idempotency_key` promoted from headers to typed fields by the parser.

## Implementation surface (all lab-only, `igniter-server` crate)

| File | Role |
|---|---|
| `src/protocol.rs` | protocol delta + unit tests (4) |
| `src/host.rs` | std-blocking loopback HTTP/1.1 + `execute(decision)` + `serve_once` / `serve_bounded`. **No async runtime, no framework, no machine.** Holds no route table. |
| `src/fixture.rs` | `DemoApp` — routing as a plain `match` on `(method, path)`; generic names (no SparkCRM terms) |
| `src/bin/igniter-server.rs` | binds `127.0.0.1` only, serves a bounded count, then exits. No daemon. |
| `tests/loopback_tests.rs` | real loopback HTTP proofs (5) |

Dependencies stay exactly `serde` + `serde_json` (see `Cargo.toml`) — **no web framework, no tokio,
no `igniter-machine`** was added.

### Why execution of Invoke / InvokeEffect is deferred to P3

The card explicitly allows recording `Invoke`/`InvokeEffect` as **observed protocol decisions** for
P2 (acceptance: "otherwise explicitly document execution as a P3 follow-up"). Executing them through
the proven path means calling `ingress::handle_effect` / `run_write_effect_atomic`, which requires
pulling a **tokio runtime + RocksDB-backed `igniter-machine`** into this crate and standing up a
fixture pool + signed recipe + fake executor + `SingleFlight` + `EffectBridgeConfig`. That is a large
diff against the "keep the proof small, protocol-first" guardrail and edges toward DB/live. So P2
keeps execution as a faithful, observable decision (HTTP 202, body names `decision` + `target` +
`execution: deferred_to_p3` + the correlation/idempotency keys) and hands execution to
**`LAB-MACHINE-IGNITER-SERVER-EFFECT-P3`**. The protocol does not change between P2 and P3 — P3 only
swaps the `execute()` arm for `Invoke`/`InvokeEffect` from "observe" to "run via the P7 path".

When P3 wires it, the exactly-one guarantees are inherited verbatim (P1 Q9): one replica
(`select_replica`), one atomic effect (`run_write_effect_atomic`), receipt replay — because execution
will be the unchanged `ingress` contour, and the app still carries no effect identity to leak.

## Acceptance — met

- [x] `igniter-server cargo test` passes — **9 tests, 0 failed**.
- [x] Protocol JSON tests cover `Invoke { target }` and `InvokeEffect { target }` (+ the no-effect-
      identity invariant).
- [x] A real loopback HTTP request to `/health` returns `200` through `ServerApp::call`
      (`health_returns_200_through_server_app_call` + live binary run).
- [x] A fixture app route proves product routing lives in app code, not server config
      (`routing_lives_in_app_not_server_config`: the same host routes a different app differently;
      `/health` becomes 404 under another app).
- [x] `InvokeEffect` is NOT executed in P2 → execution documented as the P3 follow-up (above).
- [x] No dependency on SparkCRM, Postgres, public network, or web framework.
- [x] No `igniter-machine` semantic change (no machine code touched at all in P2).
- [x] Proof doc (this file) + closing report in the card.

## Exact commands + pass counts

```text
$ cd igniter-server && cargo test
  unittests src/lib.rs ............ 4 passed; 0 failed   (protocol delta tests)
  unittests src/bin/igniter-server 0 passed; 0 failed
  tests/loopback_tests.rs ......... 5 passed; 0 failed   (real loopback HTTP)
  Doc-tests igniter_server ........ 0 passed; 0 failed
  TOTAL: 9 passed; 0 failed
```

Live binary (loopback, bounded — serves 2 requests then exits):

```text
$ ./target/debug/igniter-server 8803 2
igniter-server listening on http://127.0.0.1:8803 (loopback, 2 request(s) then exit)

$ curl -i http://127.0.0.1:8803/health
HTTP/1.1 200 OK
content-type: application/json
{"ok":true,"service":"igniter-server"}

$ curl -i -X POST http://127.0.0.1:8803/effect/demo \
       -H 'x-correlation-id: corr-live' -H 'idempotency-key: evt-live' -d '{"event":"lead"}'
HTTP/1.1 202 Accepted
content-type: application/json
{"correlation_id":"corr-live","decision":"invoke_effect","execution":"deferred_to_p3",
 "idempotency_key":"evt-live","target":"demo-effect"}

igniter-server served 2 request(s); exiting
```

The 202 body shows the app's `InvokeEffect` decision faithfully observed (target `demo-effect`,
correlation + idempotency echoed), with no effect identity present — exactly the protocol boundary
P1 specified.

## Closed surfaces (held)

No public listener · no daemon (bounded request count is the only exit) · no route-config framework ·
no SparkCRM routes/tables/terms · no DB/live · no new effect semantics · no canon claim.

## Next

- **`LAB-MACHINE-IGNITER-SERVER-EFFECT-P3`** — execute `InvokeEffect` end-to-end through
  `igniter-machine` (the P7 `ingress::handle_effect` / `run_write_effect_atomic` path), with the
  byte-identical-vs-direct-ingress equality proof (P1 Q9). This is where the machine dep + a fixture
  pool/recipe/executor land.
- `LAB-MACHINE-IGNITER-SERVER-HOT-RELOAD-P4` — app `Arc` swap between requests (P1 Q7).
- `LAB-MACHINE-SPARKCRM-SERVER-APP-P*` — a SparkCRM-shaped app only after the server protocol is
  proven locally (gated by the human live-gate `LAB-MACHINE-SPARKCRM-LIVE-GATE-P1`).
