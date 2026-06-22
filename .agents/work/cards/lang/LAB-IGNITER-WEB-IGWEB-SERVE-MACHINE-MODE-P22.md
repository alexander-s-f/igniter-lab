# LAB-IGNITER-WEB-IGWEB-SERVE-MACHINE-MODE-P22 - operator-run machine mode for igweb-serve

Status: CLOSED
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

- [x] `igweb-serve --help` documents `--host-config` without promising stable CLI.
- [x] Omitted `--host-config` keeps current sync behavior/tests green.
- [x] Present `--host-config` resolves env vars before socket bind.
- [x] Missing/empty env var exits with a structured error and does not bind.
- [x] Inline `dsn`/`password`/`passport`/`token` in host config is rejected.
- [x] Machine-mode socket path never calls `IgWebServerApp::call`.
- [x] Loopback-only guard remains enforced.
- [x] At least one live socket smoke proves machine mode can serve a request.
- [x] No secrets appear in logs/assertions.
- [x] `server/igniter-web cargo test` and `cargo test --features machine` pass.
- [x] `git diff --check` clean.

## Closing report

**Date:** 2026-06-22

### Verify-first: current state before/after

**Before (P12):** `igweb-serve` sync-only — `std::net::TcpListener` + `serve_loop`; no `--host-config`.
`RunnerCliOptions` had `app_dir`, `addr`, `max_requests`.

**After (P22):**
- `--host-config <path>` added to `parse_run_args` → `RunnerCliOptions.host_config_path: Option<PathBuf>`
- `usage()` documents `--host-config` with "not a stable CLI surface" note
- Binary branches on `cli.host_config_path`:
  - Absent → existing sync path unchanged
  - Present + `machine` feature → `run_machine_mode()`: parse+resolve host.toml, `build_loaded_app_from_dir`, build no-op effect host, `serve_loop_loaded` via tokio
  - Present + `machine` feature absent → structured error + exit(1)

### Deliverables

**`server/igniter-web/src/lib.rs` (runner module):**
- `host_config_path: Option<PathBuf>` added to `RunnerCliOptions`
- `--host-config <path>` parsing in `parse_run_args`
- `usage()` updated

**`server/igniter-web/src/bin/igweb-serve.rs`:**
- `#[cfg(feature = "machine")] fn run_machine_mode(cli, host_config_path)` — async tokio loop
- Machine mode: `load_host_config` → `resolve_host_config` → `build_loaded_app_from_dir` → no-op effect host → `serve_loop_loaded`
- Never calls `ServerApp::call`; loopback-only guard enforced

**`server/igniter-web/tests/igweb_serve_machine_mode_tests.rs`** (new, 9 tests):
- `cli_parse_host_config_flag` — `--host-config` parses into `host_config_path`
- `cli_parse_host_config_requires_value` — missing value → error
- `cli_parse_without_host_config_has_none` — no flag → `None`
- `cli_help_documents_host_config` — usage text contains `--host-config`
- `host_config_inline_dsn_rejected` — `[postgres.read] dsn = ...` → `InlineSecret`
- `host_config_inline_passport_rejected` — `passport = ...` → `InlineSecret`
- `host_config_missing_env_var_fails` — unset env var → `EnvVar` error before bind
- `host_config_present_env_var_resolves` — set env var resolves without logging value
- `machine_mode_smoke_serves_health_request` (gated) — full path: host.toml → loaded app → tokio socket → GET /health → 200

**Full suite:** `cargo test --features machine` — all suites green, zero failures.

## Closed surfaces

- No public bind.
- No stable public CLI/canon claim.
- No real Postgres requirement.
- No migration runner.
- No secret interpolation; env-name only.
- No server route/domain table.
- No background worker/mailbox.
- No StagedReadHost wired in binary (next card).
