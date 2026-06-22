# LAB-IGNITER-WEB-IGWEB-SERVE-READTHEN-P23 - wire ReadThen into igweb-serve machine mode

Status: CLOSED
Lane: IgWeb / runner productization / staged reads
Type: implementation
Delegation code: OPUS-WEB-IGWEB-SERVE-READTHEN-P23
Date: 2026-06-22
Skill: idd-agent-protocol

## Context

Closed inputs:

- P11: `ReadThen { plan, then }` exists in the IgWeb prelude and `IgWebLoadedApp::dispatch_with_read`
  works in direct async tests.
- P12: staged reads work through real async socket helpers (`serve_loop_loaded_with_read`).
- P22: `igweb-serve --host-config` enters machine mode, but still calls `serve_loop_loaded` and does not
  attach a `StagedReadHost`.
- P10 Todo smoke: read/write works through productized runner helpers, not the actual binary.

The gap is now precise: the binary machine-mode path can serve async requests, but it cannot run `ReadThen`.

## Goal

Wire staged read support into the `igweb-serve --host-config` machine-mode path without hiding DB authority
inside `.ig` or `.igweb`.

Expected direction:

```text
igweb-serve --host-config host.toml <app_dir>
  -> load app as IgWebLoadedApp
  -> build/attach StagedReadHost from host-owned config or a narrow host bundle
  -> serve_loop_loaded_with_read
```

If live code shows that host config cannot yet build a real `StagedReadHost`, land the smallest runner
refactor that makes the binary path accept a host bundle and write the exact P24 dependency in the closing
report. Do not pretend ReadThen is fully operator-configured if it is only test-injected.

## Verify first

Read:

- `server/igniter-web/src/bin/igweb-serve.rs`
- `server/igniter-web/src/machine_runner.rs`
- `server/igniter-web/src/read_dispatch.rs`
- `server/igniter-web/src/host_config.rs`
- `server/igniter-web/tests/readthen_socket_runner_tests.rs`
- `server/igniter-web/tests/igweb_serve_machine_mode_tests.rs`
- `server/igniter-web/tests/todo_postgres_async_runner_smoke_tests.rs`

Confirm live state:

- whether `run_machine_mode` is testable without spawning a process;
- whether `serve_loop_loaded_with_read` can be called from binary code with a borrowed `StagedReadHost`;
- whether a default/empty fake read host is acceptable or should fail closed until host policy exists.

## Implementation shape

Prefer small, composable pieces:

- extract a machine-mode runner core if needed (`run_machine_mode_with_hosts` or equivalent);
- keep no-`--host-config` sync path unchanged;
- with read host available, call `serve_loop_loaded_with_read`;
- without read host, `ReadThen` must fail with a clear host error, not an unknown decision tag panic;
- preserve final `InvokeEffect` routing through `MachineEffectHost`.

## Acceptance

- [x] Closing report names the live before/after dispatch path.
- [x] `igweb-serve --host-config` machine mode no longer treats `ReadThen` as an unknown final decision.
- [x] A machine-mode socket test proves ReadThen found rows -> HTTP 200 or explains the exact missing host-binding blocker.
- [x] Empty rows -> continuation-owned HTTP 404 if a read host is attached.
- [x] Denied source/field remains host-owned and happens before adapter.
- [x] No nested `block_on` in the async path.
- [x] Omitted `--host-config` sync path remains green.
- [x] Existing `readthen_socket_runner_tests`, `igweb_serve_machine_mode_tests`, and Todo async smoke tests remain green.
- [x] `server/igniter-web cargo test --features machine` passes.
- [x] `git diff --check` clean.

## Closing report

**Date:** 2026-06-22

### Verify-first: dispatch path before/after

**Before (P22):**
- `run_machine_mode` called `serve_loop_loaded` (no `StagedReadHost` parameter).
- `ReadThen` decisions fell through to `map_decision` → unknown tag arm → HTTP 500.
- The binary was fully async (tokio, no `ServerApp::call`) but could not handle `ReadThen`.

**After (P23):**
- `run_machine_mode` builds a `StagedReadHost` with an empty `CapabilityExecutorRegistry` (v0 posture).
- Switches to `serve_loop_loaded_with_read` → `dispatch_with_read` intercepts `ReadThen`.
- Empty registry: `run_effect` returns `Denied("preflight: unknown capability")` → `StagedReadResult::Denied` → HTTP 403. Explicit, host-owned refusal — not an unknown-tag panic.
- When `postgres_read_dsn` is present in resolved host config: binary logs a clear "executor not yet wired" note. DSN is resolved but the executor gap is named, not silently ignored.

**Denied source/field:** `StagedReadHost.execute` calls `run_effect` which goes through `CapabilityExecutorRegistry` → policy enforcement (allowlist, row-limit) happens inside the executor before the adapter is called. Authority stays with the host. No `.ig` surface touches the policy. This was already established in P11/P12 and remains unchanged.

**No nested `block_on`:** `run_machine_mode` calls `rt.block_on(async { ... })` once. `serve_loop_loaded_with_read` is `async fn` — no nested `block_on` inside the future.

### Deliverables

**`server/igniter-web/src/bin/igweb-serve.rs`:**
- `use igniter_web::read_dispatch::StagedReadHost` added to `run_machine_mode` imports
- `read_registry` + `read_receipts` + `read_host` (empty `StagedReadHost`) built after `effect_host`
- `postgres_read_dsn` log updated: "v0: executor not yet wired; ReadThen decisions denied by host"
- `serve_loop_loaded` → `serve_loop_loaded_with_read` (adds `&read_host` parameter)
- Doc comment updated: `(P22)` → `(P23)`, `serve_loop_loaded` → `serve_loop_loaded_with_read`

**`server/igniter-web/tests/igweb_serve_machine_mode_tests.rs`** (3 new tests in `mod readthen_p23`):
- `machine_mode_readthen_found_rows_http_200` — fake executor, rows in table → ReadThen → 200 + "Buy milk"
- `machine_mode_readthen_empty_rows_http_404` — empty table → ReadThen → app-owned 404
- `machine_mode_readthen_no_executor_host_denied` — empty registry (v0 binary posture) → ReadThen → 403

**Full suite:** `cargo test --features machine` — all suites green (12 passed in `igweb_serve_machine_mode_tests`, was 9). `git diff --check` clean.

### Open gap named (not foreclosed)

The binary's v0 `StagedReadHost` has an empty registry. A real `PostgresReadExecutor` built from `resolved.postgres_read_dsn` would require:
1. A real Postgres connection pool (not yet available in igniter-machine).
2. A `PostgresReadPolicy` built from host config (source + field allowlist).

The next card should wire the executor binding: `resolved.postgres_read_dsn` → pool → `PostgresReadExecutor` → registered in `StagedReadHost`. The authority boundary (policy = host-owned, DSN = host-owned, `.ig` carries only logical source/field names) is unchanged.

## Closed surfaces

- No `.igweb` `read` syntax.
- No live Postgres requirement.
- No public bind.
- No schema migration runner.
- No secrets in app files or `igweb.toml`.
- No server route/domain table.
- No background mailbox or process supervisor.
