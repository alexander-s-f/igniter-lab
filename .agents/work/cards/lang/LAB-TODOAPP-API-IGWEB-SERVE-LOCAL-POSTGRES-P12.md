# LAB-TODOAPP-API-IGWEB-SERVE-LOCAL-POSTGRES-P12 - Todo API through igweb-serve with local Postgres

Status: OPEN
Lane: TodoApp API / runner productization / local Postgres
Type: integration proof
Delegation code: OPUS-TODOAPP-API-IGWEB-SERVE-LOCAL-POSTGRES-P12
Date: 2026-06-22
Skill: idd-agent-protocol

## Context

Closed inputs:

- `LAB-TODOAPP-API-LOCAL-POSTGRES-P8` - real local Postgres read/write adapters are proven.
- `LAB-TODOAPP-API-IGWEB-SERVE-E2E-P11` - fake adapters + host-config-derived bindings prove Todo API through extracted runner core.
- `LAB-IGNITER-WEB-IGWEB-SERVE-READ-BINDING-P25` - expected to wire real reads into the actual binary path.
- `LAB-IGNITER-WEB-IGWEB-SERVE-WRITE-BINDING-P26` - expected to wire real writes into the actual binary path.

This card should start only after P25/P26 are closed or explicitly declare which prerequisite is still missing.

## Goal

Prove the product-shaped command:

```text
cargo run --features postgres --bin igweb-serve -- \
  --host-config <tmp-host.toml> \
  --addr 127.0.0.1:0 \
  --max-requests N \
  server/igniter-web/examples/todo_postgres_app
```

against a local Postgres database, using operator-owned `host.toml` and test-owned DDL/seed/cleanup.

## Verify first

Read:

- `server/igniter-web/src/bin/igweb-serve.rs`
- `server/igniter-web/tests/todo_postgres_local_e2e_tests.rs`
- `server/igniter-web/tests/todo_igweb_serve_e2e_tests.rs`
- `server/igniter-web/examples/todo_postgres_app/`
- `runtime/igniter-machine/src/postgres_read.rs`
- `runtime/igniter-machine/src/postgres_write.rs`

Confirm whether spawning the binary is practical in Cargo tests. If not, use extracted binary core but
document the reason. Prefer actual subprocess if the binary can be located reliably.

## Test shape

Use `IGNITER_TODO_PG_DSN` as the live DB gate. If unset, skip cleanly.

The test must:

1. create isolated test tables/schema or namespaced rows;
2. write a temporary `host.toml` with env-var DSN refs only;
3. start bounded loopback runner;
4. exercise:
   - read found -> 200;
   - read empty -> app-owned 404;
   - write create/done -> committed;
   - replay same idempotency key -> no second mutation;
5. cleanup test-owned rows/tables.

## Acceptance

- [ ] Closing report states actual subprocess vs extracted core.
- [ ] Uses `examples/todo_postgres_app`, not a private Rust-only app.
- [ ] Uses temp `host.toml` with env-var refs, no inline secrets.
- [ ] Live DB test skips cleanly when `IGNITER_TODO_PG_DSN` is unset.
- [ ] Read found -> HTTP 200.
- [ ] Read empty -> app-owned HTTP 404.
- [ ] Write create/done -> committed with receipt.
- [ ] Replay same idempotency key -> no second mutation.
- [ ] `--max-requests` exits deterministically; no daemon left running.
- [ ] App files still contain no DSN, passport, capability id, or raw SQL.
- [ ] `igniter-server` remains route/domain-free.
- [ ] `server/igniter-web cargo test --features postgres` passes or live test skips cleanly.
- [ ] `git diff --check` clean.

## Closed surfaces

- No production DB.
- No schema migration product feature.
- No public CLI stability claim.
- No pool/backpressure.
- No SparkCRM.
- No `.ig` raw SQL.

## Next

If this lands, the Todo API runner has a credible v0 operator path. Next would be documentation and
host-config examples, not more hidden test harnesses.
