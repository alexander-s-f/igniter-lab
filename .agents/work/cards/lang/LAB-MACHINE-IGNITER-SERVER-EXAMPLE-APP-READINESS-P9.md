# Card: LAB-MACHINE-IGNITER-SERVER-EXAMPLE-APP-READINESS-P9 — first external ServerApp example shape

**Lane:** standard / readiness-design
**Skill:** idd-agent-protocol
**Status:** OPEN
**Date opened:** 2026-06-18
**Authority:** Lab-only design/readiness. No implementation unless a later card opens it.

## Why this card exists

P6 moved domain apps out of `igniter-server` core. P7 defined the extension model: static Rust apps
implement `ServerApp`; core stays generic. The next DX question is what a **discoverable external app**
should look like so future users do not learn the wrong lesson from test fixtures.

This card designs the first example-app shape. It must stay separate from P8 middleware implementation.

## Read first

- `igniter-server/README.md`
- `igniter-server/src/protocol.rs`
- `igniter-server/src/fixture.rs`
- `igniter-server/tests/fixtures/sparkcrm_app.rs`
- `lab-docs/lang/lab-machine-igniter-server-extensions-readiness-p7-v0.md`
- `lab-docs/lang/lab-machine-igniter-server-app-boundary-p6-v0.md`
- `lab-docs/lang/lab-machine-igniter-server-app-stack-composition-v0.md`

## Goal

Write a readiness packet for a first **external** `ServerApp` example that demonstrates:

- app code lives outside `igniter-server` core;
- routing belongs inside the app's `ServerApp::call`, not server config;
- effects are requested as logical `InvokeEffect { target, input, idempotency_key }` decisions;
- host wiring supplies the effect authority later;
- the example is generic enough for third-party developers and not SparkCRM-specific.

## Required questions

1. **Where should the example live?**
   - `igniter-server/examples/...` binary?
   - sibling crate under `igniter-lab`?
   - test fixture only?
   - Explain recommended v0 and why.

2. **What should the example domain be?**
   - Must be neutral: avoid SparkCRM/vendor/VoIP/operator domain vocabulary.
   - Candidate: `echo-workflow`, `ticket-intake`, or `demo-counter`.
   - Pick a domain that proves routing + effect target without teaching product ontology.

3. **What is the minimum app code?**
   - `struct ExampleApp`;
   - `impl ServerApp for ExampleApp`;
   - `identity()`;
   - a small `match (method, path)` inside the app.

4. **What effect shape should it emit?**
   - Use logical `target`, sanitized JSON input, explicit `correlation_id`, explicit `idempotency_key`.
   - No `capability_id`, `operation`, `scope`, passport, secret, or DB handle in app code.

5. **How does it run without machine?**
   - Should work through P2 `host` as `Respond`/observed `InvokeEffect` if machine feature is off.
   - Do not require `igniter-machine` for the example's basic compile/test.

6. **How does it connect to machine later?**
   - Host-side binding only; app unchanged.
   - Reference P3/P5/P6 shapes but do not implement them.

7. **How does hot reload/middleware compose?**
   - Example app should be composable under P4/P8 wrappers.
   - Do not require middleware in this card.

8. **What files should a future implementation card create?**
   - Name exact candidate paths, but do not create them.
   - Include expected tests and command list.

9. **What must remain forbidden?**
   - No domain module in `src/lib.rs`.
   - No route table in server core.
   - No live network, DB, credentials, SparkCRM, public listener.

10. **Next card recommendation.**
    - If ready, name one bounded implementation card for the example app.

## Deliverable

Readiness packet:

`lab-docs/lang/lab-machine-igniter-server-example-app-readiness-p9-v0.md`

Closing report in this card with:

- recommended location and app shape;
- rejected locations/domains;
- one implementation-card proposal.

## Acceptance

- [ ] Packet answers all 10 required question groups.
- [ ] Packet keeps the example outside `igniter-server` core.
- [ ] Packet avoids SparkCRM/vendor/product-specific vocabulary.
- [ ] Packet explains machine-free run and later host-machine bridge separately.
- [ ] Packet names exact future files/tests without creating them.
- [ ] No code changes.
- [ ] No new crate or example created.
- [ ] No live/network/DB/credential work.

## Closed surfaces

- No implementation.
- No example crate creation.
- No middleware implementation.
- No machine bridge implementation.
- No SparkCRM/live/staging.
- No public listener.
- No DB/network/credentials.
- No canon claim.

## Suggested conclusion shape

The likely answer is:

```text
examples/server_app_basic/ (or equivalent) as a standalone Cargo example
  -> neutral ExampleApp implements ServerApp
  -> server core stays unchanged
  -> machine integration remains host-side and optional
```

But verify against the live crate layout before finalizing.
