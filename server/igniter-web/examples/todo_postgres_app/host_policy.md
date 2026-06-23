# todo_postgres_app — host policy (LAB-TODOAPP-API-IGWEB-SERVE-LOCAL-POSTGRES-P12)

This is the host-owned configuration reference for mapping this app's read/write intents to `igniter-machine` Postgres capability executors. The configuration is parsed by the web runner from the `--host-config host.toml` file at runtime.

> **Runnable, commit-safe config:** see [`host.example.toml`](host.example.toml) in this directory — it is the exact, parseable config (env-var names only) the runner accepts, plus the run command. The crate README's "Postgres Host Config (Operator)" section walks through it. The tables below are the conceptual policy this config expresses.
>
> **Product API contract:** see [`API.md`](API.md) for the route table, run modes (sync observed vs async machine), status semantics, idempotency, and the v0 request-body contract.

The app names only logical effect targets and structured intents; everything below is the **host's** concern. Schema/migrations are operator-owned and are managed at the database layer (not by the application compiler).

## Read policy (host-declared; mirrors `PostgresReadPolicy::allow_source_typed`)

| source | field | value kind |
|---|---|---|
| `accounts` | `id` | Text |
| `accounts` | `name` | Text |
| `todos` | `id` | Text |
| `todos` | `account_id` | Text |
| `todos` | `title` | Text |
| `todos` | `done` | Boolean |
| `todos` | `inserted_at` | Timestamp |

Row limit cap: e.g. `100`. SELECT-only (mutating ops refused before the adapter). `eq`-only filters (v0).

## Write policy (host-declared; mirrors `PostgresWritePolicy`)

- target: `todos`
- key column: `id`
- writable columns: `account_id`, `title`, `done`

## Effect-target → capability map (the host effect-host seam's lookup)

| logical target (named in `.ig`) | capability | operation |
|---|---|---|
| `todo-create` | `IO.PostgresWrite` | insert |
| `todo-done` | `IO.PostgresWrite` | update |

The app's `InvokeEffect { target: "todo-create" | "todo-done" }` carries the logical target only; the capability id / operation binding lives here, host-side.

## Environment / connection

- `IGNITER_PG_DSN` — read DSN (a dedicated local DB; never SparkCRM/dev business DBs)
- `IGNITER_PG_WRITE_DSN` — write DSN (dedicated `igniter_pg_test`-style DB)
- loopback-only server; secret provider = env; no inline secrets, no TLS/pool in v0.

## Suggested local DDL (operator-owned; documentation only, applied externally)

```sql
CREATE TABLE accounts ( id text PRIMARY KEY, name text );
CREATE TABLE todos (
  id text PRIMARY KEY, account_id text NOT NULL, title text, done boolean,
  inserted_at timestamptz DEFAULT now()
);
CREATE TABLE effect_receipts (
  idempotency_key text PRIMARY KEY, correlation_id text, target text, business_key text
);
```

Status: **Implemented and Active**. The policy is loaded and enforced at startup. Postgres capability executors run queries and writes against the database using either a fake in-memory adapter or a real local Postgres connection (under the `postgres` cargo feature and `IGNITER_PG_DSN`/`IGNITER_PG_WRITE_DSN` env variables).
