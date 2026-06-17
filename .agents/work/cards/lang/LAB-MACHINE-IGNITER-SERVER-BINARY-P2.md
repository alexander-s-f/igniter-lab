# Card: LAB-MACHINE-IGNITER-SERVER-BINARY-P2 — local loopback binary over ServerApp protocol

**Lane:** standard / implementation proof · **Skill:** idd-agent-protocol
**Status:** OPEN
**Date opened:** 2026-06-17
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
