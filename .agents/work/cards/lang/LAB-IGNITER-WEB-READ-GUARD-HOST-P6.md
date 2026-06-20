# LAB-IGNITER-WEB-READ-GUARD-HOST-P6 - Direct-dispatch read guard host proof

Status: CLOSED
Lane: standard
Type: implementation-proof
Delegation code: OPUS-IGWEB-READ-GUARD-HOST-P6
Date: 2026-06-20
Skill: idd-agent-protocol

## Context

`LAB-IGNITER-WEB-READ-GUARD-HOST-READINESS-P5` chose the first honest read seam:

```text
query contract -> QueryPlan
host executes read under PostgresReadPolicy
rows -> authored continuation
continuation -> ordinary final Decision
```

Do **not** implement the final staged `.igweb` syntax yet. P5 explicitly says v0 should be a
machine-gated **direct-dispatch harness**, mirroring P4's direct write proof, because full socket-runner
productization still has the `block_on` / re-entry boundary.

P6 proves the seam with fake Postgres read execution and an authored continuation. It is a host proof, not
a new public API.

## Goal

Implement the smallest end-to-end proof that an IgWeb/Todo query intent can be executed by the host and
fed into an authored continuation:

```text
.ig query contract returns QueryPlan
  -> host harness serializes QueryPlan
  -> fake PostgresReadExecutor gates + executes
  -> rows_json
  -> .ig continuation contract
  -> final Respond
```

No live DB. No new `.igweb` syntax. No prelude `ReadThen` arm yet. No runner productization.

## Verify First

Read live surfaces before editing:

- `lab-docs/lang/lab-igniter-web-read-guard-host-readiness-p5-v0.md`
- `server/igniter-web/examples/todo_postgres_app/`
  - existing relational query/write shapes
  - existing route/guard conventions
- `server/igniter-web/tests/todo_postgres_app_tests.rs`
- `server/igniter-web/tests/todo_postgres_effect_host_tests.rs`
- `server/igniter-web/src/lib.rs`
  - current `IgWebServerApp`
  - testkit helpers
  - machine feature gating
- `runtime/igniter-machine/src/postgres_read.rs`
  - `PostgresReadExecutor`
  - `PostgresReadPolicy`
  - `FakePostgresAdapter`
  - `EffectOutcome` mapping
- `runtime/igniter-machine/tests/relational_queryplan_bridge_tests.rs`
- `runtime/igniter-machine/tests/postgres_read_tests.rs`
- `lang/igniter-compiler/src/igweb.rs`
  - current `Decision` arms
  - context/via lowering remains pure

Confirm or correct:

- there is an existing small way to dispatch an IgWeb app/contract directly enough for a harness;
- if not, a test-local helper may call the compiler/VM directly, but do not invent a production runtime;
- `PostgresReadExecutor` can be used under the `machine` feature without live `postgres`;
- fake adapter query counts can prove gate-before-adapter;
- rows can be serialized as JSON string for the continuation.

## Required Shape

Prefer a test-support harness in `server/igniter-web` gated by `machine` tests, or a narrow integration test
if the existing helpers are enough.

The authored `.ig` side should include:

```text
ListTodosByAccount(account_id) -> QueryPlan
AccountTodoIndex(req, rows_json : String) -> Decision
```

The host/test harness should:

1. dispatch/call the query contract to obtain a `QueryPlan` value;
2. convert that value to the JSON expected by `PostgresReadExecutor`;
3. run it through `PostgresReadExecutor<FakePostgresAdapter>` with a host-owned `PostgresReadPolicy`;
4. serialize returned rows to `rows_json`;
5. dispatch/call the continuation with `req` + `rows_json`;
6. assert the final `Decision` maps to the expected response shape.

If direct contract dispatch is too expensive or not already available, use the smallest test-local mirror
only after documenting why, but still keep the `.ig` query/continuation fixture compiled so the authored
shape is real.

## Data / Policy

Use a Todo-shaped fake table:

```json
[
  { "id": "todo-1", "account_id": "acct-7", "title": "Buy milk", "done": false },
  { "id": "todo-2", "account_id": "acct-7", "title": "Write spec", "done": true }
]
```

Policy should allow only the intended source/fields:

```text
source: todos
fields: id, account_id, title, done
limit cap: small number, enough to prove clamp
ops: select / eq only
```

The authored `.ig` must not contain:

- raw SQL;
- DSN;
- capability id;
- scope;
- host source binding beyond the logical `source` field in `QueryPlan`.

## Continuation v0

Rows reach the continuation as `rows_json : String`.

This is deliberately humble. P6 proves the host seam, not typed row destructuring. The continuation may:

- return `200` with rows_json or a deterministic derived summary for found rows;
- return app-owned `404` for empty rows.

If the language cannot parse rows_json, the harness may choose the continuation based on empty/non-empty and
call a simple continuation with a string summary, but the closing report must be precise about what was
proved and what remains deferred.

## Error Mapping

Keep P5's split:

- empty rows = legitimate app not-found, continuation-owned 404;
- denied source/field/raw SQL = host-owned refusal before app continuation;
- unavailable/transient = host-owned unavailable/retryable outcome;
- malformed plan = permanent host failure.

Do not leak SQL, DSN, raw row bodies, or machine internals in user-facing app decisions.

## Closed Scope

- No live Postgres / DSN / DDL / migrations / pool / TLS.
- No new `.igweb` syntax (`read`, `ReadThen`, staged route body).
- No new IgWeb prelude arm.
- No runner/socket-loop productization.
- No async runtime redesign.
- No typed row destructuring into `.ig` records.
- No final write execution in this card.
- No automatic DB reads from `via`.
- No raw SQL.
- No schema inference / ORM.
- No public CLI/canon/stable API claim.

## Required Tests / Acceptance

- [x] Authored query contract compiles and produces/mirrors a structural `QueryPlan`.
- [x] Found rows flow through fake `PostgresReadExecutor` into an authored continuation and return `200`.
- [x] Empty rows are treated as not-found by the app/continuation and return authored `404`.
- [x] Denied source fails before the adapter (`query_count == 0` or equivalent evidence).
- [x] Forbidden projection field fails before the adapter.
- [x] Limit clamp is applied by host policy.
- [x] Raw-SQL keys (`sql` / `raw_sql` / `query`) are refused before adapter.
- [x] Authored `.ig` has no capability id, scope, DSN, raw SQL, or DB handle.
- [x] Default/no-machine build remains unchanged; P6 tests are gated or located so default suites stay clean.
- [x] No live DB or `IGNITER_PG_DSN` needed.
- [x] The proof explicitly states it is a direct-dispatch harness, not the full async socket loop.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-20)

**Deliverable:** the first mid-request **read** seam, proven as a direct-dispatch harness with **both `.ig`
ends dispatched for real**:
`ListTodosByAccount -> QueryPlan` → host `PostgresReadExecutor<FakePostgresAdapter>` (policy gate + clamp) →
`rows_json` → `TodoIndexFromRows(req, rows_json) -> Decision`.
- `server/igniter-web/tests/fixtures/read_harness/read_harness.ig` (authored query + continuation).
- `server/igniter-web/tests/todo_postgres_read_host_tests.rs` (`#![cfg(feature = "machine")]`, **4 tests**).
- Proof doc: `lab-docs/lang/lab-igniter-web-read-guard-host-p6-v0.md`.

**Key verify-first:** `IgniterMachine::load_program` registers **every** contract; `dispatch(name, inputs)`
runs any of them async — so the harness dispatches both `.ig` contracts directly (`.await`), avoiding
`IgWebServerApp::call`'s internal `block_on` (the P4 boundary). The fake `PostgresReadExecutor` is in the
machine **default** build (no live DB).

**Proof — all green:**
- `cargo test --features machine --test todo_postgres_read_host_tests` → **4 passed** (found→200,
  empty→app-404, denied source/field + raw-SQL before adapter + clamp, no authored DB surface).
- default `igniter-web` → **49** (read test gated to 0); `--features machine` → **58** (49 + read 4 +
  effect-host 5); `git diff --check` clean.

**Honest scope:** direct-dispatch harness (not full async socket loop — same P4 `block_on` boundary, worse
for reads); rows as a JSON **string** (typed destructuring deferred); no staged `.igweb`/`ReadThen` arm; no
write execution. App owns the query + not-found 404; host owns policy/executor; `.ig` names no capability
id/scope/DSN/SQL.

**Next:** `LAB-TODOAPP-API-READ-P*` (product Todo read route), staged `read …`/`ReadThen` syntax,
read-then-write composition, `…-EFFECT-HOST-RUNNER-P*` (productize runner; resolve sync/async).

## Suggested Verification Commands

Adjust exact test names to the implementation, but report exact counts:

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test --features machine --test todo_postgres_read_host_tests
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test --features machine
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/runtime/igniter-machine && cargo test --no-default-features --test relational_queryplan_bridge_tests
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/runtime/igniter-machine && cargo test --no-default-features --test postgres_read_tests
git diff --check
```

Also run a source scan over the authored app/fixture:

```bash
rg -n "sql|raw_sql|query|DSN|capability|scope|postgres://" server/igniter-web/examples/todo_postgres_app
```

If a broad suite has unrelated failures, isolate them with touched-file evidence.

## Deliverables

- Narrow implementation/test harness proving the read seam.
- Authored `.ig` query/continuation fixture or app update.
- Proof doc:
  - `lab-docs/lang/lab-igniter-web-read-guard-host-p6-v0.md`
- Closing report in this card.

## Expected Result

After P6, the DB-backed Todo API path has a proven read half:

```text
Authored query intent -> host read policy/executor -> rows_json -> authored continuation
```

Then the next slices can be:

1. `LAB-TODOAPP-API-READ-P*` — product-shaped Todo read route over the proven seam;
2. staged `.igweb` syntax / `ReadThen` arm;
3. read-then-write composition with P4;
4. runner productization after the sync/async boundary is addressed.
