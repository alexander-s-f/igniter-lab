# LAB-TODOAPP-API-PRODUCT-SURFACE-P41 — historical product-surface checkpoint

**Date:** 2026-06-23
**Type:** documentation + CI/smoke hardening (drift-prevention; NO behavior change)
**Delegation:** OPUS-TODOAPP-API-PRODUCT-SURFACE-P41
**Authority note:** lab evidence only — this is the `examples/todo_postgres_app` product surface, not Igniter canon.

> **Superseded status note (2026-06-26).** This P41 checkpoint is historical. It was current when written,
> but later cards landed the app-scoped error envelope (`P43`), delete (`P44`), legacy string-body removal
> (`P45`), keyset pagination (`P47`), and the generic typed `ReadThen`/`DatasetMeta` boundary. For current
> Todo API behavior, start with
> `server/igniter-web/examples/todo_postgres_app/API.md` and
> `server/igniter-web/IMPLEMENTED_SURFACE.md`; do not route new work from the P41 route table below.

This was the current surface for the Todo API at P41. It superseded scattered re-reading of
P18/P20/P35/P36/P38 proof docs at the time; the current front doors listed above now supersede this packet.
Everything below was **implemented and verified as of P41** unless a row says *designed*.

## Route table (machine/product path)

| Method & path | Handler | Idempotency | Success | Not-found / denied |
| --- | --- | --- | --- | --- |
| `GET /health` | `Health` | — | 200 `ok` | — |
| `GET /accounts/:account_id/todos` | `AccountTodoIndex` → **two-stage** `ReadThen` | — | 200 rows; existing account + empty → **`200 []`** | **404 `account not found`** if the account row is absent (P38); denied → 403; read error → 503 |
| `GET /accounts/:account_id/todos/:todo_id` | `AccountTodoShow` → `ReadThen(FindTodo)` | — | 200 row JSON | 404 `todo not found`; 403/503 as above |
| `POST /accounts/:account_id/todos` | `AccountTodoCreate` → `InvokeEffect{todo-create}` | **required** | 200 committed (replay → 200 dedup) | keyless → 400; invalid body → 400; same key + different body → 409; sync mode → 202 observed |
| `POST /accounts/:account_id/todos/:todo_id/done` | `AccountTodoDone` → `InvokeEffect{todo-done}` | **required** | 200 committed (replay → 200 dedup) | keyless → 400; same key + different `todo_id` → 409; sync mode → 202 |

Unmatched path → 404; wrong method on a known pattern → 405. Source of truth: `routes.igweb` + `todo_handlers.ig`.

## Request body (create)

- **Canonical (P35):** JSON object `{ "title": "Buy milk" }`. The host parses it to the generic
  `req.body_json : Map[String, Unknown]`; the app reads `title` via `map_get_string` (fail-closed).
- **Legacy (DEPRECATED — compatibility window, P35/P40):** a bare JSON string `"Buy milk"` is still accepted;
  to be removed once no caller depends on it.
- **400** for: object missing/non-string/empty/blank `title`; array/number/bool/null; empty/malformed body.
  Message: `create body must provide a non-empty title` (no body value echoed). `done` ignores the body.

## Id & idempotency semantics

- **Resource id (P36):** the created `todos.id` is a **host-minted surrogate** —
  `todo_<blake3(method ␟ path ␟ idempotency_key)[..32]>`, minted by the host (`igniter_web::surrogate_id`),
  prefixed `todo_` by the app. It is **decoupled** from the idempotency key; the raw key is never the id.
- **Idempotency key:** the `idempotency-key` header is the **effect** identity (replay/correlation). Receipts
  (machine + PG `effect_receipts.idempotency_key`) key on it. `effect_receipts.business_key` records the
  surrogate id. Replaying the same key performs no second mutation; same key + different body → 409.
- `done` targets the previously-minted id as its route `todo_id`.

## Read semantics

- **Implemented:** account-existence two-stage read (P38) — stage 1 reads `accounts` (empty ⇒ 404), stage 2
  reads `todos` (empty ⇒ `200 []`). Generic sequential `ReadThen` with a host-opaque `carry` and a bounded
  loop (`MAX_READ_HOPS = 8`). Read **freshness** (P23): uncorrelated reads run fresh; `x-correlation-id`
  opts into replay. Multi-source read allowlist via `[postgres.read.<name>]`.
- **Not a separate "designed/pending" item anymore** — P38 implemented what the P37 readiness packet
  designed; the only deferred read items are typed row destructuring (rows still cross as a JSON string) and
  JOINs / a query language (explicitly out of scope).

## Error body shapes (owner-shaped; envelope deferred — P39)

- **App-owned** (`.ig` `Respond`): `{"body": "<message>"}` — 400 (keyless / invalid body), 404 (route /
  account / todo not found), 405.
- **Host-owned read** (`dispatch_with_read`): 403/503/500 `{"error": "<string>"}` (names only the requested
  source/field/op).
- **Host-owned write** (`ingress.rs`): `{"status":"committed","result":…}` / `accepted_unknown` +
  `correlation_id` / `denied` + `detail` / `retry_later` / `failed`.
- No body leaks a DSN, bearer token, raw SQL, or host-config path. A single `{error:{code,message}}` envelope
  is a **decided-but-deferred** P39 follow-on (app-scoped `RespondError`); not implemented here.

## Host env / config (operator)

- `host.example.toml` is the exact, commit-safe, parseable config (env-var **names** only).
- `IGNITER_TODO_PG_DSN` — read **and** write DSN (one dedicated local DB, e.g. `igniter_todo_test`).
- `IGNITER_TODO_EFFECT_TOKEN` — bearer token (`Authorization: Bearer <value>`), named by `[effects.*].passport_env`.
- Read allowlist: `todos(id,account_id,title,done)` + `accounts(id,name)`; write: `todos`, ops `insert,upsert`,
  key `id`, cols `account_id,title,done`. The app names no DSN, token, capability, route, or SQL.

## Canonical curl

```bash
# health
curl http://127.0.0.1:PORT/health

# list (existing account → rows or 200 []; missing account → 404)
curl http://127.0.0.1:PORT/accounts/acct-1/todos

# create (OBJECT body is canonical) → 200; response/list carries the minted todo_<id>
curl -X POST -H "Authorization: Bearer $IGNITER_TODO_EFFECT_TOKEN" \
     -H 'idempotency-key: k1' --data '{"title":"Buy milk"}' \
     http://127.0.0.1:PORT/accounts/acct-1/todos

# show / done target the minted id (e.g. todo_ab12…), not the idempotency key
curl http://127.0.0.1:PORT/accounts/acct-1/todos/todo_ab12...
curl -X POST -H "Authorization: Bearer $IGNITER_TODO_EFFECT_TOKEN" \
     -H 'idempotency-key: k2' http://127.0.0.1:PORT/accounts/acct-1/todos/todo_ab12.../done
```

## Exact test / guard commands

```bash
cd server/igniter-web

# No-DB product-surface guard (CI): test steps + host.toml parse + smoke-preflight refusal + doc markers.
bash scripts/check_todo_product_surface.sh

# No-DB suites individually
cargo test --features machine --test todo_postgres_app_tests          # routes + body matrix + list-empty
cargo test --features machine --test todo_error_contract_tests        # app error shapes, no leak
cargo test --features machine --test todo_postgres_effect_host_tests  # idempotency conflict + object/legacy create
cargo test --features machine --test todo_postgres_async_runner_smoke_tests  # ReadThen + write + replay

# Real local Postgres e2e (operator-gated; skips cleanly without the DSN)
IGNITER_TODO_PG_DSN="host=localhost user=alex dbname=igniter_todo_test" \
  cargo test --features "machine postgres" --test todo_postgres_local_e2e_tests -- --test-threads=1
```

## What P41 changed

- `scripts/check_todo_product_surface.sh`: added a **DB-free doc-marker step** — asserts API.md carries the
  current body (`req.body_json`), id (`surrogate id`), account-existence (`account not found`), and error
  (`Error contract`) markers, and that superseded claims (P18 string-only message, idem-key-as-id) are
  **absent**. Catches doc drift the test steps cannot.
- `host_policy.md`: corrected stale values to match `host.example.toml` + the `.ig` — write capability
  `IO.PostgresWrite`→`IO.TodoWrite`, op `update`→`upsert`, env `IGNITER_PG_DSN`/`_WRITE_DSN`→`IGNITER_TODO_PG_DSN`
  (+ `IGNITER_TODO_EFFECT_TOKEN`), `done boolean`→`text`; noted the surrogate id + the two-stage `accounts` read.
- `API.md` / `RUNBOOK.md` were already current (P35/P36/P38/P40); no contradictory wording remains (guarded now).

## Verification

- `bash scripts/check_todo_product_surface.sh` → **PASS** (6 test/smoke steps + 6 doc markers).
- No-DB Todo suites green; `git diff --check` clean. No production behavior changed.

## Designed-vs-implemented (explicit, so it is never blurred)

| Capability | State |
| --- | --- |
| object create body, surrogate id, account-existence 404 vs 200 [] | **implemented** (P35/P36/P38) |
| product error `{code,message}` envelope | **designed, deferred** (P39 — app-scoped `RespondError`) |
| legacy string-body removal | **decided: deprecate now, remove later** (P40) |
| typed row destructuring, JOINs / query language, response pooling/TLS | out of scope |
| `scripts/todo_postgres_smoke.sh` (operator, DB-gated) | **known stale** — legacy body + pre-P36 id; fix flagged separately (does not affect this no-DB guard, which only checks the smoke's preflight refusal) |
