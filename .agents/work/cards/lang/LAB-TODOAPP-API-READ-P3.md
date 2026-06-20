# LAB-TODOAPP-API-READ-P3 - Product Todo read route over the proven host-read seam

Status: CLOSED
Lane: standard
Type: implementation-proof
Delegation code: OPUS-TODOAPP-API-READ-P3
Date: 2026-06-20
Skill: idd-agent-protocol

## Context

`LAB-TODOAPP-API-SHAPE-P2` created the Postgres-shaped Todo API app:

```text
server/igniter-web/examples/todo_postgres_app/
  igweb.toml
  routes.igweb
  todo_handlers.ig
  host_policy.md
```

That app proves the authored product shape, but reads are still canned/pure and writes are observed
`InvokeEffect`.

`LAB-IGNITER-WEB-READ-GUARD-HOST-P6` then proved the read host seam as a direct-dispatch harness:

```text
.ig query contract -> QueryPlan
host PostgresReadExecutor<FakePostgresAdapter> under PostgresReadPolicy
rows -> rows_json
.ig continuation contract -> final Decision
```

P3 applies that seam to the real `todo_postgres_app` product surface. This is still a lab proof. Do not
productize the runner or introduce staged `.igweb` syntax yet.

## Goal

Make the **read half** of `todo_postgres_app` real enough to prove the product route can be served from
host-executed read results:

```text
GET /accounts/:account_id/todos
  -> authored query intent
  -> fake Postgres read executor with host policy
  -> authored continuation
  -> Respond 200/404
```

The important shift from P6: use the **TodoApp product files/contracts**, not a generic read-harness
fixture. Keep DB execution fake and host-owned.

## Verify First

Read live surfaces before editing:

- `server/igniter-web/examples/todo_postgres_app/`
  - `routes.igweb`
  - `todo_handlers.ig`
  - `host_policy.md`
- `server/igniter-web/tests/todo_postgres_app_tests.rs`
- `server/igniter-web/tests/todo_postgres_read_host_tests.rs`
- `lab-docs/lang/lab-todoapp-api-shape-p2-v0.md`
- `lab-docs/lang/lab-igniter-web-read-guard-host-p6-v0.md`
- `runtime/igniter-machine/src/postgres_read.rs`
- `runtime/igniter-machine/tests/relational_queryplan_bridge_tests.rs`
- `runtime/igniter-machine/tests/postgres_read_tests.rs`
- current dirty tree:
  - there may be unrelated `todo_view_app` / `LAB-IGNITER-WEB-VIEWARTIFACT-LIST-AUTHORING-P21` work;
  - do not include or modify that work unless explicitly instructed.

Confirm or correct:

- `todo_postgres_app` already has query contracts (`ListTodosByAccount`, `FindTodo`, or equivalent);
- current route handlers may be canned and may need a continuation contract;
- `IgniterMachine::dispatch(name, inputs).await` can dispatch arbitrary contracts loaded from the app files;
- P6's host-read helper can be copied/test-localized or extracted narrowly inside the test, not promoted to a
  public API;
- fake adapter + policy are enough; no `IGNITER_PG_DSN` required.

Live code wins over this card.

## Required Shape

Implement a focused, machine-gated test/proof under `server/igniter-web`, preferably:

```text
server/igniter-web/tests/todo_postgres_api_read_tests.rs
```

The proof should load:

- IgWeb prelude as needed;
- `todo_postgres_app/todo_handlers.ig`;
- any generated/lowered app artifact only if it is already cheap and useful.

Prefer direct contract dispatch over socket-loop execution for this card:

1. dispatch the app's authored query contract to obtain a `QueryPlan`;
2. run it through `PostgresReadExecutor<FakePostgresAdapter>` with a host-owned `PostgresReadPolicy`;
3. serialize returned rows as `rows_json`;
4. dispatch an authored app continuation contract with `req` + `rows_json`;
5. assert final `Decision`.

If `todo_postgres_app` does not yet have an explicit continuation contract, add the smallest app-local one in
`todo_handlers.ig`, for example:

```ig
pure contract AccountTodoIndexFromRows {
  input req       : Request
  input rows_json : String
  compute d : Decision = if rows_json == "[]" {
    Respond { status: 404, body: "no todos" }
  } else {
    Respond { status: 200, body: rows_json }
  }
  output d : Decision
}
```

Use live app naming and style; do not force this exact name if the existing file has a better convention.

## Data / Host Policy

Use fake Todo rows shaped like the product app:

```json
[
  { "id": "todo-1", "account_id": "acct-7", "title": "Buy milk", "done": false },
  { "id": "todo-2", "account_id": "acct-7", "title": "Write spec", "done": true }
]
```

Host policy should allow only:

- source: `todos`;
- fields: `id`, `account_id`, `title`, `done`;
- op: `select`;
- filters: only allow the fields the app actually uses;
- row cap small enough to prove clamp.

This policy is test/host-owned. The `.ig` app must not name:

- capability id;
- passport/scope;
- DSN;
- SQL;
- table DDL;
- secrets.

Logical `source: "todos"` inside `QueryPlan` is allowed.

## Required Acceptance

- [x] Product app query contract compiles and produces a structural `QueryPlan`.
- [x] `GET /accounts/:account_id/todos` read intent maps to host fake rows and an authored continuation.
- [x] Found rows return final `Decision.Respond` 200 with deterministic Todo-shaped body.
- [x] Empty rows return app-owned `Decision.Respond` 404.
- [x] Denied source fails before the adapter (`query_count == 0` or equivalent evidence).
- [x] Forbidden projection/filter field fails before the adapter.
- [x] Limit clamp is applied and visible in the host result.
- [x] Raw-SQL keys (`sql` / `raw_sql` / `query`) are refused before the adapter.
- [x] Authored `todo_postgres_app` code contains no raw SQL, capability id, scope/passport, DSN, or secret.
- [x] Existing P2 loopback tests still pass; writes remain observed `InvokeEffect`.
- [x] Default/no-machine `igniter-web` suite remains clean; new read-host test is `machine`-gated.
- [x] No live Postgres, no `IGNITER_PG_DSN`, no migrations.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-20)

**Deliverable:** the read half of the **real `todo_postgres_app`** product surface, proven over the P6
host-read seam with the **app's own contracts**.
- App change: one small pure continuation `AccountTodoIndexFromRows(req, rows_json : String) -> Decision`
  added to `examples/todo_postgres_app/todo_handlers.ig` (`"[]"` → 404, else 200). No route/manifest/other
  handler changed.
- Test: `server/igniter-web/tests/todo_postgres_api_read_tests.rs` (`#![cfg(feature = "machine")]`, **4
  tests**), dispatching the product `ListTodosByAccount` → host `PostgresReadExecutor<FakePostgresAdapter>`
  (policy gate + clamp) → `rows_json` → product `AccountTodoIndexFromRows`.
- Proof doc: `lab-docs/lang/lab-todoapp-api-read-p3-v0.md`.

**Proof — all green:**
- `cargo test --features machine --test todo_postgres_api_read_tests` → **4 passed** (found→200, empty→app
  404, denied source/projection/filter + raw-SQL before adapter + clamp, no authored DB surface).
- P2 loopback `todo_postgres_app_tests` → **3/3** (app rebuilds with the new contract; writes still observed
  `InvokeEffect`). `git diff --check` clean.

**Honest scope:** direct-dispatch (both contracts via `IgniterMachine::dispatch().await`, avoiding the P4
`block_on` boundary); rows as a JSON **string**; no staged `read`/`ReadThen` syntax; no write execution.
**Dirty-tree disclosure:** unrelated **P21 view-authoring** work (`todo_view_app/*`, its test, a P21 doc) is
present in the tree — **not touched**; broad counts (default 50 / machine 63) include it. My only modified
source is `todo_postgres_app/todo_handlers.ig`.

**Next:** `LAB-TODOAPP-API-WRITE-P4` (product write route over the P4 seam), `…-READ-WRITE-E2E-P5`, then
staged `read`/`ReadThen` syntax + runner productization.

## Required Verification

Run and report exact counts:

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test --features machine --test todo_postgres_api_read_tests
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test --features machine
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/runtime/igniter-machine && cargo test --no-default-features --test relational_queryplan_bridge_tests
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/runtime/igniter-machine && cargo test --no-default-features --test postgres_read_tests
git diff --check
```

If unrelated dirty P21 view-authoring work is present, do not revert it. Report clearly whether broad counts
include that dirty work.

## Required Proof Doc

Create:

```text
lab-docs/lang/lab-todoapp-api-read-p3-v0.md
```

It must state:

- what product route/read intent was proved;
- which app contracts were dispatched;
- exact fake rows and host policy;
- exact denial/clamp evidence;
- whether the app handler itself changed;
- why this is still a direct-dispatch proof, not full runner/socket-loop productization;
- what remains deferred.

## Closed Scope

- No live Postgres / DSN / DDL / migrations / pool / TLS.
- No new `.igweb` syntax (`read`, `ReadThen`, staged route body).
- No new IgWeb prelude arm.
- No runner/socket-loop productization.
- No async runtime redesign.
- No typed row destructuring into `.ig` records.
- No write execution in this card.
- No automatic DB reads from `via`.
- No raw SQL.
- No ORM / schema inference.
- No server-core route table or domain logic.
- No public CLI/canon/stable API claim.
- Do not touch unrelated P21 view/list authoring work.

## Suggested Next

If this lands cleanly:

1. `LAB-TODOAPP-API-WRITE-P4` — product write route over the already-proven effect-host write seam;
2. `LAB-TODOAPP-API-READ-WRITE-E2E-P5` — read + write + receipt with fake/local host adapters;
3. staged `.igweb` `read` / `ReadThen` syntax only after product pressure confirms the shape;
4. runner productization after the sync/async re-entry boundary is explicitly resolved.
