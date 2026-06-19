# lab-igniter-relational-queryplan-bridge-p3-v0 — `.ig` QueryPlan → fake Postgres read executor

**Card:** `LAB-IGNITER-RELATIONAL-QUERYPLAN-BRIDGE-P3` · **Delegation:** `OPUS-RELATIONAL-QUERYPLAN-BRIDGE-P3`
**Status:** CLOSED (lab proof) — bridges the P2 `.ig` relational `QueryPlan` shape to the **existing fake**
`PostgresReadExecutor`, proving the language intent and the machine read boundary line up and that the
executor gates a P2-shaped plan correctly. **No live DB, no `postgres` feature, no DSN, no SQL, no
compiler/VM/production-source change.**
**Authority:** Lab proof. Builds on `lab-igniter-relational-contracts-todo-p2-v0.md`; machine read behavior
is `runtime/igniter-machine/src/postgres_read.rs`.

## 1. Executive summary

The P2 pure-`.ig` `QueryPlan` type and the live machine read boundary line up **field-for-field**: the
executor's `QueryPlan::from_args` reads exactly `source / op / projection / filters:[{field, op, value}] /
limit` — the same fields the P2 `RelationalTodo.QueryPlan` / `QueryFilter` types declare. A new
default-build test feeds a `QueryPlan` JSON that mirrors the P2 `TodosByAccount("acct-7")` plan to the fake
`PostgresReadExecutor` and proves the full gate set: rows returned through the receipt machinery, source/
field/op allowlist denials before the adapter, row-limit clamp, replay bypass, and structural raw-SQL
refusal. The shapes line up and the fake executor gates them correctly — the intended modest outcome.

## 2. Chosen proof shape — **B (host-side mirror)**, and why

The card offered **A** (execute the compiled P2 `.ig` contract, extract its `QueryPlan` value, feed the
executor) or **B** (construct a shape-aligned `QueryPlan` JSON host-side). Verify-first showed **A is not a
small existing path**: a machine test would need the **compiler crate** to lower `.ig`, an `.igapp` load
into `IgniterMachine`, a VM dispatch of `TodosByAccount`, and value extraction — a new cross-crate runtime
bridge the card explicitly says not to invent. So this card takes **B** and does **not** overclaim:

- the mirror JSON is **tied** to the P2 fixture, not hand-waved — the test `include_str!`s
  `lang/igniter-compiler/tests/fixtures/relational_todo/relational_todo.ig` and asserts it declares the
  `QueryPlan`/`QueryFilter` fields the executor reads, plus the `TodosByAccount` source/columns/eq-filter;
- **actual VM-result extraction is deferred** to `LAB-IGNITER-RELATIONAL-VM-EXECUTION-BRIDGE-P4`.

## 3. Verified P2 `.ig` QueryPlan shape

From the P2 fixture (`type QueryPlan`, `type QueryFilter`, `pure contract TodosByAccount`):

```ig
type QueryFilter { field : String, op : String, value : String }
type QueryPlan { source : String, op : String, projection : Collection[String],
                 filters : Collection[QueryFilter], limit : Integer }
-- TodosByAccount: source "todos", projection ["id","account_id","title","done"],
--                 filters [ {field:"account_id", op:"eq", value: account_id} ], limit 50
```

## 4. Verified machine QueryPlan / executor shape

`runtime/igniter-machine/src/postgres_read.rs`:
- `QueryPlan::from_args(args)` reads `source` (required), `op` (default `"select"`), `projection`,
  `filters:[{field, op (default "eq"), value}]`, `limit`; and **refuses raw SQL** if `args` carries a
  `sql` / `raw_sql` / `query` string (`postgres_read.rs:54-60`).
- `execute` gate order: raw-SQL refusal → source allowlist → mutating-op refusal → op allowlist →
  projection+filter field allowlist → row-limit clamp → adapter (`postgres_read.rs:228-282`). The adapter
  is the only place the external port is reached; every gate runs before it.
- The executor is a `CapabilityExecutor`, so it rides the existing `run_effect` receipt/replay machinery.
- **Honest v0 bound:** filters are carried structurally but **not evaluated** by the fake adapter — this
  proof does not claim row filtering.

JSON-key-for-`.ig`-field alignment is exact, so a serialized P2 `QueryPlan` lands cleanly in `from_args`.

## 5. Tests — what each proves

`runtime/igniter-machine/tests/relational_queryplan_bridge_tests.rs` (6 tests, default build):

1. `p2_fixture_declares_the_queryplan_shape_the_executor_reads` — the **shape tie**: the P2 fixture
   declares the `QueryPlan`/`QueryFilter` fields the executor reads + the `TodosByAccount` specifics
   (source `"todos"`, eq filter on `account_id`, the four columns).
2. `p2_queryplan_reaches_executor_and_returns_rows` — the mirrored `TodosByAccount("acct-7")` plan →
   `Succeeded`, `kind: "rows"`, projection-shaped rows, `query_count == 1`, receipt persisted as a fact.
3. `allowlist_source_field_and_op_gates` — unknown source (`secrets`), forbidden projection field, forbidden
   filter field, and a mutating op (`update`) each **Denied before the adapter** (`query_count == 0`).
4. `limit_clamped_to_policy` — the fixture's `limit: 50` clamped to a policy cap of 1 (`effective_limit: 1`,
   `row_limit_clamped: true`, one row).
5. `replay_same_key_bypasses_adapter` — same idempotency key + payload twice → identical result,
   `query_count == 1`.
6. `raw_sql_refused_structurally` — a plan smuggling `sql` / `raw_sql` / `query` → `PermanentFailure`
   ("raw SQL refused") for each, adapter untouched.

## 6. Commands + pass counts

```text
$ cd runtime/igniter-machine && cargo test --no-default-features --test relational_queryplan_bridge_tests
  → 6 passed; 0 failed              (default build: no `postgres` feature, no DSN, no live DB)
$ cd lang/igniter-compiler && cargo test --test relational_todo_tests
  → 4 passed; 0 failed              (P2 fixture remains compiler-clean)
$ git diff --check                  → clean (only the new bridge test + this card/doc are added)
```

No production source changed (only a new test file); no `Cargo.toml`, feature flag, or dependency edit.

## 7. Limitations

- **Host-side mirror, not VM execution** (proof shape B) — the `.ig` contract is not *run*; its compiled
  shape (proven in P2) is mirrored as JSON. VM-result extraction is `…-VM-EXECUTION-BRIDGE-P4`.
- **Filters carried, not evaluated** (machine v0); `eq`-only.
- **Rows are JSON** (text-shaped on the real adapter); typed reads are `…-TYPED-READ-P10`.
- Fake adapter only — no live Postgres, pool, TLS, or schema.

## 8. Next recommendation

`LAB-IGNITER-RELATIONAL-IGWEB-VIA-P4` — call a relational query contract from an IgWeb `via` guard (the
guard's `Ok` context = the query result), now that the language shape (P2) and the machine boundary (P3)
both check out. In parallel: `LAB-MACHINE-POSTGRES-TYPED-READ-P10` (typed read values) and, only if real
VM-result extraction is needed, `LAB-IGNITER-RELATIONAL-VM-EXECUTION-BRIDGE-P4`.

---

*Lab proof. Compiled 2026-06-19; 6 bridge tests green on the default build (no DB/feature/DSN); P2 fixture
still compiler-clean (4 tests). No live Postgres, compiler, VM, or production-source change.*
