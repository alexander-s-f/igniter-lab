# igniter-web — Implemented Surface (ReadThen · EffectHost · host.toml · igweb-serve)

**Status: lab / prototype. Not canon, not a public stability promise, not a production or hosting
surface. Loopback-only.** This is the code-anchored answer to "what does `igniter-web` actually
implement *today*?" for agents who keep finding older readiness/proof docs that say "ReadThen not
implemented", "observed only", or "no live effect execution". When this file and an old proof doc
disagree, **this file + live source wins** (see [Historical docs rule](#historical-docs-rule)).

Last verified against source: 2026-06-23.

## Implemented today

| Surface | Status | Where (source) | Notes |
| --- | --- | --- | --- |
| Sync observed mode (default) | Implemented | `src/bin/igweb-serve.rs` (`run`/no-flag path), `igniter-server::serving_loop` | Bounded loopback `serve_loop` via `ServerApp::call`. `InvokeEffect` is **observed, not executed**; effect identity never leaves the host. No `machine` feature needed. |
| Async machine mode | Implemented | `src/bin/igweb-serve.rs::run_machine_mode` (`--host-config`), `src/machine_runner.rs` | Tokio loop via `serve_loop_loaded_with_read`; **never calls `ServerApp::call`**. Requires `--features machine`. |
| `ReadThen { plan, then }` | Implemented | `src/lib.rs::IgWebLoadedApp::dispatch_with_read` (intercepts before `map_decision`) | Host runs the plan via `read_host`, then re-dispatches `then` with `{ req, rows_json }`. Rows → continuation Decision; `Denied` → 403; `HostError` → 503. **Limited:** continuation receives rows as a JSON **string** (`rows_json`) — no typed row destructuring (humble v0). |
| `StagedReadHost` | Implemented | `src/read_dispatch.rs` | Wraps a `CapabilityExecutorRegistry` + receipts; read idempotency key = `correlation_id` folded with a `plan_digest` (so distinct queries never collide — P12 fix). `Succeeded`→Rows, `Denied`→Denied(reason), other→HostError. |
| Final `InvokeEffect` via `MachineEffectHost` | Implemented (async mode) | `src/machine_runner.rs` → `igniter-server::effect_host::{dispatch, MachineEffectHost}` | In **async machine mode** a final `InvokeEffect` routes through `MachineEffectHost`. It executes for real **only** when a write host is wired (see below); otherwise the target is unbound. In **default sync mode** `InvokeEffect` stays observed. |
| `host.toml` read/write/effects | Implemented | `src/host_config.rs` (`parse_host_config`/`load_host_config`/`resolve_host_config`) | Keys: `[host] mode` (`"loopback"` only); `[effects.<t>]` `route`(req)+`passport_env`(opt); `[postgres.read]` `dsn_env`(req)+`source`+`fields`+`row_limit`(def 100)+`capability`; `[postgres.write]` `dsn_env`(req)+`targets`+`ops`+`capability`+`key_column`(def `id`)+`columns`. Fail-closed on unknown section/key, inline secrets (`dsn`/`password`/`secret`/`token`/`passport`/`api_key`), template `*_env`, route w/o `/`, missing `route`/`dsn_env`, bad `mode`. `resolve_host_config` resolves every `*_env` **before** any socket bind. |
| Real Postgres read/write | Implemented under `postgres` | `src/host_binding.rs::{build_staged_read_host_from_resolved, build_write_host_from_resolved}` over `igniter_machine::postgres_real::{TokioPostgresReadAdapter, TokioPostgresWriteAdapter}` | Wired **only** under `--features postgres` **and** `--host-config` with the matching sections. Without the feature the DSN still resolves but no executor is built (reads denied / `InvokeEffect` unbound). Write path also needs `[effects.*]` + a `passport_env` bearer token. |
| `host.example.toml` | Implemented (P28) | `examples/todo_postgres_app/host.example.toml` | Committed, commit-safe (env-var names only). Guarded by unit test `committed_host_example_toml_parses`. |
| `todo_postgres_smoke.sh` | Implemented (P13) | `scripts/todo_postgres_smoke.sh` | One-command operator smoke; reuses `host.example.toml` (writes no config file); refuses without `IGNITER_TODO_PG_DSN`; PASS/FAIL receipt. |
| Runner diagnostics | Implemented (P29/P30) | `src/runner_diag.rs`, used by `src/bin/igweb-serve.rs` | Startup failures get a **stable** `DiagCode` (`CONFIG_PARSE`=2, `CONFIG_RESOLVE`=3, `APP_BUILD`=4, `BIND_REFUSED`=5, `POSTGRES_CONNECT`=6, …) with distinct non-zero exit codes and DSN/passport **redaction**. Process-exit diagnostics only; per-request denials (`READ_DENIED`/`WRITE_DENIED`/`EFFECT_UNBOUND`/`PASSPORT_DENIED`) are HTTP responses, named in the taxonomy but never emitted as exits. |

## Not implemented / intentionally closed

| Surface | Status | Note |
| --- | --- | --- |
| Public listener mode | Closed | Loopback-only; non-loopback bind is refused (`ServingPolicy::loopback_only`). |
| Stable CLI promise | Closed | `igweb-serve` is a lab prototype; flags may change. |
| Pool / backpressure | Closed | One connection at a time, bounded by `--max-requests`. |
| Schema migration runner | Closed | DDL is operator-owned; the runner never creates/migrates tables. |
| Generic multi-source read config | Not implemented | `[postgres.read]` binds a **single** `source` in v0 (`PostgresReadConfig.source: Option<String>`). |
| Typed row destructuring | Not implemented | `ReadThen` continuation receives `rows_json` as a `String`; no typed columns yet. |
| Production deployment story | Closed | No daemon, no hosting, no SparkCRM/production DB interaction. |

## Evidence commands

**One-command guard (start here):** `scripts/check_implemented_surface.sh` runs the bounded evidence
below and prints a compact `implemented-surface: … ok` receipt. It needs no `IGNITER_TODO_PG_DSN` and no
live DB — run it to confirm this surface is live before trusting any older "deferred / observed only"
doc.

From `server/igniter-web/`:

```bash
scripts/check_implemented_surface.sh   # bounded guard: ReadThen + effect path + diagnostics + example + postgres-free tree

# ReadThen + StagedReadHost + async MachineEffectHost + runner diagnostics (all machine-gated):
cargo test --features machine
#   readthen_dispatch_tests:        found_rows_flow_to_continuation_200,
#                                   empty_rows_gives_continuation_owned_404,
#                                   denied_source_gives_host_403_before_adapter,
#                                   raw_sql_key_in_plan_is_refused_before_adapter,
#                                   dispatch_with_read_has_no_nested_block_on
#   readthen_socket_runner_tests:   found/empty/denied over socket (200/404/403),
#                                   serve_loop_serves_multiple_staged_read_requests
#   async_machine_runner_tests:     serve_once_loaded_executes_invoke_effect_over_socket,
#                                   replay_same_key_no_second_mutation_over_socket
#   igweb_serve_diagnostics_tests:  missing_dsn_env_fails_config_resolve_before_bind,
#                                   inline_secret_fails_config_parse_without_leaking_value,
#                                   non_loopback_addr_fails_closed,
#                                   minimal_host_config_serves_one_request_and_exits_zero

# host.toml parser + committed example guard (feature-free lib unit tests):
cargo test --lib host_config  # parser fail-closed cases + committed_host_example_toml_parses

# Real Postgres read/write through the actual binary (subprocess), skips cleanly w/o DSN:
cargo test --features postgres --test todo_postgres_local_e2e_tests -- --test-threads=1
#   subprocess_product_command_read_write_replay_e2e (read 200 / read 404 / write / replay)
# With a dedicated local DB:
IGNITER_TODO_PG_DSN="host=localhost user=alex dbname=igniter_todo_test" \
  cargo test --features postgres --test todo_postgres_local_e2e_tests -- --test-threads=1

# One-command operator smoke (dedicated local DB):
export IGNITER_TODO_PG_DSN="host=localhost user=alex dbname=igniter_todo_test"
scripts/todo_postgres_smoke.sh

# Run the real product command against local Postgres (reuses the committed example):
export IGNITER_TODO_EFFECT_TOKEN="some-local-bearer-token"
cargo run --features postgres --bin igweb-serve -- \
  --host-config examples/todo_postgres_app/host.example.toml \
  --addr 127.0.0.1:0 --max-requests 8 examples/todo_postgres_app
```

## Historical docs rule

Older readiness/proof docs under `lab-docs/` and `.agents/` are **evidence of what was true when
written**, not current backlog. Lines like "ReadThen not implemented", "observed only", "manual only",
or "no live effect execution" were historically correct but are **stale as current status**. Do not
treat them as open work. This file plus live source is the current implemented-surface map; old proof
prose is not rewritten (it stays an accurate historical record). See `lab-docs/STATUS.md` (Operating
Rule) and the crate `README.md` for the front-door pointers here.
