# Card: LAB-MACHINE-IGNITER-SERVER-APP-RUNNER-EXAMPLE-P13 - build_app + thin runner example

**Lane:** standard / implementation
**Skill:** idd-agent-protocol
**Status:** CLOSED (implementation)
**Date opened:** 2026-06-18
**Date closed:** 2026-06-18
**Authority:** Lab implementation in `igniter-server` examples/tests only. No new crate, no live/deploy.

## Why this card exists

P12 defined the v0 packaging model:

```text
app exports build_app(config) -> Arc<dyn ServerApp + Send + Sync>
  -> thin runner owns listener + ServingPolicy + ReloadableApp
  -> host owns effect bindings/secrets later
```

P10 taught the raw `ServerApp` trait. P13 teaches the next layer: **how a packaged app is built and
run** without creating a new crate or a framework.

## Read first

- `lab-docs/lang/lab-machine-igniter-server-app-packaging-readiness-p12-v0.md`
- `igniter-server/examples/server_app_basic.rs`
- `igniter-server/src/protocol.rs`
- `igniter-server/src/middleware.rs`
- `igniter-server/src/reload.rs`
- `igniter-server/src/serving_loop.rs`
- `igniter-server/src/host.rs`
- `igniter-server/README.md`

## Goal

Create a second machine-free Cargo example showing the P12 packaging pattern:

- `igniter-server/examples/server_app_runner.rs`
- `igniter-server/tests/app_runner_example_tests.rs`

This is still an example, not a new crate. It should demonstrate:

```text
RunnerConfig -> build_app(config) -> Arc<dyn ServerApp + Send + Sync>
  -> ReloadableApp::new(stack)
  -> ServingPolicy::new(n).loopback_only()
  -> serve_loop / serve_bounded_reloadable over caller-bound loopback listener
```

## Implementation requirements

1. `examples/server_app_runner.rs`
   - define a small `RunnerConfig` or `AppConfig`;
   - define `pub fn build_app(config) -> Arc<dyn ServerApp + Send + Sync>`;
   - build a composed stack using P8 middleware (`with_trace`, optional `with_auth`, `with_body_limit`);
   - reuse or define a neutral app (do not import SparkCRM/domain fixtures);
   - `main()` demonstrates the runner path in a bounded, machine-free way.

2. `tests/app_runner_example_tests.rs`
   - include the example via `#[path = "../examples/server_app_runner.rs"] mod runner_example;`
     or a better live-compatible route;
   - test `build_app` directly;
   - test bounded loopback serving;
   - test `ReloadableApp::swap(build_app(new_cfg))` changes the whole stack for the next request.

3. Optional README pointer
   - only if useful;
   - keep it short and do not rewrite architecture.

## Required behavior / tests

Prove:

1. `build_app(config)` returns `Arc<dyn ServerApp + Send + Sync>` and handles a direct `GET /health`.
2. Middleware from config works:
   - with auth enabled, missing/invalid token short-circuits;
   - valid token reaches the app and trace decorates the response.
3. Body limit from config rejects oversized request bodies before the app.
4. `ReloadableApp::new(build_app(v1))` + `swap(build_app(v2))` swaps the entire composed stack.
   Example: token `TOKA` works before swap and fails after swap if v2 expects `TOKB`.
5. Bounded loopback serving works on `127.0.0.1` only.
6. The runner owns serving policy / listener; the app owns routing; no server route table appears.
7. Serialized decisions still carry no privileged effect identity (`capability_id`, `operation`, `scope`).
8. The example remains machine-free: default build/test works without `igniter-machine`.

Run:

```bash
cd igniter-server && cargo build --examples
cd igniter-server && cargo run --example server_app_runner
cd igniter-server && cargo test
cd igniter-server && cargo test --features machine
```

## Deliverable

- `igniter-server/examples/server_app_runner.rs`
- `igniter-server/tests/app_runner_example_tests.rs`
- proof doc: `lab-docs/lang/lab-machine-igniter-server-app-runner-example-p13-v0.md`
- closing report in this card
- README pointer if useful

## Acceptance

- [ ] Example demonstrates `build_app(config) -> Arc<dyn ServerApp + Send + Sync>`.
- [ ] Example demonstrates a thin runner over `ReloadableApp` + bounded serving loop.
- [ ] Middleware composition is explicit and config-driven at the edge.
- [ ] App owns routing; runner owns listener/policy/reload.
- [ ] No new crate.
- [ ] No domain module in `src/`.
- [ ] No machine bridge implementation.
- [ ] No public listener/live network/DB/credentials/vendor API.
- [ ] `cargo build --examples` green.
- [ ] `cargo run --example server_app_runner` succeeds.
- [ ] `cargo test` green.
- [ ] `cargo test --features machine` green.
- [ ] Proof doc and closing report written.

## Closed surfaces

- No new crate.
- No release packaging.
- No dynamic plugin loading.
- No machine/effect host implementation.
- No SparkCRM/vendor app.
- No public listener.
- No DB.
- No credentials.
- No assets/raw-response protocol.
- No route config framework.
- No canon claim.

## Guardrail

This is a **packaging-pattern example**, not a framework. If the implementation starts adding config
files, route registries, generic app builders, or machine host wiring, stop and split the work.

---

## Closing report - 2026-06-18

**Outcome:** Second machine-free Cargo example implemented, teaching the P12 packaging pattern:
`build_app(config) -> Arc<dyn ServerApp + Send + Sync>` (explicit P8 middleware composition) + a thin
runner over `ReloadableApp` and a bounded `serve_loop`. No new crate, no `src/` domain module, no
machine bridge, no live IO, no `igniter-machine` change.

**Deliverable:** `lab-docs/lang/lab-machine-igniter-server-app-runner-example-p13-v0.md`.

**Files created:**
- `igniter-server/examples/server_app_runner.rs` - neutral `CoreApp` (GET /health->200; POST /echo w/
  idempotency-key->`InvokeEffect{target:"echo-record"}`; keyless->400; else 404), `AppConfig{version,
  auth_token,body_limit}`, `pub fn build_app(&AppConfig) -> Arc<dyn ServerApp + Send + Sync>`
  (`BodyLimit->[Auth]->Trace->CoreApp`), and a `main()` running a real bounded `serve_loop` + a swap demo.
- `igniter-server/tests/app_runner_example_tests.rs` - includes the example via `#[path]`; 7 tests.
- `igniter-server/README.md` - one-line pointer.

**Exact commands + output:**
```text
$ cargo build --examples                       -> Finished (0 warnings)
$ cargo run --example server_app_runner
  req1 GET /health (TOKA)             -> 200
  req2 GET /health (TOKA, after swap) -> 401
  served 2 requests; app versions seen: ["v1", "v2"]
$ cargo test                  -> 49 passed; 0 failed   (was 42; +7)
$ cargo test --features machine -> 62 passed; 0 failed (was 55; +7)
```

**Tests:** `build_app` returns Send+Sync + serves /health; auth short-circuit + trace decoration;
body-limit 413 before app; whole-stack reload over loopback (TOKA 200 -> swap v2/TOKB -> TOKA 401,
`app_versions_seen == ["v1","v2"]`); bounded loopback serves then returns; unknown route -> 404 (app
owns routing); decision carries no `capability_id`/`operation`/`scope`.

**Acceptance:** all boxes met. Guardrail honored - no config files, route registries, generic builder
framework, or machine host wiring introduced.
