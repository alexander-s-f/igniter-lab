# lab-todoapp-api-read-p3-v0 — product Todo read route over the host-read seam

**Card:** `LAB-TODOAPP-API-READ-P3` · **Delegation:** `OPUS-TODOAPP-API-READ-P3`
**Status:** CLOSED (lab implementation proof) — the **read half of the real `todo_postgres_app`** product
surface, proven over the P6 host-read seam using the **app's own authored contracts**:
`GET /accounts/:account_id/todos` read intent → product `ListTodosByAccount -> QueryPlan` → host
`PostgresReadExecutor<FakePostgresAdapter>` (host policy gates + clamps) → `rows_json` → product
`AccountTodoIndexFromRows -> Decision` → `Respond 200`/`404`.
**No live Postgres/DSN/DDL, no new `.igweb` syntax / `ReadThen` arm, no write execution, no runner
productization, no typed row destructuring, no canon.**
**Authority:** Lab. App owns the logical query + not-found `Decision`; host owns the read policy + executor.

## 1. What was proved

The product route's read flow is real end-to-end with **both ends being the app's own contracts**: the
authored `ListTodosByAccount("acct-7")` produces a structural `QueryPlan`; the host runs it through the fake
`PostgresReadExecutor` under a `PostgresReadPolicy` (allowlist + clamp); the rows return to the authored
`AccountTodoIndexFromRows(req, rows_json)`, which returns `Respond 200` carrying the todo rows or `404` for
an empty set. Host gates (denied source/field, raw SQL) refuse before the adapter.

## 2. App contracts dispatched

From `examples/todo_postgres_app/todo_handlers.ig` (module `TodoPgHandlers`), dispatched via
`IgniterMachine::dispatch(name, inputs).await` (async, direct — not through `IgWebServerApp::call`):
- `ListTodosByAccount(account_id : String) -> QueryPlan` — the P2 query contract (unchanged).
- `AccountTodoIndexFromRows(req : Request, rows_json : String) -> Decision` — **the one app change**: a small
  pure continuation added to `todo_handlers.ig` (`rows_json == "[]"` → 404 else 200). No other handler
  changed; the routes/manifest are untouched, so the P2 observed loopback behaviour is unchanged.

## 3. Fake rows + host policy

Fake `todos` table (product-shaped):

```json
[ { "id": "todo-1", "account_id": "acct-7", "title": "Buy milk",  "done": false },
  { "id": "todo-2", "account_id": "acct-7", "title": "Write spec", "done": true  } ]
```

Host policy (test/host-owned, mirrors `host_policy.md`): `allow_source("todos", ["id","account_id","title",
"done"])`, `allow_ops(["select"])`, row cap tunable (100 normally; 1 to prove clamp). `eq`-only filters.

## 4. Tests (4, `--features machine`) + denial/clamp evidence

| test | proves |
|---|---|
| `product_todos_index_found_returns_200` | product `ListTodosByAccount` → `QueryPlan{source:"todos",op:"select",filters[0].field:"account_id"}`; host read → 2 rows (`query_count==1`); `rows_json` → product `AccountTodoIndexFromRows` → `Respond 200` carrying `todo-1`/`Write spec` |
| `product_todos_index_empty_returns_app_404` | empty fake source → `rows_json=="[]"` → product continuation → app-owned **404** |
| `host_gates_before_adapter_and_clamp` | denied **source** + forbidden **projection** field + forbidden **filter** field + raw-SQL keys (`sql`/`raw_sql`/`query`) each refused **before the adapter** (`query_count==0`); the contract's `limit:50` **clamped** to cap 1 (`effective_limit==1`, `row_limit_clamped==true`, count 1) |
| `product_app_has_no_forbidden_surface` | authored app code (comments stripped) has no `select `/`insert`/`where`/`capability_id`/`io.postgres`/`passport`/`dsn`/`secret`; only the logical `source: "todos"` is present. (`scope` is the IgWeb routing keyword, excluded.) |

## 5. Did the app handler change?

Yes — **one** small pure contract `AccountTodoIndexFromRows` was added to `todo_handlers.ig` (the
continuation the seam re-enters). Nothing else changed: no route, no manifest, no other handler, no
capability/DSN/SQL. The new contract is unreferenced by the routes, so the P2 observed loopback behaviour is
identical (verified — `todo_postgres_app_tests` still 3/3 green after the app rebuilds with the new
contract).

## 6. Why this is still a direct-dispatch proof

Both contracts are dispatched directly via `IgniterMachine::dispatch().await` inside the async test, which
avoids `IgWebServerApp::call`'s internal `block_on` (the P4 §5 boundary, worse for reads since the host must
re-enter the app for the continuation). The full async socket runner + a staged two-phase dispatcher remains
**runner productization** (deferred). No `read`/`ReadThen` `.igweb` syntax or prelude arm yet — the harness
stands in for the eventual `read … as rows -> Handler` lowering.

## 7. Deferred

Staged `.igweb` `read` / `ReadThen` syntax; typed row destructuring into `.ig` records (rows are a JSON
string); read-then-write composition; fake → local Postgres; runner productization (sync/async re-entry).

## 8. Verification commands + exact counts

```text
$ cd server/igniter-web && cargo test --features machine --test todo_postgres_api_read_tests
  → 4 passed; 0 failed
$ cd server/igniter-web && cargo test            → 50 passed; 0 failed (api-read test gated to 0)
$ cd server/igniter-web && cargo test --features machine → 63 passed; 0 failed
$ cd runtime/igniter-machine && cargo test --no-default-features --test relational_queryplan_bridge_tests → 6 passed
$ cd runtime/igniter-machine && cargo test --no-default-features --test postgres_read_tests → 18 passed
$ git diff --check                               → clean
```

**Dirty-tree disclosure (per the card):** the working tree also contains unrelated **P21 view-authoring**
work — `examples/todo_view_app/*` + `tests/todo_view_app_tests.rs` (modified) and
`lab-docs/.../viewartifact-list-authoring-p21-v0.md` (new). I did **not** touch it. The broad `igniter-web`
counts above (50 default / 63 machine) therefore **include** that parallel work; my P3 deliverable is the
**+4** machine-gated `todo_postgres_api_read_tests` and the one continuation contract. `git diff --check`
clean; my only modified source file is `todo_postgres_app/todo_handlers.ig`.

## 9. Next

`LAB-TODOAPP-API-WRITE-P4` (product write route over the P4 effect-host seam), then
`LAB-TODOAPP-API-READ-WRITE-E2E-P5` (read + write + receipt), then the staged `read`/`ReadThen` syntax and
runner productization once the sync/async re-entry boundary is resolved.

---

*Lab implementation proof. Compiled 2026-06-20; 4 machine-gated product read tests green (product query →
host read → product continuation: found 200, empty 404, gates-before-adapter + clamp, no authored DB
surface); P2 loopback intact (3/3); default igniter-web 50 + machine 63 green (incl. unrelated parallel P21
work). One continuation contract added to the app; no route/manifest/runner/server/machine change. No live
DB.*
