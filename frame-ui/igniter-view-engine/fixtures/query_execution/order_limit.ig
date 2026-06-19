module Lab.QueryOrderLimit.MockedRowOrderLimit

-- LAB-QUERY-ORDER-LIMIT-P1: Order and limit semantics over mocked in-memory rows.
-- Track: lab-query-order-and-limit-semantics-over-mocked-rows-v0
--
-- Proves order and limit semantics as pure data transformation. No SQL, no DB, no ORM.
-- QueryPlan.order and QueryPlan.limit are no longer just shape — they have v0 meaning.
--
-- OrderLimit v0 = mocked rows + OrderBy + limit → ordered/limited rows + QueryResult
-- OrderLimit v0 ≠ sql order-by clause ≠ DB runtime ≠ ORM ≠ index-backed sorting
-- OrderLimit v0 ≠ StorageCapability row-limit gate
--
-- v0 order semantics:
--   direction = "asc"  → ascending lexicographic order
--   direction = "desc" → descending lexicographic order
--   unknown direction  → query_error (NOT denied)
--   missing order field in row → query_error (documented v0 rule: fail-closed)
--   equal keys → preserve input order (stable sort)
--   empty order field string → preserve input order (no ordering applied)
--
-- v0 limit semantics:
--   limit > 0  → return at most limit rows (applied after ordering)
--   limit == 0 → kind:"empty", count:0
--   limit < 0  → kind:"query_error" (NOT denied)
--   QueryPlan.limit ≠ StorageCapability row-limit gate (orthogonal)
--
-- Contracts (7):
--   BuildOrderAsc               — OrderBy { direction:"asc" } shape
--   BuildOrderDesc              — OrderBy { direction:"desc" } shape
--   BuildQueryPlanOrderLimit    — QueryPlan with order + limit + filter array
--   OrderLimitRows              — QueryResult{kind:"rows", count:N}
--   OrderLimitEmpty             — QueryResult{kind:"empty", count:0} — limit==0
--   OrderLimitQueryError        — QueryResult{kind:"query_error"} — bad direction / negative limit
--   OrderLimitMetadataReader    — map_get(result.metadata, key) + or_else
--
-- Three-layer proof:
--   Layer A — Ruby TypeChecker: 7 contracts accepted; OrderBy / QueryPlan shapes.
--   Layer B — Rust compiler + VM: fixture compiles; Rust SIR: BuildQueryPlanOrderLimit
--             order typed OrderBy; filters typed Collection[FilterPredicate] from field context.
--   Layer C — Proof-local OrderLimitSim: asc/desc sort; stable sort; limit slicing;
--             edge cases (limit==0, limit<0, unknown direction, missing field).
--
-- Authority: LAB-ONLY. No canon claim. No real DB. No SQL. No ORM.
-- No stable surface. No public API. No StorageCapability execution authority.

-- ── Types ──────────────────────────────────────────────────────────────────────

type FilterPredicate {
  field: String,
  op:    String,
  value: String
}

type QuerySource {
  table:  String,
  schema: String
}

type Projection {
  fields:      String,
  include_all: Bool
}

type OrderBy {
  field:     String,
  direction: String
}

type QueryPlan {
  kind:       String,
  source:     QuerySource,
  projection: Projection,
  filters:    Collection[FilterPredicate],
  order:      OrderBy,
  limit:      Integer,
  metadata:   Map[String, String]
}

type QueryResult {
  kind:     String,
  count:    Integer,
  message:  String,
  metadata: Map[String, String]
}

-- ── Contract 1: BuildOrderAsc ─────────────────────────────────────────────────
-- Proves OrderBy { direction:"asc" } shape.
-- "asc" = ascending lexicographic order over the named field.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildOrderAsc {
  input  field : String
  compute order = { field: field, direction: "asc" }
  output order : OrderBy
}

-- ── Contract 2: BuildOrderDesc ────────────────────────────────────────────────
-- Proves OrderBy { direction:"desc" } shape.
-- "desc" = descending lexicographic order over the named field.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildOrderDesc {
  input  field : String
  compute order = { field: field, direction: "desc" }
  output order : OrderBy
}

-- ── Contract 3: BuildQueryPlanOrderLimit ──────────────────────────────────────
-- Proves QueryPlan construction with order + limit + filter array.
-- `filters` types as Collection[FilterPredicate] from record-field context (LAB-TC-ARRAY-P2).
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildQueryPlanOrderLimit {
  input  source     : QuerySource
  input  projection : Projection
  input  order      : OrderBy
  input  limit      : Integer
  input  metadata   : Map[String, String]
  compute filters = [
    { field: "status", op: "eq", value: "active" }
  ]
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

-- ── Contract 4: OrderLimitRows ────────────────────────────────────────────────
-- Proves QueryResult{kind:"rows"} when ordering + limiting produces rows.
-- count = number of rows returned after ordering and limit slicing.
-- Fragment: CORE (pure; no capability; no IO).

pure contract OrderLimitRows {
  input  count    : Integer
  input  metadata : Map[String, String]
  compute result = { kind: "rows", count: count, message: "", metadata: metadata }
  output result : QueryResult
}

-- ── Contract 5: OrderLimitEmpty ───────────────────────────────────────────────
-- Proves QueryResult{kind:"empty"} when limit==0 or no rows remain after limit.
-- "empty" ≠ "denied": evaluation succeeded; limit produced zero rows.
-- Fragment: CORE (pure; no capability; no IO).

pure contract OrderLimitEmpty {
  input  metadata : Map[String, String]
  compute result = { kind: "empty", count: 0, message: "limit zero", metadata: metadata }
  output result : QueryResult
}

-- ── Contract 6: OrderLimitQueryError ─────────────────────────────────────────
-- Proves QueryResult{kind:"query_error"} for unknown direction or negative limit.
-- "query_error" ≠ "denied": malformed plan field (fix before retry), not access denial.
-- Unknown direction (not "asc"/"desc") → query_error.
-- Negative limit → query_error.
-- Consumer action: inspect order/limit fields, correct value, retry.
-- Fragment: CORE (pure; no capability; no IO).

pure contract OrderLimitQueryError {
  input  reason   : String
  input  metadata : Map[String, String]
  compute result = { kind: "query_error", count: 0, message: reason, metadata: metadata }
  output result : QueryResult
}

-- ── Contract 7: OrderLimitMetadataReader ──────────────────────────────────────
-- Proves map_get(result.metadata, key) + or_else on an OrderLimit QueryResult.
-- Confirms metadata access pattern works on order/limit outputs.
-- Fragment: CORE (pure; no capability; no IO).

pure contract OrderLimitMetadataReader {
  input  result    : QueryResult
  input  query_key : String
  compute meta_opt  = map_get(result.metadata, query_key)
  compute meta_str  = or_else(meta_opt, "not-found")
  output meta_str : String
}
