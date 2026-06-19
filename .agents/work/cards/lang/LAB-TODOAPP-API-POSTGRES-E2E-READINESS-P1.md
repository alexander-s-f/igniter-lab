# LAB-TODOAPP-API-POSTGRES-E2E-READINESS-P1 — real Todo API shape over IgWeb + Postgres

Status: CLOSED
Date: 2026-06-19
Lane: standard / lab readiness
Skill: idd-agent-protocol
Delegation: OPUS-TODOAPP-API-POSTGRES-E2E-P1

## Intent

Design the first **real Todo API app** shape that connects the web stack to the
Postgres connector without putting domains into `igniter-server` or inventing an
ORM:

```text
igweb.toml + igweb-serve
  -> .igweb routes
  -> .ig handlers / relational contracts
  -> Postgres read QueryPlan
  -> Postgres write intent / InvokeEffect
  -> receipts / idempotency / reconcile
```

This card is readiness/design only. It should turn the current stack into a
bounded implementation plan for a real local Todo API with a database, while
preserving all authority boundaries.

## Current Preconditions

This card depends on live or open work:

- **Done:** IgWeb runner (`igweb-serve`) and manifest path.
- **Done:** IgWeb routing stack: `scope`, `resource`, nested, route-level `via`,
  composite guards, Todo V2 app-pressure.
- **Done:** relational `.ig` Todo contract shape (pure intent, no DB handle).
- **Done:** bridge from relational `QueryPlan` shape to fake Postgres read
  executor.
- **Open:** `LAB-IGNITER-WEB-CONTEXT-COMPOSITION-P26` — `let` / one `guard`
  context composition.
- **Open:** `LAB-MACHINE-POSTGRES-TYPED-READ-P10` — typed Postgres read values.

P1 should not assume P10/P26 are complete. It should say exactly which pieces
are blocked on them and what can be mocked/faked first.

## Authority

Lab readiness only. No code, DB connection, DDL, migrations, live effects, or
public listener in this card.

The future TodoApp API owns **app/domain meaning**. `igniter-server` owns only
transport/process/concurrency/middleware mechanics. `igniter-machine` owns
capability execution, receipts, idempotency, and reconcile. Postgres schema is
operator/app-owned outside Igniter.

This card may create:

- `lab-docs/lang/lab-todoapp-api-postgres-e2e-readiness-p1-v0.md`;
- this card's closing report.

This card must **not** change:

- compiler / VM / machine / server / web code;
- `.ig` / `.igweb` examples;
- Cargo dependencies;
- DB schema or local DB state;
- canon docs.

No real DB connection. No SparkCRM/vendor DB. No production/staging.

## Verify First

Read current live surfaces before writing:

- `server/igniter-web/examples/todo_app/`
- `server/igniter-web/examples/todo_v2_app/`
- `server/igniter-web/src/bin/igweb-serve.rs`
- `server/igniter-web/src/lib.rs`
- `server/igniter-server/src/protocol.rs`
- `runtime/igniter-machine/src/postgres_read.rs`
- `runtime/igniter-machine/src/postgres_write.rs`
- `runtime/igniter-machine/src/postgres_real.rs`
- `runtime/igniter-machine/tests/relational_queryplan_bridge_tests.rs`
- `lang/igniter-compiler/tests/fixtures/relational_todo/relational_todo.ig`
- `lab-docs/lang/lab-igniter-relational-contracts-todo-p2-v0.md`
- `lab-docs/lang/lab-igniter-relational-queryplan-bridge-p3-v0.md`
- `lab-docs/lang/lab-machine-postgres-schema-query-readiness-p9-v0.md`
- open cards `LAB-IGNITER-WEB-CONTEXT-COMPOSITION-P26` and
  `LAB-MACHINE-POSTGRES-TYPED-READ-P10`

Live code wins over old proof docs.

## Questions To Answer

### Q1. What is the TodoApp boundary?

Define where a Todo API app should live:

- under `server/igniter-web/examples/todo_postgres_app/`?
- under a new `apps/todo_api/`?
- under a future app workspace/package?

State what is authored by the app:

- `igweb.toml`;
- `routes.igweb`;
- `.ig` types/handlers/relational contracts;
- host policy/config files;
- optional SQL migration fixture.

State what is **not** app-authored Rust.

### Q2. What is the schema shape and ownership?

Propose a minimal local Todo schema, but do not apply it:

- `accounts(id, name, timezone?)`;
- `todos(id, account_id, title, done, inserted_at, updated_at?)`;
- `effect_receipts(...)` required by machine writes.

Decide:

- who owns migrations;
- whether DDL lives as a fixture snippet, doc, or future package asset;
- whether schema names are host policy names or `.ig` types;
- how test setup avoids SparkCRM/dev business DBs.

### Q3. What are the API routes?

Recommend the first API surface:

- `GET /health`;
- `GET /accounts/:account_id/todos`;
- `GET /accounts/:account_id/todos/:todo_id`;
- `POST /accounts/:account_id/todos`;
- `POST /accounts/:account_id/todos/:todo_id/done`.

Use existing IgWeb grammar where possible:

- `scope`;
- `resource`;
- route-level `via` / future P26 `let`+`guard`;
- `requires idempotency` for mutating routes.

State if P26 is required or whether current `via` can cover v0.

### Q4. How do reads flow?

Map route → `.ig` contract → `QueryPlan` → Postgres read executor.

Examples:

- `ListTodosByAccount(account_id) -> QueryPlan`;
- `FindTodo(account_id, todo_id) -> QueryPlan`;
- `LoadAccountTodos` / `LoadTodoContext` as IgWeb guard(s).

Answer:

- Does the app initially use fake read executor or real local Postgres?
- Which fields must be typed by P10?
- How are not-found cases represented (`Option`, empty rows, guard-owned 404)?
- How does result mapping avoid ORM behavior?

### Q5. How do writes flow?

Map mutating route → `WriteIntent` / `InvokeEffect` → Postgres write executor.

Examples:

- `CreateTodo` / `MarkTodoDone`;
- idempotency key required by IgWeb route;
- machine receipt + PG `effect_receipts`.

Answer:

- Is write execution observed as `InvokeEffect` in v0 or actually wired to
  `MachineEffectHost`?
- What is the smallest safe e2e write slice?
- How is `UnknownExternalState` reconciled?
- Where does `correlation_id` come from?

### Q6. What host config is needed?

Define the minimal host-owned config surface:

- read policy source/field/type map;
- write target/key/columns map;
- effect target mapping (`todo-create`, `todo-done`);
- DSN env names;
- local-only guard / loopback-only server;
- secret provider shape.

Make clear: `.igweb` never names capability IDs, scopes, DSNs, table DDL, or
secrets.

### Q7. What is the runner story?

Should the first real API run through:

- existing `igweb-serve check` only;
- `igweb-serve` with observed `InvokeEffect`;
- a new local E2E harness binary/helper;
- a future host config file?

Preserve the no-authored-Rust app goal if possible. If Rust harness is needed,
classify it as lab proof infrastructure, not app authoring DX.

### Q8. What is the phased implementation plan?

Define a sequence of small cards, for example:

1. `TODOAPP-API-SHAPE-P2` — pure app files + fake DB executor;
2. `TODOAPP-API-READ-P3` — real local typed read;
3. `TODOAPP-API-WRITE-P4` — idempotent write via fake or local PG;
4. `TODOAPP-API-E2E-P5` — full local loopback with read+write+receipt;
5. views/assets later.

Choose the best sequence and justify prerequisites.

### Q9. What must remain closed?

Explicitly close:

- assets/views;
- auth/session real secrets;
- public listener;
- production/staging DB;
- SparkCRM/vendor schema;
- raw SQL from contracts;
- ORM/ActiveRecord-style model layer;
- migrations runner;
- pooling/TLS unless already proven elsewhere.

### Q10. What are success criteria for the first implementation?

Define exact acceptance for the first implementation card:

- files expected;
- commands;
- pass counts;
- loopback behavior table;
- DB env skip behavior;
- receipt assertions;
- dependency boundary checks.

## Required Deliverable

Create:

```text
lab-docs/lang/lab-todoapp-api-postgres-e2e-readiness-p1-v0.md
```

The packet must include:

1. executive summary;
2. verify-first facts;
3. app boundary;
4. schema ownership and suggested DDL shape;
5. routes;
6. read flow;
7. write flow;
8. host config/effect binding;
9. runner/deploy story for local lab;
10. phased implementation plan;
11. closed surfaces;
12. next card recommendation.

Then close this card with a compact report.

## Acceptance

- [x] Packet exists at the required path.
- [x] Packet verifies live IgWeb, relational, and Postgres surfaces.
- [x] Packet answers Q1-Q10 explicitly.
- [x] Packet states which parts depend on P10 and P26.
- [x] Packet keeps `igniter-server` domain-free and route-free.
- [x] Packet keeps Postgres schema host/operator-owned.
- [x] Packet does not propose raw SQL from contracts or ORM models.
- [x] Packet separates observed `InvokeEffect` from real machine execution.
- [x] Packet chooses a smallest next implementation card.
- [x] No code, DB, DDL, dependencies, or examples are changed.
- [x] Card is closed with a report.

---

## Closing Report (2026-06-19)

**Deliverable:** `lab-docs/lang/lab-todoapp-api-postgres-e2e-readiness-p1-v0.md` — synthesis packet, **no
code/DB/DDL/dep/example change**. Answers Q1–Q10.

**Central finding:** every *authoring + lowering + intent* layer is already proven (runner, full routing
sugar via `todo_v2_app`, relational `QueryPlan`/`WriteIntent` contracts, the P3 bridge, P10 typed reads,
the `PostgresWriteExecutor`+receipts+reconcile). The **one missing piece** for a live DB-backed API is
**host-side effect EXECUTION on the web path**: `igweb-serve` *observes* `InvokeEffect` (`lib.rs:171`, a
`202`) and never runs it, and a `via` guard is a *pure* `call_contract` that can't perform IO. So a single
request cannot yet read/write Postgres.

**Verify-first delta:** both prerequisites the card listed as "Open" are now **CLOSED** — P10 (typed reads)
and P26 (`let`/`guard`). So the path is *less* blocked than assumed; the real blocker is the effect-host
seam.

**Plan:** (P2) `LAB-TODOAPP-API-SHAPE-P2` — `todo_postgres_app/` app files + relational contracts, loopback
with **observed** effects, **no DB** (fully doable today); (P3) **new** `LAB-IGNITER-WEB-EFFECT-HOST-READINESS-P3`
— design the seam wiring the runner's read/write intents to the machine capability executors (precedent:
`igniter-machine` `frame_binding` P17/P18); (P4) real read, (P5) idempotent write+receipt, (P6) full e2e.
Boundaries held: `igniter-server` route/domain-free, schema operator-owned, no raw-SQL-from-contracts, no
ORM, observed-`InvokeEffect` strictly separated from real execution.

**Next card:** `LAB-TODOAPP-API-SHAPE-P2` (app shape, observed effects, no DB).

## Suggested Next Card

Default recommendation if the readiness confirms the path:

```text
LAB-TODOAPP-API-SHAPE-P2
```

Likely scope: app files only, fake/observed execution, no real DB yet. If P10
and P26 are needed, they are now already closed; the remaining blocker for real
local read/write is the effect-host seam.
