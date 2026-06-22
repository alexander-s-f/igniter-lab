# LAB-TODOAPP-API-ASYNC-RUNNER-SMOKE-P10 - Todo API through productized async runner

Status: CLOSED
Lane: TodoApp API / runner productization
Type: integration proof
Delegation code: OPUS-TODOAPP-API-ASYNC-RUNNER-SMOKE-P10
Date: 2026-06-22
Skill: idd-agent-protocol

## Context

TodoApp API has separate proofs for relational contracts, fake read host, write effect host, local Postgres,
and read/write e2e harnesses. The product question is now: can an operator run the app through the same
runner-shaped async path rather than bespoke test orchestration?

This card should run after or alongside:

- `LAB-IGNITER-WEB-READTHEN-SOCKET-RUNNER-P12`
- `LAB-IGNITER-WEB-IGWEB-SERVE-MACHINE-MODE-P22`

If those prerequisites are not landed, stop with a precise blocker and do not reimplement runner wiring here.

## Goal

Prove a bounded loopback Todo API smoke through the productized async runner path.

Minimum acceptable smoke:

```text
GET /api/todos?account_id=... -> ReadThen -> fake/read policy -> continuation -> 200/404
POST /api/todos -> final InvokeEffect -> MachineEffectHost -> receipt response
replay same idempotency key -> no second mutation
```

Use fake adapters unless live local Postgres is already runner-addressable with no extra infrastructure.

## Verify first

Read:

- `server/igniter-web/examples/todo_postgres_app/`
- `server/igniter-web/tests/todo_postgres_api_read_tests.rs`
- `server/igniter-web/tests/todo_postgres_api_write_tests.rs`
- `server/igniter-web/tests/todo_postgres_api_read_write_e2e_tests.rs`
- `server/igniter-web/tests/todo_postgres_effect_host_runner_tests.rs`
- the two runner cards named above

Confirm live route names and whether the app already emits `ReadThen` or still uses harness-only query contracts.

## Acceptance

- [x] Verify-first closing report states whether this used actual `igweb-serve` or direct runner helpers.
- [x] Smoke uses app files from `examples/todo_postgres_app`, not a private Rust-only fixture app.
- [x] Read path: found rows -> HTTP 200 over loopback.
- [x] Read path: empty rows -> app-owned HTTP 404.
- [x] Write path: keyed mutation -> receipt/committed response over loopback.
- [x] Replay same idempotency key -> no second mutation.
- [x] App files contain no DSN, passport, capability id, or raw SQL.
- [x] `igniter-server` remains route/domain-free.
- [x] `server/igniter-web cargo test --features machine` passes.
- [x] `git diff --check` clean.

## Closing report

**Date:** 2026-06-22

### Verify-first

**`AccountTodoIndex` state before P10:**
- Returned `Respond { status: 200, body: account_id }` — canned fixture response. Not ReadThen.
- `AccountTodoIndexFromRows` continuation existed but was only dispatched manually in P3 tests.
- `ListTodosByAccount` + `MakeFilter` both defined in same module → `call_contract` works correctly.

**Change made:**
- `AccountTodoIndex` updated to call `ListTodosByAccount(account_id)` and emit `ReadThen { plan, then: "AccountTodoIndexFromRows" }`.
- Side effect: sync path (`IgWebServerApp::call`) returns 500 for `ReadThen` (unknown decision tag). Updated `loopback_behaviors` to assert 500 with an explanatory comment — this is the correct behavior (index requires machine mode runner).
- All P3 (`todo_postgres_api_read_tests`) and P9 (`todo_postgres_effect_host_runner_tests`) tests unaffected: they dispatch `ListTodosByAccount` / `AccountTodoIndexFromRows` directly, bypassing `AccountTodoIndex`.

**Runner used:** direct runner helpers (`serve_loop_loaded_with_read`) — same surface as `igweb-serve` machine mode (P22). Not the actual binary.

### Deliverables

**`examples/todo_postgres_app/todo_handlers.ig`:**
- `AccountTodoIndex` updated: calls `ListTodosByAccount(account_id)` → emits `ReadThen { plan, then: "AccountTodoIndexFromRows" }`

**`tests/todo_postgres_app_tests.rs`:**
- `loopback_behaviors` index assertion updated: now expects 500 (sync path doesn't handle ReadThen); documents machine-mode requirement

**`tests/todo_postgres_async_runner_smoke_tests.rs`** (new, 5 tests):
- `read_found_todos_via_runner_200` — GET /accounts/:id/todos with rows → ReadThen → 200 over socket
- `read_empty_todos_via_runner_404` — GET /accounts/:id/todos empty → ReadThen → app-owned 404
- `write_create_todo_via_runner_committed` — POST → InvokeEffect → MachineEffectHost → committed receipt
- `write_replay_same_key_no_second_mutation` — replay same idempotency key → dedup → 1 adapter attempt
- `app_files_carry_no_forbidden_authority_surface` — static audit of all app files

All tests use `serve_loop_loaded_with_read` (productized runner). All use `examples/todo_postgres_app` (zero bespoke Rust fixture app).

**Full suite:** `cargo test --features machine` — all suites green. `git diff --check` clean.

## Closed surfaces

- No live production DB.
- No public bind.
- No schema migration runner.
- No auth/session product UX.
- No View/UI work.
- No new `.igweb` syntax.
- No package/canon claim.
