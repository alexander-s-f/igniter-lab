# LAB-IGNITER-WEB-IGWEB-SERVE-MACHINE-MODE-P22 - operator-run machine mode for igweb-serve

Status: OPEN
Lane: IgWeb / runner productization / host IO
Type: implementation with narrow readiness fallback
Delegation code: OPUS-WEB-IGWEB-SERVE-MACHINE-MODE-P22
Date: 2026-06-22
Skill: idd-agent-protocol

## Context

The current `igweb-serve` binary still runs the sync `std::net::TcpListener` + `serve_loop` path. P2 added
an async loaded app and machine runner helpers; P3 added `host_config`; P11 added `ReadThen`. The next product
pressure is a real operator command, not another hand-built test harness.

Desired direction:

```text
igweb-serve --host-config host.toml <app_dir>
  -> parse igweb.toml + host.toml
  -> async tokio listener
  -> machine-backed read/write/render/respond path
```

## Goal

Wire the smallest honest `igweb-serve` machine mode. If live code shows this is too large, land a precise
readiness packet naming the exact blocker and the smallest next implementation card.

## Verify first

Read:

- `server/igniter-web/src/bin/igweb-serve.rs`
- `server/igniter-web/src/lib.rs::runner` CLI parsing
- `server/igniter-web/src/host_config.rs`
- `server/igniter-web/src/machine_runner.rs`
- `server/igniter-web/src/read_dispatch.rs`
- `server/igniter-web/tests/async_machine_runner_tests.rs`
- `server/igniter-web/tests/readthen_dispatch_tests.rs`
- `runtime/igniter-machine/src/postgres_read.rs`
- `runtime/igniter-machine/src/postgres_write.rs`

Confirm:

- whether `parse_cli_args` can accept `--host-config` without breaking old syntax;
- whether feature-gating the binary path under `machine` is straightforward;
- whether fake read/write executors can be configured without adding live DB;
- whether `host.toml` values can be resolved without logging secrets.

## Implementation shape

Preferred v0:

- add `--host-config <path>` to runner CLI parse;
- without `--host-config`, existing sync loop remains unchanged;
- with `--host-config`, require `machine` feature and run a bounded loopback tokio path;
- parse/resolve host config before opening socket;
- reject inline secrets and missing env vars before binding;
- use fake adapters in tests; do not require live Postgres.

If executor construction from `host.toml` is too large, implement the CLI parse + fail-closed config resolution
and write the next card for executor binding.

## Acceptance

- [ ] `igweb-serve --help` documents `--host-config` without promising stable CLI.
- [ ] Omitted `--host-config` keeps current sync behavior/tests green.
- [ ] Present `--host-config` resolves env vars before socket bind.
- [ ] Missing/empty env var exits with a structured error and does not bind.
- [ ] Inline `dsn`/`password`/`passport`/`token` in host config is rejected.
- [ ] Machine-mode socket path never calls `IgWebServerApp::call`.
- [ ] Loopback-only guard remains enforced.
- [ ] At least one live socket smoke proves machine mode can serve a request.
- [ ] No secrets appear in logs/assertions.
- [ ] `server/igniter-web cargo test` and `cargo test --features machine` pass.
- [ ] `git diff --check` clean.

## Closed surfaces

- No public bind.
- No stable public CLI/canon claim.
- No real Postgres requirement.
- No migration runner.
- No secret interpolation; env-name only.
- No server route/domain table.
- No background worker/mailbox.
