# LAB-TODOAPP-API-IGWEB-SERVE-E2E-P11 - Todo API through actual igweb-serve machine mode

Status: OPEN
Lane: TodoApp API / runner productization
Type: integration proof
Delegation code: OPUS-TODOAPP-API-IGWEB-SERVE-E2E-P11
Date: 2026-06-22
Skill: idd-agent-protocol

## Context

P10 proved Todo API read/write through productized async runner helpers:

- read found -> 200
- read empty -> app-owned 404
- write -> committed receipt
- replay -> no second mutation

But it explicitly did **not** use the actual `igweb-serve` binary. P22 added `--host-config` machine mode;
P23/P24 should wire staged reads and host bindings into that operator path.

This card is the product smoke: prove the developer/operator command shape.

## Goal

Run `examples/todo_postgres_app` through actual `igweb-serve --host-config` in a bounded loopback test and
exercise Todo API read/write behavior.

Target command shape:

```text
cargo run --features machine --bin igweb-serve -- \
  --host-config <tmp-host.toml> \
  --addr 127.0.0.1:0 \
  --max-requests N \
  examples/todo_postgres_app
```

If spawning the binary is too brittle in Cargo tests, use the same binary entrypoint/core function and state
that clearly. Do not fall back to the old bespoke harness without naming the blocker.

## Prerequisites

Run after:

- `LAB-IGNITER-WEB-IGWEB-SERVE-READTHEN-P23`
- `LAB-IGNITER-WEB-HOST-CONFIG-EFFECT-BINDINGS-P24`

If either is not closed, stop with a precise dependency report.

## Verify first

Read:

- `server/igniter-web/src/bin/igweb-serve.rs`
- `server/igniter-web/examples/todo_postgres_app/`
- `server/igniter-web/tests/todo_postgres_async_runner_smoke_tests.rs`
- `server/igniter-web/tests/igweb_serve_machine_mode_tests.rs`
- `server/igniter-web/tests/readthen_socket_runner_tests.rs`
- latest P23/P24 closing reports

Confirm:

- exact Todo routes for read and write;
- whether app files already emit `ReadThen` for index;
- how host config builds fake or real read/write hosts;
- how to make the binary exit deterministically (`--max-requests`).

## Acceptance

- [ ] Closing report states whether the proof spawned actual `igweb-serve` or used extracted binary core.
- [ ] Uses `server/igniter-web/examples/todo_postgres_app`, not a private Rust-only app.
- [ ] Uses a temporary `host.toml`; no secrets are written inline.
- [ ] Read found -> HTTP 200 over loopback.
- [ ] Read empty -> app-owned HTTP 404 over loopback.
- [ ] Write keyed create/done -> committed receipt over loopback.
- [ ] Replay same idempotency key -> no second mutation.
- [ ] `--max-requests` exits deterministically; no daemon left running.
- [ ] App files contain no DSN, passport, capability id, or raw SQL.
- [ ] `igniter-server` remains route/domain-free.
- [ ] `server/igniter-web cargo test --features machine` passes.
- [ ] `git diff --check` clean.

## Closed surfaces

- No production DB.
- No public bind.
- No schema migration runner.
- No auth/session UX.
- No View/UI work.
- No new `.igweb` syntax.
- No package/canon claim.
- No SparkCRM production dependency.
