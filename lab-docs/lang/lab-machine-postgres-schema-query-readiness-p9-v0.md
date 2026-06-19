# lab-machine-postgres-schema-query-readiness-p9-v0 — schema/query ownership after real local Postgres

**Card:** `LAB-MACHINE-POSTGRES-SCHEMA-QUERY-READINESS-P9` · **Delegation:** `OPUS-POSTGRES-SCHEMA-QUERY-P9`
**Status:** READINESS / DESIGN (v0) — maps who owns schema and query shape now that the real local
Postgres adapter (P5→P8) exists, and how far the machine may go before it becomes an ORM / migration
framework / SQL DSL. **No code, no `Cargo.toml`, no SQL execution, no DB connection, no migrations, no
pool, no Postgres-as-`TBackend`, no canon claim.**
**Authority:** Lab readiness. Live code + closed P5–P8 cards/docs are the evidence; live code wins.

---

## 1. Executive summary

The question is no longer "can we connect?" — P5→P8 proved a real, opt-in, safe local adapter. The
question is **ownership**: schema, query shape, and types. The load-bearing recommendation:

- **Schema is operator/app-owned (external SQL migrations).** The adapter **assumes** schema and
  **validates against host-configured policy**; it never creates, alters, infers, or introspects business
  schema (that would be a migration framework or ORM — both rejected). The single machine-owned exception
  is the `effect_receipts` idempotency table, which is a **documented required shape applied by the
  operator**, not a machine-run migration.
- **Queries stay typed plans against a host allowlist, never raw SQL from contracts** (already enforced).
  The next safe step is **richer types before richer predicates**: typed JSON values for reads
  (`…-TYPED-READ-P10`), then `in`/`order_by`/range, then keyset cursors. Joins and aggregations are
  **rejected** for the adapter — cross-entity composition belongs to the relational-contract layer.
- **Pooling is correctness-neutral** (the 2-layer idempotency + wire-atomic gate already give
  exactly-once under concurrent load) and is **deferred** to its own card gated by a serving-loop load
  proof.

Recommended next card: **`LAB-MACHINE-POSTGRES-TYPED-READ-P10`** (§11).

## 2. Verified current surface (P5→P8 live truth) — Q1

All facts file:line-verified in `igniter-machine` live code (not pre-P5 claims):

| Surface | State today |
|---|---|
| **Feature/deps** | `postgres` feature is **opt-in**, `default = []` fake-only; driver `tokio-postgres 0.7` (`Cargo.toml:39-46`). Real adapters `#[cfg(feature="postgres")]`; fakes always compiled. |
| **Read adapter** | `PostgresReadExecutor` over `PostgresReadAdapter::query(plan, limit)`. Host `PostgresReadPolicy { allowed_sources, allowed_fields }`. **`eq`-only** filters, explicit projection (no `SELECT *`), row-limit clamp. All identifiers quoted; values bound `$1..$n` (`postgres_read.rs`, `postgres_real.rs:86-138`). |
| **Type mapping (read)** | Every column cast `::text`; returned as `Value::String`/`Value::Null` — **all strings** (`postgres_real.rs:86-138`). |
| **Write adapter** | `PostgresWriteIntent { operation, target, key, values, correlation_id }`; host-bound single `target`/`key_column`/`columns`; **insert/upsert** (`postgres_real.rs:204-224`). |
| **Idempotency (2-layer)** | Machine `__receipts__` **plus** PG-side `effect_receipts(idempotency_key)` upserted in the **same atomic writable-CTE statement** (`WITH ins AS (… ON CONFLICT DO NOTHING …), biz AS (INSERT … WHERE EXISTS (SELECT 1 FROM ins) …)`); duplicate key ⇒ no second mutation (`postgres_real.rs:274-311`). |
| **Wire-atomic gate (P7)** | Host-provided `SingleFlight` serializes same-key writes before the adapter; closes the same-key double-execute window a yielding backend opens (`IMPLEMENTED_SURFACE.md`). |
| **Reconcile** | **Read-only** `lookup_effect_receipt(idempotency_key)` → Found⇒Committed / NotFound⇒PermanentFailure / Unavailable⇒still-unknown; identity-keyed, no re-execution (`postgres_write.rs:500-558`, `postgres_real.rs:320-333`). |
| **DSN / env / safety** | Read DSN `IGNITER_PG_DSN`; write DSN **separate** `IGNITER_PG_WRITE_DSN` (so writes can't touch SparkCRM). `NoTls` loopback only. One `Client` per adapter — **no pool** (`postgres_real.rs`). |
| **Raw-SQL boundary** | `sql`/`raw_sql`/`query` keys **structurally refused** before plan parse; identifiers come only from host allowlist, always quoted (`postgres_read.rs:53-62`). |
| **Tests** | `#![cfg(feature="postgres")]`; **skip** when env DSN unset. Read: 6 tests vs dev SparkCRM `companies` (SELECT-only). Write: 5 tests vs **dedicated `igniter_pg_test`** `leads` (commit, PG-side dedup with lost machine receipt, replay-bypass, constraint→permanent+rollback, read-only reconcile). |
| **Default build** | Postgres-free, dependency-clean; real tests excluded. |

**Bottom line of the surface:** correct exactly-once writes and gated `eq` reads work today; the gaps are
**types (all-strings), predicates (`eq`-only), pooling (one connection), TLS (none), and schema ownership
(implicit)**.

## 3. Schema ownership decision — Q2

| Option | Verdict |
|---|---|
| A. host-owned fixture DDL only | partial — fine for tests, insufficient as the real model |
| **B. app/operator-owned SQL migrations outside Igniter** | **RECOMMEND (v0/v1)** |
| C. Igniter-owned migrations | **REJECT** — makes the machine a migration framework |
| D. schema inferred from contracts | **REJECT** — makes the machine an ORM (violates the card's anti-ORM rule) |

**Decision: schema is owned by the operator/app via external SQL migrations (B).** The machine adapter
**assumes** the schema exists and **validates intent against host-configured policy** (`allowed_sources`,
`allowed_fields`, write `target`/`key_column`/`columns`) — exactly what the live code already does. The
adapter **may assume**: named tables/columns exist with compatible types. The adapter **may not create**:
no `CREATE`/`ALTER`/`DROP` of business schema, no introspection-driven schema, no contract-derived DDL.
Schema **identity authority = host-side hand-written policy**, never contract input, never DB
introspection. This keeps "contracts describe intent; they never receive a DB handle and never become a
SQL dialect."

The **one machine-owned table** is `effect_receipts` (§4) — and even that is operator-applied DDL, not a
machine-run migration.

## 4. `effect_receipts` table decision — Q3

The live test DDL is the de-facto contract:

```sql
CREATE TABLE IF NOT EXISTS effect_receipts (
  idempotency_key TEXT PRIMARY KEY,            -- SEMANTIC: the dedup key (required)
  correlation_id  TEXT,                        -- OBSERVABILITY: trace linkage
  target          TEXT NOT NULL,               -- SEMANTIC: reconcile identity (which table)
  business_key    TEXT NOT NULL,               -- SEMANTIC: reconcile identity (which row)
  committed_at    TIMESTAMPTZ NOT NULL DEFAULT now()  -- OBSERVABILITY: audit timestamp
);
```

- **Semantic (load-bearing for correctness):** `idempotency_key` (PK — the atomic-CTE dedup pivot),
  `target` + `business_key` (the read-only reconcile identity that closed P7's false-positive gap).
- **Observability (non-load-bearing):** `correlation_id`, `committed_at`.

**Decision: fixed adapter contract on column SEMANTICS, host-configurable table NAME** (default
`effect_receipts`). It is **operator-applied DDL** shipped as a documented canonical snippet — **not** a
machine-run migration, **not** generated per build. Today it lives only in test setup; the next step is to
promote it to a documented "required shape + operator migration snippet" in `IMPLEMENTED_SURFACE.md`. This
keeps the machine free of a migration runner while making the one table it depends on explicit and
auditable.

## 5. Query-shape roadmap — Q4

All shapes are built **internally from a typed `QueryPlan`** against the host allowlist; **no raw SQL from
contracts**, ever. Verdict per operator:

| Operator | Verdict | Rationale |
|---|---|---|
| `eq` | **proven** | parameter-bound, allowlisted (`postgres_real.rs:92-108`) |
| `in` | **support next** | bounded list ⇒ `= ANY($1)`; safe, parameter-bound; common need |
| `order_by` | **support** | allowlisted columns + ASC/DESC; deterministic; pagination prerequisite |
| `gt`/`lt`/`range` | **support, after types** | comparisons need typed columns to be meaningful → pairs with §6; parameter-bound |
| `limit` | **proven** (clamped) | keep host clamp |
| `offset` | **defer** | O(n) pagination; prefer **keyset/cursor** later |
| cursor (keyset) | **support, later** | stable pagination on an ordered, allowlisted key |
| joins | **REJECT (adapter)** | pushes toward query planner/ORM; cross-entity composition belongs to relational contracts (§10), as composed single-source reads |
| aggregations | **REJECT/defer (adapter)** | `count` maybe later; `sum`/`group by` is an analytics DSL — out of the adapter's lane |

**Recommended sequence:** typed reads (§6) → `in` + `order_by` → range/comparison → keyset cursor. Each is
a bounded plan extension with no raw SQL and no `SELECT *`.

## 6. Type-mapping roadmap — Q5

Today every column is `::text` → `String`/`Null`, so an integer column silently becomes a string — a real
correctness gap. **Decision: return typed `serde_json::Value` per column** (the machine's existing neutral
value type), driven by the PG column type (or a host `field → type` map in the policy), **not** all-strings
and **not** a Rust typed row struct (that drifts toward ORM):

| PG type | → machine value |
|---|---|
| `int2/int4/int8` (≤ i64) | `Value::Number` (integer) |
| `numeric/decimal` | **`Value::String`** — preserve precision; never lossy float |
| `bool` | `Value::Bool` |
| `text/varchar/uuid` | `Value::String` |
| `timestamptz/date/time` | `Value::String` **RFC3339** (lossless, sortable) |
| `json/jsonb` | the JSON value itself |
| arrays | `Value::Array` of the element mapping |
| NULL (any) | `Value::Null` |

This is the **`…-TYPED-READ-P10`** body. It is read-only, bounded, testable against the existing dev read
DB, and is the prerequisite for meaningful range/comparison predicates (§5). The neutral-JSON choice keeps
the adapter ORM-free: contracts interpret typed values; they don't receive Rust row structs.

## 7. Pool / concurrency boundary — Q6

**Pooling is correctness-neutral and deferred.** Exactly-once already holds under concurrent wire load via
the **`SingleFlight` per-key gate (P7)** + **2-layer idempotency (P8)**; a pool only adds *throughput* for
**distinct** keys. So:

- **Where it belongs:** inside the **`postgres_real` adapter layer** (host authority), behind the existing
  `PostgresReadAdapter` / write traits, as a separate impl — **not** in the executor/policy layer, which
  stays connection-agnostic.
- **Concurrency invariant the pool must preserve:** `SingleFlight` still serializes **same-key** writes;
  the pool only parallelizes **distinct-key** work. A pool must never let two same-key writes race the DB.
- **Shutdown:** graceful drain on machine shutdown (no half-open connections); bounded size; backpressure
  when exhausted maps to `unknown`/`retryable`, never silent loss.
- **Gating:** open `LAB-MACHINE-POSTGRES-POOL-P*` only after a **serving-loop load proof** shows the
  single connection is the bottleneck. Use a vetted pool crate (e.g. `deadpool-postgres`/`bb8`) under the
  `postgres` feature. **Not the next card** — typed reads are higher value and pooling is correctness-neutral.

## 8. Outcome taxonomy — Q7

Grounded in the live `classify_write_error` / read-result mapping; classify by **epistemics** (did it
commit?), not by surface:

| Condition | SQLSTATE / source | Outcome |
|---|---|---|
| host policy: source/field/target not allowlisted | (gate, pre-DB) | **Denied** |
| permission denied | `42501` | **Denied** |
| missing table | `42P01` | **Permanent** |
| missing column | `42703` | **Permanent** |
| type mismatch / bad value | `22xxx` / `42804` | **Permanent** |
| integrity constraint | `23xxx` | **Permanent** |
| **migration drift** (schema changed under the adapter) | surfaces as `42P01`/`42703` | **Permanent — fail loud**, never silent-retry |
| serialization failure / deadlock | `40001` / `40P01` | **Retryable** |
| transient DB unavailable (connection/IO, non-DbError) | — | **Unknown** (epistemic — no proof it didn't commit) |

Rules: **Denied** = host policy/permission refusal (no attempt or DB refusal); **Permanent** = the request
shape is wrong and will keep failing (loud, so drift is visible); **Retryable** = same request may succeed
(serialization/deadlock); **Unknown** = we don't know if it committed → reconcile via `effect_receipts`,
never blind-retry. This matches live code and must stay stable.

## 9. Receipt observability rules — Q8

Receipts carry **names, counts, classes, keys — never values, SQL, DSN, or secrets.** From live receipts:

| Field | Read | Write | Safe? |
|---|---|---|---|
| query/source/target **name** | ✓ `source` | ✓ `target` | yes |
| row **count** | ✓ `count` | — | yes |
| effective limit / clamp flag | ✓ | — | yes |
| business **key** / idempotency key | — | ✓ `key`, `correlation_id` | yes (keys must be opaque, no PII) |
| duplicate flag | — | ✓ `duplicate` | yes |
| reconcile evidence | — | ✓ `reconciled`/`reconciled_by`/`pg_effect_receipt{correlation,target,key}` | yes |
| **policy name/version** | **ADD** | **ADD** | recommended — audit which allowlist ran |
| **SQLSTATE class** (e.g. `23`,`40`) | **ADD** | **ADD** | recommended — triage **class only**, not the full message (messages can echo values) |
| **schema version hash** | **ADD (when §11 lands)** | **ADD** | recommended — pin drift |
| raw SQL | — | — | **NO** |
| column **values** | the `rows` array is the query **result** | never | result ≠ audit: an audit receipt should carry **count + source + policy version + SQLSTATE class**, not row values; row values flow as the effect *result*, subject to the read policy's own redaction |

The result-vs-audit distinction matters: the read **result** legitimately contains rows; the **audit
receipt** should not persist row values. Make that boundary explicit when typed reads land.

## 10. Relational-contracts handoff — Q9

| Owned by the **machine adapter** (this lane) | Owned by the **relational-contract / language** layer (separate card) |
|---|---|
| connection, DSN/env, TLS, pool | how a contract **describes** a query/write intent (the `QueryPlan`/`WriteIntent` *shape* as data) |
| host allowlist policy (sources/fields/target) | entity / relationship **modeling** in `.ig` |
| plan **execution** (`eq`/projection/limit; later `in`/order/range) | **cross-entity composition** (joins-as-contract-composition over single-source reads — NOT SQL joins) |
| type conversion (PG → typed JSON) | mapping **domain types** ↔ the adapter's typed JSON |
| idempotency, wire-atomic gate, reconcile, receipts | authoring ergonomics (how `.ig` says "active companies") |
| outcome taxonomy | — |

**Handoff points:** (1) a contract emits a **typed `QueryPlan`/`WriteIntent` (JSON)** — that wire format is
the contract between layers; (2) the adapter **validates against host policy and executes**; (3) results
return as **typed JSON values** the contract interprets. Effect identity/capability authority stays
**host-owned** on both sides. Joins/aggregations live on the **composition** side, never as adapter SQL.

## 11. Recommended next card — Q10

**`LAB-MACHINE-POSTGRES-TYPED-READ-P10`** — map PG read columns to typed `serde_json::Value` (§6:
int/bool/json/timestamp-as-RFC3339/null/array; **decimal-as-string** for precision), replacing the
all-`::text` shape, behind the existing read executor/policy and gate-parity tests.

**Why first (vs pool / schema-version):**
1. **Highest correctness value** — today int/bool columns silently become strings, a real bug surface for
   any consumer.
2. **Unblocks the predicate roadmap** — range/comparison (`gt`/`lt`) are only meaningful on typed columns.
3. **Smallest safe slice** — read-only, no new external surface, no pool, testable against the existing dev
   read DB with the proven skip-when-unset harness.
4. Pooling is **correctness-neutral** (defer until a load proof); schema-version/drift is **more valuable
   after** types + predicates make the schema surface richer.

**Sequence:** `TYPED-READ-P10` → `PREDICATES (in/order_by/range) P11` → `POOL P12` (gated by serving-loop
load proof) → `SCHEMA-VERSION + canonical effect_receipts DDL P13` → TLS later. Each slice is bounded,
preserves no-raw-SQL/no-ORM, and keeps the adapter host-authoritative.

---

*Readiness/design only. Compiled 2026-06-19; grounded in live `igniter-machine` `postgres_read.rs` /
`postgres_write.rs` / `postgres_real.rs`, the real read/write test suites, `Cargo.toml`, and
`IMPLEMENTED_SURFACE.md`. No code, dependency, SQL, DB connection, or migration change.*
