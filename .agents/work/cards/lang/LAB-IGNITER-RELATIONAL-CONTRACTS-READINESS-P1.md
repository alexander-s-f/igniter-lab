# Card: LAB-IGNITER-RELATIONAL-CONTRACTS-READINESS-P1 — relational model on contracts

**Lane:** standard / language-DX readiness · **Skill:** idd-agent-protocol  
**Status: CLOSED**  
**Delegation:** OPUS-RELATIONAL-CONTRACTS-P1

## Intent

Investigate whether Igniter should grow a **relational contract** pattern: a way
to model tables, rows, relations, queries, and commands in Igniter terms without
turning the language into an ORM, SQL DSL, or database framework.

This card is the language/application side of the Postgres wave. It is paired
with `LAB-MACHINE-POSTGRES-SCHEMA-QUERY-READINESS-P9`, which owns the machine
adapter/schema/query infrastructure side.

No code in this card.

## Core Question

Can we express a useful relational model using contracts like this:

```text
contract ListTodos(req) -> Collection[Todo]
contract FindTodo(req, id) -> Option[Todo]
contract CreateTodo(req, input) -> Decision / intent
contract TodosByAccount(req, account_id) -> Collection[Todo]
```

while preserving the Igniter philosophy:

- contracts describe validated business/dataflow intent;
- host adapters own IO and authority;
- generated artifacts are inspectable;
- no hidden DB handle in capsules;
- no Rails-style magic naming/pluralization as authority;
- no raw SQL as public language surface.

## Authority

Readiness only. This card may create:

- `lab-docs/lang/lab-igniter-relational-contracts-readiness-p1-v0.md`;
- this card's closing report.

Closed:

- no compiler/typechecker/parser changes;
- no stdlib changes;
- no `.ig` syntax changes;
- no DB adapter code;
- no SQL execution;
- no package/canon decision.

## Verify First

Read current surfaces before writing:

- `lang/igniter-compiler/src/project.rs` (project/source model, if relevant)
- `lang/igniter-compiler/src/typechecker.rs` (types/collections/options/results)
- `lang/igniter-stdlib/src/` and stdlib docs if relevant
- `igniter-machine/src/postgres_read.rs`
- `igniter-machine/src/postgres_write.rs`
- `igniter-machine/src/postgres_real.rs`
- `lab-docs/lang/lab-machine-postgres-capability-readiness-p1-v0.md`
- `lab-docs/lang/lab-machine-postgres-read-executor-p2-v0.md`
- `lab-docs/lang/lab-machine-postgres-write-gate-p3-v0.md`
- `lab-docs/lang/lab-machine-postgres-reconcile-p4-v0.md`
- `lab-docs/lang/lab-machine-postgres-local-read-p6-v0.md`
- `lab-docs/lang/lab-machine-postgres-local-write-p8-v0.md`
- IgWeb route/runner docs if using Todo as pressure example.

If a claimed language feature is uncertain, verify against live compiler tests
or source. Do not assume ORM-like affordances exist.

## Questions To Answer

### Q1. What should “relational contract” mean?

Define the term without importing ORM assumptions. Is it:

- a convention over ordinary `.ig` contracts;
- a stdlib/module pattern;
- a projection dialect;
- a future compiler feature;
- a host recipe shape?

Recommend the smallest useful meaning for v0.

### Q2. What are the primitives?

Evaluate whether v0 needs first-class concepts for:

- table;
- row type;
- primary key;
- relation/foreign key;
- query;
- command/write intent;
- projection/view model;
- transaction.

Which are explicit `.ig` types/contracts today, and which remain host metadata?

### Q3. Can relations be contracts rather than fields?

Compare:

A. row type contains nested relations;
B. relation is a separate contract (`TodosByAccount(account_id)`);
C. relation is a host query policy only;
D. relation is a projection dialect sugar.

Recommend a v0 pattern.

### Q4. How should queries be expressed?

Compare:

- named query contracts;
- typed `QueryPlan` values;
- projection dialect lowering;
- host policy names;
- raw SQL strings.

Reject raw SQL unless you find a very strong reason. Explain how the chosen form
maps to Postgres adapter policy without leaking authority.

### Q5. How should writes be expressed?

Compare:

- command contracts that return typed write intents;
- contracts that return `Decision::InvokeEffect` targets;
- direct DB command contracts;
- event/receipt-backed effects.

Make sure idempotency and reconcile stay in the machine layer.

### Q6. What is the role of schema?

Should contracts define schema, mirror schema, or only consume host-published
schema metadata? Evaluate:

- schema-first SQL;
- contract-first generation;
- dual-source with drift checks;
- host-owned schema + `.ig` typed mirrors.

### Q7. How do we prevent ORM drift?

List hard rules that keep the model Igniter-native. Examples:

- no hidden lazy loads;
- no active record methods on rows;
- no implicit transactions;
- no naming/pluralization authority;
- no DB handle in contracts;
- explicit contract calls only;
- receipts for writes.

### Q8. How does this serve IgWeb?

Use Todo/Account/Ticket routes as pressure. How would an IgWeb handler call a
relational contract? What remains in `.igweb`, what lives in `.ig`, and what is
host DB policy?

### Q9. What examples should prove the idea?

Design a no-code/example matrix for future implementation:

- Todo index/show/create/done;
- Account has many todos;
- join-like projection;
- not-found as `Option`;
- permission/guard via IgWeb `via`;
- write returning receipt/Decision.

### Q10. What should be deferred?

Name deferred surfaces: migrations, package manager, schema registry,
relationship DSL, aggregation DSL, query optimizer, GraphQL-like expansion,
source-map, live DB, ORMs.

### Q11. What should the next card be?

Pick the smallest next step, for example:

- `LAB-IGNITER-RELATIONAL-CONTRACTS-TODO-P2` — pure `.ig` Todo relational
  contract example, no DB;
- `LAB-IGNITER-RELATIONAL-QUERYPLAN-BRIDGE-P2` — contract emits QueryPlan
  consumed by fake Postgres executor;
- `LAB-IGNITER-RELATIONAL-DIALECT-READINESS-P2` — if a projection dialect is
  truly needed;
- another bounded card.

Justify the choice.

## Required Deliverable

Create:

```text
lab-docs/lang/lab-igniter-relational-contracts-readiness-p1-v0.md
```

It must include:

1. executive summary;
2. verified current language/machine facts;
3. definition of relational contracts v0;
4. primitives table;
5. query model recommendation;
6. write model recommendation;
7. schema ownership stance;
8. anti-ORM rules;
9. IgWeb pressure example;
10. future proof/test matrix;
11. next-card recommendation.

Then mark this card CLOSED with a compact closing report.

## Acceptance

- [x] Packet exists at the required path.
- [x] Packet verifies live language and Postgres surfaces first.
- [x] Packet answers Q1-Q11 explicitly.
- [x] Packet does not create canon or implementation authority.
- [x] Packet rejects or tightly bounds ORM drift.
- [x] Packet explains how relational contracts interact with host Postgres
      adapter policy.
- [x] Packet names a smallest next proof card.
- [x] No code, compiler, VM, stdlib, server, DB, package, or canonical docs are
      changed.
- [x] Closing report added here.

---

## Closing Report (2026-06-19)

**Deliverable:** `lab-docs/lang/lab-igniter-relational-contracts-readiness-p1-v0.md` — readiness packet,
**no code** (`git status` shows zero `.rs`/`.ig` changes; only the packet + this card are new). Answers
Q1–Q11.

**Verify-first delta (reorg):** the card's `igniter-machine/src/postgres_*.rs` paths are now under
**`runtime/igniter-machine/src/`** — all surfaces read at the new path.

**Core finding:** a relational contract needs **no new language feature**. The live machine already accepts
a capsule's **structured intent value** — `QueryPlan { source, op, projection, filters:[{field,op:"eq",value}],
limit }` for reads (`postgres_read.rs:44-50`) and `PostgresWriteIntent { operation, target, key, values,
correlation_id }` for writes (`postgres_write.rs:44-50`) — gates it by passport + allowlist, executes it
host-side, and returns rows as JSON / a receipt, with the capsule never seeing SQL or a connection. Records
(`{ field: value }`), `Collection[T]`, `Option[T]`, `Result[T,E]` already express the intents and results.

**Recommendation:** **relational contracts v0 = a convention over ordinary `.ig` contracts** (not a dialect,
not a compiler feature): a typed `QueryPlan`/`WriteIntent` mirror vocabulary + row types, with **relations
as separate contracts, not fields** (Q3-B). Queries = named contracts returning `QueryPlan` (raw SQL
rejected); writes = command contracts returning `WriteIntent`/`InvokeEffect` (idempotency + reconcile stay
in the machine); schema = host-owned with advisory `.ig` mirrors. Nine anti-ORM rules pin it Igniter-native.

**Honest bounds flagged:** machine v0 is `eq`-only + unevaluated filters + text-JSON rows; the IgWeb seam is
the `via` guard (the guard's context = the query result), and structured effect args through a `Decision`
are deferred.

**Next card:** `LAB-IGNITER-RELATIONAL-CONTRACTS-TODO-P2` — a pure `.ig` Todo relational example (no DB),
compiled clean through the real compiler to lock the language shape. Then `…-QUERYPLAN-BRIDGE-P3` wires the
`QueryPlan` record to the **fake** read executor. Rejected a dialect-readiness next step (a convention
suffices). Pairs with the machine card `LAB-MACHINE-POSTGRES-SCHEMA-QUERY-READINESS-P9`.

## Notes

The goal is not to clone Rails ActiveRecord or SQLAlchemy. The goal is to find
an Igniter-native relational pattern: explicit contracts, inspectable dataflow,
host-owned authority, receipt-backed effects, and syntax that remains legible to
humans and agents.
