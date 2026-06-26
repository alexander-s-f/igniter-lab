# igniter-web — Implemented Surface (Routing · ViewArtifact · ReadThen · EffectHost · Todo API)

**Status: lab / prototype. Not canon, not a public stability promise, not a production or hosting
surface. Loopback-only.** This is the code-anchored answer to "what does `igniter-web` actually
implement *today*?" for agents who keep finding older readiness/proof docs that say "ReadThen not
implemented", "observed only", "single-table read only", or "no live effect execution". When this
file and an old proof doc disagree, **this file + live source wins** (see
[Historical docs rule](#historical-docs-rule)).

Last refreshed against source: 2026-06-26 (route sugar `P16`-`P20`/`P22`/`P26`/`P27`,
ViewArtifact authoring `P16`/`P19`, link node/nav `LINK-NODE`/`P27`, typed `ReadThen`
crossing + `DatasetMeta` `P6`-`P8`, Todo typed rows -> HTML `P18`, Todo API product cards
`P35`-`P41`, error envelope `P43`, delete `P44`, legacy body removal `P45`, keyset pagination
`P47`, typed Todo list envelope + `RespondJson` `P50`, typed Decimal row crossing `P23`,
DB-backed Decimal money report proof `P24`, and compiler package/admission pointers).

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
| Typed row continuations (`rows : Collection[AppRow]` + `meta : DatasetMeta`) | `runner-integrated` | `src/read_continuation.rs` classifies continuation inputs from compiled metadata; `src/read_dispatch.rs::execute_typed` materializes typed rows + `DatasetMeta`; `src/lib.rs::dispatch_with_read` auto-routes typed vs legacy; `typed_readthen_tests`, `typed_row_crossing_tests`, `typed_html_tests`. |
| Legacy `rows_json` continuations | `runner-integrated` (compatibility) | Continuations declaring `rows_json : String`, or neither `rows` nor `rows_json`, still receive `{ req, rows_json, carry }`; `legacy_lane_still_routes_to_rows_json`, `legacy_rows_json_path_still_works`. |
| Boot/check structural diagnostics for typed continuations | Implemented (source-independent subset) | `src/read_continuation.rs::validate_read_continuations`; `src/runner_diag.rs::ProjectionSchemaInvalid` (`PROJECTION_SCHEMA_INVALID`, exit 12); `igweb-serve check` and machine mode fail before bind for malformed typed continuation shapes. Source-dependent host-kind drift remains a first-dispatch guard. |

## Implemented today

| Surface | Status | Where (source) | Notes |
| --- | --- | --- | --- |
| Sync observed mode (default) | Implemented | `src/bin/igweb-serve.rs` (`run`/no-flag path), `igniter-server::serving_loop` | Bounded loopback `serve_loop` via `ServerApp::call`. `InvokeEffect` is **observed, not executed**; effect identity never leaves the host. No `machine` feature needed. |
| Async machine mode | Implemented | `src/bin/igweb-serve.rs::run_machine_mode` (`--host-config`), `src/machine_runner.rs` | Tokio loop via `serve_loop_loaded_with_read`; **never calls `ServerApp::call`**. Requires `--features machine`. |
| `ReadThen { plan, then, carry }` | See [ReadThen vocabulary](#readthen-status-vocabulary) | `src/lib.rs::dispatch_with_read` (intercepts before `map_decision`) | Host runs the plan via `read_host`, then re-dispatches `then` through the typed `{ req, rows, meta, carry }` crossing or legacy `{ req, rows_json, carry }` crossing based on compiled continuation metadata. The continuation may itself emit another `ReadThen` (sequential staged reads), bounded by `MAX_READ_HOPS = 8` → host 500. `Denied` → 403; `HostError` → 503. |
| Typed `ReadThen` crossing | Implemented | `src/read_continuation.rs`, `src/read_materialize.rs`, `src/read_dispatch.rs`, `src/lib.rs` | The host chooses between typed `{ req, rows, meta, carry }` and legacy `{ req, rows_json, carry }` from compiled continuation metadata. Typed rows reconcile host read policy to the app row type before continuation dispatch. Residual row mismatch maps to 502. P23 adds opt-in exact `Decimal[N]` crossing from host `Decimal{scale}` fields; scale drift fails closed as `projection_schema_drift`. |
| `StagedReadHost` | Implemented | `src/read_dispatch.rs` | Wraps a `CapabilityExecutorRegistry` + receipts; read idempotency key = `correlation_id` folded with a `plan_digest` (distinct queries never collide — `P12`). `Succeeded`→Rows, `Denied`→Denied(reason), other→HostError. |
| Final `InvokeEffect` via `MachineEffectHost` | Implemented (async mode) | `src/machine_runner.rs` → `igniter-server::effect_host::{dispatch, MachineEffectHost}` | In **async machine mode** a final `InvokeEffect` routes through `MachineEffectHost`. Executes for real **only** when a write host is wired (below); an unbound target fails closed to host **502**. In **default sync mode** `InvokeEffect` stays observed. |
| `host.toml` read/write/effects | Implemented | `src/host_config.rs` (`parse_host_config`/`load_host_config`/`resolve_host_config`) | Keys: `[host] mode` (`"loopback"` only); `[effects.<t>]` `route`(req)+`passport_env`(opt); `[postgres.read]` `dsn_env`(req)+`source`+`fields`+`row_limit`(def 100)+`capability`; `[postgres.read.<name>]` extra allowlisted `(source, fields)` (`P38`); `[postgres.write]` `dsn_env`(req)+`targets`+`ops`+`capability`+`key_column`(def `id`)+`columns`. Fail-closed on unknown section/key, inline secrets (`dsn`/`password`/`secret`/`token`/`passport`/`api_key`), template `*_env`, route w/o `/`, missing `route`/`dsn_env`, bad `mode`. `resolve_host_config` resolves every `*_env` **before** any socket bind. |
| Multi-table read allowlist | Implemented (`P38`) | `src/host_config.rs::PostgresReadConfig.extra_sources` | A primary `[postgres.read]` source **plus** one or more `[postgres.read.<name>]` sources (e.g. prove `accounts` exists, then list `todos`). Still a **single** read DSN; the adapter is source-generic, the policy gates each table. |
| Real Postgres read/write | Implemented under `postgres` | `src/host_binding.rs::{build_staged_read_host_from_resolved, build_write_host_from_resolved}` over `igniter_machine::postgres_real::{TokioPostgresReadAdapter, TokioPostgresWriteAdapter}` | Wired **only** under `--features postgres` **and** `--host-config` with matching sections. Without the feature the DSN still resolves but no executor is built (reads denied / `InvokeEffect` unbound). Write path also needs `[effects.*]` + a `passport_env` bearer token. |
| `host.example.toml` | Implemented (`P28`, refreshed `P38`/`P41`) | `examples/todo_postgres_app/host.example.toml` | Committed, commit-safe (env-var names only). Now wires `[postgres.read.accounts]`, `targets = todos`, `ops = insert,upsert,delete`, `capability = IO.TodoWrite`, and `[effects.todo-delete]` (`P44`). Guarded by unit test `committed_host_example_toml_parses`. |
| Runner diagnostics | Implemented (`P29`/`P30`) | `src/runner_diag.rs`, used by `src/bin/igweb-serve.rs` | See [Failure taxonomy](#failure-taxonomy) below. |

### Routing and ViewArtifact authoring

These are product-integrated IgWeb surfaces, not only design notes. The `.igweb` lowering lives in
`igniter-compiler::igweb::lower_igweb`; `server/igniter-web/src/lib.rs` calls it from the app builder,
then maps handler `Decision` variants to the server response path.

| Surface | Status | Where / proof |
| --- | --- | --- |
| `scope` + `resource` route sugar | Implemented | `lang/igniter-compiler/src/igweb.rs` composes prefixes/resources; `lang/igniter-compiler/tests/igweb_lowering_tests.rs::nested_resource_is_byte_identical_to_flat_and_compiles`; examples `todo_v2_app` and `todo_postgres_app`. |
| Nested composition + captures | Implemented | Same lowering path; tests assert nested account/todo captures and byte-identical flat output. |
| Route-level `via` | Implemented | `igweb.rs::Via` + lowering to static guard matches; `via_project_compiles_clean` and composite-guard tests. |
| Context `let` + single/same-name `guard` | Implemented | `igweb.rs::Binding`/`apply_bindings`; `ctx_let_guard_project_compiles_clean` and `ctx_accumulation_project_compiles_clean`. Distinct active guard names remain refused. |
| `Render` / raw HTML response | Implemented | `src/lib.rs::map_decision` `Render` arm -> `render_to_decision`; `render_html_app` / view tests cover content-type and body bytes. |
| `RenderView` / typed `ViewArtifact` records | Implemented | `src/lib.rs::map_decision` `RenderView` arm serializes the typed record and reuses the same renderer; `examples/todo_view_app` exercises typed authoring. |
| `RespondJson` / typed JSON body root | Implemented (`P50`) | `lang/igniter-compiler/src/igweb.rs` prelude declares `RespondJson { status : Integer, body : Unknown }`; `server/igniter-web/src/lib.rs::map_decision` serializes `body` as the JSON response root. | JSON-lane analogue of `RespondView`; not pagination-specific and not a global error envelope. Proof: Todo typed list route asserts no `{"body":...}` wrapper. |
| ViewArtifact `link` node | Implemented | `frame-ui/igniter-render-html/src/lib.rs::render_component` `kind == "link"`; `safe_url`; `todo_view_app` `MakeLink`/`TodoLinkHtml`. | Safe relative/http(s) anchors; unsafe schemes fail closed; labels and hrefs are escaped. |
| Flat link navigation | Proven with no new schema | `examples/todo_view_app::TodoNavHtml`; `todo_view_app_tests::nav_html_renders_detail_links_and_next_page_link`. | Index->detail links and `?after=` next-page links work as flat `HtmlNode` siblings. Bounded `list`/`item` layout remains held until grouping pressure appears. |
| Typed rows -> HTML | Implemented | `tests/fixtures/typed_html/typed_html.ig`; `tests/typed_html_tests.rs`; `tests/fixtures/db_money_report/db_money_report.ig`; `tests/db_money_report_tests.rs`. | Typed `ReadThen` rows + `DatasetMeta` feed `filter`/`map` into `HtmlNode` helpers, then `RenderView` returns escaped `text/html`. P24 proves DB-shaped `Decimal[2]` rows render exact money cells through `to_text` + `pad_left` and fold to an exact total. |
| Raw response / response envelope | Implemented | `map_decision` arms for `Respond`, `RespondError`, `Render`, and `RenderView`. App-authored `RespondError` is typed; host/framework errors keep their v0 shapes. |

### Todo API product path (`examples/todo_postgres_app`, cards `P35`-`P44`)

The generic surfaces above carry **one** product app end-to-end. App docs live in
`examples/todo_postgres_app/{API.md,RUNBOOK.md,host_policy.md}`; this is the status summary only.

| Product surface | Status | Where / notes |
| --- | --- | --- |
| Create request body | Implemented (`P35`) | Host crosses a JSON **object** body as `req.body_json : Map[String, Unknown]`; `.ig` reads `title` via `map_get_string`. `{"title":"…"}` is the canonical shape. Missing/non-string `title`, empty/blank title, or a non-object body → app-owned **400** (no write). `build_request_input` in `src/lib.rs`; `subprocess_non_string_create_body_writes_no_row`. |
| Legacy string create body | **Removed** (`P45`) | The bare JSON-**string** create body (P35 intro / P40 deprecation window) is removed: a non-object body fails closed to a 400. Object body `{ "title": … }` is the only accepted shape. `create_body_contract_object_only` lists the bare string under rejected shapes. |
| Todo resource id | Implemented (`P36`) | Host mints `surrogate_id = todo_<blake3(method␟path␟idempotency_key)>[..32]` (`src/lib.rs::surrogate_id`); `.ig` prefixes `todo_` and uses it as the business key. The **id is decoupled from the idempotency key** (receipts/dedup still key on the idempotency key). Deterministic across replay; leaks no body/secret. `surrogate_id_tests`. |
| Account-existence read semantics | Implemented (`P38`) | Two-stage read `FindAccount` → `CheckAccountThenList`: existing+rows → **200**; existing+empty → **200 `[]`**; missing account → app-owned **404**; denied source/field → host **403** (adapter not reached); adapter failure → host **503**. `local_account_existence_missing_404_and_existing_empty_200`. |
| Error envelope (`RespondError`) | Implemented (`P43`) | Typed IgWeb-prelude `RespondError { status, error: ApiError{code,message} }` + a `map_decision` arm → `{"error":{"code","message"}}`. App-authored errors (invalid body, account/todo not-found) carry it; framework-app errors (route-miss/405/keyless from the lowering) and host infra error shapes are unchanged. |
| Delete (`DELETE …/todos/:todo_id`) | Implemented (`P44`) | `AccountTodoDelete` → `BuildDeleteTodoIntent` (`operation: "delete"`, key = route `todo_id`) → `InvokeEffect{todo-delete}`. The write substrate's `delete` op was already seam-open (real adapter DELETE CTE + fake `remove`), gated by the host `ops` allowlist (`insert,upsert,delete`). Idempotent (absent row still commits; replay → no 2nd mutation); same key + different payload → **409**. Committed → **200**; row gone from later `show`/`list`. Proof: `write_delete_via_runner_200_removes_row_and_replay` (async HTTP through `MachineEffectHost`, DB-free), `local_delete_removes_existing_row_idempotently` (real adapter + DB), `delete_op_removes_business_row_idempotently` (fake substrate), and `scripts/todo_postgres_smoke.sh` (DELETE through the real binary → row removed, show → 404). |
| List keyset pagination + typed envelope (`?after=`) | Implemented (`P47`/`P50`) | List is ordered `id ASC`; `?after=<id>` adds a keyset filter `id > after` (Text range — enabled in `kind_allows_op`, real adapter pins `COLLATE "C"`). The Todo list route now uses typed `rows : Collection[TodoListRow]` + `DatasetMeta` and returns `RespondJson { body: { items, next } }`: `next` is the last row id when the page is host-cap truncated, else `""`. Query string parsed by the host (`parse_request` splits `?query` → `Request.query`; a query string used to break route matching). Proof: `local_keyset_pagination_pages_all_rows_once` (real DB, all rows once/ordered), `keyset_after_cursor_via_runner_filters_rows` (HTTP, DB-free), `text_keyset_range_and_order` (substrate), `parse_request_splits_query_from_path` (transport), `todo_postgres_api_read_tests`, `todo_postgres_async_runner_smoke_tests`. The single-todo **show** route is also typed (`P52`: Todo object body via `RespondJson`). **Deferred:** client `?limit=`, nested page metadata, and typed-`Bool` `done` adoption in the *shipped* API (the host `Boolean`→`.ig Bool` lane is proven DB-free in `P53`; the only missing piece is `host.toml` per-field typed-kind syntax). |
| DB-backed Decimal money report proof | Implemented as test fixture (`P24`) | `tests/fixtures/db_money_report/db_money_report.ig`; `tests/db_money_report_tests.rs`. | Host `Decimal{scale:2}` rows cross as `.ig Decimal[2]`, render via `to_text(amount)` + `pad_left(..., 8, " ")`, fold to exact total `1212.55`, and escape labels through the renderer. Test-only proof; not a product route, schema migration, currency formatter, or production report engine. |

### Package / admission front door

There is no package-local `IMPLEMENTED_SURFACE.md` for `igniter-compiler` yet. For current package truth,
start at:

- `lang/igniter-compiler/src/main.rs` for `igc package graph`, `pack`, `verify`, and `admit`.
- `lang/igniter-compiler/src/project.rs` for `admit_archive`, archive verification, and local graph logic.
- `lang/igniter-compiler/tests/package_lockfile_cli_tests.rs` and `package_workspace_tests.rs`.
- `lab-docs/lang/lab-igniter-package-graph-cli-p18-v0.md`,
  `lab-docs/lang/lab-igniter-package-archive-pack-verify-p22-v0.md`, and
  `lab-docs/lang/lab-igniter-package-remote-trust-p23-v0.md`.

Do not infer a registry, semver solver, signing layer, deployment permission, or package execution from
`package admit`; it is a deterministic local node-admission proof over a source `.igpkg`.

## Not implemented / intentionally closed

| Surface | Status | Note |
| --- | --- | --- |
| Public listener mode | Closed | Loopback-only; non-loopback bind is refused (`ServingPolicy::loopback_only`). |
| Stable CLI promise | Closed | `igweb-serve` is a lab prototype; flags may change. |
| Pool / backpressure | Closed | One connection at a time, bounded by `--max-requests`. |
| Schema migration runner | Closed | DDL is operator-owned; the runner never creates/migrates tables. |
| Typed rows in the shipped Todo JSON API routes | Adopted | Both Todo JSON read routes are typed: the **list** uses `rows : Collection[TodoListRow]` + `DatasetMeta` → `{items,next}` via `RespondJson` (P50); the **show** uses the same typed crossing → the Todo object body via `RespondJson` (P52). No product route uses the legacy `rows_json` continuation any more (`rows_json` remains only the generic runner's back-compat lane). |
| Stronger typed projection landings | Partly implemented / still bounded | v0 typed rows support String/Text/Integer/Bool plus limited Map/Collection[String]; P23 adds opt-in exact `Decimal[N]` crossing from host `Decimal{scale}`. The typed `Bool` `done` lane (host `Boolean`→`.ig Bool`→`filter` both directions→typed summary, with drift fail-closed both directions) is **proven DB-free** (`P53`), but is NOT yet adopted in the shipped Todo API because `host.toml` cannot express per-field typed read kinds — that config syntax is the named follow-on. Timestamp, nested records/Json, and a generic `Dataset[T]` envelope remain future slices. |
| Global protocol error envelope | Not implemented (deferred) | App-authored errors use the typed `RespondError` envelope (`P43`); a cross-crate envelope unifying host shapes too stays deferred. |
| Multi-DSN reads / cross-DB joins | Not implemented | Multi-**table** allowlist exists (`extra_sources`), but a single read DSN and no join planner. |
| App/export-specific file delivery | Not implemented | `ResponseBody::Raw` and HTML bytes exist, but content-disposition policy, storage handoff, streaming, and format-specific exporters remain separate work. |
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

# Implemented-surface doc guard:
cargo test --features machine --test implemented_surface_guard_tests

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

# Typed rows + boot diagnostics + typed HTML:
cargo test --features machine --test typed_readthen_tests --test typed_html_tests --test boot_diagnostic_tests
#   typed_readthen_tests: typed lane auto-routes rows + DatasetMeta; legacy rows_json remains green;
#                         drift fails before dispatch; row mismatch maps to 502.
#   boot_diagnostic_tests: source-independent continuation shape errors fail `igweb-serve check`
#                          with PROJECTION_SCHEMA_INVALID exit 12 before bind.
#   typed_html_tests: typed rows + DatasetMeta -> HtmlNode helpers -> RenderView -> escaped text/html.

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
