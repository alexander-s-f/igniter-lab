module Lab.Query.PlanBuilder

-- LAB-QUERY-P2: QueryPlan pure builder proof.
-- Track: lab-query-plan-record-fixture-and-pure-builder-proof-v0
--
-- Proves that QueryPlan / QueryResult / QuerySource / Projection /
-- FilterPredicate / OrderBy can be represented and composed today as pure
-- typed Records with Map metadata. No DB. No ORM. No execution authority.
--
-- Core formula (from LAB-QUERY-P1):
--   Query v0 = typed intent AST (QueryPlan) + denial-as-data + Map metadata.
--   Query v0 != ORM, != database connection, != persistence runtime.
--
-- Types (7):
--   QuerySource, Projection, FilterPredicate, OrderBy,
--   QueryPlan, QueryResult, StorageDenied.
--
-- Contracts (6):
--   BuildQuerySource   -- proves QuerySource record construction
--   BuildSelectQuery   -- proves full flat QueryPlan construction
--   BuildFilteredQuery -- proves simplified eq-filter plan
--   QueryResultDenied  -- proves denial-as-data (QueryResult{kind:"denied"})
--   QueryMetadataReader -- proves map_get chain on QueryResult.metadata (C1)
--   QueryMapper        -- proves three-layer mapper pattern in query domain
--
-- Fragment class: all contracts are pure -> CORE. No IO. No StorageCapability.
-- Flattened QueryPlan: filter and order embedded as scalar fields (not as
--   Collection[FilterPredicate]) in v0 — Collection of user-defined records
--   deferred to v1.
-- Nested named Records in QueryPlan deferred to v1 for type resolution safety.
--
-- Authority: LAB-ONLY. No canon claim. No SQL. No DB. No framework compat.
-- No stable surface. No public API.
-- Depends: PROP-043-P5 (Map[String,String] + map_get + or_else),
--          LAB-VM-MAP-P1 (VM runtime for map_get/or_else).

-- ── Types ──────────────────────────────────────────────────────────────────────

-- Source identification. Capability-checked at execution time (v1+).
-- schema is optional context; empty string if unused.
type QuerySource {
  table:  String,
  schema: String
}

-- Projection — which fields to return.
-- fields is a description string in v0 (comma-separated or "*").
-- Collection[String] field list deferred to v1.
-- include_all: false (preferred) with named fields; true = all fields.
type Projection {
  fields:      String,
  include_all: Bool
}

-- Filter predicate — one comparison clause.
-- op closed set (doc-declared; not type-enforced in v0 — requires variant grammar):
--   "eq"      -> field = value
--   "neq"     -> field != value
--   "gt"      -> field > value
--   "gte"     -> field >= value
--   "lt"      -> field < value
--   "lte"     -> field <= value
--   "is_null" -> field IS NULL (value ignored)
-- value is String in v0; typed value slots deferred to v1 (requires variant).
-- Multiple predicates = AND composition; OR/NOT deferred to v1.
type FilterPredicate {
  field: String,
  op:    String,
  value: String
}

-- Ordering specification.
-- direction values: "asc" | "desc" (doc-declared; not type-enforced in v0).
type OrderBy {
  field:     String,
  direction: String
}

-- QueryPlan — flat intent AST for v0.
-- Embeds one filter predicate and one order clause as scalar fields.
-- Collection[FilterPredicate] deferred to v1.
-- kind closed set (doc-declared):
--   "select" -- standard projection + filter + order + limit query
-- metadata carries trace_id, requester, etc.
type QueryPlan {
  kind:          String,
  source_table:  String,
  source_schema: String,
  filter_field:  String,
  filter_op:     String,
  filter_value:  String,
  order_field:   String,
  order_dir:     String,
  limit:         Integer,
  metadata:      Map[String, String]
}

-- QueryResult — kind-discriminated result envelope (KDR convention, PROP-044-P1).
-- kind closed set (doc-declared):
--   "rows"         -- query executed; count rows matched; no error
--   "empty"        -- query executed; zero rows matched (not an error)
--   "denied"       -- StorageCapability denied; do not retry; denial-as-data
--   "query_error"  -- malformed plan; fix the query before retrying
--   "system_error" -- infrastructure failure; retry later
-- rows field (Collection[Map[String,String]]) deferred to v1.
-- count carries the row count scalar.
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

-- ── Contract 1: BuildQuerySource ─────────────────────────────────────────────
-- Proves QuerySource record construction. Source identity layer.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildQuerySource {
  input  table  : String
  input  schema : String
  compute source = { table: table, schema: schema }
  output  source : QuerySource
}

-- ── Contract 2: BuildSelectQuery ─────────────────────────────────────────────
-- Proves full flat QueryPlan construction from individual input parameters.
-- All intent components assembled into a single typed record.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildSelectQuery {
  input  table        : String
  input  filter_field : String
  input  filter_op    : String
  input  filter_value : String
  input  order_field  : String
  input  order_dir    : String
  input  limit        : Integer
  input  context      : Map[String, String]
  compute plan = {
    kind:          "select",
    source_table:  table,
    source_schema: "public",
    filter_field:  filter_field,
    filter_op:     filter_op,
    filter_value:  filter_value,
    order_field:   order_field,
    order_dir:     order_dir,
    limit:         limit,
    metadata:      context
  }
  output plan : QueryPlan
}

-- ── Contract 3: BuildFilteredQuery ───────────────────────────────────────────
-- Simplified eq-filter plan. Proves single-predicate plan construction.
-- Order is empty (order_field=""); limit is safe default (100).
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildFilteredQuery {
  input  table    : String
  input  field    : String
  input  value    : String
  input  metadata : Map[String, String]
  compute plan = {
    kind:          "select",
    source_table:  table,
    source_schema: "public",
    filter_field:  field,
    filter_op:     "eq",
    filter_value:  value,
    order_field:   "",
    order_dir:     "asc",
    limit:         100,
    metadata:      metadata
  }
  output plan : QueryPlan
}

-- ── Contract 4: QueryResultDenied ────────────────────────────────────────────
-- Denial-as-data in the query domain.
-- StorageCapability denial -> typed QueryResult{kind:"denied"}.
-- No exception raised. No raise. Consumer branches on kind.
-- Mirrors UnauthorizedSubmission (validation), unauthorized (Rack/ContractResult).
-- Fragment: CORE (pure; no capability; no IO).

pure contract QueryResultDenied {
  input  table    : String
  input  reason   : String
  input  metadata : Map[String, String]
  compute result  = { kind: "denied", count: 0, message: reason, metadata: metadata }
  output  result  : QueryResult
}

-- ── Contract 5: QueryMetadataReader ──────────────────────────────────────────
-- Proves map_get(result.metadata, key) -> Option[String] + or_else -> String
-- over a QueryResult named-record input in the query domain.
-- Same C1 chain as MetadataInspector (LAB-RESULT-ENVELOPE-P2), MetadataReader
-- (LAB-SIDEKIQ-P5), HeaderChain (LAB-VM-MAP-P1) — fourth domain.
-- Fragment: CORE (pure; no capability; no IO).

pure contract QueryMetadataReader {
  input  result     : QueryResult
  compute src_opt   = map_get(result.metadata, "source")
  compute source    = or_else(src_opt, "unknown_source")
  compute tbl_opt   = map_get(result.metadata, "table")
  compute table_ctx = or_else(tbl_opt, "unknown_table")
  output  source    : String
}

-- ── Contract 6: QueryMapper ───────────────────────────────────────────────────
-- Low-level -> domain mapper. Strips boundary detail; consumer sees QueryResult.
-- Proves three-layer composition pattern in the query domain:
--   boundary (raw kind + context Map) -> QueryMapper -> QueryResult -> consumer.
-- map_get(context, "message") + or_else: same chain as ValidationMapper,
-- DomainResponseMapperP9, HeadersAwareHandler — fourth domain confirmation.
-- Fragment: CORE (pure; no capability; no IO).

pure contract QueryMapper {
  input  raw_kind : String
  input  table    : String
  input  context  : Map[String, String]
  compute msg     = or_else(map_get(context, "message"), "query processed")
  compute result  = { kind: raw_kind, count: 0, message: msg, metadata: context }
  output  result  : QueryResult
}
