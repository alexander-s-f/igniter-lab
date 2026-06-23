# LAB-TODOAPP-API-SHOW-READTHEN-P14 - make Todo show route a real read

Status: CLOSED
Lane: TodoApp API / product correctness / ReadThen
Type: implementation + proof
Delegation code: OPUS-TODOAPP-API-SHOW-READTHEN-P14
Date: 2026-06-23
Skill: idd-agent-protocol

## Context

The TodoApp API runner path is now real:

- `ReadThen` implemented and documented in `server/igniter-web/IMPLEMENTED_SURFACE.md`.
- `igweb-serve --host-config` wires real Postgres reads/writes under `postgres`.
- `todo_postgres_app` list route already uses `ReadThen`.

Current product gap:

`GET /accounts/:account_id/todos/:todo_id` still returns the path param (`todo_id`) directly:

```ig
pure contract AccountTodoShow {
  input req : Request
  input ctx : TodoCtx
  compute d : Decision = Respond { status: 200, body: or_else(ctx.todo_id, "none") }
  output d : Decision
}
```

That is useful for routing proof, but not a product API read.

## Goal

Change the Todo show route to use the existing `FindTodo(account_id, todo_id) -> QueryPlan` and a
new continuation, so the route behaves like a real read:

```text
GET /accounts/:account_id/todos/:todo_id
  -> FindTodo QueryPlan
  -> ReadThen { plan, then: "AccountTodoShowFromRows" }
  -> rows_json
  -> 200 with row JSON OR app-owned 404 on []
```

## Verify first

Read live surfaces:

- `server/igniter-web/IMPLEMENTED_SURFACE.md`
- `server/igniter-web/examples/todo_postgres_app/routes.igweb`
- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`
- `server/igniter-web/tests/todo_postgres_api_read_tests.rs`
- `server/igniter-web/tests/todo_postgres_async_runner_smoke_tests.rs`
- `server/igniter-web/tests/todo_postgres_local_e2e_tests.rs`
- `server/igniter-web/src/read_dispatch.rs`

Confirm whether `FindTodo` is already correct and whether a generic rows-json continuation can be reused
or should stay explicit for product readability.

## Implementation bias

Prefer a new explicit continuation:

```ig
pure contract AccountTodoShowFromRows {
  input req       : Request
  input rows_json : String
  compute d : Decision = if rows_json == "[]" {
    Respond { status: 404, body: "todo not found" }
  } else {
    Respond { status: 200, body: rows_json }
  }
  output d : Decision
}
```

Then update `AccountTodoShow` to build `FindTodo` and return `ReadThen`.

## Acceptance

- [x] Closing report states old behavior vs new behavior.
- [x] `AccountTodoShow` no longer returns the raw path param as the response body.
- [x] `FindTodo` query plan is used for show.
- [x] Empty rows map to app-owned 404 (`todo not found` or documented equivalent).
- [x] Found row maps to 200 and carries row JSON including the requested todo id/title.
- [x] Sync/default mode behavior is updated intentionally: show now emits `ReadThen` and therefore needs machine mode, same as index.
- [x] Existing list/index read behavior remains green.
- [x] `cargo test --features machine` in `server/igniter-web` passes.
- [x] `cargo test --features postgres --test todo_postgres_local_e2e_tests -- --test-threads=1` passes or skips cleanly without DSN.
- [x] `scripts/check_implemented_surface.sh` remains PASS.
- [x] `git diff --check` clean.

## Closed surfaces

- No typed row destructuring.
- No new `.igweb` syntax.
- No raw SQL.
- No schema migration runner.
- No public/stable CLI claim.

## Closing report

**Date:** 2026-06-23

### Old vs new behavior

- **Before:** `GET /accounts/:account_id/todos/:todo_id` → `AccountTodoShow` returned
  `Respond { status: 200, body: or_else(ctx.todo_id, "none") }` — it echoed the path param. Useful as a
  routing/guard proof, not a product read.
- **After:** `AccountTodoShow` builds the existing `FindTodo(account_id, todo_id) -> QueryPlan` from the
  guard-loaded context and returns `ReadThen { plan, then: "AccountTodoShowFromRows" }`. The host runs
  the read; the new `AccountTodoShowFromRows(req, rows_json)` continuation maps `"[]"` → app-owned 404
  (`todo not found`) and a found row → 200 carrying the row JSON. Exactly mirrors the index pair
  (`AccountTodoIndex` / `AccountTodoIndexFromRows`).

`FindTodo` was already correct (filters `account_id eq` + `id eq`, projection `id,account_id,title,done`,
limit 1) — no change needed. The continuation is kept explicit (not a shared generic) for product
readability, matching the index continuation.

### Files changed

- **M** `examples/todo_postgres_app/todo_handlers.ig` — new `AccountTodoShowFromRows` continuation;
  `AccountTodoShow` rewritten to emit `ReadThen { FindTodo plan }`.
- **M** `tests/todo_postgres_app_tests.rs` — sync `loopback_behaviors` show assertion updated: show now
  emits `ReadThen` so the sync path returns **500** (machine-mode only), same as index (was 200/"42").
- **M** `tests/todo_postgres_async_runner_smoke_tests.rs` — new machine-mode socket proofs
  `show_found_todo_via_runner_200` (found row → 200, body carries `t1`/`Buy milk`, not the path param)
  and `show_missing_todo_via_runner_404` (empty rows → app-owned 404 `todo not found`), plus a
  `get_todo_show` HTTP helper. Both use the fake adapter (no DB).

No `.igweb`/syntax/SQL/schema changes; no typed row destructuring.

### Acceptance

- `AccountTodoShow` no longer returns the raw path param; uses `FindTodo` plan via `ReadThen`.
- Empty rows → app-owned 404 (`todo not found`); found row → 200 with row JSON (id + title).
- Sync/default mode intentionally updated: show now needs machine mode (sync → 500), same as index.
- Existing index/list read behavior remains green (`read_found`/`read_empty` unchanged).
- `cargo test --features machine` green (full suite; new show tests pass).
- `cargo test --features postgres --test todo_postgres_local_e2e_tests -- --test-threads=1` → 8 pass
  with DSN (app still compiles/serves after the change); skips cleanly without DSN.
- `scripts/check_implemented_surface.sh` → PASS.
- `git diff --check` clean.

### Scope honored

No typed row destructuring, no new `.igweb` syntax, no raw SQL, no migration runner, no public/stable
CLI claim.
