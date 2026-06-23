# todo_postgres_app — API contract

**Status: lab example. Loopback-only, local Postgres only. NOT a public or production API and not a
stable surface.** This is the product-facing contract for the example Todo API authored in `.igweb` +
`.ig` and served by the generic `igweb-serve` runner. For what the runner/host machinery actually
implements, see the crate's [`IMPLEMENTED_SURFACE.md`](../../IMPLEMENTED_SURFACE.md).

The app names only logical effect targets and structured intents; all DB authority (DSN, capability,
allowlist, receipts, passport) is host-owned — see [`host.example.toml`](host.example.toml) and
[`host_policy.md`](host_policy.md).

## Two run modes

| Mode | How | Reads (`ReadThen`) | Writes (`InvokeEffect`) |
| --- | --- | --- | --- |
| **Sync observed** (default build) | `igweb-serve <app_dir>` | a `ReadThen` decision is unhandled → **500** | observed only → **202** (no DB write) |
| **Async machine** (`--features postgres` + `--host-config`) | `igweb-serve --host-config host.toml <app_dir>` | executed against Postgres → 200/404 | executed via `MachineEffectHost` → 200 committed / dedup |

`/health` is a plain `Respond` and returns 200 in **both** modes.

## Routes

Source of truth: [`routes.igweb`](routes.igweb) (+ handlers in [`todo_handlers.ig`](todo_handlers.ig)).
"Machine status" = behavior under async machine mode (the product path).

| Method & path | Handler | Idempotency | Success | Not-found / denied |
| --- | --- | --- | --- | --- |
| `GET /health` | `Health` | — | 200 `ok` | — |
| `GET /accounts/:account_id/todos` | `AccountTodoIndex` → `ReadThen` | — | 200 (rows JSON) | 404 if no todos for the account; 404 if account capture missing (guard); read denied by host policy → 403; host read error → 503 |
| `GET /accounts/:account_id/todos/:todo_id` | `AccountTodoShow` → `ReadThen` (`FindTodo`) | — | 200 (row JSON) | 404 `todo not found` (no matching row); 404 if account/todo missing (guard); 403/503 as above |
| `POST /accounts/:account_id/todos` | `AccountTodoCreate` → `InvokeEffect{todo-create}` | **required** | 200 committed (replay same key → 200 dedup, no 2nd write) | keyless → **400**; sync mode → 202 observed |
| `POST /accounts/:account_id/todos/:todo_id/done` | `AccountTodoDone` → `InvokeEffect{todo-done}` | **required** | 200 committed (replay → 200 dedup) | keyless → **400**; sync mode → 202 observed |

Unmatched path → **404**; wrong method on a known pattern → **405**.

### Idempotency

`create` and `done` require an `idempotency-key` header (the `.igweb` `requires idempotency` guard;
keyless → 400). The header value is the **effect** idempotency key; replaying the same key performs no
second mutation. Note the two write keys differ:

- **create**: business row primary key = the idempotency key (v0 — no generated ids).
- **done**: business row primary key = the route `todo_id`; the idempotency key stays the effect key.

## Request body (create)

v0 create body contract: the body is a **JSON string literal** whose value becomes the todo title
(e.g. `"Buy milk"`, with quotes). It is not a JSON object and there is no field parser; an empty/absent
body → empty title. `done` ignores the body. (Reads carry no body.)

```bash
# title comes from the body
curl -X POST -H "Authorization: Bearer $IGNITER_TODO_EFFECT_TOKEN" \
     -H 'idempotency-key: k1' --data '"Buy milk"' \
     http://127.0.0.1:PORT/accounts/acct-1/todos
```

`done` is a **full-row upsert** keyed by `todo_id` (the host adapter is `INSERT … ON CONFLICT DO
UPDATE`): it carries `account_id` (FK-valid) and sets `done="true"`. v0 does **not** preserve the
existing `title` (no partial PATCH).

## Host requirements (async machine mode)

- Build with `--features postgres`; pass `--host-config` pointing at a host TOML
  (see [`host.example.toml`](host.example.toml), commit-safe, env-var names only).
- `IGNITER_TODO_PG_DSN` — read **and** write DSN; use a **dedicated local test DB** (e.g.
  `igniter_todo_test`), never production / never SparkCRM.
- `IGNITER_TODO_EFFECT_TOKEN` — the bearer token clients present (`Authorization: Bearer …`) for
  `todo-create` / `todo-done`; both effects are bound to host route `/w`.
- Schema (`accounts`, `todos`, `effect_receipts`) is operator-owned; the runner never migrates it.

## Evidence

From `server/igniter-web/`:

```bash
scripts/check_implemented_surface.sh                  # bounded guard for the runner surface
IGNITER_TODO_PG_DSN="host=localhost user=alex dbname=igniter_todo_test" \
  scripts/todo_postgres_smoke.sh                      # one-command operator smoke (PASS/FAIL receipt)
cargo test --features machine                         # ReadThen + effect host + app tests (no DB)
IGNITER_TODO_PG_DSN=… cargo test --features postgres \
  --test todo_postgres_local_e2e_tests -- --test-threads=1   # real Postgres E2E (skips w/o DSN)
```

## Open product limitations (intentional v0)

- No typed row destructuring — `ReadThen` continuations receive rows as a JSON **string**.
- No request validation / no JSON-object body parsing.
- No generated ids (create key = idempotency key).
- No schema migration runner (DDL is operator-owned).
- No connection pool / backpressure; bounded, one-request-at-a-time loopback loop.
- No public listener mode, no deployment story, no stable CLI/API promise.
