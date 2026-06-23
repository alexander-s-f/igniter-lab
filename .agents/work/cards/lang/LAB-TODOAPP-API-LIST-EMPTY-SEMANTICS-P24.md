# LAB-TODOAPP-API-LIST-EMPTY-SEMANTICS-P24 - list empty vs not-found semantics

Status: CLOSED
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

- [x] `GET /accounts/:account_id/todos` with no rows returns 200 and body contains `[]`.
- [x] `GET /accounts/:account_id/todos/:todo_id` with no row still returns 404 `todo not found`.
- [x] API.md documents list-empty semantics clearly.
- [x] RUNBOOK does not claim empty list is 404.
- [x] Existing read-denied 403 and host-error 503 behavior unchanged.
- [x] `scripts/check_implemented_surface.sh` PASS.
- [x] `cargo test --features machine` PASS.
- [x] `cargo test --features postgres --test todo_postgres_local_e2e_tests -- --test-threads=1` passes or skips cleanly without DSN.
- [x] `git diff --check` clean.

## Closing report

**Date:** 2026-06-23
**Outcome:** Implemented. Empty list now returns **`200 []`** (was 404); show-missing stays 404.

### Change

`AccountTodoIndexFromRows` ([todo_handlers.ig](../../../../server/igniter-web/examples/todo_postgres_app/todo_handlers.ig))
simplified from `if rows_json == "[]" { 404 } else { 200 }` to an unconditional
`Respond { status: 200, body: rows_json }` — a list is a collection, an empty one is a valid 200.

### Scope decision (what was NOT touched, and why)

Only tests driving the **product** app (`todo_postgres_app` / `AccountTodoIndexFromRows`) were updated.
The generic mechanism fixtures — `tests/fixtures/read_then_fixture/read_then_fixture.ig` (used by
`readthen_dispatch_tests` / `readthen_socket_runner_tests`) and `tests/fixtures/read_harness/read_harness.ig`
(used by `todo_postgres_read_host_tests`) — keep their `empty → 404` because they prove the *capability*
"a continuation can own a 404", not the Todo product decision. Those are asserted by
`check_implemented_surface.sh`, which stays PASS.

### Product tests updated (404 → 200 [])

- `todo_postgres_api_read_tests::product_todos_index_empty_returns_200_empty_list`
- `todo_postgres_api_read_write_e2e_tests` (empty path → 200 [])
- `todo_postgres_async_runner_smoke_tests::read_empty_todos_via_runner_200_empty_list`
- `igweb_serve_machine_mode_tests::machine_mode_readthen_empty_rows_http_200_empty_list`
- `todo_igweb_serve_e2e_tests::e2e_read_empty_via_host_config_200_empty_list`
- `todo_postgres_local_e2e_tests`: `local_read_empty_returns_200_empty_list`, the subprocess e2e empty
  assertion, and the P23 freshness test (now: first read `200 []` with no row, post-write read `200`
  carrying the row — still proves the empty result was not replayed).

### Follow-up (out of scope)

Distinguishing "account exists, no todos" (`200 []`) from "no such account" (would be `404`) needs an
**accounts-table existence read/guard** — not done here (the card closes "no account table read guard").
Documented in API.md's new "List-empty semantics" section. Candidate next card:
`LAB-TODOAPP-API-ACCOUNT-EXISTENCE-GUARD-Pxx`.

### Verification

`cargo test --features machine`: all suites green. `cargo test --features "machine postgres" --test
todo_postgres_local_e2e_tests`: 12 pass against real PG, skips cleanly w/o DSN. Default build green.
`check_implemented_surface.sh` PASS. `git diff --check` clean.

## Closed surfaces

- No account table read guard in this card.
- No typed row destructuring.
- No schema migrations.
- No generated ids.

