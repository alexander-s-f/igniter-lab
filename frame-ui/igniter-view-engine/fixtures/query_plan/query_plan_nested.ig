module Lab.Query.PlanBuilderV1

-- LAB-QUERY-P3: QueryPlan nested records + Collection[FilterPredicate] proof.
-- Track: lab-query-plan-nested-records-and-filter-collection-proof-v0
--
-- Upgrades QueryPlan from flat scalar fields (P2) to nested typed records:
--   source:     QuerySource               -- named nested record
--   projection: Projection                -- named nested record
--   filters:    Collection[FilterPredicate] -- collection of named records
--   order:      OrderBy                   -- named nested record
--   limit:      Integer
--   metadata:   Map[String, String]
--
-- Contracts (8):
--   BuildFilterPredicate  -- proves FilterPredicate record construction
--   BuildOrderBy          -- proves OrderBy record construction
--   BuildProjection       -- proves Projection record construction
--   BuildQuerySource      -- proves QuerySource record construction
--   BuildRichSelectPlan   -- proves nested QueryPlan with Collection[FilterPredicate]
--   PlanNestedFieldReader -- proves chained field access (plan.source.table)
--   PlanMetadataReader    -- proves map_get(plan.metadata, key) + or_else (C1 chain)
--   QueryResultDenied     -- proves denial-as-data in query domain
--
-- Core formula:
--   QueryPlan v1 = nested typed records + Collection[FilterPredicate] + Map metadata.
--   Query v1 != ORM, != database connection, != persistence runtime.
--   All contracts pure -> CORE. No IO. No StorageCapability.
--
-- Depends: LAB-QUERY-P1 (boundary), LAB-QUERY-P2 (P2 flat proof),
--          LAB-RECORD-VM-P3 (nested field access), LAB-VM-MAP-P1 (map_get/or_else),
--          PROP-043-P5 (Map[String,String] surface)
--
-- Authority: LAB-ONLY. No canon claim. No SQL. No DB. No framework compat.
-- No stable surface. No public API.

-- ── Types ──────────────────────────────────────────────────────────────────────

-- Source identification. Capability-checked at execution time (v1+).
-- schema is optional context; empty string if unused.
type QuerySource {
  table:  String,
  schema: String
}

-- Projection — which fields to return.
-- fields is a description string in v0/v1 (comma-separated or "*").
-- include_all: false preferred; true = all fields (subject to capability gate).
type Projection {
  fields:      String,
  include_all: Bool
}

-- Filter predicate — one comparison clause.
-- op closed set (doc-declared; not type-enforced — requires variant grammar):
--   "eq"      -> field = value
--   "neq"     -> field != value
--   "gt"      -> field > value
--   "gte"     -> field >= value
--   "lt"      -> field < value
--   "lte"     -> field <= value
--   "is_null" -> field IS NULL (value ignored)
type FilterPredicate {
  field: String,
  op:    String,
  value: String
}

-- Ordering specification.
-- direction: "asc" | "desc" (doc-declared; not type-enforced in v0/v1).
type OrderBy {
  field:     String,
  direction: String
}

-- QueryPlan v1 — richer intent AST with nested typed records.
-- Upgrades P2 flat shape by replacing scalar filter/order/source fields
-- with named nested records and Collection[FilterPredicate].
-- kind closed set (doc-declared):
--   "select" -- projection + filter collection + order + limit query
-- metadata carries trace_id, requester, request_id, etc.
type QueryPlan {
  kind:       String,
  source:     QuerySource,
  projection: Projection,
  filters:    Collection[FilterPredicate],
  order:      OrderBy,
  limit:      Integer,
  metadata:   Map[String, String]
}

-- QueryResult — kind-discriminated result envelope (KDR convention, PROP-044-P1).
-- kind closed set (doc-declared):
--   "rows"         -- query executed; count rows matched; no error
--   "empty"        -- query executed; zero rows matched (not an error)
--   "denied"       -- StorageCapability denied; do not retry; denial-as-data
--   "query_error"  -- malformed plan; fix the query before retrying
--   "system_error" -- infrastructure failure; retry later
type QueryResult {
  kind:     String,
  count:    Integer,
  message:  String,
  metadata: Map[String, String]
}

-- StorageDenied — explicit capability-denial record.
-- kind: always "denied". Consumer branches deterministically.
-- Denial is typed data. No exception. No raise.
type StorageDenied {
  table:  String,
  op:     String,
  reason: String,
  kind:   String
}

-- ── Contract 1: BuildFilterPredicate ─────────────────────────────────────────
-- Proves FilterPredicate record construction.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildFilterPredicate {
  input  field : String
  input  op    : String
  input  value : String
  compute pred = { field: field, op: op, value: value }
  output pred : FilterPredicate
}

-- ── Contract 2: BuildOrderBy ──────────────────────────────────────────────────
-- Proves OrderBy record construction.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildOrderBy {
  input  field     : String
  input  direction : String
  compute order = { field: field, direction: direction }
  output order : OrderBy
}

-- ── Contract 3: BuildProjection ───────────────────────────────────────────────
-- Proves Projection record construction.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildProjection {
  input  fields      : String
  input  include_all : Bool
  compute proj = { fields: fields, include_all: include_all }
  output proj : Projection
}

-- ── Contract 4: BuildQuerySource ─────────────────────────────────────────────
-- Proves QuerySource record construction. Source identity layer.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildQuerySource {
  input  table  : String
  input  schema : String
  compute source = { table: table, schema: schema }
  output source : QuerySource
}

-- ── Contract 5: BuildRichSelectPlan ──────────────────────────────────────────
-- Proves nested QueryPlan construction with:
--   - nested QuerySource, Projection, OrderBy records
--   - Collection[FilterPredicate]: passed as input (not built inline)
--   - Map[String,String] metadata passthrough
--
-- Design note: Collection[FilterPredicate] is accepted as an INPUT by both the
-- Ruby typechecker (Layer A) and the Rust compiler (Layer B). Inline array
-- literal construction ([filter1, filter2]) is accepted by Layer A but blocked
-- by the Rust typechecker (array_literal not supported in v0 Rust typecheck
-- pass). Array literal inference is proved separately via inline Layer A test
-- in the proof runner. This is the P3 VM-compilable form.
--
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildRichSelectPlan {
  input  source     : QuerySource
  input  projection : Projection
  input  filters    : Collection[FilterPredicate]
  input  order      : OrderBy
  input  limit      : Integer
  input  metadata   : Map[String, String]
  compute plan = {
    kind:       "select",
    source:     source,
    projection: projection,
    filters:    filters,
    order:      order,
    limit:      limit,
    metadata:   metadata
  }
  output plan : QueryPlan
}

-- ── Contract 6: PlanNestedFieldReader ────────────────────────────────────────
-- Proves chained field access through nested records in QueryPlan.
-- plan.source.table and plan.order.direction require two OP_GET_FIELD hops.
-- Relies on LAB-RECORD-VM-P3 compiler fix (recursive compile_expr in field_access).
-- Fragment: CORE (pure; no capability; no IO).

pure contract PlanNestedFieldReader {
  input  plan   : QueryPlan
  compute tbl   = plan.source.table
  compute dir   = plan.order.direction
  output tbl : String
}

-- ── Contract 7: PlanMetadataReader ───────────────────────────────────────────
-- Proves map_get(plan.metadata, key) -> Option[String] + or_else -> String
-- over a richer QueryPlan with nested records. Same C1 chain as LAB-QUERY-P2
-- but input is the nested QueryPlan (v1 shape), not the flat P2 shape.
-- Fragment: CORE (pure; no capability; no IO).

pure contract PlanMetadataReader {
  input  plan      : QueryPlan
  compute src_opt  = map_get(plan.metadata, "source")
  compute source   = or_else(src_opt, "unknown_source")
  compute tbl_opt  = map_get(plan.metadata, "table")
  compute table    = or_else(tbl_opt, "unknown_table")
  output  source   : String
}

-- ── Contract 8: QueryResultDenied ────────────────────────────────────────────
-- Denial-as-data in the query domain.
-- StorageCapability denial -> typed QueryResult{kind:"denied"}.
-- No exception raised. No raise. Consumer branches on kind.
-- Fragment: CORE (pure; no capability; no IO).

pure contract QueryResultDenied {
  input  table    : String
  input  reason   : String
  input  metadata : Map[String, String]
  compute result  = { kind: "denied", count: 0, message: reason, metadata: metadata }
  output  result  : QueryResult
}
