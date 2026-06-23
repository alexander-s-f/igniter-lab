# LAB-TODOAPP-API-LIST-EMPTY-SEMANTICS-P24 - list empty vs not-found semantics

Status: TODO
Lane: TodoApp API / product semantics
Type: product decision + implementation
Delegation code: OPUS-TODOAPP-API-LIST-EMPTY-SEMANTICS-P24
Date: 2026-06-23
Skill: idd-agent-protocol

## Context

The current Todo API returns 404 for an empty list:

```ig
AccountTodoIndexFromRows(rows_json == "[]") -> Respond { status: 404, body: "no todos" }
```

That was useful while proving `ReadThen` and app-owned not-found decisions, but a real API usually treats:

- `GET /accounts/:id/todos` with zero todos as **200 []**;
- missing account as **404**.

The current guard only checks "capture is non-empty"; it does not read accounts from the DB. That means the
app cannot currently distinguish "account exists with no todos" from "account missing" through the list query.

## Goal

Decide and implement the correct v0 product semantics for list-empty.

Preferred v0 unless verify-first finds a better existing path:

- list empty returns **200 []**;
- account existence remains a separate future read/guard problem;
- docs clearly state that v0 does not verify account existence on list beyond the route capture.

## Verify first

Read:

- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`
- `server/igniter-web/examples/todo_postgres_app/API.md`
- `server/igniter-web/examples/todo_postgres_app/RUNBOOK.md`
- tests mentioning `"no todos"` or list 404:
  - `server/igniter-web/tests/todo_postgres_*`
  - `server/igniter-web/tests/readthen_*`

Do not assume old docs are current; live handlers decide behavior.

## Plan

1. Characterize current tests expecting list-empty 404.
2. Change `AccountTodoIndexFromRows` to return 200 with `rows_json` for `[]`.
3. Update API/RUNBOOK wording and test names/expectations.
4. Keep `show` not-found as 404.
5. If account-existence semantics need a future card, write it as a short follow-up in the closing report.

## Acceptance

- [ ] `GET /accounts/:account_id/todos` with no rows returns 200 and body contains `[]`.
- [ ] `GET /accounts/:account_id/todos/:todo_id` with no row still returns 404 `todo not found`.
- [ ] API.md documents list-empty semantics clearly.
- [ ] RUNBOOK does not claim empty list is 404.
- [ ] Existing read-denied 403 and host-error 503 behavior unchanged.
- [ ] `scripts/check_implemented_surface.sh` PASS.
- [ ] `cargo test --features machine` PASS.
- [ ] `cargo test --features postgres --test todo_postgres_local_e2e_tests -- --test-threads=1` passes or skips cleanly without DSN.
- [ ] `git diff --check` clean.

## Closed surfaces

- No account table read guard in this card.
- No typed row destructuring.
- No schema migrations.
- No generated ids.

