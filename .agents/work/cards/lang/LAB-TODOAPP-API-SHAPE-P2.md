# LAB-TODOAPP-API-SHAPE-P2 - Todo API app shape with observed effects

Status: CLOSED
Date: 2026-06-19
Lane: standard / lab implementation
Skill: idd-agent-protocol
Delegation: OPUS-TODOAPP-API-SHAPE-P2

## Intent

Create the first **Todo API app shape** that looks like the future Postgres app
but still stays inside today's proven execution boundary:

```text
igweb.toml
  -> routes.igweb
  -> .ig handlers + relational QueryPlan/WriteIntent contracts
  -> igweb-serve / build_app_from_dir
  -> loopback responses + observed InvokeEffect
```

This is the app-files-only proof recommended by
`LAB-TODOAPP-API-POSTGRES-E2E-READINESS-P1`. It must prove that an Igniter-only
author can write the Todo API surface with relational contracts and logical
effect targets, while the current runner honestly **observes** effects instead
of executing Postgres IO.

## Authority

Lab implementation. The Todo app owns app/domain meaning. `igniter-server` stays
route/domain-free. `igniter-web` runner owns build/loopback/observed decisions.
`igniter-machine` will own real DB capability execution later, but is **not**
invoked by this card.

This card may create/change:

- `server/igniter-web/examples/todo_postgres_app/igweb.toml`;
- `server/igniter-web/examples/todo_postgres_app/routes.igweb`;
- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`;
- optionally `server/igniter-web/examples/todo_postgres_app/host_policy.md`
  or similar doc snippet for future read/write allowlists and effect target map;
- focused tests under `server/igniter-web/tests/`;
- optionally a focused compiler fixture/test only if the example cannot prove
  relational contracts through `igniter-web`;
- one proof doc under `lab-docs/lang/`;
- this card's closing report.

This card must **not** change:

- `runtime/igniter-machine`;
- `server/igniter-server`;
- `server/igniter-web` runner semantics;
- `lang/igniter-compiler` syntax/semantics;
- Cargo dependencies;
- DB schema or local DB state;
- canon docs.

No real DB. No DDL application. No migrations runner. No real effect execution.
No public listener. No SparkCRM/vendor schema. No assets/views. No ORM.

## Verify First

Read before editing:

- `lab-docs/lang/lab-todoapp-api-postgres-e2e-readiness-p1-v0.md`
- `server/igniter-web/examples/todo_v2_app/{igweb.toml,routes.igweb,todo_handlers.ig}`
- `server/igniter-web/tests/todo_v2_app_tests.rs`
- `server/igniter-web/src/lib.rs`
- `server/igniter-web/src/bin/igweb-serve.rs`
- `lang/igniter-compiler/tests/fixtures/relational_todo/relational_todo.ig`
- `runtime/igniter-machine/src/postgres_read.rs`
- `runtime/igniter-machine/src/postgres_write.rs`

Then confirm live facts:

- `igweb-serve` / `build_app_from_dir` still observes `InvokeEffect` as `202`
  and does not execute capability IO;
- manifest still rejects `[effects]`;
- `todo_v2_app` already proves scope/resource/via/idempotency route shape;
- relational `QueryPlan` / `WriteIntent` shape still mirrors the machine
  executor boundary;
- P10/P26 may be present in the tree, but this card must not depend on their
  uncommitted runtime changes.

Live code wins over this card.

## App To Create

Create:

```text
server/igniter-web/examples/todo_postgres_app/
  igweb.toml
  routes.igweb
  todo_handlers.ig
  host_policy.md        # optional but recommended: future host-owned config sketch
```

This app is named "postgres-shaped" because its contracts mirror the DB
boundary, not because it opens a DB connection.

### `igweb.toml`

Use the existing runner manifest shape:

```toml
[app]
entry = "Serve"

[server]
mode = "loopback"
max_requests = 16

[middleware]
trace = true
body_limit_bytes = 65536
```

No `[effects]`, no DSN, no secrets, no public bind, no route table.

### `routes.igweb`

Use the P1/P23 route shape, no new syntax:

```igweb
app TodoPgWeb entry Serve {
  handlers TodoPgHandlers

  route GET "/health" -> Health

  scope "/accounts/:account_id" {
    resource todos "/todos" {
      index  GET                     via LoadAccountTodos(account_id) as ctx          -> AccountTodoIndex
      show   GET    "/:todo_id"       via LoadTodoContext(account_id, todo_id) as ctx  -> AccountTodoShow
      create POST                    via LoadAccountTodos(account_id) as ctx          -> AccountTodoCreate requires idempotency
      member POST   "/:todo_id/done"  via LoadTodoContext(account_id, todo_id) as ctx  -> AccountTodoDone requires idempotency
    }
  }
}
```

If live formatter/style in `todo_v2_app` differs, follow the live style.

### `todo_handlers.ig`

This file should be self-contained except for `import IgWebPrelude`.

Include:

- row/advisory schema types: `Account`, `Todo`;
- relational intent types: `QueryFilter`, `QueryPlan`, `WriteValues`,
  `WriteIntent`;
- factories like `MakeFilter` / `MakeWriteValues` if needed by the compiler;
- query contracts:
  - `ListTodosByAccount(account_id) -> QueryPlan`;
  - `FindTodo(account_id, todo_id) -> QueryPlan`;
- command contracts:
  - `BuildCreateTodoIntent(account_id, idempotency_key) -> WriteIntent`;
  - `BuildMarkTodoDoneIntent(todo_id, idempotency_key) -> WriteIntent`;
- composite guards:
  - `LoadAccountTodos(account_id) -> Result[TodoListCtx, Decision]`;
  - `LoadTodoContext(account_id, todo_id) -> Result[TodoCtx, Decision]`;
- route handlers:
  - `Health`;
  - `AccountTodoIndex`;
  - `AccountTodoShow`;
  - `AccountTodoCreate`;
  - `AccountTodoDone`.

Important: because there is no effect-host seam yet, guards must remain pure and
return fixture/canned contexts. The query contracts must exist and compile, but
do not pretend they are executed.

Writes should return logical observed effects:

```ig
InvokeEffect {
  target: "todo-create",
  input: "...",              -- stable sanitized payload string for v0
  idempotency_key: req.idempotency_key
}
```

and:

```ig
InvokeEffect { target: "todo-done", ... }
```

Do not put capability IDs, scopes, DSNs, table DDL, SQL, or secrets in `.ig`.

### Optional `host_policy.md`

If added, keep it short and clearly non-authoritative:

- read allowlists: sources `accounts`, `todos`, fields and value kinds;
- write policies: target `todos`, key, columns;
- effect target map: `todo-create`, `todo-done`;
- env names for future local PG;
- statement that schema/migrations are operator-owned and not applied here.

This doc is future host config evidence, not runtime authority.

## Required Tests

Add focused tests under `server/igniter-web/tests/`, for example:

```text
todo_postgres_app_tests.rs
```

At minimum prove:

1. App files exist on disk and build through `build_app_from_dir`.
2. `igweb-serve check examples/todo_postgres_app` succeeds with no socket.
3. Loopback behavior:

   | request | expected |
   |---|---|
   | `GET /health` | 200 |
   | `GET /accounts/7/todos` | 200 canned/shape response |
   | `GET /accounts/7/todos/9` | 200 canned/shape response |
   | `POST /accounts/7/todos` without idempotency key | 400 |
   | `POST /accounts/7/todos` with key | 202 observed `InvokeEffect`, target `todo-create` |
   | `POST /accounts/7/todos/9/done` with key | 202 observed `InvokeEffect`, target `todo-done` |
   | `GET /missing` | 404 |
   | `DELETE /accounts/7/todos` | 405 |

4. Relational contracts are present and compile as part of the app.
5. The app text has no raw SQL and no capability IDs/scopes/DSNs/secrets.
6. `InvokeEffect` is observed only; no receipt assertions, no DB env, no
   machine write/read execution.
7. `igniter-server` normal dependency tree remains small/serde-only.

Prefer reusing existing `testkit`/roundtrip helpers from `igniter-web`.

## Required Verification

Run and record exact counts:

```text
cd server/igniter-web && cargo test
cd server/igniter-web && cargo run --bin igweb-serve -- check examples/todo_postgres_app
cd server/igniter-server && cargo test
cd server/igniter-server && cargo tree -e normal | rg 'igniter_web|igniter_machine|igniter_compiler|tokio|regex'
git diff --check
```

The `cargo tree` grep should have no matches for those heavy deps in
`igniter-server` normal dependencies. If warnings exist in transitive crates,
report them separately from P2 behavior.

Do **not** run or require Postgres. Do **not** require `IGNITER_PG_DSN`.

## Required Proof Doc

Create:

```text
lab-docs/lang/lab-todoapp-api-shape-p2-v0.md
```

It must include:

1. executive summary;
2. verify-first facts from P1/live code;
3. file layout;
4. route table and loopback behavior;
5. relational contract inventory (`QueryPlan`/`WriteIntent`);
6. clear statement that reads/writes are shaped/observed, not executed;
7. boundary checks (no SQL/capability IDs/DSNs/secrets; server remains
   route/domain-free);
8. verification commands and exact counts;
9. next recommendation.

## Acceptance

- [x] `todo_postgres_app` exists as authored app files with zero authored Rust.
- [x] App builds through `build_app_from_dir` and `igweb-serve check`.
- [x] Loopback proves health/list/show/create/done/404/405.
- [x] Mutating routes keep keyless 400 and keyed observed `InvokeEffect`.
- [x] Effect targets are logical (`todo-create`, `todo-done`) only.
- [x] Relational `QueryPlan` and `WriteIntent` contracts compile.
- [x] No DB, DSN, SQL execution, receipts, or effect-host execution.
- [x] No raw SQL / ORM / capability IDs / scopes / secrets in authored app.
- [x] `igniter-server` normal deps remain small.
- [x] Proof doc + closing report written.

---

## Closing Report (2026-06-19)

**Deliverable:** `server/igniter-web/examples/todo_postgres_app/` — the first Postgres-shaped Todo API,
**zero authored Rust**. Files: `igweb.toml`, `routes.igweb`, `todo_handlers.ig` (module `TodoPgHandlers`),
`host_policy.md` (non-authoritative host-config sketch). Test:
`server/igniter-web/tests/todo_postgres_app_tests.rs` (3). Proof doc:
`lab-docs/lang/lab-todoapp-api-shape-p2-v0.md`.

**Shape proven:** routes = the P16–P22 stack verbatim (scope + resource + route-level `via` composite
guards + `requires idempotency`, no new syntax); `todo_handlers.ig` combines the proven routing
handlers/guards (`LoadAccountTodos`/`LoadTodoContext` → `Result[Ctx, Decision]`) **with** the relational
intent contracts (`QueryPlan` reads `ListTodosByAccount`/`FindTodo`; `WriteIntent` writes
`BuildCreateTodoIntent`/`BuildMarkTodoDoneIntent`) — all compiling in one module.

**Honest boundary:** reads are **shaped** (guards stay pure, return canned context; `QueryPlan` contracts
compile but are not dispatched — no effect-host seam yet); writes are **observed** (`InvokeEffect`
`todo-create`/`todo-done` → `202`, no executor/receipt/DB). Depends on neither P10 nor P26.

**Proof — all green:**
- `igweb-serve check examples/todo_postgres_app` → `check ok … entry=Serve sources=2 (no socket)`.
- `igniter-web cargo test` → builder 5 · ctx_demo 1 · example 7 · runner 17 · **todo_postgres 3** · todo_v2
  1, all 0 failed.
- `igniter-server cargo test` → 49 passed; `cargo tree -e normal` serde-only (no web/machine/compiler/
  tokio/regex).
- `git diff --check` clean.

**Loopback table met:** health 200, index/show 200 (ctx threaded), keyless create/done 400, keyed 202
observed `InvokeEffect` (target only, no `capability_id`/`scope`), 404, 405. No SQL/identity/DSN/secret in
the comment-stripped authored code.

**Next:** `LAB-IGNITER-WEB-EFFECT-HOST-READINESS-P3` (host seam: observed intent → machine capability
execution), then `…-API-READ-P4` / `…-API-WRITE-P5`. These app files become their live target unchanged.

## Closed Surfaces

No real Postgres. No fake executor wiring. No effect-host seam. No receipts.
No reconcile. No migrations. No schema creation. No assets/views. No public
listener. No SparkCRM/vendor schema. No changes to `igniter-machine`,
`igniter-server`, VM/typechecker/compiler semantics, Cargo dependencies, or
canon.

## Suggested Next

After P2 lands:

1. `LAB-IGNITER-WEB-EFFECT-HOST-READINESS-P3` — design the host seam that turns
   observed read/write intent into machine capability execution.
2. Then `LAB-TODOAPP-API-READ-P4` — fake/typed read through that seam.
3. Then `LAB-TODOAPP-API-WRITE-P5` — idempotent write + receipt.

