# LAB-TODOAPP-API-IGWEB-SERVE-LOCAL-POSTGRES-P12 - Todo API through igweb-serve with local Postgres

Status: CLOSED
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

- [x] Closing report states actual subprocess vs extracted core.
- [x] Uses `examples/todo_postgres_app`, not a private Rust-only app.
- [x] Uses temp `host.toml` with env-var refs, no inline secrets.
- [x] Live DB test skips cleanly when `IGNITER_TODO_PG_DSN` is unset.
- [x] Read found -> HTTP 200.
- [x] Read empty -> app-owned HTTP 404.
- [x] Write create/done -> committed with receipt.
- [x] Replay same idempotency key -> no second mutation.
- [x] `--max-requests` exits deterministically; no daemon left running.
- [x] App files still contain no DSN, passport, capability id, or raw SQL.
- [x] `igniter-server` remains route/domain-free.
- [x] `server/igniter-web cargo test --features postgres` passes or live test skips cleanly.
- [x] `git diff --check` clean.

## Closed surfaces

- No production DB.
- No schema migration product feature.
- No public CLI stability claim.
- No pool/backpressure.
- No SparkCRM.
- No `.ig` raw SQL.

## Closing report

**Date:** 2026-06-22

### Subprocess vs extracted core — REAL SUBPROCESS

Unlike P25/P26 (which call the binary's builder fns directly, bypassing `main()`), P12 spawns the
ACTUAL compiled `igweb-serve` binary as a child process and drives it over a real loopback socket.
The binary is located via `env!("CARGO_BIN_EXE_igweb-serve")` (Cargo compiles it with the same
`--features` as the test target), so subprocess is reliable — no fragile path discovery. This proves
the parts no prior card touched: CLI arg parsing (`--host-config`/`--addr`/`--max-requests`/app_dir),
env-var resolution before socket bind, the combined `[postgres.read]` + `[postgres.write]` +
`[effects.*]` wiring inside `run_machine_mode`, and deterministic `--max-requests` exit (no daemon).

### Test added

`tests/todo_postgres_local_e2e_tests.rs` section 8: `subprocess_product_command_read_write_replay_e2e`
(gated `#![cfg(all(feature = "machine", feature = "postgres"))]`; skips cleanly without
`IGNITER_TODO_PG_DSN`). One operator-owned temp `host.toml` (env-var DSN refs only, no inline secret;
both read+write DSN refs point at the same dedicated test DB). Spawns the binary with `--max-requests 4`,
parses the bound addr from the binary's stdout `listening http://…` line, then drives four sequential
requests through the real socket and asserts at the HTTP **and** DB level:
- read found → 200 (carries a seeded todo id)
- read empty (other account) → app-owned 404
- write create → 200, **real `todos` business row committed** + PG `effect_receipts` row
- replay same idempotency-key → 200, **exactly one** business row (no second mutation)

then waits for deterministic exit (status success) and cleans up its rows/account/temp file.

### Two real bugs surfaced and fixed

P12 is the first card to assert DB truth through the **whole binary** (P26 asserted only HTTP status),
so it exposed two latent issues:

1. **Read idempotency-key collision** (`server/igniter-web/src/read_dispatch.rs`, FIXED).
   `StagedReadHost::execute` keyed the read effect on `req.correlation_id` alone, falling back to the
   constant `"staged-read"` when correlation was empty. Two DIFFERENT queries served on one host
   instance with empty/equal correlation collided on one key → the second read REPLAYED the first's
   cached rows (an empty-account read returned the populated account's rows). Fix: fold a deterministic
   `plan_digest(plan)` (fixed-seed `DefaultHasher` over the serialized plan) into the key
   (`"{corr}:{digest}"`). Same correlation + same plan still replays safely; distinct plans never
   collide. Without this, read-empty → 404 was unreachable through the binary.

2. **`effect_receipts` key suffix vs test cleanup** (test-harness, FIXED in the test).
   The ingress/coordination path keys PG `effect_receipts` by `intent.key + ":<attempt>"` (e.g.
   `p12-write-k1:0`), while `business_key` stays the bare `intent.key`. The shared `prepare` helper
   cleans by exact (un-suffixed) `idempotency_key`, so a leftover suffixed receipt from a prior run
   silently blocked the business insert (`ON CONFLICT DO NOTHING` → `ins` empty → business insert
   skipped) while still returning 200. The subprocess test now clears `effect_receipts` by the stable
   `business_key` on both ends, making it re-runnable. (The `:0` suffix itself is correct host-internal
   behavior — dedup/replay verified: two POSTs → one business row.)

Also hardened the shared `prepare` helper: it now blanket-deletes child `todos` under the test's
account before deleting the account row, so the full file is order-independent on a real DB (previously
`local_read_found` left `acct-7` children that tripped `todos_account_id_fkey` for `local_write_*`).

### Local DB

Operator-owned dedicated DB `igniter_todo_test` (psql role `alex`, no password, localhost), created for
this card — NEVER SparkCRM. Test-owned DDL only (`CREATE TABLE IF NOT EXISTS`, OnceCell-guarded). DSN
values never logged or asserted.

### Acceptance

- Real subprocess (not extracted core) — stated above.
- Uses `examples/todo_postgres_app` (no private Rust-only app); temp `host.toml`, env-var refs only.
- Skips cleanly without `IGNITER_TODO_PG_DSN`.
- read found → 200; read empty → app 404; write → committed + receipt; replay → no 2nd mutation.
- `--max-requests 4` → deterministic exit; no daemon.
- App files carry no DSN/passport/capability-id/raw SQL (grep-verified).
- `igniter-server` untouched (route/domain-free).
- `cargo test --features postgres` — green; DB tests skip cleanly without DSN; all 8 local-e2e pass
  WITH `IGNITER_TODO_PG_DSN` set.
- `cargo test --features machine` — 55+ green (read_dispatch fix, zero regression).
- `git diff --check` clean.

## Next

The Todo API runner now has a verified v0 operator path (product command proven against a real local
Postgres). Next is documentation + host-config examples — not more hidden test harnesses.
