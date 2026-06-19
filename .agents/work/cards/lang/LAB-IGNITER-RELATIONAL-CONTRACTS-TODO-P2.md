# Card: LAB-IGNITER-RELATIONAL-CONTRACTS-TODO-P2 — pure `.ig` Todo relational proof

**Lane:** standard / lab proof · **Skill:** idd-agent-protocol  
**Status: CLOSED**  
**Delegation:** OPUS-RELATIONAL-TODO-P2

## Intent

Prove the language/app side of relational contracts with a **pure `.ig` Todo
example**, no DB, no machine adapter, no compiler changes.

This card implements the next step recommended by
`LAB-IGNITER-RELATIONAL-CONTRACTS-READINESS-P1`:

```text
ordinary .ig contracts
  -> row / intent mirror types
  -> query contracts returning QueryPlan
  -> command contracts returning WriteIntent
  -> relation as a contract, not a field
  -> real compiler proof
```

The goal is to lock the **authoring shape** before wiring it to the fake or real
Postgres executor.

## Authority

Lab proof only. This card may create a fixture `.ig` module, compiler tests, a
proof doc, and this card's closing report.

This card must not change:

- parser/typechecker/VM semantics;
- stdlib;
- `runtime/igniter-machine` or Postgres adapters;
- `server/igniter-web` / runner;
- package manager;
- canon docs.

No DB, no SQL execution, no `Cargo.toml`, no feature flags.

## Verify First

Read before editing:

- `lab-docs/lang/lab-igniter-relational-contracts-readiness-p1-v0.md`
- `lab-docs/lang/lab-machine-postgres-schema-query-readiness-p9-v0.md`
- `runtime/igniter-machine/src/postgres_read.rs`
- `runtime/igniter-machine/src/postgres_write.rs`
- `lang/igniter-compiler/src/typechecker.rs` if type behavior is unclear
- existing compiler fixture/test patterns under:
  - `lang/igniter-compiler/tests/fixtures/`
  - `lang/igniter-compiler/tests/*`

Important live facts from P1 that should be re-verified if uncertain:

- records construct as bare `{ field: value }` literals under typed
  annotations, not `TypeName { ... }`;
- `Collection[T]`, `Option[T]`, and `Result[T,E]` already exist;
- `QueryPlan` and `PostgresWriteIntent` are ordinary structured values at the
  machine boundary;
- relational contracts are a convention over ordinary `.ig`, not a dialect.

## Required Fixture

Create a dedicated fixture directory, for example:

```text
lang/igniter-compiler/tests/fixtures/relational_todo/
```

Suggested module:

```text
relational_todo.ig
```

The fixture should define:

### Row / mirror types

- `Todo`
- `Account`
- `QueryFilter`
- `QueryPlan`
- `WriteValues` or another small typed value record
- `WriteIntent`
- optional `Decision` if useful for write/IgWeb-shaped proof

Keep the shapes close to the live machine boundary:

```ig
type QueryFilter {
  field : String
  op    : String
  value : String
}

type QueryPlan {
  source     : String
  op         : String
  projection : Collection[String]
  filters    : Collection[QueryFilter]
  limit      : Integer
}

type WriteIntent {
  operation      : String
  target         : String
  key            : String
  values         : WriteValues
  correlation_id : String
}
```

Use typed records rather than raw JSON strings wherever the language supports it.
If a richer map/value shape is not currently ergonomic, document that honestly
in the proof.

### Query contracts

At minimum:

- `TodosByAccount(account_id) -> QueryPlan`
- `FindTodo(account_id, todo_id) -> QueryPlan`
- `ListTodos() -> QueryPlan`

They must:

- return structured `QueryPlan` values;
- use explicit `source`, `projection`, `filters`, `limit`;
- use only `eq` filters for now;
- contain no SQL strings;
- not infer table names from type names.

### Relation-as-contract proof

Define relation as a separate contract, not a nested field:

```text
TodosByAccount(account_id) -> QueryPlan
```

The `Account` row type must not contain a lazy `todos` field. If a view type
includes `todos`, it should be an explicit projection/composition type, not an
active relation.

### Command/write contracts

At minimum:

- `CreateTodo(account_id, title, idempotency_key) -> WriteIntent`
- `MarkTodoDone(todo_id, idempotency_key) -> WriteIntent`

They must:

- return structured `WriteIntent` values;
- use explicit `operation`, `target`, `key`, `values`, `correlation_id`;
- not claim to execute the write;
- not mention receipts except as a machine responsibility in comments/proof.

### Option / not-found shape

Include a pure contract that demonstrates not-found as `Option`, without DB:

- either `TodoFromRow(...) -> Option[Todo]`;
- or `FindTodoResultShape(...) -> Option[Todo]`;
- or another compiler-clean shape.

The point is to prove the language form (`some(...)` / `none()`) that the future
bridge will use, not to fake DB execution.

## Required Tests

Add focused compiler tests. Prefer the existing integration-test harness style
used by other fixture proofs.

Tests should prove:

1. The relational Todo fixture compiles cleanly through the real compiler.
2. `QueryPlan` record construction compiles.
3. `QueryFilter` collection construction compiles.
4. Relation-as-contract shape compiles (`TodosByAccount`, not nested field).
5. `WriteIntent` record construction compiles.
6. `Option[Todo]` shape compiles.
7. There is no raw SQL string in the fixture.
8. There is no ORM-ish surface in the fixture:
   - no `save`;
   - no `find_by_sql`;
   - no `belongs_to`;
   - no `has_many`;
   - no inferred/pluralized table authority.
9. The fixture remains pure `.ig` — no machine/import/runtime dependency.

If current compiler fixtures do not expose an easy way to assert these, keep the
tests simple: compile clean + `include_str!` assertions over the fixture source
are acceptable for the anti-ORM/no-SQL checks.

## Required Proof Doc

Create:

```text
lab-docs/lang/lab-igniter-relational-contracts-todo-p2-v0.md
```

It must include:

1. executive summary;
2. verify-first notes and any reorg path correction;
3. fixture file path(s);
4. the row / intent / query / write contracts created;
5. what compiled cleanly;
6. explicit anti-ORM checks;
7. exact commands and pass counts;
8. limitations and deferred work;
9. next recommendation.

## Acceptance

- [x] Dedicated relational Todo fixture exists.
- [x] Real compiler accepts the fixture.
- [x] Query contracts return structured `QueryPlan` values.
- [x] Command contracts return structured `WriteIntent` values.
- [x] Relation is represented as a contract, not as a lazy row field.
- [x] `Option[Todo]` not-found shape compiles.
- [x] Fixture contains no raw SQL surface.
- [x] Fixture contains no ORM-ish API surface.
- [x] No compiler/typechecker/VM/stdlib/machine/server changes.
- [x] No DB connection, SQL execution, feature flag, or dependency edit.
- [x] Proof doc exists with exact commands and counts.
- [x] This card is marked CLOSED with a compact closing report.

---

## Closing Report (2026-06-19)

**Deliverable:** a pure `.ig` relational Todo module compiling clean through the **real** compiler.
- Fixture: `lang/igniter-compiler/tests/fixtures/relational_todo/relational_todo.ig` (module
  `RelationalTodo`, self-contained, no imports).
- Tests: `lang/igniter-compiler/tests/relational_todo_tests.rs` — **4 passed; 0 failed**.
- Proof doc: `lab-docs/lang/lab-igniter-relational-contracts-todo-p2-v0.md`.

**Shape proven:** query contracts return structured `QueryPlan` records (`ListTodos`, `TodosByAccount`,
`FindTodo`); command contracts return `WriteIntent` records (`CreateTodo`, `MarkTodoDone`); the
relation "Account has many Todos" is the **`TodosByAccount` contract**, not a field (`Account` is flat,
no `todos` field); not-found is `Option[Todo]` via `some(..)`/`none()`. Records use the proven `MakeXxx`
factory pattern (inline record literals infer to `Unknown` — confirmed against live `query_engine`); the
fixture compiles with **0 diagnostics**.

**Verify-first delta:** machine types re-confirmed at the reorg path `runtime/igniter-machine/src/`.

**Anti-ORM/no-SQL:** asserted over comment-stripped code — no SQL keywords, no ORM surface
(`save`/`has_many`/`belongs_to`/`lazy`/…), no `todos` relation field, no machine/import/capability surface.

**Boundary respected:** no compiler/typechecker/VM/stdlib/machine/server change; no DB, SQL execution,
feature flag, or dependency edit (`git diff --check` clean; only new fixture + test file).

**Next:** `LAB-IGNITER-RELATIONAL-QUERYPLAN-BRIDGE-P3` — feed the `QueryPlan` record into the **fake**
`PostgresReadExecutor` (default build), proving `.ig`-intent → machine-`QueryPlan` + allowlist gating
without a live DB.

## Closed Surfaces

Do not wire to `PostgresReadExecutor` in this card. Do not add a fake executor
bridge. Do not add a dialect. Do not add schema registry, migration runner,
package manager, source-map, live DB, or real Postgres dependency.

## Next Routes

Expected next card after this proof:

- `LAB-IGNITER-RELATIONAL-QUERYPLAN-BRIDGE-P3` — take the compiled `.ig`
  `QueryPlan` shape and feed it to the **fake** Postgres read executor, proving
  the language intent -> machine boundary without a live DB.

Possible later:

- `LAB-MACHINE-POSTGRES-TYPED-READ-P10` — machine-side typed read values.
- IgWeb pressure fixture that uses a relational query contract from a P20/P22
  `via` guard.

## Notes For The Agent

Keep this boring and legible. The win is not a shiny relational DSL; the win is
that ordinary `.ig` can already express enough relational intent while the host
keeps authority over schema, SQL, connection, idempotency, and receipts.
