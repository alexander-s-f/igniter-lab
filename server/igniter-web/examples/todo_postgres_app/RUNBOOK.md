# todo_postgres_app — RUNBOOK

**One page for an agent/operator: run it, know what's real, know what's not, and the command that
proves each claim.** Lab prototype — **loopback-only, local Postgres only, NOT production**, no stable
CLI/API promise.

Companion docs (read these for depth):
[API.md](API.md) (routes, status/error contract, body contract) ·
[host.example.toml](host.example.toml) (commit-safe operator config) ·
[host_policy.md](host_policy.md) (read/write/effect authority) ·
[../../IMPLEMENTED_SURFACE.md](../../IMPLEMENTED_SURFACE.md) (what `igniter-web` implements **today** —
the source-of-truth when an older doc disagrees).

## 1. What this app proves

Zero authored Rust — the whole product is `.igweb` routes + `.ig` handlers, built by the generic
`igweb-serve` runner:

- **`.igweb` routes + `.ig` handlers** — [routes.igweb](routes.igweb), [todo_handlers.ig](todo_handlers.ig).
- **`ReadThen` reads** — a handler emits a typed `QueryPlan`; the host runs it and re-enters the
  continuation with the rows. A continuation may emit another `ReadThen` (bounded sequential staged
  reads, P38). List uses a **two-stage** read: existing account + no todos → `200 []`; **missing account
  → 404 `account not found`** (P38); show of a missing row → app-owned 404.
- **`InvokeEffect` writes** — a handler emits a logical `target` (`todo-create` / `todo-done`) + a typed
  `WriteIntent`; the host binds the target to a Postgres write capability and executes it.
- **Host-owned Postgres authority** — DSN, capability id, source/field/target allowlists, bearer token,
  receipts all live in `host.toml` / the host, never in `.ig`.
- **Idempotency receipts** — replay of the same key performs no second mutation; same key + a different
  body → **409 conflict** (never a silent overwrite).
- **Local loopback runner** — bounded `--max-requests`, `127.0.0.1` only; a non-loopback bind is refused.

## 2. Run modes

| Mode | Build / command | Reads | Writes |
| --- | --- | --- | --- |
| **Sync observed** (default) | `cargo run --bin igweb-serve -- <app_dir>` | `ReadThen` is unhandled → **500** | `InvokeEffect` **observed** → 202 (no DB write) |
| **Async machine, no DB** (tests) | `cargo test --features machine` | executed against a **fake** read host | executed via `MachineEffectHost` over a fake adapter |
| **Local Postgres** (product path) | `cargo run --features postgres --bin igweb-serve -- --host-config … <app_dir>` | real `TokioPostgresReadAdapter` → 200/404 | real `TokioPostgresWriteAdapter` → 200 committed / dedup |

`GET /health` returns 200 in every mode.

## 3. Step-by-step local run (Postgres path)

```bash
# from server/igniter-web/

# 1. Create a DEDICATED local test DB (never production / never SparkCRM).
createdb igniter_todo_test

# 2. Create the operator-owned schema (the runner never migrates — DDL is yours).
#    See host_policy.md "Suggested local DDL" for the accounts/todos/effect_receipts tables.

# 3. Export secrets into the ENVIRONMENT (the committed host.example.toml holds env-var NAMES only).
export IGNITER_TODO_PG_DSN="host=localhost user=alex dbname=igniter_todo_test"
export IGNITER_TODO_EFFECT_TOKEN="some-local-bearer-token"

# 4. One-command operator smoke (builds the binary, serves a bounded loopback run, asserts the contract).
scripts/todo_postgres_smoke.sh
```

Expected: a compact PASS receipt (no token/DSN echoed) —

```text
todo_postgres_smoke: preflight ok (db=igniter_todo_test, loopback only; DSN/token not echoed)
todo_postgres_smoke: schema ready
todo_postgres_smoke: serving on http://127.0.0.1:<port> (bounded to 8 loopback requests)
  PASS  health -> 200 …
  PASS  create -> 200 … / create replay -> 200 …
  PASS  list found / show / done / done persisted …
  PASS  create replay: one receipt   1
todo_postgres_smoke: PASS
```

To drive the real binary directly instead of the smoke:

```bash
cargo run --features postgres --bin igweb-serve -- \
  --host-config examples/todo_postgres_app/host.example.toml \
  --addr 127.0.0.1:0 --max-requests 8 examples/todo_postgres_app
```

## 4. Troubleshooting

| Symptom | Cause | What you see |
| --- | --- | --- |
| smoke exits **2** at preflight | `IGNITER_TODO_PG_DSN` or `IGNITER_TODO_EFFECT_TOKEN` unset, or a non-local / `spark`/`prod`/`production` / empty dbname | a clear non-secret refusal line (override a non-local host with `IGNITER_TODO_SMOKE_ALLOW_NONLOCAL=1`) |
| binary exits **3** `[CONFIG_RESOLVE]` | a `*_env` in `host.toml` names an unset/empty env var | stderr names the **env var**, never its value; fails **before** the socket binds |
| binary exits **2** `[CONFIG_PARSE]` | inline secret / unknown section/key / non-loopback `--addr` in `host.toml` | coded stderr line; inline secret values are never echoed |
| binary exits **5** `[BIND_REFUSED]` | the `--addr` port is already in use | use `--addr 127.0.0.1:0` (ephemeral port) |
| binary exits **6** `[POSTGRES_CONNECT]` | DB unreachable / wrong DSN | message is **DSN-redacted** |
| HTTP **401** `{"error":"unauthorized"}` | wrong/missing `Authorization: Bearer <token>` (bad token) | per-request, not a process exit |
| HTTP **403** `{"error":"…"}` | the read plan asked for a source/field/op outside the host allowlist | names the requested source/field only — no DSN/SQL |
| HTTP **400** `{"body":"…"}` | keyless mutation (no `idempotency-key`) or invalid create body (non-string/empty/malformed JSON) | app-owned product error |
| HTTP **409** `{"error":"conflict"}` | same idempotency key reused with a different body | no mutation performed |

(Full status/body table: [API.md → Error contract](API.md).)

## 5. Limitations (intentional v0)

- **Local-only, not production** — loopback bind only; no daemon, no hosting, no deployment story; never
  point a DSN at a production or SparkCRM database.
- **No schema migrations** — DDL is operator-owned; the runner never creates or migrates tables.
- **Host-minted surrogate ids** — a create's business key is a deterministic host surrogate
  (`todo_<digest of method+path+idempotency_key>`), decoupled from the idempotency key (P36); not a DB
  sequence or random id.
- **No typed row destructuring** — `ReadThen` continuations receive rows as a JSON **string**.
- **Object create body (canonical) + legacy string (deprecated)** — create accepts `{ "title": "…" }`
  (parsed into the generic `req.body_json` map; the app reads `title`) and, during a **deprecated**
  compatibility window, a bare JSON string title (P35; policy P40). New clients use the object body; legacy
  string support is removed in a named follow-up once no caller depends on it. No general JSON query
  language / nested destructuring.
- **No pooling / backpressure** — one request at a time, bounded by `--max-requests`.
- **Multi-source reads** — `[postgres.read]` (primary) plus `[postgres.read.<name>]` extra sources (P38);
  the index route allowlists both `todos` and `accounts`. No JOINs / query language — each stage is one
  single-table plan.

## 6. Verification commands (each proves a claim)

From `server/igniter-web/`:

```bash
scripts/check_todo_product_surface.sh       # NO-DB CI guard for THIS app: body contract + idempotency conflict + error contract + list-empty + host.example parse + smoke-refusal (needs no env, no DB)
scripts/check_implemented_surface.sh        # bounded guard: ReadThen + effect path + diagnostics + example + postgres-free tree (runner machinery)
cargo test --features machine               # ReadThen + StagedReadHost + MachineEffectHost + diagnostics + error contract (no DB)
cargo test --test todo_error_contract_tests # app-owned error shapes (404/405/400), sync, no DB
cargo test --features postgres --test todo_postgres_local_e2e_tests -- --test-threads=1   # real binary vs local Postgres; skips cleanly without IGNITER_TODO_PG_DSN
IGNITER_TODO_PG_DSN="host=localhost user=alex dbname=igniter_todo_test" \
IGNITER_TODO_EFFECT_TOKEN="dev-token" \
  scripts/todo_postgres_smoke.sh            # one-command operator smoke → PASS receipt
```
