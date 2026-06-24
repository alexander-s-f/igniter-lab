# LAB-TODOAPP-API-DELETE-P44 - implement Todo delete product slice

Status: CLOSED (2026-06-24) — Todo delete slice implemented + proven (real-PG e2e + async HTTP + operator smoke, all green)
Lane: TodoApp API / product surface
Type: implementation + proof
Date: 2026-06-24
Skill: idd-agent-protocol

## Context

P43 implemented the app-scoped error envelope. The next product slice is DELETE. This is not just an
endpoint: `MachineEffectHost` / the Postgres write adapter currently support `insert`/`upsert`, not
`delete`, so it forces a new write-substrate operation. `run_write_effect` is operation-agnostic (the
receipt gate / dedup / payload-conflict logic is the same for any op), so the new op lives in:
the write **policy allowlist**, the **adapter** (`transact` SQL), and the **app intent + route**.

## Goal

Account-scoped Todo delete: `DELETE /accounts/:account_id/todos/:todo_id`.

## Verify First (done)

- `runtime/igniter-machine/src/{write.rs,postgres_write.rs,postgres_real.rs}` — write runner, policy,
  fake + real adapter (`transact` builds a writable-CTE `ins`+`biz`; op-agnostic gate).
- `server/igniter-web/src/host_binding.rs` — `build_write_policy` already threads `ops` → policy;
  `bind_targets` already covers every `[effects.*]` (no change needed).
- `lang/igniter-compiler/src/igweb.rs` — `member <METHOD> "<suffix>"` forwards an arbitrary method;
  method-chain lowers `if req.method == "DELETE"` (no method allowlist).
- `examples/todo_postgres_app/{todo_handlers.ig,routes.igweb,host.example.toml,API.md,RUNBOOK.md}`.

## Decisions

- **Success status: 200** (consistent with create/done committed `InvokeEffect` → 200).
- **Idempotent delete**: a well-formed but absent todo still commits (DELETE affects 0 rows) → 200; the
  guard `LoadTodoContext` only 404s an empty route capture. "No longer appears" is proven by the real
  read paths: after delete, `show` (FindTodo ReadThen) → 404, `list` → row gone.
- Delete intent `values` are empty (`""`); the real DELETE adapter ignores values entirely.

## Requirements / Acceptance

- [x] `member DELETE "/:todo_id"` route → `AccountTodoDelete` via `LoadTodoContext` + `requires idempotency`.
- [x] `BuildDeleteTodoIntent` (op `delete`, target `todos`, key `todo_id`); no raw SQL in `.ig`.
- [x] Write policy/adapter gate + perform `delete`: `transact` adds a DELETE `biz` CTE under the same
      `ins` effect-receipt gate; fake adapter models delete as row removal.
- [x] host config: `[effects.todo-delete]` + `ops` includes `delete`.
- [x] Idempotency preserved: replay same key → no second mutation; same key + different payload → 409.
- [x] Missing account/todo (empty capture) → app-owned `RespondError`; host failures keep host shape.
- [x] Deleted todo no longer appears in list/show.
- [x] Docs (API.md, RUNBOOK, host_policy.md, web + machine IMPLEMENTED_SURFACE) + smoke/product checks updated.
- [x] No migration (reuses `todos`/`effect_receipts`); real local-PG e2e green (env available); `git diff --check` clean.

## Closed Surfaces

- No new endpoints beyond delete; no schema migration; no canon claim; no global protocol envelope.

## Closing Report (2026-06-24)

**Key finding (verify-first): the *gate* was op-agnostic, but the *adapters* needed a real delete op.**
`run_write_effect` and the effect-receipt gate are operation-agnostic, so idempotency/dedup/conflict were
inherited for free. But the write adapters were insert/upsert-only and DID need changes (igniter-machine
was in scope, as the card predicted):
- `postgres_real.rs::transact` now branches on `intent.operation`: `delete` swaps the business CTE for
  `DELETE FROM {target} WHERE {key}=$5 AND EXISTS (SELECT 1 FROM ins)` under the SAME `ins`
  effect-receipt gate (so delete inherits the identical two-layer idempotency; absent row → fresh
  receipt → Committed). The insert/upsert path is unchanged.
- `postgres_write.rs` (`FakePostgresWriteAdapter`): the Commit branch now REMOVES the business row when
  `operation == "delete"` (was insert-only).
With the adapters delete-capable, the rest was host `ops` policy + an app route/handler.

**Components (app + host config + tests + docs):**
- App: `BuildDeleteTodoIntent` (`operation:"delete"`, target `todos`, key = route `todo_id`, empty
  values) + `AccountTodoDelete` handler (`InvokeEffect{todo-delete}`), guarded by `LoadTodoContext`
  (empty capture → `RespondError` 404). No raw SQL in `.ig`.
- Route: `member DELETE "/:todo_id" … requires idempotency` (the lowering already forwards any verb).
- Host config: `[effects.todo-delete]` + `ops = insert,upsert,delete`; test/policy helpers allow `delete`.
- Success status = **200** (consistent with create/done committed `InvokeEffect`); idempotent (absent
  row still commits); replay → no 2nd mutation; same key + different payload → **409**.

**Evidence (all green):**
- Real-PG e2e `local_delete_removes_existing_row_idempotently` — delete commits, row gone, replay no 2nd
  mutation, same-key-different-payload → Denied(409). `cargo test --features postgres --test todo_postgres_local_e2e_tests -- --test-threads=1` → 14/14.
- DB-free async HTTP through the runner: `write_delete_via_runner_200_removes_row_and_replay`
  (`tests/todo_postgres_async_runner_smoke_tests.rs`) — DELETE → 200 through `MachineEffectHost` + the
  fake adapter's DELETE branch; row removed, replay deduped. (Proves the `todo-delete` effect-host binding
  without a DB.)
- DB-free substrate `delete_op_removes_business_row_idempotently`
  (`runtime/igniter-machine/tests/postgres_write_tests.rs`) — fake adapter: delete removes the row
  (`business_row_count` 0), replay deduped (attempts 2). Fake suite 11/11; real `postgres_real_write_tests`
  5/5 (insert/upsert regression-clean). igniter-web `--features machine` suite green.
- Operator smoke (real local DB) — **delete → 200, delete replay → 200, show after delete → 404, db row
  count 0, delete replay one receipt** (19/19 PASS).
- `scripts/check_todo_product_surface.sh` PASS (added a `DELETE /accounts` doc marker).
- Docs: API.md route row, RUNBOOK, host_policy.md, web + machine `IMPLEMENTED_SURFACE.md` all carry delete.
- `git diff --check` clean. No schema migration (reuses `todos`/`effect_receipts`). No canon claim.

**Follow-up:** legacy string create-body removal (`LAB-TODOAPP-API-CREATE-BODY-LEGACY-REMOVAL`); the global
cross-crate protocol error envelope stays deferred.
