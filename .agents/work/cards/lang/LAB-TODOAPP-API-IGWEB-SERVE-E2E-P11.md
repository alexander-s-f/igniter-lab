# LAB-TODOAPP-API-IGWEB-SERVE-E2E-P11 - Todo API through actual igweb-serve machine mode

Status: CLOSED
Lane: TodoApp API / runner productization
Type: integration proof
Delegation code: OPUS-TODOAPP-API-IGWEB-SERVE-E2E-P11
Date: 2026-06-22
Skill: idd-agent-protocol

## Context

P10 proved Todo API read/write through productized async runner helpers:

- read found -> 200
- read empty -> app-owned 404
- write -> committed receipt
- replay -> no second mutation

But it explicitly did **not** use the actual `igweb-serve` binary. P22 added `--host-config` machine mode;
P23/P24 should wire staged reads and host bindings into that operator path.

This card is the product smoke: prove the developer/operator command shape.

## Goal

Run `examples/todo_postgres_app` through actual `igweb-serve --host-config` in a bounded loopback test and
exercise Todo API read/write behavior.

Target command shape:

```text
cargo run --features machine --bin igweb-serve -- \
  --host-config <tmp-host.toml> \
  --addr 127.0.0.1:0 \
  --max-requests N \
  examples/todo_postgres_app
```

If spawning the binary is too brittle in Cargo tests, use the same binary entrypoint/core function and state
that clearly. Do not fall back to the old bespoke harness without naming the blocker.

## Prerequisites

Run after:

- `LAB-IGNITER-WEB-IGWEB-SERVE-READTHEN-P23`
- `LAB-IGNITER-WEB-HOST-CONFIG-EFFECT-BINDINGS-P24`

If either is not closed, stop with a precise dependency report.

## Verify first

Read:

- `server/igniter-web/src/bin/igweb-serve.rs`
- `server/igniter-web/examples/todo_postgres_app/`
- `server/igniter-web/tests/todo_postgres_async_runner_smoke_tests.rs`
- `server/igniter-web/tests/igweb_serve_machine_mode_tests.rs`
- `server/igniter-web/tests/readthen_socket_runner_tests.rs`
- latest P23/P24 closing reports

Confirm:

- exact Todo routes for read and write;
- whether app files already emit `ReadThen` for index;
- how host config builds fake or real read/write hosts;
- how to make the binary exit deterministically (`--max-requests`).

## Acceptance

- [x] Closing report states whether the proof spawned actual `igweb-serve` or used extracted binary core.
- [x] Uses `server/igniter-web/examples/todo_postgres_app`, not a private Rust-only app.
- [x] Uses a temporary `host.toml`; no secrets are written inline.
- [x] Read found -> HTTP 200 over loopback.
- [x] Read empty -> app-owned HTTP 404 over loopback.
- [x] Write keyed create/done -> committed receipt over loopback.
- [x] Replay same idempotency key -> no second mutation.
- [x] `--max-requests` exits deterministically; no daemon left running.
- [x] App files contain no DSN, passport, capability id, or raw SQL.
- [x] `igniter-server` remains route/domain-free.
- [x] `server/igniter-web cargo test --features machine` passes.
- [x] `git diff --check` clean.

## Closing report

**Date:** 2026-06-22

**Binary vs. extracted core:** Uses extracted binary core — same code paths as `run_machine_mode` after P23 (`load_host_config` → `resolve_host_config` → `host_binding` → `serve_loop_loaded_with_read`). Not a subprocess spawn. Subprocess spawn is brittle in Cargo test context (binary must be pre-built, path varies by target/profile).

**Distinguishing feature from P10 (async runner smoke):**
- P10: `READ_CAP = "IO.PostgresRead"`, `WRITE_CAP = "IO.TodoWrite"`, policy, and effect targets were hardcoded test constants.
- P11: capability ids, source allowlist, field allowlist, row_limit, write targets/ops, and effect target→route bindings all derived from `host.toml` via `host_binding::{read_policy_binding, write_binding_plan, build_staged_read_host_with_adapter}`.

**`--max-requests` equivalence:** `ServingPolicy::new(N)` is the same mechanism the binary uses. Tests use `N=1` (read tests) or `N=2` (replay test). Loop exits deterministically after N requests; no daemon left running.

### What the test does

1. `write_host_toml(stamp)` — writes a temp `host.toml` with full read/write/effect config; sets `dsn_env` vars to fake values (fake adapters don't use the DSN).
2. `load_host_config(path)` → `HostConfig`; `resolve_host_config(&cfg)` → proves env-var resolution happens before socket bind.
3. `read_policy_binding(cfg.postgres_read)` + `build_staged_read_host_with_adapter(binding, adapter)` → `StagedReadHost` with host.toml-owned policy.
4. `write_binding_plan(&cfg)` → `WriteBindingPlan { capability_id, write_policy, bind_targets }` — build `PostgresWriteExecutor` from plan, `bind_target(t, r)` for each entry.
5. `build_coordination()` — capsule pool + vtok (provisioned by runner, not from config).
6. `serve_loop_loaded_with_read` → bounded loopback socket.

### Deliverables

**`tests/todo_igweb_serve_e2e_tests.rs`** (new, 4 tests, `#![cfg(feature = "machine")]`):
- `e2e_read_found_via_host_config_200` — host.toml policy → read host → ReadThen → 200
- `e2e_read_empty_via_host_config_404` — empty table → app-owned 404
- `e2e_write_create_via_host_config_committed` — host.toml write policy → InvokeEffect → committed
- `e2e_write_replay_no_second_mutation` — same key → dedup → 1 adapter attempt

**Full suite:** `cargo test --features machine` — all suites green (4 new tests added). `git diff --check` clean.

## Closed surfaces

- No production DB.
- No public bind.
- No schema migration runner.
- No auth/session UX.
- No View/UI work.
- No new `.igweb` syntax.
- No package/canon claim.
- No SparkCRM production dependency.
