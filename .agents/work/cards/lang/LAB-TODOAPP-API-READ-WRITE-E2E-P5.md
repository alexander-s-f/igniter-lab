# LAB-TODOAPP-API-READ-WRITE-E2E-P5 - Product Todo read+write fake-host e2e

Status: CLOSED
Lane: standard
Type: implementation-proof
Delegation code: OPUS-TODOAPP-API-READ-WRITE-E2E-P5
Date: 2026-06-20
Skill: idd-agent-protocol

## Context

The Todo API Postgres-shaped stack now has both halves proven, but still as adjacent seams:

- `LAB-TODOAPP-API-READ-P3` / `LAB-IGNITER-WEB-READ-GUARD-HOST-P6` proved app-authored `QueryPlan`
  contracts can flow through a host-owned fake `PostgresReadExecutor` and into an app continuation.
- `LAB-TODOAPP-API-WRITE-P4` proved mutating Todo handlers now build `WriteIntent` through command
  contracts and still execute final `InvokeEffect` decisions through `MachineEffectHost` + fake write
  executor + receipts.

P5 should stitch these into one product-shaped fake-host e2e proof for `todo_postgres_app`, without live
Postgres and without pretending the runner is fully productized.

## Goal

Prove the smallest end-to-end product contour:

```text
GET /accounts/:account_id/todos
  -> app query contract builds QueryPlan
  -> host fake read executor returns rows
  -> app continuation returns Respond 200 / app-owned 404

POST /accounts/:account_id/todos
  -> app command contract builds WriteIntent
  -> handler emits logical InvokeEffect
  -> host MachineEffectHost executes fake write
  -> receipt/replay preserved
```

The proof can be a direct-dispatch / harness-level e2e. Do not force the whole socket runner to become
async/product-ready in this card. The goal is product shape and seam composition, not production serving.

## Verify First

Read live surfaces before editing:

- `server/igniter-web/examples/todo_postgres_app/routes.igweb`
- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`
- `server/igniter-web/tests/todo_postgres_app_tests.rs`
- `server/igniter-web/tests/todo_postgres_api_read_tests.rs`
- `server/igniter-web/tests/todo_postgres_api_write_tests.rs`
- `server/igniter-web/tests/todo_postgres_effect_host_tests.rs`
- `lab-docs/lang/lab-todoapp-api-read-p3-v0.md`
- `lab-docs/lang/lab-igniter-web-read-guard-host-p6-v0.md`
- `lab-docs/lang/lab-todoapp-api-write-p4-v0.md`
- `server/igniter-web/src/lib.rs`
- `server/igniter-server/src/effect_host.rs`
- `runtime/igniter-machine/src/postgres_read.rs`
- `runtime/igniter-machine/src/postgres_write.rs`
- `runtime/igniter-machine/tests/postgres_{read,write}_tests.rs`

Confirm or correct:

- whether there is already a reusable test harness that can combine the P3 read and P4 write paths;
- whether `todo_postgres_app` route handlers already expose enough product shape for read+write;
- whether direct `IgniterMachine::dispatch` is still the cleanest way to call query/continuation contracts;
- whether `InvokeEffect.input` is still string-only;
- whether fake read/write executors can be used in the same test without live DB / DSN.

Live code wins over this card.

## Recommended Shape

Prefer a focused machine-gated integration test:

```text
server/igniter-web/tests/todo_postgres_api_read_write_e2e_tests.rs
```

Suggested flow:

1. Build/load the `todo_postgres_app` authored files once.
2. Execute a product read for `acct-7` through the existing fake read host seam.
3. Assert the continuation returns a product `Respond` with expected rows / body.
4. Execute a product create or done route through the existing effect host seam.
5. Assert fake write executor records one committed write + receipt.
6. Replay the same idempotency key and assert exactly one executor mutation.
7. Assert app-authored files still contain no capability identity, DSN, SQL, passport, or `[effects]`.

If the existing read/write harnesses are too duplicated, extract the smallest **test-only** helper inside the
new test file. Do not create public API or move runner code unless live code proves it is required.

## Required Acceptance

- [x] Product read path and product write path are exercised in one test target.
- [x] Read uses app-authored `QueryPlan` contract, not Rust-invented SQL.
- [x] Read host policy gates source/fields before adapter.
- [x] Read found path returns app-owned 200.
- [x] Read empty path returns app-owned 404, not infra failure.
- [x] Write uses app-authored command contract / mutating route handler from P4.
- [x] Write executes through `MachineEffectHost` + fake write executor.
- [x] Write receipt/replay performs one executor mutation for the same idempotency key.
- [x] App-authored files contain no `capability_id`, `operation`, `scope`, passport, DSN, or raw SQL.
- [x] No live Postgres, no migrations, no `IGNITER_PG_DSN` / `IGNITER_PG_WRITE_DSN`.
- [x] Existing P3 read tests remain green.
- [x] Existing P4 write/effect-host tests remain green.
- [x] `server/igniter-web cargo test` remains green.
- [x] `server/igniter-web cargo test --features machine` remains green.
- [x] `runtime/igniter-machine postgres_read_tests` and `postgres_write_tests` remain green.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-20)

**Deliverable:** one new test target `server/igniter-web/tests/todo_postgres_api_read_write_e2e_tests.rs`
(`#![cfg(feature = "machine")]`); **no production code changed.** Proof doc:
`lab-docs/lang/lab-todoapp-api-read-write-e2e-p5-v0.md`.

**Outcome:** the P3 read seam and P4 write seam are stitched into ONE product contour for the authored
`examples/todo_postgres_app` (zero app Rust). `product_read_then_write_e2e` proves: read `ListTodosByAccount`
→ host fake `PostgresReadExecutor` → `AccountTodoIndexFromRows` → **200 found / 404 empty**; then POST create
→ `InvokeEffect` → `MachineEffectHost` + fake write executor → **committed**, and **replay same key → exactly
one** executor mutation. `product_app_has_no_authority_surface` proves the authored files name no
capability/DSN/SQL/passport/`[effects]` — host authority stays outside `.ig`/`.igweb`.

**Harness:** hybrid (read = direct `IgniterMachine::dispatch`; write = `build_app` + sync `app.call`
off-runtime + async effect host) — reuses the proven P3/P4 helpers as test-only code in the new file.

**Honest limitation:** `InvokeEffect.input` is string-only, so the intent's structured `WriteValues` aren't
carried to the executor (only `operation`/`key`). Next: `LAB-IGNITER-WEB-STRUCTURED-EFFECT-INPUT-READINESS-P*`,
then local-Postgres adapter swap, then effect-host runner productization.

**Proof — all green:** new e2e 2; P3 read 4 + P4 write 2 + effect-host 5 + read-host 4 + app 3 intact;
igniter-web 17/17 (default + machine); igniter-machine pg read 18 + write 10; `git diff --check` clean.

## Required Verification

Run and report exact counts:

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test --features machine --test todo_postgres_api_read_write_e2e_tests
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test --features machine --test todo_postgres_api_read_tests
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test --features machine --test todo_postgres_api_write_tests
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test --features machine --test todo_postgres_effect_host_tests
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test --features machine
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/runtime/igniter-machine && cargo test --no-default-features --test postgres_read_tests
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/runtime/igniter-machine && cargo test --no-default-features --test postgres_write_tests
git diff --check
```

## Required Proof Doc

Create:

```text
lab-docs/lang/lab-todoapp-api-read-write-e2e-p5-v0.md
```

It must state:

- exact authored files used;
- whether the proof uses direct dispatch, loopback, or a hybrid harness;
- exact read plan and fake rows;
- exact continuation decision for found and empty cases;
- exact write effect target/key/input and receipt/replay evidence;
- what remains blocked by string-only `InvokeEffect.input`;
- why host authority remains outside `.ig` / `.igweb`;
- what moves next toward local Postgres / product runner.

## Closed Scope

- No live Postgres / DSN / DDL / migrations / pool / TLS.
- No new `.igweb` syntax.
- No new IgWeb prelude decision unless already present and needed.
- No product runner async re-entry.
- No structured effect payload protocol unless already present.
- No server-core route table or domain logic.
- No capability id / operation / scope in app-authored files.
- No raw SQL.
- No ORM / schema inference.
- No public/canon/stable API claim.

## Suggested Next

If P5 lands cleanly:

1. `LAB-IGNITER-WEB-STRUCTURED-EFFECT-INPUT-READINESS-P*` if string-only input blocks real DB writes;
2. `LAB-TODOAPP-API-LOCAL-POSTGRES-P*` for local DDL + fake-to-real adapter swap;
3. `LAB-IGNITER-WEB-EFFECT-HOST-RUNNER-P*` for productizing runner execution after the sync/async seam is
   clear.
