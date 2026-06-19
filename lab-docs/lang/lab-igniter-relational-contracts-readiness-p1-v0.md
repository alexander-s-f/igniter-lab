# lab-igniter-relational-contracts-readiness-p1-v0 — a relational model on contracts

**Card:** `LAB-IGNITER-RELATIONAL-CONTRACTS-READINESS-P1` · **Delegation:** `OPUS-RELATIONAL-CONTRACTS-P1`
**Status:** READINESS / DESIGN (v0) — the **language/app** side of the Postgres wave, paired with the
machine card `LAB-MACHINE-POSTGRES-SCHEMA-QUERY-READINESS-P9`. **No code, no compiler/stdlib/parser/`.ig`
syntax change, no DB adapter code, no SQL, no canon claim.**
**Authority:** Lab readiness. `.ig` contracts + the existing host Postgres capability remain the
behavioral truth.

---

## 0. Verify-first deltas (reorg + live facts)

**Path delta (reorg):** the card's verify-first paths `igniter-machine/src/postgres_*.rs` are now under
**`runtime/igniter-machine/src/postgres_*.rs`** (the machine crate moved to `runtime/`). All listed
surfaces were read at the new path; the readiness docs are still under `lab-docs/lang/`.

**Live machine boundary (read against `runtime/igniter-machine/src/postgres_{read,write,real}.rs` +
`capability.rs` + their tests):**

| Surface | Shape today | Evidence |
|---|---|---|
| **Read** | a structured **`QueryPlan { source, op, projection, filters: [{field, op, value}], limit }`** — **zero SQL, zero handle** | `postgres_read.rs:44-50` |
| Filters | carried structurally; **`op` must be `eq`** (real adapter), and the fake adapter **does not evaluate** filters in v0 | `postgres_read.rs:92-101`, `:373-374` |
| Read result | `rows: Vec<Value>` (JSON objects, projection-shaped); real adapter returns **every column as `::text`** | `postgres_read.rs:283-291`, `postgres_real.rs:127-137` |
| **Write** | a structured **`PostgresWriteIntent { operation, target, key, values, correlation_id }`** via `run_write_effect` → receipt | `postgres_write.rs:44-50` |
| Idempotency | **two layers**: machine `__receipts__` (replay / different-payload refusal) + PG-side `effect_receipts(idempotency_key)` unique key | `postgres_write.rs:256-262`, `postgres_write_tests.rs:275-327` |
| Write outcomes | `Committed / DuplicateKey / Denied / ConstraintViolation / SerializationFailure / Unknown` | `postgres_write.rs:128-137` |
| Reconcile | **read-only** lookup of `effect_receipts` by idempotency key; never re-transacts | `postgres_write.rs:502-558`, `postgres_reconcile_tests.rs:112-160` |
| Authority | capsule emits a typed intent; host gates via **passport/scope + allowlist policy**; **capsule never sees DSN/connection** | `capability.rs:154-218`, `postgres_read.rs:9-20` |
| Schema | **no schema object in the VM** — host holds `PostgresReadPolicy { allowed_sources, allowed_ops, allowed_fields, row_limit }`; SELECT-only enforced before the adapter | `postgres_read.rs:147-156`, `:246-249` |
| Feature gating | `postgres` **opt-in**; default build **fake-only**; fake & real share one adapter trait | `postgres_real.rs:1-11`, `postgres_read.rs:81-82` |

**Live language facts (read against `typechecker.rs` + prod `.ig`, carried from P19–P21):**
`Collection[T]` is recognized (`typechecker.rs:63-97`); `Option[T]` (`some/none`, `Some{value}/None`) and
`Result[T,E]` (`ok/err`, `Ok{value}/Err{error}`) are sealed built-ins; **records construct as bare
`{ field: value }` literals** (type from annotation), proven in `lead_router/pipeline.ig:104`. **Everything
the relational pattern needs already exists** — no new syntax.

---

## 1. Executive summary

A "relational contract" needs **no new language feature**. The existing machine already accepts a capsule's
**structured intent value** (`QueryPlan` for reads, `WriteIntent` for writes), gates it by passport +
allowlist, executes it host-side, and returns rows as JSON / a receipt — with the capsule never touching
SQL or a connection. Records, `Collection[T]`, `Option[T]`, and `Result[T,E]` already express the
intents and results. So **relational contracts v0 = a convention over ordinary `.ig` contracts**: a small
typed vocabulary (`QueryPlan` / `WriteIntent` mirror records, row types) plus the rule that *relations are
contracts, not fields*. This keeps Igniter ORM-free: explicit dataflow, host-owned authority,
receipt-backed writes, inspectable plans.

## 2. Relational contracts v0 — definition (Q1)

> **A relational contract is an ordinary pure `.ig` contract that returns a structured *intent* value the
> host Postgres capability executes — a `QueryPlan` record for reads, a `WriteIntent` record for writes —
> never a DB handle, connection, or SQL string.**

Smallest useful meaning: a **convention** (a) over ordinary contracts, *not* a projection dialect, *not* a
compiler feature, *not* a host recipe shape. Rejected framings: a *dialect* (no new syntax is needed —
records already express plans; a dialect would add surface without power); a *compiler feature* (premature —
prove the convention first); *host-recipe-only* (opaque — the plan should be inspectable `.ig`).

## 3. Primitives (Q2)

| Concept | v0 home | Notes |
|---|---|---|
| table | **host metadata** (allowlist) + a logical name string in `.ig` | `PostgresReadPolicy.allowed_sources`; `.ig` names it, host validates |
| row type | **`.ig` `type Todo { … }`** — *advisory mirror* | rows return as untyped JSON today (real adapter = text-only), so the row type is a projection target, **not enforced** (gap, §7/§10) |
| primary / business key | a **field convention** (`WriteIntent.key`) | not a language primitive |
| relation / FK | a **separate contract** (Q3-B) | `TodosByAccount(account_id) -> Collection[Todo]` |
| query | a **`QueryPlan` record** | mirrors `postgres_read::QueryPlan` |
| command / write intent | a **`WriteIntent` record** (or `Decision::InvokeEffect` for IgWeb) | mirrors `PostgresWriteIntent` |
| projection / view model | an **`.ig` row/record type** + the plan's `projection` list | host shapes output to projection |
| transaction | **host-owned**, one atomic write effect | multi-statement txn = deferred (§10) |

Explicit in `.ig` today: row/intent records, `Collection`/`Option`/`Result`. Host metadata: table existence,
schema, allowlists, connection, transaction, receipts.

## 4. Query model (Q4)

**Named query contracts returning a typed `QueryPlan` record** that the host executes. Raw SQL is
**rejected** (matches the machine: structured plan, zero SQL). The `.ig` mirror is exactly the machine type:

```ig
type QueryFilter { field : String, op : String, value : String }
type QueryPlan {
  source     : String,           -- host-allowlisted table/view
  op         : String,           -- "select" (read capability refuses mutating ops)
  projection : Collection[String],
  filters    : Collection[QueryFilter],
  limit      : Integer
}

pure contract TodosByAccount {
  input account_id : Option[String]
  compute plan : QueryPlan = {
    source: "todos", op: "select",
    projection: ["id", "title", "done"],
    filters: [ { field: "account_id", op: "eq", value: or_else(account_id, "") } ],
    limit: 50
  }
  output plan : QueryPlan
}
```

The host runs `plan` through the **read** `CapabilityExecutor` (passport + `allowed_sources`/`allowed_ops`/
`allowed_fields` + row-limit clamp, all before the adapter) and returns `rows : Collection`. **v0 honest
bounds, inherited from the machine:** `op = "eq"` only; filters are *carried* but evaluation is a machine
follow-on; rows come back text-shaped JSON. The `.ig` plan therefore *mirrors* the machine `QueryPlan`
field-for-field — no authority leaks, the host owns every gate.

## 5. Write model (Q5)

**Command contracts returning a typed `WriteIntent` record** (or, for IgWeb handlers, a
`Decision::InvokeEffect` naming a write target). The host runs it through `run_write_effect`:

```ig
type WriteIntent {
  operation      : String,   -- "insert" | "upsert" | "update" | "delete"
  target         : String,   -- host-allowlisted table
  key            : String,   -- business key (bound param, never SQL)
  values         : ...,       -- column→value record (bound params)
  correlation_id : String
}

pure contract CreateTodo {
  input account_id : Option[String]
  input title      : Option[String]
  compute intent : WriteIntent = {
    operation: "insert", target: "todos",
    key: req_idempotency_key,
    values: { account_id: or_else(account_id, ""), title: or_else(title, ""), done: "false" },
    correlation_id: ""
  }
  output intent : WriteIntent
}
```

Idempotency and reconcile **stay in the machine** (two-layer: machine receipt + PG `effect_receipts`;
reconcile is read-only). The contract supplies only logical intent; the host owns the atomic transaction
and the receipt. Reject *direct DB command contracts* and *contracts that perform the write* — the write is
always a host-executed, receipt-backed effect.

## 6. Schema ownership (Q6)

**Host-owned schema + `.ig` typed mirrors (advisory).** The VM has no schema object; the host publishes the
allowlist (`PostgresReadPolicy`), which is the only authority on tables/columns. `.ig` row/plan types
*mirror* that schema for readability and projection shaping but are **not** enforcement. Rejected:
*schema-first SQL in `.ig`* and *contract-first DDL generation* (migration/ORM territory). **Dual-source
drift checks** (compare `.ig` mirror vs host allowlist) are a sensible later slice, not v0.

## 7. Anti-ORM rules (Q7)

Hard rules that keep the model Igniter-native (each backed by the live boundary):

1. **No hidden lazy loads** — a relation is an explicit `call_contract` to a query contract, never a field
   access that triggers IO.
2. **No active-record methods on rows** — rows are plain records / JSON; no `todo.save()`.
3. **No implicit transactions** — every write is an explicit `WriteIntent` → receipt; no ambient txn.
4. **No naming / pluralization authority** — table names are explicit allowlisted strings; no `Todo`→`todos`
   inference grants access.
5. **No DB handle / connection / DSN in contracts** — structurally guaranteed by the capability boundary.
6. **Explicit contract calls only** — joins/relations compose by calling contracts, not by ORM graph walks.
7. **Receipts for writes; read-only reconcile** — idempotency and recovery live in the machine.
8. **Structured plans, never SQL** — the `.ig` surface is `QueryPlan`/`WriteIntent`, SQL stays host-internal.
9. **Reads are SELECT-only** — enforced by the read capability before the adapter.

## 8. IgWeb pressure example (Q8)

Todo/Account, split across the three layers:

```igweb
# routes.igweb  (.igweb — routing + guards only)
scope "/accounts/:account_id" {
  resource todos "/todos" {
    index  GET             via TodosByAccount(account_id) as todos -> AccountTodosIndex
    show   GET "/:todo_id" via FindTodo(account_id, todo_id) as todo -> AccountTodoShow
    create POST            -> AccountTodoCreate requires idempotency
  }
}
```

- **`.igweb`** owns routing + `via` guards. A read flows through a **`via` guard that names a query
  contract** (P19/P20): the host runs the query capability and injects the rows as the guard's typed
  context — `AccountTodosIndex(req, todos)` then shapes a `Respond`. `FindTodo -> Option[Todo]` gives
  not-found as `None` (a `via` that rejects with `Respond 404` on `None`).
- **`.ig`** owns the relational contracts (`TodosByAccount` → `QueryPlan`, `FindTodo` → `Option[Todo]`,
  `AccountTodoCreate` → `Decision::InvokeEffect` / `WriteIntent`) and the row types.
- **host DB policy** owns the allowlist, passport, connection, and write receipts.

**Honest bridging gap (flagged, not hidden):** today the read capability takes a structured `QueryPlan` as
`EffectRequest.args`, while IgWeb's `Decision::InvokeEffect.input` is a `String`. So v0 relational reads run
on the **capability/coordination path** (host builds/runs the plan from the contract's returned `QueryPlan`
record and supplies rows to the `via` guard), not by smuggling a plan through `InvokeEffect`. Carrying
structured effect args through an IgWeb `Decision` is a deferred slice (§10). This is exactly the seam the
`via`-guard model (P19/P20) was built for: the guard's context *is* the query result.

## 9. Future proof / test matrix (Q9)

For the implementation card(s):

- Todo **index** (`TodosByAccount` → `QueryPlan`, rows → `Respond`).
- Todo **show** (`FindTodo` → `Option[Todo]`; `Some`→200, `None`→404 via guard).
- Todo **create** (`CreateTodo` → `WriteIntent`/`InvokeEffect` → receipt).
- Todo **done** (mutating `member` action → `WriteIntent` update, `requires idempotency`).
- **Account has-many todos** (`TodosByAccount(account_id)` — relation as a contract, no nested field).
- **join-like projection** (a contract composing two query contracts host-side, or a host view as `source`).
- **not-found as `Option`** (`FindTodo -> Option[Todo]`, `Some/None`).
- **permission/guard** via an IgWeb `via` guard returning `Result[Ctx, Decision]`.
- **write returning receipt/Decision** (host receipt surfaced; no SQL/values in the receipt).
- **real-compile proof**: the `QueryPlan`/`WriteIntent` records + `Collection`/`Option` types compile clean
  through the real multifile compiler (no `OOF-TY0`), **no DB**.

## 10. Deferred surfaces (Q10)

Migrations; package manager; schema registry; relationship DSL; aggregation DSL; query optimizer; GraphQL-
like expansion; source-map; live DB; ORMs. Plus machine-bounded follow-ons that gate richer language shapes:
**non-`eq` filter predicates + filter evaluation**, **typed-row enforcement / rich PG types** (today rows
are text-JSON), **multi-statement transactions**, **joins in one plan**, **structured effect args through an
IgWeb `Decision`**, and **schema drift checks**. None block the v0 convention.

## 11. Next card (Q11)

**`LAB-IGNITER-RELATIONAL-CONTRACTS-TODO-P2`** — a **pure `.ig` Todo relational example, no DB**: row types
+ `QueryPlan`/`WriteIntent` mirror records + query/command/relation contracts (`TodosByAccount`, `FindTodo`
→ `Option[Todo]`, `CreateTodo` → `WriteIntent`), compiled clean through the **real** compiler to prove the
records/`Collection`/`Option`/`Result` shapes typecheck and that relations-as-contracts read well. **Why
first:** it is zero-risk (no DB, no machine, no compiler change), it locks the *language shape* before any
wiring, and it directly de-risks the IgWeb pressure example (§8).

**Then** `LAB-IGNITER-RELATIONAL-QUERYPLAN-BRIDGE-P3` — feed the contract's `QueryPlan` record into the
**fake** `PostgresReadExecutor` (already in the default build), proving the `.ig`-plan → machine-`QueryPlan`
mapping + allowlist gating end-to-end without a live DB.

**Reject** `…-DIALECT-READINESS` as the next step: the whole finding is that a *convention* suffices — a
dialect would add surface without power. Open it only if the pure-`.ig` example proves the records too noisy
to author by hand.

---

*Readiness/design only. Compiled 2026-06-19; grounded in live `runtime/igniter-machine/src/postgres_*.rs`
(+ tests), `capability.rs`, the P2/P3/P4/P6/P8 Postgres docs, and `typechecker.rs`/prod `.ig`. No code,
compiler, VM, stdlib, server, DB, package, or canon change.*
