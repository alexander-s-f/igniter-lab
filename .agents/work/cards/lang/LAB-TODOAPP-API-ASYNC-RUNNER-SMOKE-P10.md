# LAB-TODOAPP-API-ASYNC-RUNNER-SMOKE-P10 - Todo API through productized async runner

Status: OPEN
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

- [ ] Verify-first closing report states whether this used actual `igweb-serve` or direct runner helpers.
- [ ] Smoke uses app files from `examples/todo_postgres_app`, not a private Rust-only fixture app.
- [ ] Read path: found rows -> HTTP 200 over loopback.
- [ ] Read path: empty rows -> app-owned HTTP 404.
- [ ] Write path: keyed mutation -> receipt/committed response over loopback.
- [ ] Replay same idempotency key -> no second mutation.
- [ ] App files contain no DSN, passport, capability id, or raw SQL.
- [ ] `igniter-server` remains route/domain-free.
- [ ] `server/igniter-web cargo test --features machine` passes.
- [ ] `git diff --check` clean.

## Closed surfaces

- No live production DB.
- No public bind.
- No schema migration runner.
- No auth/session product UX.
- No View/UI work.
- No new `.igweb` syntax.
- No package/canon claim.
