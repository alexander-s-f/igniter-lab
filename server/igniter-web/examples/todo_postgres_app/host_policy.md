# todo_postgres_app — host policy (LAB-TODOAPP-API-IGWEB-SERVE-LOCAL-POSTGRES-P12)

This is the host-owned configuration reference for mapping this app's read/write intents to `igniter-machine` Postgres capability executors. The configuration is parsed by the web runner from the `--host-config host.toml` file at runtime.

> **Runnable, commit-safe config:** see [`host.example.toml`](host.example.toml) in this directory — it is the exact, parseable config (env-var names only) the runner accepts, plus the run command. The crate README's "Postgres Host Config (Operator)" section walks through it. The tables below are the conceptual policy this config expresses.
>
> **Product API contract:** see [`API.md`](API.md) for the route table, run modes (sync observed vs async machine), status semantics, idempotency, the object request-body contract (object `{ "title": … }` is the only accepted shape; the legacy string body was removed in P45), and the host-minted surrogate id (P36).

The app names only logical effect targets and structured intents; everything below is the **host's** concern. Schema/migrations are operator-owned and are managed at the database layer (not by the application compiler).

## Read policy (host-declared; mirrors `PostgresReadPolicy::allow_source_typed`)

| source | field | value kind |
|---|---|---|
| `accounts` | `id` | Text |
| `accounts` | `name` | Text |
| `todos` | `id` | Text |
| `todos` | `account_id` | Text |
| `todos` | `title` | Text |
| `todos` | `done` | Text (`"false"`/`"true"` — the app's `WriteValues.done` is a string in v0) |

Read capability id: `IO.PostgresRead`. The allowlisted read projection is `id,account_id,title,done` (per
`[postgres.read]` in `host.example.toml`); the `accounts` source (`id,name`) is allowlisted via
`[postgres.read.accounts]` for the two-stage account-existence read (P38). Row limit cap: e.g. `100`.
SELECT-only (mutating ops refused before the adapter). `eq`-only filters (v0).

## Write policy (host-declared; mirrors `PostgresWritePolicy`)

- target: `todos`
- key column: `id`
- writable columns: `account_id`, `title`, `done`

## Effect-target → capability map (the host effect-host seam's lookup)

| logical target (named in `.ig`) | capability | operation |
|---|---|---|
| `todo-create` | `IO.TodoWrite` | insert |
| `todo-done` | `IO.TodoWrite` | upsert |
| `todo-delete` | `IO.TodoWrite` | delete |

The app's `InvokeEffect { target: "todo-create" | "todo-done" | "todo-delete" }` carries the logical target only; the capability id / operation binding lives here, host-side. `done` is an `upsert` (the adapter is a single-statement `INSERT … ON CONFLICT DO UPDATE`); `delete` runs a `DELETE` under the same effect-receipt idempotency gate (LAB-TODOAPP-API-DELETE-P44). `insert`/`upsert`/`delete` are the allowlisted ops.

## Environment / connection

- `IGNITER_TODO_PG_DSN` — read **and** write DSN (one dedicated local DB; e.g. `igniter_todo_test`; never SparkCRM/dev business DBs). Referenced by both `[postgres.read]` and `[postgres.write]` in `host.example.toml`.
- `IGNITER_TODO_EFFECT_TOKEN` — the bearer token clients present (`Authorization: Bearer <value>`); named by each `[effects.*].passport_env`.
- loopback-only server; secret provider = env; no inline secrets, no TLS/pool in v0.

## Suggested local DDL (operator-owned; documentation only, applied externally)

```sql
CREATE TABLE accounts ( id text PRIMARY KEY, name text );
CREATE TABLE todos (
  id text PRIMARY KEY, account_id text NOT NULL REFERENCES accounts(id), title text,
  done text NOT NULL DEFAULT 'false', inserted_at timestamptz DEFAULT now()
);
CREATE TABLE effect_receipts (
  idempotency_key text PRIMARY KEY, correlation_id text, target text NOT NULL, business_key text NOT NULL
);
```

`done` is `text` (`"false"`/`"true"`) — the schema mirrors the app's authored `WriteValues.done` string. A
created `todos.id` is the host-minted surrogate (`todo_<digest>`, P36), not the idempotency key; the
`effect_receipts.business_key` records that surrogate.

Status: **Implemented and Active**. The policy is loaded and enforced at startup. Postgres capability executors run queries and writes against the database using either a fake in-memory adapter or a real local Postgres connection (under the `postgres` cargo feature and the `IGNITER_TODO_PG_DSN` env variable).
