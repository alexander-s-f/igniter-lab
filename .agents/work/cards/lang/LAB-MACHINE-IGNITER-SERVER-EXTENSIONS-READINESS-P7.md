# Card: LAB-MACHINE-IGNITER-SERVER-EXTENSIONS-READINESS-P7 — extension model for domain apps

**Lane:** standard / readiness-design
**Skill:** idd-agent-protocol
**Status:** CLOSED (readiness packet)
**Date opened:** 2026-06-18
**Date closed:** 2026-06-18
**Authority:** Lab-only design/readiness. No implementation. No plugin framework authority.

## Why this card exists

P6 moved the SparkCRM-shaped app out of `igniter-server` core. That fixed the immediate boundary
smell, but it also exposed the durable design question:

```text
How should third-party/domain apps extend or specialize igniter-server
without hard-wiring domains into the base crate?
```

Future users may build SparkCRM apps, notification hubs, operator consoles, VoIP UIs, asset-serving
apps, or their own private domains. `igniter-server` must stay server substrate (protocol, wire,
reload, serving loop, optional machine bridge), while app-specific behavior lives outside core and
implements the stable protocol.

## Read first

- `igniter-server/README.md`
- `igniter-server/src/protocol.rs`
- `igniter-server/src/reload.rs`
- `igniter-server/src/serving_loop.rs`
- `igniter-server/src/effect_host.rs`
- `igniter-server/tests/fixtures/sparkcrm_app.rs`
- `lab-docs/lang/lab-machine-igniter-server-app-boundary-p6-v0.md`
- `lab-docs/lang/lab-machine-igniter-server-app-stack-composition-v0.md`
- `lab-docs/lang/lab-machine-igniter-server-middleware-shape-v0.md`

## Goal

Write a readiness packet that defines the v0 extension model for `igniter-server`:

- how domain apps are packaged;
- how they implement `ServerApp`;
- how middleware/wrappers compose;
- how optional machine/effect host pieces are supplied;
- how future assets could fit without turning server core into a framework;
- what remains forbidden in the base crate.

This card is **design only**. Do not implement a plugin system yet.

## Required questions

1. **Core boundary.**
   - What exactly belongs in `igniter-server` core?
   - What must remain outside core?
   - How does P6 constrain future domain examples?

2. **Static app packages.**
   - What is the recommended v0 shape for a Rust domain app?
   - Options to compare:
     - separate crate depending on `igniter_server`;
     - workspace example crate;
     - test fixture;
     - feature-gated module in core (likely forbidden except generic adapters).

3. **Dynamic plugins.**
   - Should v0 support dynamic loading?
   - If not, explain why: safety, ABI, authority, deployment complexity.
   - Name what would be required before dynamic plugins become legitimate.

4. **Middleware composition.**
   - How do wrapper middlewares fit with `ReloadableApp`?
   - Confirm the composition rule:
     `ReloadableApp` wraps the **entire composed stack**, not just the inner app.
   - Keep middleware route-agnostic; no product route tables.

5. **Machine/effect integration.**
   - How should apps request effects without receiving effect authority?
   - Re-state: app emits `ServerDecision::InvokeEffect { target, input, idempotency_key }`;
     host supplies target binding + `MachineEffectHost` + `EffectBridgeConfig`.
   - Do not let extensions inject `capability_id`, `operation`, or `scope`.

6. **Assets and non-API apps.**
   - Sketch how future assets might appear without implementing them now.
   - Compare:
     - app returns `Respond` with static bytes/JSON manifest;
     - future `AssetManifest` trait;
     - external static asset server.
   - State what is explicitly deferred.

7. **Versioning and identity.**
   - How should `AppIdentity { name, version, digest }` work for composed stacks and third-party apps?
   - What is observation only vs authority?
   - Avoid mandating a hash algorithm.

8. **Distribution / developer DX.**
   - What does a third-party developer need to implement at minimum?
   - What helpers/examples should exist later?
   - What should not be required (SparkCRM knowledge, machine internals, route config framework)?

9. **Security and live gate.**
   - What extension points can be used in lab/local only?
   - What requires human gate before live: public listener, credentials, real DB, vendor API, dynamic code.

10. **Recommended next cards.**
    - One implementation card max, if justified.
    - Prefer small slices:
      - examples crate / example app;
      - middleware wrappers;
      - static app package proof;
      - asset readiness.
    - Do not propose live SparkCRM as next work.

## Deliverable

Readiness packet:

`lab-docs/lang/lab-machine-igniter-server-extensions-readiness-p7-v0.md`

Closing report in this card with:

- what extension model is recommended for v0;
- what is explicitly rejected/deferred;
- next 1-3 cards.

## Acceptance

- [ ] Packet answers all 10 required question groups.
- [ ] Packet keeps `igniter-server` core domain-free.
- [ ] Packet distinguishes static app crates/examples from dynamic plugins.
- [ ] Packet preserves app/middleware/host authority split.
- [ ] Packet covers future assets without implementing them.
- [ ] Packet names what is forbidden in core.
- [ ] Packet proposes bounded next cards, no live work.
- [ ] No code changes.
- [ ] No new crates unless only mentioned as future route.

## Closed surfaces

- No code.
- No plugin system implementation.
- No dynamic loading.
- No middleware implementation.
- No assets protocol implementation.
- No SparkCRM live/staging.
- No public listener.
- No credentials.
- No DB/network.
- No canon claim.

## Suggested conclusion shape

Recommended v0 should probably be:

```text
static Rust app crates/examples implement ServerApp
  -> optional wrapper middlewares compose into one stack
  -> ReloadableApp owns the outer composed stack
  -> host supplies effect/machine bindings
  -> dynamic plugins/assets remain future readiness slices
```

But verify this against live code before finalizing.

---

## Closing report — 2026-06-18

**Outcome:** Readiness packet delivered, answering all 10 question groups, grounded in the live P2–P6
surface (trait shapes re-verified in `protocol.rs`/`reload.rs`/`serving_loop.rs`/`effect_host.rs`).
Design only — no code, no plugin system, no middleware, no assets protocol, no new crate.

**Deliverable:** `lab-docs/lang/lab-machine-igniter-server-extensions-readiness-p7-v0.md`.

**Recommended v0 extension model (confirmed against live code):** static Rust apps implement
`ServerApp` (separate crate / workspace example / test fixture — never a `pub mod` of core) → optional
zero-cost wrapper middleware (Approach 1) composes into ONE stack → `ReloadableApp` wraps the **outer
composed stack** (so a swap is atomic and an in-flight request runs middleware+core under one revision)
→ host supplies `target` bindings + `MachineEffectHost` + `EffectBridgeConfig` (effect authority stays
host/recipe-owned; the app emits only logical `target` + canonical `idempotency_key`).

**Explicitly rejected / deferred:** dynamic plugin loading (ABI/authority/determinism — needs C-ABI or
wasm sandbox + capability restriction + signing + human gate first); an assets protocol in core (an app
returns `Respond` with bytes/manifest instead); feature-gated domain modules in core; any app/
middleware injection of `capability_id`/`operation`/`scope`; route tables in middleware; live
SparkCRM/DB/public listener.

**Forbidden in core (named):** product domains/vocabulary, route tables, effect-identity injection,
hidden mutable state, exposing host internals, duplicating host transport concerns.

**Next 1–3 cards:** (1) `LAB-MACHINE-IGNITER-SERVER-MIDDLEWARE-P8` — the single justified
implementation slice (Tracing/Auth/BodyLimit wrapper middleware + composition/short-circuit/in-flight
tests). (2) `LAB-MACHINE-IGNITER-SERVER-EXAMPLE-APP-P*` — a discoverable workspace example app
(readiness/small). (3) `LAB-MACHINE-IGNITER-SERVER-ASSETS-READINESS-P*` — assets, only if a real need
appears. No live work proposed.

**Acceptance:** all boxes met — packet answers all 10 groups; keeps core domain-free; distinguishes
static app crates/examples from dynamic plugins; preserves the app/middleware/host authority split;
covers future assets without implementing them; names what's forbidden in core; proposes bounded next
cards with no live work; no code changes; no new crates (only named as future routes).
