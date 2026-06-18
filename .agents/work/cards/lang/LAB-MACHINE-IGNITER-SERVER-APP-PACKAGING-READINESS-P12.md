# Card: LAB-MACHINE-IGNITER-SERVER-APP-PACKAGING-READINESS-P12 — external app packaging and DX

**Lane:** standard / readiness-design
**Skill:** idd-agent-protocol
**Status:** OPEN
**Date opened:** 2026-06-18
**Authority:** Lab-only design/readiness. No packaging implementation. No release authority.

## Why this card exists

P10 proved the smallest external `ServerApp` as a Cargo example. That teaches the trait, but a real
third-party developer eventually needs to know how to package an app: example, separate crate,
application binary, reloadable stack, config boundary, tests, and optional machine host wiring.

This card designs the **developer DX / packaging shape** before creating any new crate or framework.

## Read first

- `igniter-server/README.md`
- `igniter-server/Cargo.toml`
- `igniter-server/examples/server_app_basic.rs`
- `igniter-server/src/protocol.rs`
- `igniter-server/src/reload.rs`
- `igniter-server/src/serving_loop.rs`
- `igniter-server/src/middleware.rs`
- `igniter-server/src/effect_host.rs`
- `lab-docs/lang/lab-machine-igniter-server-example-app-p10-v0.md`
- `lab-docs/lang/lab-machine-igniter-server-extensions-readiness-p7-v0.md`

## Goal

Write a readiness packet for how an external app should be packaged and run:

- standalone Cargo example vs separate crate vs binary runner;
- where app code, config, middleware composition, and host wiring live;
- how reload identity works for packaged apps;
- what tests a developer should write;
- what `igniter-server` core must **not** know.

No implementation in this card.

## Required questions

1. **Packaging levels.** Compare:
   - `examples/server_app_basic.rs` teaching example;
   - separate app crate depending on `igniter_server`;
   - app binary embedding server host;
   - workspace/sibling crate in lab.

2. **Minimum app package contents.**
   - `App` struct implementing `ServerApp`;
   - optional middleware stack builder;
   - optional `main` runner;
   - tests for `call` decisions;
   - no server route config.

3. **Config boundary.**
   - What config belongs to app (routes/targets/normalization)?
   - What config belongs to host (listener, loop policy, machine target bindings, secrets/passports)?
   - What config belongs to middleware (token/body limit/tracing labels)?

4. **Effect host boundary.**
   - App emits logical `InvokeEffect target` only.
   - Host maps target to `MachineEffectHost` route and `EffectBridgeConfig`.
   - App package must not embed `capability_id`, `operation`, `scope`, passport, or secret.

5. **Reload and identity.**
   - How should a packaged app expose `AppIdentity`?
   - How should composed middleware affect identity/digest?
   - Observation only vs authority.

6. **Testing contract.**
   - Which tests are mandatory for a packaged app?
   - direct `call` tests;
   - middleware composition tests;
   - loopback smoke;
   - optional machine-feature host tests with fake executor only.

7. **Distribution forms.**
   - Library crate exporting `build_app()`?
   - Binary crate with `main()`?
   - Both?
   - What is v0 recommendation?

8. **Developer ergonomics.**
   - What should docs/examples show?
   - What helper APIs might be useful later?
   - What should stay explicit to avoid magic framework drift?

9. **Security/live gate.**
   - Public listener, secrets, DB, vendor APIs, dynamic plugins remain gated.
   - Packaging readiness does not imply deploy readiness.

10. **Next card recommendation.**
    - Name one bounded implementation slice if justified, e.g. a `server_app_basic` packaging guide,
      a sample app crate, or a runner example.
    - Avoid opening live/SparkCRM.

## Deliverable

Readiness packet:

`lab-docs/lang/lab-machine-igniter-server-app-packaging-readiness-p12-v0.md`

Closing report in this card with:

- recommended v0 packaging model;
- config/authority split;
- next route.

## Acceptance

- [ ] Packet answers all 10 required question groups.
- [ ] Packet gives a clear v0 packaging recommendation.
- [ ] Packet preserves server core/domain app boundary.
- [ ] Packet separates app config, host config, middleware config, and effect authority.
- [ ] Packet defines a packaged-app testing contract.
- [ ] Packet avoids release/live/deployment claims.
- [ ] No code changes.
- [ ] No new crate or example created.
- [ ] No public listener, DB, credentials, vendor API.

## Closed surfaces

- No implementation.
- No new crate.
- No runner binary.
- No release packaging.
- No dynamic plugin loading.
- No live network/public listener.
- No DB/credentials/vendor API.
- No SparkCRM-specific packaging.
- No canon claim.

## Suggested conclusion shape

Likely v0:

```text
app crate exports build_app(config) -> Arc<dyn ServerApp + Send + Sync>
  -> binary runner owns listener + ServingPolicy + ReloadableApp
  -> host owns machine/effect bindings and secrets
  -> app owns routing/normalization/logical targets
  -> middleware is composed explicitly at the edge
```

Verify against live crate layout before finalizing.
