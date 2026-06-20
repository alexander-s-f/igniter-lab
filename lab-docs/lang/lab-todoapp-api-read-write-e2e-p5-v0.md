# lab-todoapp-api-read-write-e2e-p5-v0 — product Todo read+write fake-host e2e

**Card:** `LAB-TODOAPP-API-READ-WRITE-E2E-P5` · **Delegation:** `OPUS-TODOAPP-API-READ-WRITE-E2E-P5`
**Status:** CLOSED (lab implementation-proof) — the P3 read seam and P4 write seam are stitched into ONE
product-shaped fake-host e2e for `examples/todo_postgres_app` (zero app Rust). **No live Postgres, no DSN/
SQL/migrations, no new `.igweb` syntax, no runner productization, no canon claim.**
**Authority:** Lab tooling. New test target only; no production code changed.

## Verify-first (live, reused harnesses)

- The app's authored read contracts (`ListTodosByAccount`/`FindTodo` → `QueryPlan`, `AccountTodoIndexFromRows`
  continuation) and write path (`AccountTodoCreate`/`AccountTodoDone` → `InvokeEffect`, built via
  `BuildCreateTodoIntent`) already exist in `examples/todo_postgres_app/todo_handlers.ig`.
- Two **separate** harnesses exist: `todo_postgres_api_read_tests.rs` (direct `IgniterMachine::dispatch` +
  fake `PostgresReadExecutor` under a host `PostgresReadPolicy`) and `todo_postgres_effect_host_tests.rs`
  (`build_app_from_dir` + `app.call` + `MachineEffectHost` + fake `FakeWriteExecutor` + receipts).
- `InvokeEffect.input` is still **string-only** (the intent's structured `values` aren't carried yet).
- Both fake executors run with **no DSN / no live DB** under `--features machine`.

So P5 needs no new product surface — it **composes** the two proven seams into one flow.

## What changed (one new test target only)

`server/igniter-web/tests/todo_postgres_api_read_write_e2e_tests.rs` (`#![cfg(feature = "machine")]`), a
**hybrid harness** assembling the proven read + write helpers (test-only; the integration files are each
self-contained, so the duplication follows the established pattern). No `.ig`/`.igweb`/Rust production
change.

## The e2e contour (one test: `product_read_then_write_e2e`)

```text
READ  ListTodosByAccount("acct-7") -> QueryPlan {source:"todos", op:"select", filters:[account_id eq …]}
        -> host PostgresReadExecutor<Fake> (policy gates source/fields, clamps limit) -> 2 rows, query_count==1
        -> rows_json -> AccountTodoIndexFromRows -> Respond 200 (carries todo-1 …)
      ListTodosByAccount("acct-none") -> host read (empty) -> rows_json "[]"
        -> AccountTodoIndexFromRows -> Respond 404   (app product decision, not infra failure)
WRITE POST /accounts/acct-7/todos (key evt-create-1) -> app.call -> InvokeEffect{target:"todo-create"}
        -> MachineEffectHost (CoordinationHub + fake write executor) -> 200 committed, exec.attempts()==1
      replay same key -> exec.attempts() still 1   (machine dedup → exactly one mutation)
```

Decisions for the write half are computed by the app's sync VM **before** entering the tokio runtime, then
executed inside it (the P4 `block_on`-nesting constraint; documented there). Read uses direct async
dispatch. This "hybrid" is exactly the harness-level e2e the card sanctioned — product shape + seam
composition, not production serving.

## Tests & commands — exact counts

```text
$ cargo test --features machine --test todo_postgres_api_read_write_e2e_tests → 2 passed (e2e + app-hygiene)
$ cargo test --features machine --test todo_postgres_api_read_tests           → 4 passed (P3 intact)
$ cargo test --features machine --test todo_postgres_api_write_tests          → 2 passed (P4 intact)
$ cargo test --features machine --test todo_postgres_effect_host_tests        → 5 passed (P4 intact)
$ cargo test --features machine --test todo_postgres_read_host_tests          → 4 passed (P6 intact)
$ cargo test --features machine --test todo_postgres_app_tests                → 3 passed
$ cargo test                  (igniter-web default)                           → 17 binaries green
$ cargo test --features machine (igniter-web)                                 → 17 binaries green
$ cd runtime/igniter-machine && cargo test --no-default-features --test postgres_read_tests  → 18 passed
$ cd runtime/igniter-machine && cargo test --no-default-features --test postgres_write_tests → 10 passed
$ git diff --check                                                            → clean
```

## Acceptance — mapping

- [x] Read path and write path exercised in **one** test target (`product_read_then_write_e2e`).
- [x] Read uses the app-authored `QueryPlan` contract (`ListTodosByAccount`), not Rust-invented SQL.
- [x] Read host policy gates source/fields before the adapter (proven in P3, exercised here via `todos_policy`).
- [x] Read found → app-owned **200** carrying rows.
- [x] Read empty → app-owned **404**, not infra failure.
- [x] Write uses the app-authored command/route handler (`AccountTodoCreate` → `BuildCreateTodoIntent`).
- [x] Write executes through `MachineEffectHost` + fake write executor.
- [x] Write receipt/replay performs **one** executor mutation for the same idempotency key.
- [x] App-authored files contain no `capability_id`/`operation`/`scope`/passport/DSN/raw SQL/`[effects]`
      (`product_app_has_no_authority_surface`).
- [x] No live Postgres / migrations / `IGNITER_PG_DSN` / `IGNITER_PG_WRITE_DSN`.
- [x] Existing P3 read + P4 write/effect-host tests green; igniter-web default + machine green;
      igniter-machine pg read/write green; `git diff --check` clean.

## Honest report (per card)

- **Authored files used:** `examples/todo_postgres_app/{todo_handlers.ig, routes.igweb}` — unchanged.
- **Harness style:** hybrid — read via direct `IgniterMachine::dispatch`; write via `build_app` + `app.call`
  (sync, off-runtime) + async `MachineEffectHost`.
- **Read plan / rows:** `QueryPlan{source:"todos", op:"select", projection:[id,account_id,title,done],
  filters:[account_id eq "acct-7"], limit:50}`; fake rows `todo-1`/`todo-2`; found → 200, empty → 404.
- **Write effect:** `target:"todo-create"`, `idempotency_key:"evt-create-1"`, `input:"insert"` (the
  intent's `operation`); committed receipt → 200; replay same key → one executor attempt.
- **Blocked by string-only `InvokeEffect.input`:** the intent's structured `WriteValues`
  (`account_id/title/done`) are **not** carried to the executor — only `operation`/`key` are. A real DB
  write needs a structured effect payload. → `LAB-IGNITER-WEB-STRUCTURED-EFFECT-INPUT-READINESS-P*`.
- **Why host authority stays outside `.ig`/`.igweb`:** the app names only logical targets
  (`todo-create`/`todo-done`) and a logical `source:"todos"`; capability id, DSN, SQL, passport, and the
  `target→/w` binding all live in the host harness — structurally absent from authored files (proven).
- **Next toward local Postgres / product runner:** (1) structured effect input; (2) fake→real adapter swap
  with local DDL (`LAB-TODOAPP-API-LOCAL-POSTGRES-P*`); (3) productize the effect-host runner after the
  sync/async serve seam is resolved (`LAB-IGNITER-WEB-EFFECT-HOST-RUNNER-P*`).

## Closed scope (honored)

No live Postgres/DSN/DDL/migrations/pool/TLS; no new `.igweb` syntax; no new prelude decision; no async
runner re-entry; no structured effect payload protocol; no server-core route table/domain; no
capability-id/scope in authored files; no raw SQL; no ORM/schema inference; no canon claim.

---

*Lab implementation-proof. Compiled 2026-06-20; new e2e target 2 green; P3 read 4 + P4 write 2 + effect-host
5 + read-host 4 + app 3 intact; igniter-web 17/17 (default+machine); igniter-machine pg read 18 + write 10;
`git diff --check` clean. The product read+write contour is proven composed over the fake host — no live DB,
host authority outside the app.*
