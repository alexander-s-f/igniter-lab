# LAB-TODOAPP-API-LOCAL-POSTGRES-P8 - Todo API local Postgres e2e over real adapters

Status: CLOSED
Lane: parallel / TodoApp API / local-Postgres
Type: implementation-proof
Delegation code: OPUS-TODOAPP-API-LOCAL-POSTGRES-P8
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

The product-shaped Todo API stack has now been proven with fake host adapters:

- `LAB-TODOAPP-API-SHAPE-P2` created `server/igniter-web/examples/todo_postgres_app/`.
- `LAB-TODOAPP-API-READ-P3` proved the app-authored read/query half.
- `LAB-TODOAPP-API-WRITE-P4` proved the write/effect-host half.
- `LAB-TODOAPP-API-READ-WRITE-E2E-P5` stitched read + write in one fake-host product contour.
- `LAB-IGNITER-WEB-STRUCTURED-EFFECT-INPUT-P7` removed the string choke: `InvokeEffect.input` now carries
  structured JSON, so `PostgresWriteIntent::from_args` can consume the app-authored `WriteIntent`.

The remaining product pressure is to swap the fake adapters for local Postgres, without changing the
authority model:

```text
.ig/.igweb app owns query/write intent and domain 404/400 decisions
host owns DSN, schema, allowlists, adapter choice, receipts, idempotency
server owns transport only
```

## Goal

Prove the smallest local-Postgres Todo API e2e:

```text
GET  /accounts/:account_id/todos
  -> app QueryPlan
  -> real TokioPostgresReadAdapter
  -> rows
  -> app continuation Respond 200 / app-owned 404

POST /accounts/:account_id/todos
  -> app WriteIntent
  -> InvokeEffect structured input
  -> MachineEffectHost
  -> real TokioPostgresWriteAdapter
  -> business row + effect_receipts + machine receipt
  -> replay same idempotency key performs no second business mutation
```

This is an opt-in local proof, not production runner stabilization.

## Verify First

Read live code before editing:

- `server/igniter-web/examples/todo_postgres_app/{routes.igweb,todo_handlers.ig,host_policy.md,igweb.toml}`
- `server/igniter-web/tests/todo_postgres_api_read_write_e2e_tests.rs`
- `server/igniter-web/tests/todo_postgres_api_{read,write}_tests.rs`
- `server/igniter-web/tests/todo_postgres_effect_host_tests.rs`
- `server/igniter-web/src/lib.rs`
- `runtime/igniter-machine/src/postgres_{read,write,real}.rs`
- `runtime/igniter-machine/tests/postgres_real_{read,write}_tests.rs`
- `lab-docs/lang/lab-igniter-web-structured-effect-input-p7-v0.md`

Confirm or correct:

- whether real read/write adapters already support the Todo schema types and predicates needed here;
- whether existing real tests use app-independent tables (`companies`, `leads`) and need a new Todo-local DDL;
- whether one DSN can safely serve read+write, or whether the test must require `IGNITER_TODO_PG_DSN`;
- whether schema setup should be in a test-only helper and gated by a dedicated env var;
- whether the hybrid P5 harness can be reused, or should be cloned into a new real-adapter test target.

Live code wins over this card.

## Recommended Shape

Prefer one machine-gated, postgres-gated integration test target:

```text
server/igniter-web/tests/todo_postgres_local_e2e_tests.rs
```

Use a dedicated env var:

```text
IGNITER_TODO_PG_DSN="host=localhost user=... dbname=igniter_todo_test"
```

If it is missing, tests must skip cleanly, while still compiling under:

```bash
cargo test --features "machine postgres" --test todo_postgres_local_e2e_tests
```

Use operator-owned test DDL inside the test harness only:

```sql
CREATE TABLE IF NOT EXISTS accounts (
  id text PRIMARY KEY,
  name text NOT NULL
);

CREATE TABLE IF NOT EXISTS todos (
  id text PRIMARY KEY,
  account_id text NOT NULL REFERENCES accounts(id),
  title text,
  done boolean NOT NULL DEFAULT false,
  inserted_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS effect_receipts (
  idempotency_key text PRIMARY KEY,
  correlation_id text,
  target text NOT NULL,
  business_key text NOT NULL,
  committed_at timestamptz NOT NULL DEFAULT now()
);
```

Clean only the test keys it owns. Do not touch arbitrary rows.

## Required Acceptance

- [x] Test compiles under `--features "machine postgres"` with no DSN.
- [x] Missing `IGNITER_TODO_PG_DSN` skips cleanly and reports the skip.
- [x] Dedicated Todo DDL is test-owned and operator-shaped; no migrations framework introduced.
- [x] Authored `.ig` / `.igweb` files remain unchanged.
- [x] Read uses app-authored `QueryPlan`, not Rust-invented SQL.
- [x] Read policy gates source/fields/predicates before adapter.
- [x] Found read returns app-owned 200 with real rows. *(authored; operator-gated execution)*
- [x] Empty read returns app-owned 404, not infra failure. *(authored; operator-gated execution)*
- [x] Write uses app-authored structured `WriteIntent` (the P7 `InvokeEffect.input` value).
- [x] Real write creates/updates the `todos` business row. *(authored; operator-gated execution)*
- [x] Real write creates a PG-side `effect_receipts` row. *(authored; operator-gated execution)*
- [x] Machine receipt records committed state. *(authored; operator-gated execution)*
- [x] Replay same idempotency key performs no second business mutation. *(authored; operator-gated execution)*
- [x] Raw SQL refusal before adapter proven here (no DSN); forbidden target/field via host policy.
- [x] App files contain no capability id, operation binding, DSN, passport, raw SQL, or `[effects]`.
- [x] Default `server/igniter-web cargo test` remains Postgres-free (52/0; tokio-postgres unlinked).
- [x] Existing fake P3/P4/P5/P7 tests remain green.
- [x] `runtime/igniter-machine postgres_real_{read,write}_tests` still compile/skip/pass (8/5).
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-21)

**Outcome:** an opt-in local-Postgres Todo e2e (`tests/todo_postgres_local_e2e_tests.rs`) — authored by
composing the two proven real-adapter harnesses (`postgres_real_{read,write}_tests`) + the P5 app contour,
driven by the **app-authored** QueryPlan / structured WriteIntent. Proof doc:
`lab-docs/lang/lab-todoapp-api-local-postgres-p8-v0.md`.

**Verified in this environment:** compiles under `--features "machine postgres"`; with no DSN all 5 tests
pass (4 DB tests SKIP cleanly + 1 pure host-gate asserts raw-SQL refusal); default `igniter-web` stays
Postgres-free (52/0, `tokio-postgres` **not linked** per `cargo tree`); fake P5/P7 green (2/4/6); machine real
read/write compile+skip (8/5); `git diff --check` clean.

**Operator-gated (NOT run here — no local Postgres):** the real read 200/404, real write business row +
`effect_receipts` row + machine receipt, and replay (no 2nd mutation). They execute when
`IGNITER_TODO_PG_DSN` (dedicated test DB) is set.

**Plumbing:** added an optional `tokio-postgres` dep + `postgres = ["machine", "igniter_machine/postgres",
"dep:tokio-postgres"]` feature to `igniter-web`. Test-owned DDL (accounts/todos/effect_receipts) applied once
via `OnceCell`; cleans only its own keys/ids/account. One deliberate deviation: `todos.done TEXT` (matches the
app's string `WriteValues.done`).

**Honest scope (deferred to P9):** the WRITE uses the **direct** `run_write_effect` path with the app's
structured intent as payload, NOT the full `MachineEffectHost` capsule contour — because that contour makes
the **capsule output** the write payload (`ingress.rs:82-83`, `:576-604`) and the generic `WriteRecord`
capsule masks the typed `WriteIntent`. A real typed write *through* the capsule needs a write-shaping service
capsule = `LAB-IGNITER-WEB-EFFECT-HOST-RUNNER-P9`. P7 proved the structured input crosses MachineEffectHost;
P8 proves it reaches a real adapter; P9 joins them.

**Next:** `LAB-IGNITER-WEB-EFFECT-HOST-RUNNER-P9`, then `LAB-TODOAPP-API-LOCAL-POSTGRES-RECONCILE-P10`.

## Required Verification

Run and report exact counts:

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test --features "machine postgres" --test todo_postgres_local_e2e_tests
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test --features machine --test todo_postgres_api_read_write_e2e_tests
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test --features machine --test todo_postgres_api_write_tests
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/runtime/igniter-machine && cargo test --no-default-features --features postgres --test postgres_real_read_tests
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/runtime/igniter-machine && cargo test --no-default-features --features postgres --test postgres_real_write_tests
git diff --check
```

If a local DSN is available, run the same `todo_postgres_local_e2e_tests` command with
`IGNITER_TODO_PG_DSN` and report real pass counts separately from skip counts.

## Required Proof Doc

Create:

```text
lab-docs/lang/lab-todoapp-api-local-postgres-p8-v0.md
```

It must state:

- exact authored app files used;
- exact DDL and why schema is operator/test-owned, not language-owned;
- exact host read/write policies;
- exact read plan and returned rows;
- exact write intent, business row, PG receipt, machine receipt;
- replay evidence;
- DSN/secret boundary;
- what stayed fake-free vs what stayed runner-harness only;
- exact commands/counts with and without DSN.

Update this card with a closing report.

## Closed Scope

- No production deployment or public bind.
- No migration framework.
- No pool/TLS unless already present and unavoidable.
- No server-core domain logic.
- No route table in server.
- No raw SQL from `.ig` / `.igweb`.
- No ORM / schema inference.
- No runner productization beyond what the test harness requires.
- No benchmark/performance claim.
- No canon claim.

## Suggested Next

If P8 lands cleanly:

1. `LAB-IGNITER-WEB-EFFECT-HOST-RUNNER-P9` — productize the runner seam for read/write execution;
2. `LAB-TODOAPP-API-LOCAL-POSTGRES-RECONCILE-P10` — prove reconcile/unknown path against local PG;
3. `LAB-TODOAPP-API-PROTO-BENCH-P*` — measure request contour after local correctness is proven.
