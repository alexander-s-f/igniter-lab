# Lab: Query / Arel-like Data Access — Pressure Boundary Research

**Card:** LAB-QUERY-P1  
**Track:** lab-query-arel-like-data-access-pressure-boundary-v0  
**Category:** lang / RESEARCH / DESIGN / LAB-ONLY  
**Status:** CLOSED — research complete; design boundary defined  
**Date:** 2026-06-09  
**Authority:** Lab-only. No grammar change. No compiler change. No canon claim. No stable surface.  
**Depends on:** PROP-043-P5, LAB-RESULT-ENVELOPE-P2, LAB-STDLIB-NET-P9, LAB-RACK-P14, LAB-SIDEKIQ-P5, LAB-CONCURRENCY-P4

---

## Executive Summary

Query/data-access pressure is real and well-motivated: any web application that
touches data needs a path from "describe what data I want" to "receive typed
results." The central finding of this research is that **query intent can be fully
expressed today as typed Records without any new grammar**. No parser changes, no
new IR node kinds, no VM opcodes. The plan-building layer is entirely CORE.

The key design distinction is:

> **Query v0 = typed intent AST (QueryPlan record) + capability boundary + mocked execution.**  
> **Query v0 ≠ ORM, ≠ database connection, ≠ ActiveRecord compatibility, ≠ persistence runtime.**

The analogy to Arel is instructive for one reason only: **AST-as-data**. Arel
builds a tree of node objects that describe a query without executing it; a
`to_sql` visitor serializes the tree later. Igniter can adopt the same separation
(plan record → executor contract) while rejecting all of Arel's dangerous
consequences (lazy loading, global connection state, implicit IO, relation magic).

**Immediate recommendation:** Open LAB-QUERY-P2 — a proof fixture implementing
three QueryPlan-building contracts + a mocked QueryRouter, proving plan
construction, kind-discriminant result routing, denial-as-data, and the closed
surface (no SQL connection, no ORM, no storage IO).

---

## 1. Research Context

### 1.1 What Igniter can express today

The Stage 1 compiler-proven subset (post-PROP-043-P5) supports:
- Named `Record` types with typed fields
- `Collection[T]`, `Option[T]`, `Map[String, String]`
- `pure contract` with multi-step `compute` chains
- `Map[String,String]` metadata with `map_get` + `or_else` chains
- Kind-discriminant records (PROP-044-P1 convention)
- `effect contract` with `capability` declarations (PROP-035)

**Everything needed for QueryPlan intent records is available today.**

### 1.2 What does NOT exist in the Igniter codebase

- No query planning types, contracts, or experiments anywhere
- No Arel-like AST nodes or visitors
- No SQL generation (production or lab)
- No database capability type
- No storage fragment class (distinct from TEMPORAL/TBackend)

`Store[T]` in ch3 (§3.1) is the *temporal substrate type* — it is bound to
`TBackend` (the bitemporal event store defined in PROP-008). It is NOT a
relational storage type. `OLAPPoint[T, Dims]` (PROP-024) is multidimensional
time-series analysis (Stage 2 reserved). Neither is the right anchor for
relational query planning.

**This research defines a new, orthogonal track: relational query intent as
typed records.** It does not interact with `Store[T]`, `TBackend`, or `OLAPPoint`.

### 1.3 Fragment classification for query contracts

Following ch4 fragment classification:

| Contract | Fragment class | Reason |
|----------|---------------|--------|
| `BuildSelectQuery` | **CORE** | Pure; no external capability; builds a Record |
| `BuildFilteredQuery` | **CORE** | Pure; predicate composition; builds a Record |
| `QueryRouter` | **CORE** | Pure; routes on kind; no IO |
| `ExecuteQuery` (future) | **ESCAPE → named STORAGE** | Requires `IO.StorageCapability`; touches external state |

In v0, all proof contracts are `pure` → CORE. The execution path is mocked in the
proof-local simulation (Layer C). No `effect contract` is needed yet.

---

## 2. Arel/ORM Concept Classification

### 2.1 Useful ideas from Arel — adopt these

| Concept | Arel source | Igniter expression |
|---------|------------|-------------------|
| **Query as composable data** | Arel::Nodes form a composable AST | `QueryPlan` record built by `pure contracts`; `Collection[FilterPredicate]` composes predicates |
| **Delayed execution** | AST built first; executed on `.to_a` | Plan-building contracts are CORE; execution requires explicit capability invocation |
| **Predicate composition** | `Arel::Nodes::And`, `Or`, `Eq`, `Gt` | `FilterPredicate` records with `op: String`; `Collection[FilterPredicate]` for AND composition |
| **Projection as explicit data** | `table[:col]` creates `Attribute` nodes | `Projection { fields: Collection[String] }` — named, never implicit `SELECT *` in typed path |
| **Renderer/executor separation** | `to_sql` visitor separate from AST | `PlanSerializer` (proof-local sim) separate from `BuildSelectQuery`; serializer is NOT production API |
| **Source table as typed node** | `Arel::Table.new(:users)` | `QuerySource { table: String, schema: String }` — explicit, auditable, capability-checked |
| **Direction/order as data** | `Arel::Nodes::Ascending`, `Descending` | `OrderBy { field: String, direction: String }` — "asc" | "desc" |
| **Limit as explicit constraint** | `.take(n)` → `LIMIT n` | `QueryPlan.limit: Integer` — explicit row budget |

### 2.2 Dangerous ORM ideas — permanently closed in v0

| Pattern | ORM source | Why it's closed |
|---------|-----------|----------------|
| **Hidden database IO** | `.where.first` fires SQL silently | Violates pure-contract model; CORE contracts must have no IO |
| **Lazy relation magic** | `user.posts` — deferred query | Implicit IO; impossible to type-check statically |
| **Global connection state** | `ActiveRecord::Base.connection` | No global mutable state in Igniter |
| **Callbacks** | `before_save`, `after_create` | No side-effect hooks in pure contracts |
| **Object identity persistence** | `model.save!` | Persistence is an `effect`; not a method on a record |
| **Implicit transactions** | `ActiveRecord::Base.transaction` | Not expressible in pure contracts; ESCAPE-class boundary |
| **Dynamic column access** | `user[attr]` — dynamic attribute lookup | OOF-MAP2 (Map[String,Any] permanently closed); use named Records |
| **N+1 query generation** | `.includes(:assoc)` | Joins deferred entirely; v0 = single-source only |
| **Schema migration DSL** | `create_table :users do` | Permanently closed; no persistence runtime |
| **ActiveRecord compatibility** | `User.find(1)` | Permanently closed; different design philosophy |
| **Connection pooling** | `connection_pool` | Runtime concern; no Igniter expression |
| **Implicit type coercion** | `user.created_at` → ActiveSupport::Time | Igniter: strict types; no silent coercion |

---

## 3. QueryPlan v0 — Candidate Type Shape

### 3.1 Core record types

```igniter
-- ── Source identification ──────────────────────────────────────────────────
-- Names the data source. Capability-checked at execution time.
-- schema is optional context (e.g. "public", "analytics"); "" if unused.
type QuerySource {
  table:  String,
  schema: String
}

-- ── Projection — what fields to return ────────────────────────────────────
-- include_all: Bool drives SELECT * equivalent — explicit, not implicit.
-- include_all: false (always preferred) + fields: Collection[String] = SELECT a, b, c
-- include_all: true = SELECT * — permitted in v0 for prototype contexts only
type Projection {
  fields:      Collection[String],
  include_all: Bool
}

-- ── Filter predicate — one comparison clause ──────────────────────────────
-- op values (v0 closed set, doc-declared):
--   "eq"      → field = value
--   "neq"     → field != value
--   "gt"      → field > value
--   "gte"     → field >= value
--   "lt"      → field < value
--   "lte"     → field <= value
--   "is_null" → field IS NULL (value ignored)
-- value is String in v0; typed value column deferred (requires variant grammar)
-- Multiple FilterPredicates in QueryPlan.filters = AND composition
-- OR composition: deferred to v1
type FilterPredicate {
  field: String,
  op:    String,
  value: String
}

-- ── Ordering ────────────────────────────────────────────────────────────────
-- direction values: "asc" | "desc" (doc-declared; not type-enforced in v0)
type OrderBy {
  field:     String,
  direction: String
}

-- ── Top-level query plan ──────────────────────────────────────────────────
-- kind values (v0 closed set):
--   "select"     → standard projection + filter + order + limit query
-- Deferred: "join", "aggregate", "union", "subquery"
-- filters are AND-composed. OR / NOT deferred to v1.
-- limit = 0 means "no limit"; executor may apply a safety cap from capability.
type QueryPlan {
  source:     QuerySource,
  projection: Projection,
  filters:    Collection[FilterPredicate],
  order:      Collection[OrderBy],
  limit:      Integer,
  kind:       String
}
```

### 3.2 Result envelope (kind-discriminant — PROP-044-P1 convention)

```igniter
-- QueryResult: kind-discriminated result envelope.
-- Follows the KDR convention (PROP-044-P1): kind is the primary discriminant.
-- kind values (v0 closed set):
--   "rows"          → query executed; rows contains zero or more results
--   "empty"         → query executed; zero rows matched (not an error)
--   "denied"        → StorageCapability denied this source/operation
--   "query_error"   → malformed plan (bad field name, bad op, etc.)
--   "system_error"  → infrastructure failure (connection lost, timeout, etc.)
-- Denial-as-data: "denied" flows as typed data, never as exception.
-- rows: Collection[Map[String,String]] in v0 — typed row projection deferred
--   (typed rows require Row[T] or named Record per-query; deferred to v1)
type QueryResult {
  kind:     String,
  rows:     Collection[Map[String, String]],
  count:    Integer,
  message:  String,
  metadata: Map[String, String]
}

-- StorageDenied: explicit denial record for the capability boundary.
-- Returned when StorageCapability rejects the query source or operation.
-- Always carries kind: "denied" — consumer branches deterministically.
type StorageDenied {
  table:    String,
  op:       String,
  reason:   String,
  kind:     String
}
```

### 3.3 Candidate operations (v0 scope)

```igniter
-- ── Plan construction (all pure / CORE) ───────────────────────────────────

pure contract BuildSelectQuery {
  input  source:     QuerySource
  input  projection: Projection
  input  filters:    Collection[FilterPredicate]
  input  order:      Collection[OrderBy]
  input  limit:      Integer
  compute plan = {
    source: source, projection: projection,
    filters: filters, order: order, limit: limit, kind: "select"
  }
  output plan: QueryPlan
}

pure contract BuildFilteredQuery {
  input  source: QuerySource
  input  field:  String
  input  op:     String
  input  value:  String
  input  limit:  Integer
  compute filter     = { field: field, op: op, value: value }
  compute filters    = [filter]
  compute projection = { fields: [], include_all: true }
  compute order      = []
  compute plan       = {
    source: source, projection: projection,
    filters: filters, order: order, limit: limit, kind: "select"
  }
  output plan: QueryPlan
}

-- ── Metadata access (pure / CORE) ────────────────────────────────────────

pure contract PlanInspector {
  input  plan:      QueryPlan
  compute table_opt = map_get(plan.metadata, "trace_id")
  compute trace_id  = or_else(table_opt, "no_trace")
  output trace_id:  String
}
-- Note: plan.metadata requires adding metadata: Map[String,String] to QueryPlan.
-- Deferred to P2 fixture design; included here as design candidate.

-- ── Query routing (pure simulation / CORE) ─────────────────────────────────

pure contract QueryRouter {
  -- Routes a QueryResult to an action string based on kind.
  -- Layer C simulation only; no real storage IO.
  input  result: QueryResult
  compute action = or_else(map_get(result.metadata, "route"), "unhandled")
  output action: String
}
```

### 3.4 Deferred to v1 (explicitly closed in v0)

| Feature | Deferral reason |
|---------|----------------|
| OR / NOT predicate composition | Requires variant/sum type for predicate tree |
| JOIN operations | Cross-source type relationships; N+1 risk; complex scope |
| Aggregates (COUNT/SUM/AVG/GROUP BY) | Requires Projection variant or aggregate node kind |
| Subqueries | Require recursive plan type; needs variant grammar |
| Write operations (INSERT/UPDATE/DELETE) | Separate mutation model; requires `effect` + transaction |
| Typed row projection (Row[T]) | Each query needs its own output Record; variant grammar |
| Parameterised queries | String interpolation safety; requires typed parameter slots |
| Schema discovery | Runtime concern; no static schema info at compile time |
| HAVING predicates | Aggregate-dependent; deferred with aggregates |
| WINDOW functions | OLAP territory; separate track |

---

## 4. Capability Boundary

### 4.1 StorageCapability model (following PROP-035 pattern)

When query execution is needed beyond mocked simulation, it requires an
`effect contract` with an `IO.StorageCapability` declaration. The capability
carries:

```
IO.StorageCapability {
  allowed_sources:   Collection[String],  -- table names; empty = deny all
  allowed_ops:       Collection[String],  -- ["read"] in v0; "write" deferred
  row_limit:         Integer,             -- safety cap; executor enforces
  allow_include_all: Bool,               -- whether SELECT * is permitted
  deny_reason:       String              -- human-readable if denied
}
```

This follows the same capability declaration model as `IO.NetworkCapability`
(PROP-035). The schema is lab-only; canon type opaque (CR-001 analog for storage).

```igniter
-- Future (v1+): effect contract for real execution
-- NOT authorized in v0
effect contract ExecuteQuery {
  capability storage: IO.StorageCapability
  effect read_from_storage using storage
  input  plan:   QueryPlan
  output result: QueryResult
}
```

In v0, this contract is **not written**. The proof-local simulation (Layer C)
stands in for execution.

### 4.2 Denial-as-data for storage operations

Following the cross-domain invariant proved in LAB-RESULT-ENVELOPE-P1/P2 and
PROP-044-P1: capability denial for storage **flows as `QueryResult { kind: "denied" }`**,
never as exception, never as raise.

The StorageCapability check fires before plan execution:
1. Is `plan.source.table` in `allowed_sources`? If not → `QueryResult { kind: "denied" }`
2. Is `plan.kind` ("select") in `allowed_ops`? If not → `QueryResult { kind: "denied" }`
3. Does `plan.limit` exceed `row_limit`? Apply cap (don't deny; log in metadata)

**Design law:** A denied storage query is data, not an exception. Consumer routes
on `kind` deterministically.

### 4.3 Source allowlist

The source table allowlist is the capability's primary guard. Unlike
IO.NetworkCapability (URL glob patterns), storage sources are simple string
equality checks against the allowlist. Dynamic table name construction is
rejected at design time (OOF candidate: OOF-STORE1).

### 4.4 Read/write split

v0 is **read-only**. `allowed_ops: ["read"]`. No write path in v0.
Write operations (INSERT/UPDATE/DELETE) require:
- A separate mutation capability (`IO.MutationCapability`) — not designed yet
- Transaction semantics — not in v0 scope
- Idempotency proof — not in v0 scope

### 4.5 Fragment classification implications

| Layer | Fragment class | Notes |
|-------|---------------|-------|
| Plan-building contracts | **CORE** | Pure; no capability; all in v0 scope |
| Plan-routing contracts | **CORE** | Pure; kind-discriminant on result; all in v0 scope |
| Query execution (future v1+) | **ESCAPE → new STORAGE class** | Requires `IO.StorageCapability`; not in v0 |
| SQL generation in production | **ESCAPE** | Runtime serialization; not production API in v0 |

A future **STORAGE** fragment class (analogous to TEMPORAL for TBackend reads)
could be added when the execution path lands. This is a ch4 extension — Stage 2+.

---

## 5. Closed Surfaces Matrix

| Surface | v0 status | Notes |
|---------|-----------|-------|
| Real database connections | ❌ CLOSED | No DB adapter, no connection pooling |
| SQL string execution | ❌ CLOSED | Proof-local simulation only; no production SQL runner |
| SQL string generation (production API) | ❌ CLOSED | PlanSerializer is proof-local sim; not stable API |
| ORM (ActiveRecord-style) | ❌ PERMANENTLY CLOSED | Design philosophy incompatible |
| ActiveRecord compatibility | ❌ PERMANENTLY CLOSED | No compatibility claim |
| Lazy relation semantics | ❌ PERMANENTLY CLOSED | Implicit IO; violates pure-contract model |
| Global connection state | ❌ PERMANENTLY CLOSED | No global mutable state |
| Callbacks (before_/after_) | ❌ PERMANENTLY CLOSED | No side-effect hooks |
| Model persistence (save!/destroy) | ❌ CLOSED | Mutation requires `effect`; not in v0 |
| Schema migrations | ❌ CLOSED | No persistence runtime |
| Transactions | ❌ CLOSED | ESCAPE-class boundary; not designed |
| Joins | ❌ CLOSED until v1 | Deferred; N+1 risk; cross-source type complexity |
| Aggregates | ❌ CLOSED until v1 | Separate node kind needed |
| Write operations | ❌ CLOSED until v1 | Mutation capability not designed |
| Dynamic column access | ❌ CLOSED | OOF-MAP2 (Map[String,Any] banned) |
| Implicit `SELECT *` in typed path | ❌ CLOSED | Must use explicit Projection; include_all=true for prototype only |
| Stable public query API | ❌ CLOSED | Lab-only until grammar + execution path proven |
| Canon production file edits | ❌ CLOSED | Lab-only boundary |

---

## 6. Query Plan vs. TBackend (Store[T]) — Design Boundary

A common confusion to address explicitly:

| Aspect | `Store[T]` / TBackend | `QueryPlan` / StorageCapability |
|--------|----------------------|-------------------------------|
| Purpose | Temporal substrate — event append, replay, bitemporal reads | Relational intent — filter/project/order rows |
| PROP | PROP-008 | (new — no PROP yet; lab-only) |
| Stage | Stage 2 reserved | Stage 1 addressable (types exist today) |
| Key operation | `read as_of(Tt)`, `append`, `replay` | `select where filter order limit` |
| Fragment class | TEMPORAL | CORE (plan) / ESCAPE→STORAGE (exec, future) |
| Value type | `History[T]`, `BiHistory[T]` | `QueryPlan`, `QueryResult` |
| SQL generation | Not applicable | Proof-local sim only |
| Interaction | None — separate tracks | None — separate tracks |

**Do not anchor query planning to `Store[T]`.** They are orthogonal.

---

## 7. Envelope Comparison — QueryResult vs. Existing Envelopes

| Field | QueryResult | ValidationResult | HttpResult | ContractResult |
|-------|------------|-----------------|-----------|---------------|
| `kind` | rows/empty/denied/query_error/system_error | valid/invalid/unauthorized/system_error | success/client_error/server_error | ok/not_found/unauthorized/upstream_error/system_error |
| Domain | Data access | Form validation | HTTP transport | HTTP upstream |
| Denial kind | `denied` | `unauthorized` | `client_error` (403) | `unauthorized` |
| Denial-as-data | ✅ (design law) | ✅ (VENV-DENIED, 7th proof) | ✅ | ✅ |
| Metadata | `Map[String,String]` | `Map[String,String]` | `Map[String,String]` | — |

**Design continuity:** QueryResult follows the KDR convention (PROP-044-P1). Same
`kind`-discriminant shape. Same `Map[String,String]` metadata pattern. Same
denial-as-data invariant. This is the 4th domain for the cross-domain pattern.

---

## 8. Explicit Answers

| Question | Answer |
|----------|--------|
| Query/Arel-like pressure should open now? | **YES** — QueryPlan as typed Records; no new grammar needed; pressure from every data-touching application |
| ORM implementation too early? | **YES — and permanently incompatible** for the ORM-style patterns; the typed-plan approach is the right path |
| Query intent expressible as typed records today? | **YES** — QuerySource/Projection/FilterPredicate/OrderBy/QueryPlan/QueryResult are all named Records expressible in Stage 1 today |
| SQL/string generation proof-local only? | **YES** — PlanSerializer is Layer C simulation only; not production API |
| Execution mocked only for first implementation proof? | **YES** — v0 proof = plan-building (CORE, VM-executed) + routing (CORE) + mocked execution (Layer C simulation) |
| StorageCapability required before any execution path? | **YES** — `effect contract ExecuteQuery` requires `capability storage: IO.StorageCapability`; pure plan-building needs no capability |
| Joins deferred? | **YES** — deferred to v1; cross-source type complexity + N+1 risk |
| Aggregates deferred? | **YES** — deferred to v1; requires separate projection node kind |
| ActiveRecord compatibility permanently closed? | **YES — permanently closed**; design philosophy incompatible; not "deferred" — excluded |
| Database runtime permanently closed? | **YES** — no real DB connections in any lab version without explicit StorageCapability + STORAGE fragment class |
| Exact next route? | **LAB-QUERY-P2**: fixture (4-6 contracts: BuildSelectQuery, BuildFilteredQuery, QueryRouter + optional MetadataInspector/PlanInspector); proof runner (35-45 checks: compile, types, plan shape, mocked execution, denial-as-data, closed surface); 35-45/35-45 PASS gate |

---

## 9. Recommended P2 Proof Structure

### 9.1 Fixture: `query_plan/query_plan.ig`

Module: `Lab.Query.PlanBuilder`

Contracts (5 suggested):
1. `BuildSelectQuery` — full plan with source/projection/filters/order/limit
2. `BuildFilteredQuery` — simplified plan from single-field eq filter
3. `BuildProjection` — explicit field list, include_all=false
4. `QueryMetadataReader` — map_get(result.metadata, "source") + or_else chain
5. `QueryMapper` — raw kind+fields → QueryResult (mapper pattern, three-layer composition)

### 9.2 Proof sections (suggested, 35-45 checks)

| Section | Checks | Scope |
|---------|--------|-------|
| QPLAN-COMPILE | 4 | fixture compiles; 5 contracts; SIR; no type_errors |
| QPLAN-TYPES | 5 | QueryPlan/QueryResult/FilterPredicate typed fields |
| QPLAN-BUILD | 6 | plan construction; kind="select"; filter composition |
| QPLAN-DENIED | 4 | denial-as-data; StorageDenied route; no raise |
| QPLAN-MAP | 4 | Map[String,String] metadata chain in QueryResult |
| QPLAN-VM | 5 | VM execution: BuildSelectQuery/BuildFilteredQuery |
| QPLAN-ROUTE | 5 | QueryRouter: 5 kind paths (rows/empty/denied/query_error/system_error) |
| QPLAN-COMPARE | 4 | Comparison vs ValidationResult/ContractResult |
| QPLAN-CLOSED | 5 | No SQL, no DB, no ORM, no joins, no aggregates, no stable API |
| **Total** | **42** | |

### 9.3 Architecture (same three-layer model)

- **Layer A** — Production Ruby TypeChecker (type-level proof; read-only)
- **Layer B** — Lab Rust VM (behavioral; BuildSelectQuery/BuildFilteredQuery executed)
- **Layer C** — Proof-local `QueryExecutorSim` module (routing determinism; in-memory mock data)

```ruby
module QueryExecutorSim
  ROUTES = {
    'rows'        => { action: 'process',  summary: 'rows returned; iterate and transform' },
    'empty'       => { action: 'empty',    summary: 'zero rows; show empty state' },
    'denied'      => { action: 'deny',     summary: 'access denied; do not retry' },
    'query_error' => { action: 'invalid',  summary: 'malformed plan; fix query' },
    'system_error'=> { action: 'error',    summary: 'infrastructure failure; retry later' }
  }.freeze

  MOCK_TABLE = { 'users' => [...], 'posts' => [...] }

  def self.execute(plan) ... end         # returns QueryResult
  def self.denial_as_data?(kind) ... end # "denied" → true
end
```

---

## 10. Gap Packet

```
proof:          lab-query-arel-like-data-access-pressure-boundary / v0
status:         CLOSED — research complete; boundary defined
authority:      research + design / lab_only
date:           2026-06-09

capability_layer:
  plan_building:      CORE — pure contracts; no capability; types exist today
  plan_execution:     ESCAPE→STORAGE (future) — requires IO.StorageCapability
  storage_frag_class: OPEN — ch4 extension; Stage 2+; needed for exec path

query_plan_v0:
  types_defined:     YES — QuerySource/Projection/FilterPredicate/OrderBy/QueryPlan/QueryResult/StorageDenied
  grammar_needed:    NONE — all expressible as named Records + Collection[T]
  new_grammar:       NONE in v0
  new_ir_nodes:      NONE in v0
  new_vm_opcodes:    NONE in v0

closed_permanently:
  orm:                YES — permanently incompatible
  activerecord:       YES — permanently incompatible
  lazy_relations:     YES — permanently incompatible
  global_connection:  YES — permanently incompatible
  callbacks:          YES — permanently incompatible

closed_until_v1:
  joins:              YES — cross-source complexity; N+1 risk
  aggregates:         YES — new projection node kind needed
  write_ops:          YES — mutation capability not designed
  typed_row_T:        YES — variant grammar needed (Row[T] per query)
  or_not_predicates:  YES — variant grammar needed

next_authorized:
  immediate:          LAB-QUERY-P2 (fixture + proof runner; 35-45 checks)
  after_p2:           IO.StorageCapability design (follows PROP-035 model)
  future:             PROP-045 or similar (Query grammar; joins; aggregates)
```

---

## 11. Authority Statement

Lab-only — no canon claim, no stable surface, no framework compatibility.  
No production files modified. No grammar added. No VM modified.  
No PROP opened. No SQL connection established.

Evidence source: LAB-RESULT-ENVELOPE-P1/P2 (KDR pattern), PROP-043-P5
(Map[String,String] production), PROP-044-P1 (denial-as-data convention),
PROP-035 (capability grammar model), PROP-008/ch3 (TBackend boundary),
ch4 (fragment classification).
