# Card: LAB-MACHINE-IGNITER-SERVER-EXAMPLE-APP-P10 — first external ServerApp example

**Lane:** standard / implementation
**Skill:** idd-agent-protocol
**Status:** CLOSED (implementation)
**Date opened:** 2026-06-18
**Date closed:** 2026-06-18
**Authority:** Lab implementation in `igniter-server` examples/tests only. No domain module in core.

## Why this card exists

P6 moved domain apps out of `igniter-server` core. P7 defined the extension model. P9 decided the
first discoverable example shape. Now implement the smallest teaching artifact:

```text
external app code -> impl ServerApp -> host observes Respond / InvokeEffect
```

The example must teach the boundary: apps live outside core, routing is inside `ServerApp::call`, and
effect authority stays host-side.

## Read first

- `lab-docs/lang/lab-machine-igniter-server-example-app-readiness-p9-v0.md`
- `igniter-server/src/protocol.rs`
- `igniter-server/src/host.rs`
- `igniter-server/src/middleware.rs`
- `igniter-server/src/reload.rs`
- `igniter-server/README.md`

## Goal

Create a machine-free Cargo example:

- `igniter-server/examples/server_app_basic.rs`
- `igniter-server/tests/example_app_tests.rs`

The example domain is neutral **ticket-intake**:

- `GET /health` -> `Respond(200)`;
- `POST /tickets` with `idempotency-key` -> `InvokeEffect { target: "ticket-create", ... }`;
- keyless `POST /tickets` -> `Respond(400)`;
- anything else -> `Respond(404)`.

## Implementation requirements

1. `examples/server_app_basic.rs`
   - define `pub struct ExampleApp`;
   - `impl ServerApp for ExampleApp`;
   - `identity()` returns something like `ticket-intake-example`, `v0`, opaque digest string;
   - `call` uses a small `match (method, path)`;
   - `main()` is machine-free and demonstrable (prints sample decisions or runs a small bounded
     loopback if the existing host API makes that simple).

2. `tests/example_app_tests.rs`
   - include the example via `#[path = "../examples/server_app_basic.rs"] mod example_app;` or a better
     live-compatible route;
   - verify the routes and decision shapes below.

3. Optional README pointer
   - only if useful for discoverability;
   - do not rewrite the server architecture section.

## Required tests

Prove:

1. `GET /health` returns `Respond` status 200.
2. `POST /tickets` with `idempotency-key` returns `InvokeEffect` with:
   - `target == "ticket-create"`;
   - `idempotency_key == Some(<header value>)`;
   - explicit/sensible `correlation_id` propagation if present;
   - sanitized JSON input.
3. Keyless `POST /tickets` returns `Respond` status 400; no silent fresh effect.
4. Unknown route returns 404.
5. Serialized decision contains **no** `capability_id`, `operation`, or `scope`.
6. `identity().name == "ticket-intake-example"` (or the chosen equivalent).
7. The example composes with middleware from P8 (at least one small test: `with_trace` or `with_auth`).
8. Optional: one loopback host round-trip for `/health` if small and stable.

Run:

```bash
cd igniter-server && cargo build --examples
cd igniter-server && cargo run --example server_app_basic
cd igniter-server && cargo test
cd igniter-server && cargo test --features machine
```

## Deliverable

- `igniter-server/examples/server_app_basic.rs`
- `igniter-server/tests/example_app_tests.rs`
- proof doc: `lab-docs/lang/lab-machine-igniter-server-example-app-p10-v0.md`
- closing report in this card
- README pointer if useful

## Acceptance

- [ ] Example app lives under `examples/`, not `src/`.
- [ ] No `pub mod` domain module added to core.
- [ ] Example compiles with default features; no `igniter-machine` dependency required.
- [ ] Tests prove route behavior and effect decision shape.
- [ ] Tests prove no privileged effect identity fields.
- [ ] Example composes with P8 middleware.
- [ ] `cargo build --examples` green.
- [ ] `cargo run --example server_app_basic` succeeds.
- [ ] `cargo test` green.
- [ ] `cargo test --features machine` green.
- [ ] Proof doc and closing report written.

## Closed surfaces

- No domain module in `igniter-server/src`.
- No server route table.
- No machine bridge implementation.
- No live network/public listener.
- No DB.
- No credentials.
- No SparkCRM/vendor-specific vocabulary.
- No dynamic plugin system.
- No assets protocol.
- No canon claim.

## Guardrail

This is a teaching artifact, not a product app. If the implementation starts needing a framework,
configuration format, real effect host, or domain ontology, stop and split the work.

---

## Closing report — 2026-06-18

**Outcome:** First discoverable external `ServerApp` implemented as a standalone Cargo example +
verifying test. Teaches the boundary: app lives in `examples/` (not `src/`), routing inside
`ServerApp::call`, effects as logical `InvokeEffect { target, … }`, effect authority host-side.
Machine-free; no `src/` domain module; no `igniter-machine` change; warning-clean.

**Deliverable:** `lab-docs/lang/lab-machine-igniter-server-example-app-p10-v0.md`.

**Files created:**
- `igniter-server/examples/server_app_basic.rs` — `pub struct ExampleApp` + `impl ServerApp` (neutral
  `ticket-intake`: `GET /health`→Respond 200; `POST /tickets` w/ idempotency-key→`InvokeEffect{target:
  "ticket-create"}`; keyless→400; else 404), `identity()` = `ticket-intake-example`/`v0`, sanitizing
  `normalize_ticket`, machine-free `main()` printing decisions + a P8-middleware demo.
- `igniter-server/tests/example_app_tests.rs` — includes the example via `#[path]`; 8 tests.
- `igniter-server/README.md` — one-line pointer to the runnable example (no architecture rewrite).

**Exact commands + pass counts:**
```text
$ cargo build --examples                     → Finished (warning-clean)
$ cargo run --example server_app_basic       → prints health/tickets/keyless/unknown + middleware demo, exit 0
$ cargo test                                 → 42 passed; 0 failed   (was 34; +8)
$ cargo test --features machine              → 55 passed; 0 failed   (was 47; +8)
```

**Tests:** health→Respond 200; POST /tickets w/ key→InvokeEffect (target `ticket-create`,
idempotency_key `Some("tkt-1001")`, correlation propagated, sanitized input); keyless→400; unknown→404;
serialized decision has no `capability_id`/`operation`/`scope`; `identity().name`; composes with P8
middleware (`with_trace().with_auth(...)` → 401 short-circuit / 200 + x-correlation-id); real loopback
`host::serve_once` `/health`→200.

**Acceptance:** all boxes met. Guardrail honored — no framework/config-format/real-effect-host/domain
ontology introduced.
