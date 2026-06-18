# lab-machine-igniter-server-app-packaging-readiness-p12-v0 — external app packaging & DX

**Card:** `LAB-MACHINE-IGNITER-SERVER-APP-PACKAGING-READINESS-P12`
**Status:** READINESS / DESIGN (v0, recommended) — how a third-party developer should package and run
an external `ServerApp`. **Design only. No packaging implementation, no new crate, no runner binary, no
release/deploy, no live/public/DB/credentials/vendor API, no canon claim.**
**Authority:** Lab-only. Grounded in the live `igniter-server` crate layout + public API.

---

## 0. Live surface (verified)

- `igniter_server` crate: deps `serde`/`serde_json`; `igniter_machine`+`tokio` **optional** behind
  feature `machine`; `default = []`. Cargo auto-discovers `src/bin/igniter-server.rs` (the P2 loopback
  binary, fixture `DemoApp`) and `examples/server_app_basic.rs` (P10).
- Public modules: `protocol`, `host`, `reload`, `serving_loop`, `middleware`, `fixture`; `effect_host`
  (feature `machine`).
- Key signatures:
  - `ReloadableApp::new(Arc<dyn ServerApp + Send + Sync>)` · `current()` · `swap()` · `identity()`;
  - `serving_loop::serve_loop(&TcpListener, &ReloadableApp, &ServingPolicy) -> io::Result<ServingReport>`;
    `ServingPolicy::new(max)` / `.loopback_only()`;
  - `host::serve_once` / `serve_bounded` / `serve_once_reloadable` / `serve_bounded_reloadable` (sync,
    machine-free);
  - `ServerAppExt::{with_trace, with_auth(token), with_body_limit(n)}`;
  - `effect_host` (machine): `MachineEffectHost::new(router,hub,cfg)` + `bind_target(target,route)`;
    `EffectBridgeConfig`; `serve_loop_effect(&listener,&ReloadableApp,&MachineEffectHost,&policy)`.

The suggested conclusion (`build_app(config) -> Arc<dyn ServerApp + Send + Sync>` + a thin runner that
owns listener/policy/reload, host owns effect bindings) holds against this surface.

---

## 1. Packaging levels (Q1)

| Level | Shape | When |
|---|---|---|
| **Teaching example** (`examples/server_app_basic.rs`, P10) | one file, `ExampleApp` + `main` demo | learning the trait; the "hello world". Already exists. |
| **Library app crate** depending on `igniter_server` | exports `build_app(config) -> Arc<dyn ServerApp + Send + Sync>` (+ tests) | **the reusable unit** — testable, composable, embeddable by any runner. **v0 recommended packaging.** |
| **App binary** embedding the host | a thin `main()` owning `TcpListener` + `ServingPolicy` + `ReloadableApp` (+ machine wiring under feature) calling `build_app` | when the app must actually run a process. A *thin* runner over the library crate, not where logic lives. |
| **Workspace/sibling crate in lab** | the library crate placed beside `igniter-server` | the natural home once a real app graduates from example → crate; deferred until a second consumer exists (`igniter-server` is standalone today, no workspace). |

Recommendation: **library crate exporting `build_app` is the unit of reuse; an optional thin binary is
the runner.** Start by demonstrating the pattern as an example (no new crate), graduate to a sibling
crate when a real app needs it.

---

## 2. Minimum app package contents (Q2)

- a `struct App` + `impl ServerApp for App` (routing = a `match (method,path)` inside `call`;
  `identity()`);
- a `build_app(config) -> Arc<dyn ServerApp + Send + Sync>` that constructs the app and **composes
  middleware explicitly** (`App.with_trace().with_auth(cfg.token).with_body_limit(cfg.max)`), returning
  the boxed outer stack;
- optional thin `main()` runner (own listener + `ServingPolicy` + `ReloadableApp::new(build_app(cfg))`
  + `serve_loop`);
- tests for `call` decisions (direct + middleware composition + loopback smoke);
- **no server route config**, no listener config baked into the app, no machine internals.

---

## 3. Config boundary (Q3)

| Config | Owner | Examples |
|---|---|---|
| routing, request classification, normalization, **logical effect targets** | **app** | `(method,path)` match; `target = "ticket-create"`; input shaping |
| listener address, `ServingPolicy` (max_requests/loopback_only), reload cadence, **machine target→route bindings**, secrets/passports | **host / runner** | `TcpListener::bind(127.0.0.1:0)`; `MachineEffectHost::bind_target`; `EffectBridgeConfig.effect_passport` |
| token / body-limit / tracing labels | **middleware (composed at the edge)** | `with_auth(token)`, `with_body_limit(n)` |

The split is the whole DX lesson: **app config is product meaning; host config is infrastructure;
middleware config is cross-cutting policy.** None of them leak into the others.

---

## 4. Effect host boundary (Q4)

The app package emits only a **logical** `ServerDecision::InvokeEffect { target, input,
correlation_id, idempotency_key }`. The **host/runner** (under feature `machine`) maps `target → route`
on a `MachineEffectHost` and supplies `EffectBridgeConfig` (which carries `capability_id`/`operation`/
`scope` + the host effect passport). The app package must **never** embed `capability_id`,
`operation`, `scope`, a passport, or a secret — structurally impossible through `ServerDecision`, and
the packaging guidance must keep it that way. The same app crate runs **machine-free** (decisions
observed) or **machine-backed** (host wires the bridge) with **zero app change** — that portability is
the point.

---

## 5. Reload & identity (Q5)

- A packaged app exposes `AppIdentity { name, version, digest }` via `identity()` — `name`/`version`
  describe the package; `digest` is app-supplied/opaque (no mandated algorithm).
- **Composed middleware:** today the P8 wrappers **delegate** `identity()` to the inner app unchanged
  (verified in `middleware.rs`). Decorating the digest with active middleware config (token
  fingerprint, body limit) so a stack reconfiguration shows a different digest is a **possible future
  enhancement**, not required for v0.
- Identity is **observation only** (operator/test visibility), never an authority input — auth lives in
  the host passport / signed recipe. The runner holds the stack in `ReloadableApp` and may
  `swap(build_app(new_cfg))` between requests; `ReloadableApp` wraps the **outer composed stack** so a
  swap replaces middleware+app atomically (P4/P7 rule).

---

## 6. Testing contract (Q6)

A packaged app SHOULD ship:
- **mandatory:** direct `call` decision tests (routes → `Respond`/`Invoke`/`InvokeEffect` shapes;
  keyless/unknown handling; no `capability_id`/`operation`/`scope` in serialized decisions);
- **mandatory:** middleware composition tests (e.g. `with_auth` short-circuit, `with_trace` decoration)
  — proving the packaged stack behaves;
- **recommended:** a loopback smoke test via `host::serve_once` (or `serve_loop` for a bounded run);
- **optional (feature `machine`):** host tests with a **fake** executor + in-memory backend only
  (mirror the P3/P6/P10 fixtures) — never a live executor/DB/network.

This is exactly the shape `tests/example_app_tests.rs` (P10) already demonstrates; a packaged app
generalizes it.

---

## 7. Distribution forms (Q7)

**v0 recommendation: a library crate exporting `build_app(config) -> Arc<dyn ServerApp + Send + Sync>`,
plus an optional thin binary runner.** Rationale:
- the **library** is the testable, reusable, composable unit (any runner — loopback, bounded loop,
  future async host — embeds it);
- the **binary** is a thin `main()` that owns transport + policy + reload + (optional) machine wiring;
- "both," but the library is primary; the binary must hold **no** product logic.

For the very first step this can be shown as an **example** (no new crate); a separate crate is the
graduation once a real/second consumer exists.

---

## 8. Developer ergonomics (Q8)

- **Docs/examples should show:** the `match`-in-`call` routing; `build_app` composing middleware
  explicitly; a runner owning listener + `ServingPolicy` + `ReloadableApp`; the machine wiring as a
  **separate, optional** host step.
- **Helpers that may be useful later:** the `ServerAppExt` builder already exists
  (`with_trace/with_auth/with_body_limit`); a future `build_app(config)` convention + a tiny
  `run(app, addr, policy)` runner helper could reduce boilerplate.
- **Stay explicit (avoid framework drift):** no hidden auto-routing, no config-file-driven route table,
  no implicit global app/registry, no magic middleware ordering. The stack is built in plain Rust and
  visible at the call site.

---

## 9. Security / live gate (Q9)

Packaging readiness does **not** imply deploy readiness. Gated (human/separate): public (non-loopback)
listener; real secrets/credentials; real DB; vendor APIs; dynamic plugin loading. A packaged app and
its runner are lab/loopback only until a live gate is cleared; the recommended `build_app` + thin-runner
shape changes nothing about that boundary.

---

## 10. Next card (Q10)

**One bounded slice:** `LAB-MACHINE-IGNITER-SERVER-APP-RUNNER-EXAMPLE-P13` — a second **example**
(`examples/server_app_runner.rs`, no new crate) demonstrating the recommended packaging pattern:
`build_app(config) -> Arc<dyn ServerApp + Send + Sync>` (composing P8 middleware) → a thin runner that
owns a loopback `TcpListener` + `ServingPolicy` + `ReloadableApp` + bounded `serve_loop`, with a
loopback smoke test and a `swap(build_app(new_cfg))` reload test. Machine wiring referenced as the
optional feature-gated step, not implemented. **No new crate, no live IO, no SparkCRM.** The
separate-crate graduation (`igniter-server-sample-app`) is named as a *later* optional route, opened
only when a real second consumer exists.

---

## Boundary recap

- v0 packaging: **library `build_app(config) -> Arc<dyn ServerApp + Send + Sync>`** (composes
  middleware) + a **thin binary runner** (owns listener/`ServingPolicy`/`ReloadableApp`); host owns
  machine/effect bindings + secrets; app owns routing/normalization/logical targets.
- Config split: app = product meaning; host = infrastructure; middleware = cross-cutting policy.
- Effect authority stays host/recipe-owned; the app crate embeds no effect identity/secret.
- Testing contract: direct `call` + middleware + loopback smoke (+ optional machine/fake-executor).
- Next = one example runner card (`RUNNER-EXAMPLE-P13`); separate crate deferred; no live/deploy.

*Readiness/design only. Compiled 2026-06-18. Verified against the live standalone `igniter-server` crate.*
