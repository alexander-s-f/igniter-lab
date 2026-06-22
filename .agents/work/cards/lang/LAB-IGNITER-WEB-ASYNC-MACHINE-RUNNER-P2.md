# LAB-IGNITER-WEB-ASYNC-MACHINE-RUNNER-P2 - async IgWeb runner for machine-backed effects

Status: READY
Lane: server / IgWeb / machine host IO
Type: implementation
Delegation code: OPUS-WEB-ASYNC-MACHINE-RUNNER-P2
Date: 2026-06-22
Skill: idd-agent-protocol

## Context

P1 readiness concluded that the host IO substrate already exists, but `igweb-serve` cannot be the first full
consumer while it stays on the sync path:

- `igweb-serve` uses `std::net::TcpListener` + sync `serve_loop`;
- `MachineEffectHost` uses `tokio::net::TcpListener` + async `serve_loop_effect`;
- `IgWebServerApp::call` does internal `rt.block_on(machine.dispatch(...))`, so wrapping the socket loop in
  Tokio is insufficient and risks nested-runtime failures.

Gemini's review added two important constraints:

- do not let `host.toml` store raw secrets; use env-var references only in v0;
- do not turn `IgWebServerApp` into permanent legacy by duplicating app logic. Prefer one core loaded app with
  async dispatch, plus a sync compatibility adapter.

## Goal

Implement the smallest production-shaped async IgWeb runner slice:

```text
tokio listener -> async IgWeb dispatch -> final InvokeEffect -> MachineEffectHost -> receipt response
```

This card is **effects/write only**. Do not implement `ReadThen` here.

## Verify first

Read live code:

```text
server/igniter-web/src/bin/igweb-serve.rs
server/igniter-web/src/lib.rs
server/igniter-server/src/effect_host.rs
server/igniter-server/src/serving_loop.rs
server/igniter-web/tests/todo_postgres_effect_host_runner_tests.rs
server/igniter-web/tests/todo_postgres_api_write_tests.rs
server/igniter-web/tests/todo_postgres_api_read_write_e2e_tests.rs
runtime/igniter-machine/src/ingress.rs
runtime/igniter-machine/src/postgres_write.rs
```

Read P1:

```text
lab-docs/lang/lab-igniter-machine-host-io-substrate-readiness-p1-v0.md
```

## Required design

Introduce a single core IgWeb app abstraction that can dispatch async without nested `block_on`.

Suggested shape (names may change):

```text
IgWebLoadedApp
  machine: IgniterMachine
  entry: String
  async dispatch(req: ServerRequest) -> ServerDecision

IgWebServerApp
  sync compatibility adapter implementing ServerApp
  owns/uses a runtime only at the sync edge

igweb-serve machine mode
  awaits IgWebLoadedApp::dispatch directly
```

The async runner must not call `IgWebServerApp::call`.

## Host config v0

Add only the minimum config needed to prove fake machine-backed effects. Keep it operator-owned.

Allowed v0 shape:

```toml
[host]
mode = "loopback"

[effects.todo-create]
route = "/w"
passport_env = "IGNITER_EFFECT_PASSPORT"

[postgres.write]
dsn_env = "IGNITER_PG_WRITE_DSN"
```

For this card, fake executors may ignore DSN, but the parser must reject inline secret fields:

```toml
dsn = "postgres://..."
password = "..."
passport = "..."
token = "..."
```

Use env variable names only (`*_env`). Do not add interpolation.

If host config parsing becomes too large, implement the narrow subset for the test and leave full hardening to
`LAB-IGNITER-HOST-CONFIG-SCHEMA-P3`.

## Implementation boundaries

Allowed:

- `server/igniter-web` app loading / runner code.
- `server/igniter-server` only if a small async helper is missing and can be shared without breaking sync API.
- Tests under `server/igniter-web/tests`.
- Minimal host config fixture under `server/igniter-web/examples` or `tests/fixtures`.

Closed:

- No `ReadThen` arm, staged reads, compiler grammar, or read continuation driver.
- No real Postgres requirement; fake executor proof is enough.
- No public bind; loopback only.
- No server route table.
- No DSN/passport inline secrets in app files or host config.
- No unbounded `tokio::spawn` or background daemon.

## Acceptance

- [ ] Async runner path uses `tokio::net::TcpListener` and awaits a machine-backed effect path.
- [ ] Async path does not call `IgWebServerApp::call` and has no nested `block_on`.
- [ ] One core IgWeb loaded-app dispatch path is shared by async runner and sync compatibility adapter, or the
      diff explains why a smaller interim shape is safer.
- [ ] Existing sync `igweb-serve` / `serve_loop` tests remain green for machine-free apps.
- [ ] Machine-backed route executes a final `InvokeEffect` through `MachineEffectHost` and returns a receipt.
- [ ] Host config v0 uses `*_env` references and rejects inline `dsn`/`password`/`passport`/`token`.
- [ ] No `ReadThen` implementation in this card.
- [ ] `igniter-server` remains route/domain-free.
- [ ] `cargo test --features machine` for `server/igniter-web` passes targeted new tests.
- [ ] `git diff --check` clean.

## Closing report

TBD.
