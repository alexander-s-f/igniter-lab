# LAB-TODOAPP-API-ERROR-ENVELOPE-IMPL-P43 - implement the app-scoped typed error envelope

Status: CLOSED (2026-06-24) — app-scoped typed `RespondError` envelope implemented + proven (machine suite + real-PG e2e + full smoke)
Lane: TodoApp API / product surface / error contract
Type: implementation + proof
Date: 2026-06-24
Skill: idd-agent-protocol

## Context

`LAB-TODOAPP-API-NEXT-PRODUCT-SLICE-READINESS-P42` recommended this slice; `P39`
(`lab-docs/lang/lab-todoapp-api-error-envelope-readiness-p39-v0.md`) locked the design: a small,
**app-scoped** typed error envelope. Today app-authored errors carry `{"body": "<message>"}` (same
shape as a success body), so a client cannot machine-read an error code. `map_decision`
(`src/lib.rs`) has arms `Respond/RespondView/InvokeEffect/Render/RenderView` — no `RespondError`.

This card promotes the design into real code for the **app side only**. Host-owned shapes
(`{"error":…}` ingress/read, write-outcome `{"status","detail",…}`) stay unchanged; no cross-crate
change to igniter-server/igniter-machine; no canon claim.

## Verify First

- `lang/igniter-compiler/src/igweb.rs` (`PRELUDE_SOURCE`, `variant Decision`)
- `server/igniter-web/src/lib.rs` (`map_decision`, `variant_of`)
- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig` (app-authored error `Respond` sites)
- `server/igniter-web/tests/todo_error_contract_tests.rs`
- `server/igniter-web/tests/todo_postgres_local_e2e_tests.rs` (account-existence asserts)
- `server/igniter-web/examples/todo_postgres_app/API.md`, `IMPLEMENTED_SURFACE.md`

## Scope (app-authored errors only)

Convert these `todo_handlers.ig` sites from `Respond {status, body}` to `RespondError {status, error}`:

- create-body 400 (`AccountTodoCreate`) → code `invalid_body`
- account-not-found 404 (`LoadAccountTodos`, `LoadTodoContext`, `CheckAccountThenList`) → `account_not_found`
- todo-not-found 404 (`LoadTodoContext`, `AccountTodoShowFromRows`) → `todo_not_found`

Framework-generated errors (route-miss 404, method 405, keyless 400 from the `.igweb` lowering) and all
host-owned errors stay as-is. Messages are preserved verbatim (only wrapped).

## Acceptance

- [x] Prelude adds `type ApiError { code, message }` and `Decision` arm `RespondError { status : Integer, error : ApiError }`.
- [x] `map_decision` gains a `RespondError` arm → `{"error":{"code","message"}}` at `status`; other arms unchanged.
- [x] App-authored 400/404 errors in `todo_handlers.ig` lowered to `RespondError` with stable codes.
- [x] Host-owned shapes unchanged; no igniter-server/igniter-machine change.
- [x] No status-code changes — only app error body shape.
- [x] `todo_error_contract_tests.rs` + `todo_postgres_local_e2e_tests.rs` updated to the envelope; no leak checks preserved.
- [x] `API.md` error table + `IMPLEMENTED_SURFACE.md` updated (`RespondError` designed → implemented).
- [x] No new DB op/adapter/predicate/migration; `git diff --check` clean.

## Closed Surfaces

- No host/runner error-shape changes; no global protocol envelope (that stays deferred).
- No new endpoints, DB ops, or migrations. No canon claim.

## Closing Report (2026-06-24)

**Prelude + decision arm.** `lang/igniter-compiler/src/igweb.rs` `PRELUDE_SOURCE`: added
`type ApiError { code, message }` and `Decision` arm `RespondError { status : Integer, error : ApiError }`
(additive — other IgWeb apps unaffected). `server/igniter-web/src/lib.rs` `map_decision`: added a
`RespondError` arm serializing `{"error": {"code","message"}}` at the given status (the `error` record is
discriminant-free, serialized clean). Other arms untouched.

**App sites converted** (`examples/todo_postgres_app/todo_handlers.ig`): added `MakeApiError` factory
(mirrors `MakeWriteValues`); lowered 6 app-authored error sites to `RespondError` with stable codes —
`invalid_body` (create 400, `AccountTodoCreate`), `account_not_found` (`LoadAccountTodos`,
`LoadTodoContext`, `CheckAccountThenList`), `todo_not_found` (`LoadTodoContext`, `AccountTodoShowFromRows`).
Messages preserved verbatim. Framework-app errors (route-miss/405/keyless from the `.igweb` lowering) and
all host-owned shapes were intentionally left unchanged (app-scoped per P39).

**Tests/docs.** Updated `tests/todo_error_contract_tests.rs` (`invalid_create_body_is_400` → envelope +
header note) and `tests/todo_postgres_local_e2e_tests.rs` (account-existence 404 → `error.code/message`).
Substring asserts in `todo_postgres_async_runner_smoke_tests.rs` (`contains("account not found")` /
`"todo not found"`) still hold (message preserved). `API.md` error contract → three owner shapes + typed
rows; `IMPLEMENTED_SURFACE.md` → `RespondError` designed→implemented.

**Evidence (all green).**
- `cargo test --features machine` — 18/18 test binaries ok (no regression across all IgWeb apps).
- `IGNITER_TODO_PG_DSN=… cargo test --features postgres --test todo_postgres_local_e2e_tests -- --test-threads=1` — 13/13 (incl. account-existence envelope + create-400 envelope subprocess).
- `scripts/check_todo_product_surface.sh` — PASS (doc markers + smoke preflight).
- full `scripts/todo_postgres_smoke.sh` (local DB) — PASS 14/14 (404 path exercises `RespondError`).
- `git diff --check` — clean. No DB op/adapter/migration; no igniter-server/igniter-machine change.

**Follow-up.** `LAB-TODOAPP-API-DELETE-P44` (next product slice; calls out the DELETE write-op substrate);
the global cross-crate protocol envelope stays deferred.
