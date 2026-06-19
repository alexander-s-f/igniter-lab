# lab-igniter-relational-contracts-todo-p2-v0 — pure `.ig` Todo relational proof

**Card:** `LAB-IGNITER-RELATIONAL-CONTRACTS-TODO-P2` · **Delegation:** `OPUS-RELATIONAL-TODO-P2`
**Status:** CLOSED (lab proof) — a **pure `.ig`** relational Todo module that expresses queries as
structured `QueryPlan` records and writes as `WriteIntent` records (mirroring the live machine boundary),
with **relations as contracts, not fields**, compiling clean through the **real** multifile compiler.
**No DB, no machine adapter, no SQL execution, no compiler/typechecker/stdlib/server change, no canon.**
**Authority:** Lab proof. Implements the next step from
`lab-docs/lang/lab-igniter-relational-contracts-readiness-p1-v0.md`.

## 1. Executive summary

Ordinary `.ig` already expresses relational intent — no dialect, no new language feature. A query contract
returns a structured `QueryPlan` record (mirror of `postgres_read::QueryPlan`); a command contract returns a
`WriteIntent` record (mirror of `postgres_write::PostgresWriteIntent`); a relation ("Account has many
Todos") is a **contract** (`TodosByAccount(account_id) -> QueryPlan`), never a lazy field; not-found is
`Option[Todo]` via `some(..)`/`none()`. The whole module compiles clean through the real compiler with
**zero diagnostics**, and carries no SQL, no ORM surface, and no machine/import dependency. This locks the
authoring shape before any executor wiring.

## 2. Verify-first notes (+ reorg correction)

- The machine boundary types were re-confirmed at the **reorg path** `runtime/igniter-machine/src/` (the
  card's `igniter-machine/src/` is stale): `QueryPlan { source, op, projection, filters:[{field,op,value}],
  limit }` (`postgres_read.rs:44-50`), `PostgresWriteIntent { operation, target, key, values,
  correlation_id }` (`postgres_write.rs:44-50`).
- **Record-construction fact (decisive):** inline/array record literals infer to `Unknown` in the Rust
  typechecker; the proven pattern is the **`MakeXxx` factory** (a contract whose `output r : T` gives the
  record its nominal type), exactly as the live `query_engine` app does (`apps/igniter-apps/query_engine/
  example.ig:11-49`). The fixture follows this verbatim: `MakeFilter`/`MakeWriteValues` factories, then
  top-level plan/intent records (which *do* type under a `compute … : QueryPlan = { … }` annotation when
  their collection fields reference typed computes).
- Collections: `compute projection : Collection[String] = ["id", …]` and `compute filters :
  Collection[QueryFilter] = [f_acct]` (annotated, factory-built elements) — both proven shapes
  (`query_engine`, `vector_editor` empty collections, `arch_patterns` non-empty).
- `some(..)`/`none()` for `Option[Todo]` — the lowercase sealed constructors confirmed in P19/P20.

## 3. Fixture

`lang/igniter-compiler/tests/fixtures/relational_todo/relational_todo.ig` — one self-contained module
`RelationalTodo`, no imports.

## 4. What it defines

- **Row types (advisory schema mirrors):** `Account { id, name }` — **flat, no `todos` field**;
  `Todo { id, account_id, title, done }` — FK `account_id` is a plain value field.
- **Query intent mirror:** `QueryFilter { field, op, value }`, `QueryPlan { source, op, projection:
  Collection[String], filters: Collection[QueryFilter], limit }`.
- **Write intent mirror:** `WriteValues { account_id, title, done }`, `WriteIntent { operation, target,
  key, values, correlation_id }`.
- **Factories:** `MakeFilter`, `MakeWriteValues` (nominal record construction).
- **Query contracts:** `ListTodos() -> QueryPlan`, `TodosByAccount(account_id) -> QueryPlan` (the
  relation-as-contract), `FindTodo(account_id, todo_id) -> QueryPlan`. All `eq`-only filters, explicit
  `source`/`projection`/`limit`, no SQL, no table-name inference from type names.
- **Not-found shape:** `TodoFromRow(found, todo) -> Option[Todo]` = `if found == 1 { some(todo) } else {
  none() }`.
- **Command contracts:** `CreateTodo(account_id, title, idempotency_key) -> WriteIntent` (insert),
  `MarkTodoDone(todo_id, idempotency_key) -> WriteIntent` (update). They return intent only; they do **not**
  execute or mention receipts except as a host responsibility in comments.

## 5. What compiled cleanly

The real multifile compiler accepts the module with **zero diagnostics** (`igapp` artifact written). A
clean compile is the proof that: `QueryPlan` record construction typechecks; `Collection[QueryFilter]` /
`Collection[String]` construction typechecks; the relation-as-contract shape typechecks; `WriteIntent`
(incl. nested `WriteValues`) typechecks; and the `Option[Todo]` `some/none` shape typechecks.

## 6. Anti-ORM / no-SQL checks (asserted over the authored code)

The tests strip `--` comments and assert the **code** carries none of: raw SQL (`select `, `insert into`,
`update `, `delete from`, `where `, ` join `, `create table`); ORM surface (`.save`, `save(`,
`find_by_sql`, `belongs_to`, `has_many`, `has_one`, `active_record`, `.all(`, `lazy`); machine/effect
surface (`import `, `invokeeffect`, `call_capability`, `capability`, `passport`). And **no row type carries
a `todos` field** — the relation is the `TodosByAccount` contract. (Comments may discuss SQL/capability
concepts; the checks target code only.)

## 7. Commands + pass counts

```text
$ cd lang/igniter-compiler && cargo test --test relational_todo_tests   → 4 passed; 0 failed
  · relational_todo_compiles_clean   (real compiler, no OOF-TY0, no error diagnostics + shape sanity)
  · fixture_has_no_raw_sql
  · fixture_has_no_orm_surface
  · fixture_is_pure_ig
$ igniter_compiler compile tests/fixtures/relational_todo/relational_todo.ig --out /tmp/rel_todo.igapp
  → diagnostics: 0; igapp written
$ git diff --check                                                      → clean (only new fixture + test file)
```

No compiler/typechecker/VM/stdlib/machine/server source changed; no `Cargo.toml`, feature flag, or
dependency edit.

## 8. Limitations & deferred

- **Row types are advisory mirrors, not enforcement.** The machine returns rows as text-JSON today; a
  typed-row guarantee is a machine follow-on (`…-TYPED-READ-P10`).
- **`eq`-only filters; filters carried, not evaluated** (machine v0 bound). Richer predicates are deferred.
- **`WriteValues` is a fixed record**, not an arbitrary column map — heterogeneous/dynamic value maps are
  deferred (mirrors the `query_engine` fixed-row pressure note).
- The fixture **does not execute** anything — it is a language-shape proof only. Wiring the `QueryPlan` to
  the fake read executor is the next card.

## 9. Next recommendation

`LAB-IGNITER-RELATIONAL-QUERYPLAN-BRIDGE-P3` — feed this compiled `QueryPlan` shape into the **fake**
`PostgresReadExecutor` (already in the default build), proving the `.ig`-intent → machine-`QueryPlan`
mapping + allowlist gating end-to-end **without a live DB**. Later: `LAB-MACHINE-POSTGRES-TYPED-READ-P10`
(typed read values) and an IgWeb pressure fixture that calls a relational query contract from a P20 `via`
guard.

---

*Lab proof. Compiled 2026-06-19; relational Todo fixture compiles clean through the real multifile compiler
(0 diagnostics); 4 tests green. No DB, machine, compiler, stdlib, server, or canon change.*
