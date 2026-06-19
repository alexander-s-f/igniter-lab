# Card: LAB-MACHINE-POSTGRES-SCHEMA-QUERY-READINESS-P9 — schema/query ownership after real local Postgres

**Lane:** standard / readiness design · **Skill:** idd-agent-protocol  
**Status: CLOSED**  
**Delegation:** OPUS-POSTGRES-SCHEMA-QUERY-P9

## Intent

Postgres P5→P8 proved the real local adapter path: opt-in `postgres` feature,
real read, wire atomicity, real write + reconcile against a dedicated test DB.
The next DB question is no longer “can we connect?” — yes, locally and safely.
The next question is **who owns schema and query shape**, and how far the machine
should go before it accidentally becomes an ORM, migration framework, or SQL DSL.

Produce a readiness packet for the next Postgres wave:

```text
real local Postgres adapter exists
  -> schema/query ownership map
  -> migration boundary
  -> richer query mapping plan
  -> type mapping plan
  -> pool/concurrency preconditions
  -> next implementation card
```

No code in this card.

## Authority

Lab readiness only. The current authority surfaces are live code +
`igniter-machine/IMPLEMENTED_SURFACE.md` + closed P5/P6/P7/P8 cards/docs.
Docs/cards are evidence, not behavior. Live code wins.

This card may create:

- `lab-docs/lang/lab-machine-postgres-schema-query-readiness-p9-v0.md`;
- this card's closing report.

Closed in this card:

- no `Cargo.toml` changes;
- no SQL execution;
- no local DB connection;
- no migrations runner;
- no connection pool;
- no ORM;
- no Postgres-as-`TBackend`;
- no production/staging/SparkCRM DB writes.

## Verify First

Read current live code and docs before writing:

- `igniter-machine/IMPLEMENTED_SURFACE.md`
- `.agents/work/cards/lang/LAB-MACHINE-POSTGRES-LOCAL-FEATURE-READINESS-P5.md`
- `.agents/work/cards/lang/LAB-MACHINE-POSTGRES-LOCAL-READ-P6.md`
- `.agents/work/cards/lang/LAB-MACHINE-POSTGRES-WIRE-ATOMIC-P7.md`
- `.agents/work/cards/lang/LAB-MACHINE-POSTGRES-LOCAL-WRITE-P8.md`
- `lab-docs/lang/lab-machine-postgres-local-feature-readiness-p5-v0.md`
- `lab-docs/lang/lab-machine-postgres-local-read-p6-v0.md`
- `lab-docs/lang/lab-machine-postgres-wire-atomic-p7-v0.md`
- `lab-docs/lang/lab-machine-postgres-local-write-p8-v0.md`
- `igniter-machine/src/postgres_read.rs`
- `igniter-machine/src/postgres_write.rs`
- `igniter-machine/src/postgres_real.rs`
- `igniter-machine/tests/postgres_real_read_tests.rs`
- `igniter-machine/tests/postgres_real_write_tests.rs`

Also verify current `Cargo.toml` feature/dependency shape.

## Questions To Answer

### Q1. What exactly exists today?

Summarize P5→P8 as live truth:

- feature shape;
- read adapter;
- write adapter;
- wire atomic gate;
- reconcile;
- DSN/env gates;
- dedicated DB constraint;
- default-build cleanliness.

Do not rely on stale pre-P5 claims.

### Q2. Who owns schema in v0/v1?

Compare:

A. host-owned fixture DDL only;
B. app-owned SQL migrations outside Igniter;
C. Igniter-owned migrations;
D. schema inferred from contracts.

Recommend a v0/v1 boundary. Be explicit about what the machine adapter may
assume versus create.

### Q3. Should `effect_receipts` be a fixed machine table?

Define the minimal required table/columns for PG-side idempotency/reconcile and
which columns are semantic vs observability. Decide whether this is:

- fixed adapter contract;
- host-configurable table name;
- generated migration snippet;
- test-only for now.

### Q4. What richer query shapes are safe next?

Current real read is narrow. Evaluate next query operators:

- `eq` (already proven);
- `in`;
- `range` / `gt` / `lt`;
- `order_by`;
- `limit/offset` or cursor;
- joins;
- aggregations.

For each: say whether v0 should support, defer, or reject. Preserve no raw SQL
from contracts.

### Q5. What type mapping is needed?

Current read maps columns as text-like values. Decide next shape for:

- integer/numeric;
- boolean;
- timestamp/date;
- json/jsonb;
- nullable values;
- arrays.

Should the adapter return all strings, typed JSON values, or a typed row model?

### Q6. Where does connection pooling belong?

P8 used a real adapter without opening pool semantics. Decide whether pool is:

- part of `postgres_real` adapter;
- host layer around adapter;
- separate readiness/impl card;
- not needed until serving-loop load proof.

Include concurrency and shutdown concerns.

### Q7. How should schema/query errors map to machine outcomes?

Define taxonomy for:

- missing table;
- missing column;
- type mismatch;
- bad host policy;
- transient DB unavailable;
- permission denied;
- serialization/deadlock;
- migration drift.

Which are permanent vs retryable vs unknown vs denied?

### Q8. What should be observable in receipts?

Receipts must not leak SQL values/secrets. Decide what evidence is safe:

- query/source name;
- policy name/version;
- row count;
- table/target name;
- idempotency key;
- SQLSTATE class;
- schema version hash;
- raw SQL? probably no.

### Q9. How does this relate to relational contracts?

Draw the boundary between machine adapter policy and language/application
contracts. This card owns the machine/DB side; relational contract modeling is a
separate card. State exact handoff points.

### Q10. What is the next implementation card?

Pick the smallest next implementation, for example:

- `LAB-MACHINE-POSTGRES-TYPED-READ-P10`;
- `LAB-MACHINE-POSTGRES-POOL-P10`;
- `LAB-MACHINE-POSTGRES-SCHEMA-VERSION-P10`;
- another bounded slice.

Justify the sequence.

## Required Deliverable

Create:

```text
lab-docs/lang/lab-machine-postgres-schema-query-readiness-p9-v0.md
```

It must include:

1. executive summary;
2. verified current P5→P8 surface;
3. schema ownership decision;
4. effect_receipts table decision;
5. query-shape roadmap;
6. type-mapping roadmap;
7. pool/concurrency boundary;
8. outcome taxonomy;
9. receipt observability rules;
10. relational-contracts handoff;
11. recommended next card.

Then mark this card CLOSED with a compact closing report.

## Acceptance

- [x] Packet exists at the required path.
- [x] Packet verifies live P5→P8 surfaces before making claims.
- [x] Packet answers Q1-Q10 explicitly.
- [x] Packet does not propose raw SQL from contracts.
- [x] Packet does not promote ORM or Postgres-as-`TBackend`.
- [x] Packet separates schema ownership from runtime adapter behavior.
- [x] Packet names the smallest next implementation card.
- [x] No code, dependencies, SQL execution, DB connection, or migrations are changed.
- [x] Closing report added here.

---

## Closing Report (2026-06-19)

**Deliverable:** `lab-docs/lang/lab-machine-postgres-schema-query-readiness-p9-v0.md` — readiness packet,
**no code** (only the packet + this card touched). All 11 required sections; Q1–Q10 answered.

**Verify-first (live `igniter-machine`, not stale claims):** confirmed the P5→P8 surface file:line —
`postgres` feature opt-in (`default = []`), `tokio-postgres 0.7` NoTls one-connection-per-adapter; read
executor with host allowlist policy, **`eq`-only**, projection, limit-clamp, **all columns `::text`→String**;
write executor host-bound to one target, insert/upsert, **2-layer idempotency** (machine `__receipts__` +
PG `effect_receipts` in one atomic writable-CTE), SingleFlight wire-atomic gate, **read-only reconcile**;
separate `IGNITER_PG_DSN`/`IGNITER_PG_WRITE_DSN`, dedicated `igniter_pg_test` for writes; **raw SQL
structurally refused**; tests feature+env-gated, skip when unset.

**Key decisions:**
- **Schema ownership = operator/app external SQL migrations (B).** Adapter assumes + validates against
  host policy; never creates/alters/infers/introspects business schema. Reject Igniter-owned migrations (C)
  and contract-inferred schema (D). Sole machine-owned table `effect_receipts` = documented required-shape,
  operator-applied DDL (configurable name), not a machine-run migration.
- **Types before predicates.** Next: typed `serde_json::Value` reads (int/bool/json/timestamp-RFC3339/null/
  array; **decimal-as-string** for precision) — not all-strings, not a Rust row struct (ORM-ish).
- **Query roadmap:** `eq`(done)→`in`→`order_by`→range→keyset cursor; **reject joins/aggregations** in the
  adapter (push to relational-contract composition). No raw SQL, no `SELECT *`.
- **Pooling = correctness-neutral, deferred** (idempotency+gate already give exactly-once); belongs in the
  `postgres_real` adapter layer, gated by a serving-loop load proof.
- **Outcome taxonomy** (denied/permanent/retryable/unknown) and **receipt redaction** (names/counts/classes/
  keys, never values/SQL/DSN; result≠audit) specified from live `classify_write_error`.

**Recommended next card:** **`LAB-MACHINE-POSTGRES-TYPED-READ-P10`** (typed read values) — highest
correctness value, unblocks range predicates, smallest read-only slice; then PREDICATES P11 → POOL P12
(load-gated) → SCHEMA-VERSION/canonical-DDL P13 → TLS later.

## Notes

Prefer boring, auditable DB infrastructure over clever ORM shape. The adapter is
host authority. Contracts may describe intent; they do not receive a database
handle and they do not become a SQL dialect by accident.
