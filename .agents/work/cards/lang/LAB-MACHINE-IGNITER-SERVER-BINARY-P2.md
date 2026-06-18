# Card: LAB-MACHINE-IGNITER-SERVER-BINARY-P2 — local loopback binary over ServerApp protocol

**Lane:** standard / implementation proof · **Skill:** idd-agent-protocol
**Status:** CLOSED (implementation proof)
**Date opened:** 2026-06-17
**Date closed:** 2026-06-17
**Authority:** Lab-only implementation proof. No public listener. No SparkCRM-specific code. No DB/live.

## Why this card exists

P1 settled the shape: `igniter-server` should be a Rack-like protocol host, not a
config-driven route table. The server owns transport/runtime infrastructure; the app owns
routing/product meaning.

P2 is the first executable proof of that shape:

```text
loopback HTTP request
  -> ServerRequest
  -> fixture ServerApp::call
  -> ServerDecision
  -> host executes the decision
  -> ServerResponse over the socket
```

This must prove the protocol boundary without opening SparkCRM, Postgres writes, a public listener,
or a route-config framework.

## Read first

- `igniter-server/README.md`
- `igniter-server/src/protocol.rs`
- `lab-docs/lang/lab-machine-igniter-server-protocol-readiness-p1-v0.md`
- `.agents/work/cards/lang/LAB-MACHINE-IGNITER-SERVER-PROTOCOL-READINESS-P1.md`
- `igniter-machine/src/ingress.rs`
- `igniter-machine/src/serving_loop.rs`
- `LAB-MACHINE-POSTGRES-WIRE-ATOMIC-P7.md`
- `LAB-MACHINE-POSTGRES-LOCAL-WRITE-P8.md`

## Goal

Implement a minimal local loopback `igniter-server` binary that proves a `ServerApp` fixture can
drive responses through the protocol. Keep the proof small and protocol-first.

## Required shape

1. **Apply P1 protocol delta.**
   - Rename `ServerDecision::Invoke { contract, ... }` to `Invoke { target, ... }`.
   - Add `ServerDecision::InvokeEffect { target, input, correlation_id, idempotency_key }`.
   - Do **not** add `capability_id`, `operation`, or `scope` to app decisions.
2. **Add local-only binary.**
   - Suggested binary: `igniter-server/src/bin/igniter-server.rs`.
   - Bind only `127.0.0.1:0` in tests.
   - Serve exactly one request or a bounded number of requests; no daemon.
3. **Fixture app, no framework.**
   - Implement a tiny `ServerApp` with a direct `match` on `(method, path)`.
   - `/health` returns `Respond(200)`.
   - One fixture action returns `Invoke` or `InvokeEffect` as protocol data.
4. **Host execution proof.**
   - For P2, it is acceptable to execute `Respond` fully and record `Invoke`/`InvokeEffect` as
     observable protocol decisions, OR wire one local fixture through the existing machine path if
     the diff stays small.
   - If using `InvokeEffect`, it must go through the existing P7 atomic wire path, not a bespoke
     effect runner.
5. **No route table authority.**
   - The binary may hold infra bindings (`target -> pool`) only if execution needs them.
   - Product route meaning must come from the fixture `ServerApp`, not server config.

## Acceptance

- [ ] `igniter-server cargo test` passes.
- [ ] Protocol JSON tests cover `Invoke { target }` and `InvokeEffect { target }`.
- [ ] A real loopback HTTP request to `/health` returns `200` through `ServerApp::call`.
- [ ] A fixture app route proves product routing lives in app code (not server config).
- [ ] If `InvokeEffect` is executed, prove it uses existing `ingress`/P7 path and exactly-one
      semantics; otherwise explicitly document execution as a P3 follow-up.
- [ ] No dependency on SparkCRM, Postgres, public network, or web framework.
- [ ] No change to `igniter-machine` semantics unless needed for a narrow adapter; prefer no machine
      code changes in P2.
- [ ] Proof doc written:
      `lab-docs/lang/lab-machine-igniter-server-binary-p2-v0.md`.
- [ ] Closing report added to this card with exact commands and pass counts.

## Closed surfaces

- No public listener.
- No long-running daemon.
- No route-config framework.
- No SparkCRM routes/tables/business terms.
- No DB/live credentials.
- No new effect semantics.
- No language canon claim.

## Next routes

- `LAB-MACHINE-IGNITER-SERVER-EFFECT-P3` — execute `InvokeEffect` end-to-end through
  `igniter-machine` if P2 keeps it as observed protocol data.
- `LAB-MACHINE-IGNITER-SERVER-HOT-RELOAD-P4` — app `Arc` swap between requests.
- `LAB-MACHINE-SPARKCRM-SERVER-APP-P*` — SparkCRM-shaped app only after the server protocol is
  proven locally.

---

## Closing report — 2026-06-17

**Outcome:** First executable proof of the Rack-like `igniter-server` protocol. A real loopback HTTP
request flows `wire → ServerRequest → ServerApp::call → ServerDecision → host execute → ServerResponse`,
and routing provably lives in the app, not server config. All guardrails held: no public listener, no
daemon, no web framework, no SparkCRM, no DB/live, **zero `igniter-machine` code changes**. Crate deps
stayed exactly `serde` + `serde_json`.

**Deliverable:** `lab-docs/lang/lab-machine-igniter-server-binary-p2-v0.md`.

**P1 delta applied (`src/protocol.rs`):** (1) `Invoke{contract}` → `Invoke{target}`; (2) added
`InvokeEffect{target,input,correlation_id,idempotency_key}`; (3) no `capability_id`/`operation`/`scope`
on any app decision (asserted by tests).

**Implementation (lab-only):**
- `src/host.rs` — std-blocking loopback HTTP/1.1, `execute(decision)`, `serve_once`/`serve_bounded`.
  No async runtime, no framework, no machine; **holds no route table** (never inspects method/path).
- `src/fixture.rs` — `DemoApp`, routing as a plain `match` (generic names, no SparkCRM terms).
- `src/bin/igniter-server.rs` — binds `127.0.0.1` only, bounded request count, then exits (no daemon).
- `tests/loopback_tests.rs` — 5 real loopback HTTP proofs.

**Execution decision:** `Invoke`/`InvokeEffect` are recorded as OBSERVED protocol decisions (HTTP 202,
body names `decision`+`target`+`execution:deferred_to_p3`+corr/idem). End-to-end execution through the
P7 `ingress::handle_effect` / `run_write_effect_atomic` path is deferred to
`LAB-MACHINE-IGNITER-SERVER-EFFECT-P3` — wiring it would pull tokio + RocksDB-backed `igniter-machine`
into this crate (large diff, against "keep small / protocol-first", edges toward DB/live). The protocol
does not change between P2 and P3; P3 only swaps the `execute()` arm from observe → run.

**Exact commands + pass counts:**

```text
$ cd igniter-server && cargo test
  unittests src/lib.rs (protocol)     4 passed; 0 failed
  unittests src/bin/igniter-server    0 passed; 0 failed
  tests/loopback_tests.rs             5 passed; 0 failed
  Doc-tests igniter_server            0 passed; 0 failed
  TOTAL                               9 passed; 0 failed
```

Live binary (loopback, bounded — 2 requests then exits):
```text
$ ./target/debug/igniter-server 8803 2
$ curl -i http://127.0.0.1:8803/health        → HTTP/1.1 200 OK  {"ok":true,"service":"igniter-server"}
$ curl -i -X POST .../effect/demo -H 'x-correlation-id: corr-live' -H 'idempotency-key: evt-live' -d '{"event":"lead"}'
   → HTTP/1.1 202 Accepted
     {"correlation_id":"corr-live","decision":"invoke_effect","execution":"deferred_to_p3",
      "idempotency_key":"evt-live","target":"demo-effect"}
   igniter-server served 2 request(s); exiting
```

**Acceptance:** all boxes met (see deliverable doc). `InvokeEffect` not executed → documented as P3
follow-up, as the card permits.
