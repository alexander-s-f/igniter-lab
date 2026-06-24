# igniter-web — Implemented Surface (ReadThen · EffectHost · host.toml · igweb-serve · Todo API)

**Status: lab / prototype. Not canon, not a public stability promise, not a production or hosting
surface. Loopback-only.** This is the code-anchored answer to "what does `igniter-web` actually
implement *today*?" for agents who keep finding older readiness/proof docs that say "ReadThen not
implemented", "observed only", "single-table read only", or "no live effect execution". When this
file and an old proof doc disagree, **this file + live source wins** (see
[Historical docs rule](#historical-docs-rule)).

Last verified against source: 2026-06-24 (after read/write binding `P25`/`P26`, hygiene `P29`-`P33`,
and Todo API product cards `P35`-`P41`).

## ReadThen status vocabulary

`ReadThen` is layered, so its status uses four exact categories (from `P31`) instead of a flat
"implemented". Each later category subsumes the earlier ones:

| Category | Meaning |
| --- | --- |
| `designed` | Semantics validated on paper / readiness packet; **no live code** yet. |
| `harness-proven` | Works in a test harness against **fake** adapters. |
| `implemented` | Live integration in `src/` is confirmed (not just the harness). |
| `runner-integrated` | Wired all the way into the actual `igweb-serve` binary path. |

| ReadThen layer | Status | Where / evidence |
| --- | --- | --- |
| Single staged read (`plan → rows → continuation`) | `runner-integrated` | `src/lib.rs::IgWebLoadedApp::dispatch_with_read` → `read_dispatch::StagedReadHost`; binary path `binary_path_readhost_from_config_found_200`. |
| Sequential / nested staged reads (`carry`, bounded loop) | `runner-integrated` | Same `dispatch_with_read` loop, `MAX_READ_HOPS = 8`; two-stage account-existence (`P38`) drives it via `[postgres.read.accounts]`; `runaway_readthen_chain_is_bounded`, `local_account_existence_missing_404_and_existing_empty_200`, subprocess product e2e. |
| Read freshness / opt-in replay | `runner-integrated` | `StagedReadHost::execute` keys receipts on `correlation_id`+`plan_digest`; uncorrelated reads run fresh (`P12`/`P23`). `uncorrelated_same_plan_reads_run_fresh`, `explicit_same_correlation_same_plan_replays`, `distinct_plans_never_collide`. |
| Typed row destructuring in the continuation | `designed` (not implemented) | Continuation receives rows as a JSON **string** (`rows_json`); no typed columns. Humble v0. |

## Implemented today

| Surface | Status | Where (source) | Notes |
| --- | --- | --- | --- |
| Sync observed mode (default) | Implemented | `src/bin/igweb-serve.rs` (`run`/no-flag path), `igniter-server::serving_loop` | Bounded loopback `serve_loop` via `ServerApp::call`. `InvokeEffect` is **observed, not executed**; effect identity never leaves the host. No `machine` feature needed. |
| Async machine mode | Implemented | `src/bin/igweb-serve.rs::run_machine_mode` (`--host-config`), `src/machine_runner.rs` | Tokio loop via `serve_loop_loaded_with_read`; **never calls `ServerApp::call`**. Requires `--features machine`. |
| `ReadThen { plan, then, carry }` | See [ReadThen vocabulary](#readthen-status-vocabulary) | `src/lib.rs::dispatch_with_read` (intercepts before `map_decision`) | Host runs the plan via `read_host`, then re-dispatches `then` with `{ req, rows_json, carry }`. The continuation may itself emit another `ReadThen` (sequential staged reads), bounded by `MAX_READ_HOPS = 8` → host 500. `Denied` → 403; `HostError` → 503. |
| `StagedReadHost` | Implemented | `src/read_dispatch.rs` | Wraps a `CapabilityExecutorRegistry` + receipts; read idempotency key = `correlation_id` folded with a `plan_digest` (distinct queries never collide — `P12`). `Succeeded`→Rows, `Denied`→Denied(reason), other→HostError. |
| Final `InvokeEffect` via `MachineEffectHost` | Implemented (async mode) | `src/machine_runner.rs` → `igniter-server::effect_host::{dispatch, MachineEffectHost}` | In **async machine mode** a final `InvokeEffect` routes through `MachineEffectHost`. Executes for real **only** when a write host is wired (below); an unbound target fails closed to host **502**. In **default sync mode** `InvokeEffect` stays observed. |
| `host.toml` read/write/effects | Implemented | `src/host_config.rs` (`parse_host_config`/`load_host_config`/`resolve_host_config`) | Keys: `[host] mode` (`"loopback"` only); `[effects.<t>]` `route`(req)+`passport_env`(opt); `[postgres.read]` `dsn_env`(req)+`source`+`fields`+`row_limit`(def 100)+`capability`; `[postgres.read.<name>]` extra allowlisted `(source, fields)` (`P38`); `[postgres.write]` `dsn_env`(req)+`targets`+`ops`+`capability`+`key_column`(def `id`)+`columns`. Fail-closed on unknown section/key, inline secrets (`dsn`/`password`/`secret`/`token`/`passport`/`api_key`), template `*_env`, route w/o `/`, missing `route`/`dsn_env`, bad `mode`. `resolve_host_config` resolves every `*_env` **before** any socket bind. |
| Multi-table read allowlist | Implemented (`P38`) | `src/host_config.rs::PostgresReadConfig.extra_sources` | A primary `[postgres.read]` source **plus** one or more `[postgres.read.<name>]` sources (e.g. prove `accounts` exists, then list `todos`). Still a **single** read DSN; the adapter is source-generic, the policy gates each table. |
| Real Postgres read/write | Implemented under `postgres` | `src/host_binding.rs::{build_staged_read_host_from_resolved, build_write_host_from_resolved}` over `igniter_machine::postgres_real::{TokioPostgresReadAdapter, TokioPostgresWriteAdapter}` | Wired **only** under `--features postgres` **and** `--host-config` with matching sections. Without the feature the DSN still resolves but no executor is built (reads denied / `InvokeEffect` unbound). Write path also needs `[effects.*]` + a `passport_env` bearer token. |
| `host.example.toml` | Implemented (`P28`, refreshed `P38`/`P41`) | `examples/todo_postgres_app/host.example.toml` | Committed, commit-safe (env-var names only). Now wires `[postgres.read.accounts]`, `targets = todos`, `ops = insert,upsert`, `capability = IO.TodoWrite`. Guarded by unit test `committed_host_example_toml_parses`. |
| Runner diagnostics | Implemented (`P29`/`P30`) | `src/runner_diag.rs`, used by `src/bin/igweb-serve.rs` | See [Failure taxonomy](#failure-taxonomy) below. |

### Todo API product path (`examples/todo_postgres_app`, cards `P35`-`P41`)

The generic surfaces above carry **one** product app end-to-end. App docs live in
`examples/todo_postgres_app/{API.md,RUNBOOK.md,host_policy.md}`; this is the status summary only.

| Product surface | Status | Where / notes |
| --- | --- | --- |
| Create request body | Implemented (`P35`) | Host crosses a JSON **object** body as `req.body_json : Map[String, Unknown]`; `.ig` reads `title` via `map_get_string`. `{"title":"…"}` is the canonical shape. Missing/non-string `title`, empty/blank title, or a non-object body → app-owned **400** (no write). `build_request_input` in `src/lib.rs`; `subprocess_non_string_create_body_writes_no_row`. |
| Legacy string create body | Implemented but **deprecated** (`P40`) | The old JSON-**string** body still works during a compatibility window; object body is the sole canonical shape. Removal deferred to a follow-up card. |
| Todo resource id | Implemented (`P36`) | Host mints `surrogate_id = todo_<blake3(method␟path␟idempotency_key)>[..32]` (`src/lib.rs::surrogate_id`); `.ig` prefixes `todo_` and uses it as the business key. The **id is decoupled from the idempotency key** (receipts/dedup still key on the idempotency key). Deterministic across replay; leaks no body/secret. `surrogate_id_tests`. |
| Account-existence read semantics | Implemented (`P38`) | Two-stage read `FindAccount` → `CheckAccountThenList`: existing+rows → **200**; existing+empty → **200 `[]`**; missing account → app-owned **404**; denied source/field → host **403** (adapter not reached); adapter failure → host **503**. `local_account_existence_missing_404_and_existing_empty_200`. |
| Error envelope (`RespondError` prelude) | `designed` / deferred (`P39`) | Readiness only — recommended a typed IgWeb-prelude `RespondError { status, error: ApiError{code,message} }` for app-authored errors. **Not yet in `map_decision`.** Today app errors are plain `Respond` bodies; host infra errors keep their current shape. |

## Not implemented / intentionally closed

| Surface | Status | Note |
| --- | --- | --- |
| Public listener mode | Closed | Loopback-only; non-loopback bind is refused (`ServingPolicy::loopback_only`). |
| Stable CLI promise | Closed | `igweb-serve` is a lab prototype; flags may change. |
| Pool / backpressure | Closed | One connection at a time, bounded by `--max-requests`. |
| Schema migration runner | Closed | DDL is operator-owned; the runner never creates/migrates tables. |
| Typed row destructuring | Not implemented | `ReadThen` continuation receives `rows_json` as a `String`; no typed columns yet. |
| Typed `RespondError` decision arm | Not implemented (`designed`, `P39`) | Error envelope is designed but not lowered; app errors are plain `Respond` today. |
| Multi-DSN reads / cross-DB joins | Not implemented | Multi-**table** allowlist exists (`extra_sources`), but a single read DSN and no join planner. |
| Production deployment story | Closed | No daemon, no hosting, no SparkCRM/production DB interaction. |

## Failure taxonomy

`src/runner_diag.rs` (`P29`) gives startup failures a **stable** `DiagCode` with a distinct non-zero
exit code and DSN/passport **redaction** (string forms are the contract; do not rename):

| Code | Exit | Kind |
| --- | --- | --- |
| `CONFIG_PARSE` | 2 | `host.toml` parse (unknown section/key, inline secret, bad route/mode). |
| `CONFIG_RESOLVE` | 3 | A `*_env` reference is missing/empty at runtime. |
| `APP_BUILD` | 4 | `.igweb`/`.ig` failed to lower/load. |
| `BIND_REFUSED` | 5 | Loopback listener could not bind (or non-loopback refused). |
| `POSTGRES_CONNECT` | 6 | Real adapter connect failed (message redacted; never carries the DSN). |
| `RUNNER_INTERNAL` | 11 | Unexpected internal runner failure (tokio/serve-loop IO). |

The per-request denial codes `READ_DENIED` (7), `WRITE_DENIED` (8), `EFFECT_UNBOUND` (9),
`PASSPORT_DENIED` (10) are **reserved in the taxonomy for completeness but are NOT process exits** —
they are returned as HTTP responses by the host policy gates (403/502/etc.).

## Evidence commands

**One-command guard (start here):** `scripts/check_implemented_surface.sh` runs the bounded evidence
below and prints a compact `implemented-surface: … PASS` receipt. It needs no `IGNITER_TODO_PG_DSN`
and no live DB — run it to confirm this surface is live before trusting any older "deferred / observed
only" doc. Its product sibling `scripts/check_todo_product_surface.sh` guards the Todo API contract
(`P35`/`P36`/`P38`/`P40`) the same DB-free way.

From `server/igniter-web/`:

```bash
scripts/check_implemented_surface.sh     # runner machinery: ReadThen + effect path + diagnostics + example + postgres-free tree
scripts/check_todo_product_surface.sh    # Todo product contract: object body + surrogate id + account-existence + error contract (no DB)

# ReadThen + StagedReadHost + async MachineEffectHost + runner diagnostics (all machine-gated):
cargo test --features machine
#   readthen_dispatch_tests:        found_rows_flow_to_continuation_200,
#                                   empty_rows_gives_continuation_owned_404,
#                                   denied_source_gives_host_403_before_adapter,
#                                   raw_sql_key_in_plan_is_refused_before_adapter,
#                                   runaway_readthen_chain_is_bounded,           # MAX_READ_HOPS (P38)
#                                   dispatch_with_read_has_no_nested_block_on,
#                                   uncorrelated_same_plan_reads_run_fresh        # freshness (P23)
#   readthen_socket_runner_tests:   found/empty/denied over socket (200/404/403),
#                                   serve_loop_serves_multiple_staged_read_requests
#   async_machine_runner_tests:     serve_once_loaded_executes_invoke_effect_over_socket,
#                                   replay_same_key_no_second_mutation_over_socket
#   igweb_serve_machine_mode_tests: machine_mode_readthen_found_rows_http_200,
#                                   machine_mode_readthen_empty_rows_http_200_empty_list,
#                                   machine_mode_readthen_no_executor_host_denied
#   igweb_serve_diagnostics_tests:  missing_dsn_env_fails_config_resolve_before_bind,
#                                   inline_secret_fails_config_parse_without_leaking_value,
#                                   unknown_section_fails_config_parse,
#                                   non_loopback_addr_fails_closed,
#                                   minimal_host_config_serves_one_request_and_exits_zero

# host.toml parser + committed example guard (lib unit tests):
cargo test --features machine --lib host_config   # parser fail-closed cases + committed_host_example_toml_parses

# Real Postgres read/write/account-existence through the real path, skips cleanly w/o DSN:
cargo test --features postgres --test todo_postgres_local_e2e_tests -- --test-threads=1
#   local_read_found_returns_app_200, local_read_empty_returns_200_empty_list,
#   local_write_creates_business_row_and_receipt, local_write_replay_no_second_mutation,
#   local_done_marks_existing_row_done, local_account_existence_missing_404_and_existing_empty_200,
#   binary_path_readhost_from_config_found_200,        # read binding (P25) through the binary
#   binary_path_write_from_config_committed,           # write binding (P26) through the binary
#   subprocess_product_command_read_write_replay_e2e,  # full product command as a subprocess
#   subprocess_non_string_create_body_writes_no_row,   # object-body contract (P35)
#   write_intent_raw_sql_refused_before_adapter
# With a dedicated local DB:
IGNITER_TODO_PG_DSN="host=localhost user=alex dbname=igniter_todo_test" \
  cargo test --features postgres --test todo_postgres_local_e2e_tests -- --test-threads=1
```

**Operator smoke (`scripts/todo_postgres_smoke.sh`).** One-command real-Postgres proof of the product
path (health, list empty/found, show, create, done, replay-no-second-mutation). Its DB-free preflight
**refusals** (no DSN → exit 2 `REFUSED`, non-local/unsafe DSN, secret-safe) are current and asserted by
`tests/todo_postgres_smoke_guard_tests.rs` and `check_todo_product_surface.sh` step 6. The full DB run
is **realigned to the current surface (`P42`)**: it sends the canonical object create body (`P35`) and
**discovers the real `todo_<…>` surrogate id from the product list response** (`P36`) for its
`show`/`done`/DB-truth checks, rather than assuming the row id equals the idempotency key. It needs a
dedicated local test DB:

```bash
export IGNITER_TODO_PG_DSN="host=localhost user=alex dbname=igniter_todo_test"
export IGNITER_TODO_EFFECT_TOKEN="local-smoke-token"
scripts/todo_postgres_smoke.sh
```

## Historical docs rule

Older readiness/proof docs under `lab-docs/` and `.agents/` are **evidence of what was true when
written**, not current backlog. Lines like "ReadThen not implemented", "observed only", "single-table
read only", "manual only", or "no live effect execution" were historically correct but are **stale as
current status**. Do not treat them as open work. This file plus live source is the current
implemented-surface map; old proof prose is not rewritten (it stays an accurate historical record).
See `lab-docs/STATUS.md` (Operating Rule) and the crate `README.md` for the front-door pointers here.
