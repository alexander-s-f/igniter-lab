# todo_postgres_app — host policy sketch (NOT runtime authority, NOT applied in P2)

This is **future host-owned config evidence** for when an effect-host seam wires this app's read/write
intents to the `igniter-machine` Postgres capability executors. It is **not** read by the runner today and
is **not** authored in `.igweb`/`.ig`. The app names only logical effect targets and structured intents;
everything below is the **host's** concern. Schema/migrations are operator-owned and are **not applied
here** (no DB connection in P2).

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

## Effect-target → capability map (the future effect-host seam's lookup)

| logical target (named in `.ig`) | capability | operation |
|---|---|---|
| `todo-create` | `IO.PostgresWrite` | insert |
| `todo-done` | `IO.PostgresWrite` | update |

The app's `InvokeEffect { target: "todo-create" | "todo-done" }` carries the logical target only; the
capability id / operation binding lives here, host-side.

## Environment / connection (future, local-only)

- `IGNITER_PG_DSN` — read DSN (a dedicated local DB; never SparkCRM/dev business DBs)
- `IGNITER_PG_WRITE_DSN` — write DSN (dedicated `igniter_pg_test`-style DB)
- loopback-only server; secret provider = env; no inline secrets, no TLS/pool in v0.

## Suggested local DDL (operator-owned; documentation only, NOT applied here)

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

Status: **shape only**. P2 executes no reads/writes; the effect-host seam (`LAB-IGNITER-WEB-EFFECT-HOST-READINESS`)
must land before any of this is wired.
