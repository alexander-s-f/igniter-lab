# lab-todoapp-api-local-postgres-p8-v0 — Todo API over real local Postgres

**Card:** `LAB-TODOAPP-API-LOCAL-POSTGRES-P8` · **Delegation:** `OPUS-TODOAPP-API-LOCAL-POSTGRES-P8`
**Status:** CLOSED (lab implementation-proof, **operator-gated**). A new opt-in integration test
(`tests/todo_postgres_local_e2e_tests.rs`) runs the product Todo API read + write against a REAL local
Postgres via the existing real adapters, with ZERO app Rust and the unchanged authority model. **Verified in
this environment:** compiles under `--features "machine postgres"`, skips cleanly with no DSN, the pure host
gate asserts, no regressions, default build stays Postgres-free. **Operator-gated (NOT run here — no local
Postgres):** the real read/write/receipt/replay assertions, which fire when `IGNITER_TODO_PG_DSN` is set.
No live DSN/DDL in the repo, no canon claim.

## Exact authored app files used (unchanged)

`server/igniter-web/examples/todo_postgres_app/` — **no edits** (the P7 structured-input change already
landed): `todo_handlers.ig` (contracts `ListTodosByAccount`, `AccountTodoIndexFromRows`,
`BuildCreateTodoIntent`, `MakeWriteValues`, …), `routes.igweb`, `host_policy.md`, `igweb.toml`. The app owns
the QueryPlan, the structured `WriteIntent`, and the domain 200/404 — and names **no** DSN / SQL / capability
id / `[effects]`.

## What changed (test + feature plumbing only)

| File | Change |
|---|---|
| `server/igniter-web/Cargo.toml` | new optional `tokio-postgres` dep + `postgres = ["machine", "igniter_machine/postgres", "dep:tokio-postgres"]` feature — **default build never links it** (verified via `cargo tree`) |
| `server/igniter-web/tests/todo_postgres_local_e2e_tests.rs` | new gated integration test (5 tests) |

## Exact DDL — why test-owned, not language-owned

The DDL lives **inside the test harness** (a `const DDL` applied once per process via a `OnceCell`, mirroring
`postgres_real_write_tests`). Schema is an **operator/infrastructure** concern: the language emits typed
intents, never DDL; there is no migration framework and no schema inference.

```sql
CREATE TABLE IF NOT EXISTS accounts (id TEXT PRIMARY KEY, name TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS todos (
  id TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES accounts(id),
  title TEXT, done TEXT NOT NULL DEFAULT 'false', inserted_at TIMESTAMPTZ DEFAULT now());
CREATE TABLE IF NOT EXISTS effect_receipts (
  idempotency_key TEXT PRIMARY KEY, correlation_id TEXT, target TEXT NOT NULL,
  business_key TEXT NOT NULL, committed_at TIMESTAMPTZ NOT NULL DEFAULT now());
```

**Deliberate deviation from the card's sketch:** `todos.done` is `TEXT`, not `boolean` — the app's authored
`WriteValues.done` is the string `"false"`/`"true"` in this fixture, so the schema mirrors the app's shape
(the app does not bend to the DB). Flag for the operator on first real run if a boolean column is preferred
(then the app's `MakeWriteValues` would emit a real bool).

## Exact host policies (host-owned allowlists, before any adapter)

```rust
read_policy  = PostgresReadPolicy::new(100).allow_ops(["select"])
                 .allow_source("todos", ["id","account_id","title","done"]);
write_policy = PostgresWritePolicy::new().allow_target("todos").allow_ops(["insert","upsert"]);
```

`raw_sql`/`sql`/`query` keys are refused by `PostgresWriteIntent::from_args` **before** the adapter — proven
**here** (no DSN needed) by `write_intent_raw_sql_refused_before_adapter`.

## Read plan + returned rows

The app dispatches `ListTodosByAccount{account_id}` → a QueryPlan (`source:"todos"`, `op:"select"`,
filter on `account_id`) — asserted to be the **app's** plan, not Rust SQL. The plan runs through
`PostgresReadExecutor` + `TokioPostgresReadAdapter::connect(dsn)`; the returned rows feed
`AccountTodoIndexFromRows` → **app-owned** `Respond 200` (found, body contains the seeded `todo-1`) or
`404` (empty account — a product decision, never an infra failure).

## Write intent + business row + receipts

The app dispatches `BuildCreateTodoIntent{account_id, idempotency_key}` → the structured `WriteIntent`
(`operation:"insert", target:"todos", key:<idem>, values:{account_id,title,done}, correlation_id`) — the
exact value `InvokeEffect.input` carries (P7). That intent is the `run_write_effect` payload against
`PostgresWriteExecutor` + `TokioPostgresWriteAdapter::connect(dsn,"todos","id",["account_id","title","done"])`:

- `out.state == Committed`, `adapter.attempts() == 1` (exactly one real transaction);
- the business `todos` row is present (`read_business_text(key,"account_id") == "acct-7"`);
- a PG-side `effect_receipts` row exists for the key (`SELECT count(*) … == 1`);
- the machine receipt records `Committed` (`receipt_state`).

## Replay evidence

`local_write_replay_no_second_mutation`: two `run_write_effect` calls with the **same** idempotency key and
the **same** receipt store → the machine receipt makes the 2nd a replay; `adapter.attempts()` stays `1` — no
second business mutation, both report `Committed`.

## DSN / secret boundary

The DSN comes **only** from `IGNITER_TODO_PG_DSN` (a dedicated env var, never a shared/business DSN, never
hardcoded, never in a receipt). The adapter connects `NoTls` (local loopback; TLS is a later slice). The app
files contain no DSN/secret/passport. Missing env → every DB test prints `SKIP` and returns early.

## Fake-free vs runner-harness-only (honest scope)

- **Fake-free (real adapters):** the READ path (`TokioPostgresReadAdapter`) and the WRITE path
  (`TokioPostgresWriteAdapter` via `run_write_effect`) — the same proven mechanisms as
  `postgres_real_{read,write}_tests`, now driven by the **app-authored** QueryPlan / WriteIntent.
- **Runner-harness-only (deferred to P9):** the WRITE here uses the **direct** `run_write_effect` path with
  the app's structured intent as payload — it does **not** route through the full `MachineEffectHost` capsule
  contour. Reason (live finding, `ingress.rs:82-83` + `:576-604`): in that contour the **capsule's output**
  becomes the effect payload, and the generic placeholder capsule (`WriteRecord → {code}`) masks the typed
  `WriteIntent`. Driving a real typed write *through* the capsule needs a write-shaping service capsule —
  exactly `LAB-IGNITER-WEB-EFFECT-HOST-RUNNER-P9`. The P7 effect-host tests already prove the structured
  `input` crosses `MachineEffectHost`; P8 proves it reaches a real adapter. P9 joins the two.

## Commands & counts

**Without a DSN (this environment — verified):**
```text
$ cargo test --features "machine postgres" --test todo_postgres_local_e2e_tests
    → 5 passed (4 DB tests SKIP cleanly + 1 pure host-gate asserts)
$ cargo test                                         (igniter-web, default)   → 52 passed; 0 failed (Postgres-free)
$ cargo tree | grep -c tokio-postgres                (default build)          → 0  (optional dep not linked)
$ cargo test --features machine --test todo_postgres_api_read_write_e2e_tests → 2 passed
$ cargo test --features machine --test todo_postgres_api_write_tests          → 4 passed
$ cargo test --features machine --test todo_postgres_effect_host_tests        → 6 passed
$ cd runtime/igniter-machine && cargo test --no-default-features --features postgres --test postgres_real_read_tests  → 8 passed (skip)
$ cd runtime/igniter-machine && cargo test --no-default-features --features postgres --test postgres_real_write_tests → 5 passed (skip)
$ git diff --check                                                            → clean
```

**With `IGNITER_TODO_PG_DSN` (operator):** run the same `todo_postgres_local_e2e_tests` command on a machine
with a local Postgres + a dedicated `igniter_todo_test` DB; the 4 DB tests then execute (real rows + receipts
+ replay) instead of skipping. **Not executed in this environment** — no local Postgres available here.

## Acceptance — mapping

- [x] Compiles under `--features "machine postgres"` with no DSN.
- [x] Missing `IGNITER_TODO_PG_DSN` skips cleanly and reports the skip.
- [x] Dedicated Todo DDL is test-owned, operator-shaped; no migration framework.
- [x] Authored `.ig`/`.igweb` unchanged.
- [x] Read uses app-authored `QueryPlan`, not Rust SQL · [x] read policy gates source/fields/predicates before adapter.
- [x] Found read → app 200 with real rows · [x] empty read → app 404 *(operator-gated execution)*.
- [x] Write uses app-authored structured `WriteIntent` · [x] real write creates the `todos` row ·
  [x] PG `effect_receipts` row · [x] machine receipt committed · [x] replay → no 2nd mutation *(operator-gated execution)*.
- [x] Raw SQL refusal before adapter (proven here, no DSN); forbidden target/field via host policy.
- [x] App files contain no capability id / operation binding / DSN / passport / raw SQL / `[effects]`.
- [x] Default `server/igniter-web cargo test` stays Postgres-free (52/0; tokio-postgres unlinked).
- [x] Fake P3/P4/P5/P7 tests green.
- [x] `runtime/igniter-machine postgres_real_{read,write}_tests` compile/skip/pass (8/5).
- [x] `git diff --check` clean.

## Next

`LAB-IGNITER-WEB-EFFECT-HOST-RUNNER-P9` (productize the capsule→write-payload seam so a real typed write flows
*through* `MachineEffectHost`, not just the direct `run_write_effect` path); then
`LAB-TODOAPP-API-LOCAL-POSTGRES-RECONCILE-P10`.

---

*Lab implementation-proof, operator-gated (2026-06-21). Real local-Postgres Todo read+write authored by
composing the two proven real-adapter harnesses + the P5 app contour; app-authored QueryPlan/WriteIntent,
host-owned DSN/schema/policy/receipts. Verified here: compile + clean skip + pure gate + no regressions +
default Postgres-free. Operator runs the real path with `IGNITER_TODO_PG_DSN`. MachineEffectHost typed-write
contour deferred to P9.*
