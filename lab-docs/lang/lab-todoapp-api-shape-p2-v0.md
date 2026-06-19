# lab-todoapp-api-shape-p2-v0 — Todo API app shape with observed effects

**Card:** `LAB-TODOAPP-API-SHAPE-P2` · **Delegation:** `OPUS-TODOAPP-API-SHAPE-P2`
**Status:** CLOSED (lab implementation) — the first **Postgres-shaped Todo API**: routes + composite `via`
guards + **relational `QueryPlan`/`WriteIntent` contracts**, authored as `.igweb` + `.ig` with **zero
authored Rust**, built through the generic runner and served over loopback. Reads are **shaped** (the
relational contracts compile), writes are **observed** (`InvokeEffect`, logical target only) — the runner
executes **no Postgres IO**.
**No DB, DSN, SQL execution, receipts, effect-host seam, assets, or ORM. No change to `igniter-machine`,
`igniter-server`, the `igniter-web` runner, the compiler, Cargo deps, or canon.**
**Authority:** Lab. The app owns domain meaning; `igniter-server` stays route/domain-free; real DB
capability execution is a later card.

## 1. Executive summary

`server/igniter-web/examples/todo_postgres_app/` is a new example whose `.ig` contracts **mirror the
Postgres boundary** (`QueryPlan` reads, `WriteIntent` writes) but open no connection. It runs through
`build_app_from_dir` / `igweb-serve check` with zero authored Rust, and its loopback behaviour matches the
P1 table (health 200, account-scoped index/show 200 via composite guards, keyless create/done → 400, keyed
→ 202 **observed** `InvokeEffect` `todo-create`/`todo-done`, 404/405). It is "postgres-shaped" because the
relational intent contracts compile alongside the routing handlers — not because it touches a database.

## 2. Verify-first facts (live)

- `igweb-serve` / `build_app_from_dir` still **observes** `InvokeEffect` as a `202`
  (`igniter-web/src/lib.rs:171`) and executes no capability IO; the manifest still rejects `[effects]`.
- `todo_v2_app` already proves the scope + resource + route-level `via` composite-guard + idempotency shape;
  this app reuses that proven shape verbatim (guards return `Result[Ctx, Decision]` via `ok(ctx)`/`err(...)`
  in `if`-branches — the P22/P24 pattern).
- The relational `QueryPlan`/`WriteIntent` shape still mirrors the machine boundary
  (`postgres_read::QueryPlan`, `postgres_write::PostgresWriteIntent`); records use the `MakeXxx` factory
  pattern (P2 relational proof).
- P10 (typed reads) and P26 (`let`/`guard`) are present in the tree but this card depends on **neither** —
  it uses only the already-proven `via` + composite-guard + observed-effect surface.

## 3. File layout

```text
server/igniter-web/examples/todo_postgres_app/
  igweb.toml          # entry=Serve, loopback, trace; NO [effects]/DSN/secrets
  routes.igweb        # scope + resource + via composite guards + requires idempotency
  todo_handlers.ig    # module TodoPgHandlers — routing handlers/guards + relational contracts
  host_policy.md      # future host-owned config sketch (NON-authoritative, not applied)
server/igniter-web/tests/todo_postgres_app_tests.rs   # 3 tests
```

## 4. Routes + loopback behavior

Routes (no new syntax — the P16–P22 stack):

```igweb
route GET "/health" -> Health
scope "/accounts/:account_id" {
  resource todos "/todos" {
    index  GET                     via LoadAccountTodos(account_id) as ctx         -> AccountTodoIndex
    show   GET    "/:todo_id"       via LoadTodoContext(account_id, todo_id) as ctx -> AccountTodoShow
    create POST                    via LoadAccountTodos(account_id) as ctx         -> AccountTodoCreate requires idempotency
    member POST   "/:todo_id/done"  via LoadTodoContext(account_id, todo_id) as ctx -> AccountTodoDone requires idempotency
  }
}
```

| request | result |
|---|---|
| `GET /health` | 200 `ok` |
| `GET /accounts/7/todos` | 200 (account ctx threaded: body `7`) |
| `GET /accounts/7/todos/42` | 200 (todo ctx threaded: body `42`) |
| `POST /accounts/7/todos` (no key) | 400 keyless |
| `POST /accounts/7/todos` (key `evt-1`) | 202 **observed** `InvokeEffect target=todo-create`, key preserved, no identity |
| `POST /accounts/7/todos/42/done` (no key) | 400 |
| `POST /accounts/7/todos/42/done` (key `evt-2`) | 202 **observed** `InvokeEffect target=todo-done` |
| `GET /missing` | 404 |
| `DELETE /accounts/7/todos` | 405 |

## 5. Relational contract inventory

In `todo_handlers.ig` (compile alongside the routing module; **not executed**):
- types: `Account`, `Todo` (advisory mirrors), `QueryFilter`, `QueryPlan`, `WriteValues`, `WriteIntent`.
- factories: `MakeFilter`, `MakeWriteValues` (nominal record construction).
- reads: `ListTodosByAccount(account_id) -> QueryPlan`, `FindTodo(account_id, todo_id) -> QueryPlan`
  (`eq`-only filters, explicit source/projection/limit, no SQL).
- writes: `BuildCreateTodoIntent(account_id, idempotency_key) -> WriteIntent`,
  `BuildMarkTodoDoneIntent(todo_id, idempotency_key) -> WriteIntent`.

## 6. Shaped / observed, not executed (honest boundary)

- **Reads are shaped, not run.** The `via` guards (`LoadAccountTodos`, `LoadTodoContext`) stay **pure** and
  return a fixture/canned context (`{ account_id }` / `{ account_id, todo_id }`). The `QueryPlan` contracts
  exist + compile but are not dispatched — there is no effect-host seam yet.
- **Writes are observed, not run.** Mutating handlers return `InvokeEffect { target: "todo-create" |
  "todo-done", … }`, which the runner surfaces as a `202` — no `PostgresWriteExecutor`, no receipt, no DB.
- This is the honest v0: the full authoring surface proven, real execution deferred to the effect-host
  seam.

## 7. Boundary checks

- **No raw SQL / capability id / scope / DSN / secret** in the authored app — asserted over the
  comment-stripped code of `routes.igweb` + `todo_handlers.ig` + `igweb.toml` (`select `, `insert into`,
  `capability_id`, `io.postgres`, `passport`, `dsn`, `secret`, `[effects]`, … all absent).
- **`.igweb` names only logical targets** (`todo-create`/`todo-done`); no effect identity smuggled (the
  loopback test asserts `capability_id`/`scope` are absent from the observed decision).
- **`igniter-server` stays route/domain-free + serde-only**: its normal dependency tree has no
  `igniter_web`/`igniter_machine`/`igniter_compiler`/`tokio`/`regex`.

## 8. Verification commands + exact counts

```text
$ cd server/igniter-web && cargo run --bin igweb-serve -- check examples/todo_postgres_app
  → igweb-serve: check ok app_dir=examples/todo_postgres_app entry=Serve sources=2 (no socket opened)
$ cd server/igniter-web && cargo test
  → builder 5 · ctx_demo 1 · example_app 7 · runner 17 · todo_postgres_app 3 · todo_v2_app 1  (all 0 failed)
$ cd server/igniter-server && cargo test
  → 49 passed; 0 failed
$ cd server/igniter-server && cargo tree -e normal | rg 'igniter_web|igniter_machine|igniter_compiler|tokio|regex'
  → (none) — serde-only
$ git diff --check (server/igniter-web/)                → clean
```

New tests (`todo_postgres_app_tests.rs`, 3): `app_files_exist_and_check_succeeds` (files on disk + dry
build + `entry=Serve`, `source_count=2`); `loopback_behaviors` (the full table above); 
`relational_contracts_present_and_no_forbidden_surface` (relational contracts declared + no SQL/identity
surface in the comment-stripped authored code).

## 9. Next recommendation

`LAB-IGNITER-WEB-EFFECT-HOST-READINESS-P3` — design the host seam that turns the runner's observed
read/write intents into machine capability execution (precedent: `igniter-machine` `frame_binding`
P17/P18). Then `LAB-TODOAPP-API-READ-P4` (fake → P10-typed real read through that seam) and
`LAB-TODOAPP-API-WRITE-P5` (idempotent write + receipt). The app files authored here become the live target
of those slices unchanged.

---

*Lab implementation. Compiled 2026-06-19; `igweb-serve check` ok; igniter-web full suite green (incl. 3 new
todo_postgres_app tests); igniter-server 49 green + serde-only. Reads shaped, writes observed — no DB,
receipts, or effect-host execution. Zero authored Rust in the app.*
