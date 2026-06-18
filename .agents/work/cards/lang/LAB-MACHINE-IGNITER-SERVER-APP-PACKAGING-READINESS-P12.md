# Card: LAB-MACHINE-IGNITER-SERVER-APP-PACKAGING-READINESS-P12 — external app packaging and DX

**Lane:** standard / readiness-design
**Skill:** idd-agent-protocol
**Status:** CLOSED (readiness packet)
**Date opened:** 2026-06-18
**Date closed:** 2026-06-18
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

---

## Closing report — 2026-06-18

**Outcome:** Readiness packet delivered, answering all 10 question groups, grounded in the live
standalone `igniter-server` layout + public API (verified `serve_loop`, `ReloadableApp::new`,
`ServerAppExt`, `MachineEffectHost`/`serve_loop_effect`; Cargo auto-discovers the P2 bin + P10 example).
Design only — no code, no new crate, no runner binary, no live/deploy.

**Deliverable:** `lab-docs/lang/lab-machine-igniter-server-app-packaging-readiness-p12-v0.md`.

**Recommended v0 packaging model:** a **library crate exporting `build_app(config) -> Arc<dyn ServerApp
+ Send + Sync>`** (which composes P8 middleware explicitly) + an optional **thin binary runner** that
owns the `TcpListener` + `ServingPolicy` + `ReloadableApp` (+ machine/effect bindings under feature
`machine`). The library is the unit of reuse; the binary holds no product logic. First shown as an
example (no new crate); graduate to a sibling crate when a real second consumer exists.

**Config / authority split:** app = routing/normalization/logical targets; host = listener, loop
policy, machine target→route bindings, secrets/passports; middleware = token/body-limit/tracing labels.
Effect authority stays host/recipe-owned — the app crate embeds no `capability_id`/`operation`/`scope`/
passport/secret. The same app crate runs machine-free or machine-backed with zero app change.

**Identity:** `AppIdentity` is observation only; P8 middleware currently delegates `identity()`
unchanged (digest decoration = optional future). `ReloadableApp` wraps the outer composed stack
(atomic swap).

**Testing contract:** mandatory direct `call` + middleware-composition tests; recommended loopback
smoke; optional machine-feature tests with fake executor only.

**Next route:** one bounded slice — `LAB-MACHINE-IGNITER-SERVER-APP-RUNNER-EXAMPLE-P13`: a second
example (`examples/server_app_runner.rs`, no new crate) demonstrating `build_app` + thin runner
(`ReloadableApp` + bounded `serve_loop`) + loopback smoke + a `swap` reload test. Separate sample crate
deferred. No live/SparkCRM/deploy.

**Acceptance:** all boxes met — 10 groups answered; clear v0 recommendation; server-core/domain-app
boundary preserved; app/host/middleware config + effect authority separated; packaged-app testing
contract defined; no release/live/deploy claims; no code; no new crate/example created; no
public-listener/DB/credentials/vendor-API.
