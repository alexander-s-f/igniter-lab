module Lab.Query.MultiColumnOrder

-- LAB-QUERY-MULTI-ORDER-P1: Multi-column order semantics over mocked in-memory rows.
-- Track: lab-query-multi-column-order-over-mocked-rows-v0
-- Route: LAB PROOF / QUERY SEMANTICS / NO DB
--
-- Extends LAB-QUERY-ORDER-LIMIT-P1 single-key ordering to Collection[OrderBy]:
-- proves deterministic stable multi-column ordering over mocked rows.
--
-- Core formula:
--   MultiOrder v0  =  mocked rows  +  Collection[OrderBy]  +  limit
--                  →  deterministic stable multi-column ordered rows + QueryResult
--   MultiOrder v0  ≠  sql order-by clause  ≠  DB runtime  ≠  ORM  ≠  index-backed sorting
--   MultiOrder v0  ≠  StorageCapability row-limit gate
--   MultiOrderSim  =  PROOF-LOCAL ONLY  ≠  production multi-order evaluation runtime
--
-- v0 multi-order semantics (Layer C):
--   Empty Collection[OrderBy]      → preserve input order (no-op)
--   Each entry: field + direction (asc / desc)
--   Empty direction in an entry    → query_error (in single-order P1, empty direction meant
--                                    "no sort"; in multi-order each entry is an explicit step —
--                                    empty direction is ambiguous, rejected as malformed)
--   Unknown direction              → query_error (NOT denied)
--   Missing order field in row     → query_error (NOT denied)
--   Sort keys applied in priority order: first = primary, second = secondary, etc.
--   All comparisons: lexicographic String in v0
--   Stable sort: equal keys preserve input order
--   Limit applied AFTER all ordering
--   query_error ≠ denied throughout pipeline
--
-- Contracts (7 — all pure CORE):
--   BuildMultiOrderPlan        — QueryPlanMultiOrder with 2-key Collection[OrderBy]
--   BuildEmptyOrderPlan        — QueryPlanMultiOrder with empty Collection[OrderBy]
--   BuildThreeKeyOrderPlan     — QueryPlanMultiOrder with 3-key Collection[OrderBy]
--   BuildMultiOrderRowsResult  — QueryResult{kind:"rows"}
--   BuildMultiOrderEmptyResult — QueryResult{kind:"empty"}
--   BuildMultiOrderQueryErrorResult — QueryResult{kind:"query_error"}
--   MultiOrderMetadataReader   — map_get + or_else on QueryResult.metadata
--
-- Three-layer proof:
--   Layer A — Ruby TypeChecker: all 7 contracts accepted; Collection[OrderBy] in type_env;
--             QueryPlanMultiOrder.order: Collection[OrderBy].
--   Layer B — Rust compiler + VM: fixture compiles; Rust SIR:
--             BuildMultiOrderPlan.order_list = Collection[OrderBy] from record-field context
--             (LAB-TC-ARRAY-P2 mechanism — 6th confirmation across fixtures);
--             all 7 contracts VM-executable.
--   Layer C — Proof-local MultiOrderSim: composite stable sort; per-key asc/desc;
--             empty list → preserve input order; multi-key tiebreaker resolution;
--             empty direction in entry → query_error (explicit step, must have direction).
--
-- Note on types: QueryPlanMultiOrder is a new type with order: Collection[OrderBy].
-- It does not mutate the existing QueryPlan type used in earlier fixtures.
--
-- Authority: LAB-ONLY. No canon claim. No real db. No sql. No ORM.
-- No stable surface. No public API. No StorageCapability authority execution.

-- ── Types ──────────────────────────────────────────────────────────────────────

type OrderBy {
  field:     String,
  direction: String
}

type QuerySource {
  table:  String,
  schema: String
}

type Projection {
  fields:      String,
  include_all: Bool
}

type FilterPredicate {
  field: String,
  op:    String,
  value: String
}

-- QueryPlanMultiOrder: QueryPlan variant with order: Collection[OrderBy].
-- Does not mutate the existing single-OrderBy QueryPlan from prior fixtures.
type QueryPlanMultiOrder {
  kind:       String,
  source:     QuerySource,
  projection: Projection,
  filters:    Collection[FilterPredicate],
  order:      Collection[OrderBy],
  limit:      Integer,
  metadata:   Map[String, String]
}

type QueryResult {
  kind:     String,
  count:    Integer,
  message:  String,
  metadata: Map[String, String]
}

-- ── Contract 1: BuildMultiOrderPlan ──────────────────────────────────────────
-- Proves QueryPlanMultiOrder with a 2-key inline Collection[OrderBy].
-- LAB-TC-ARRAY-P2 mechanism: order_list array typed Collection[OrderBy] from
-- QueryPlanMultiOrder.order record-field context (6th confirmation across fixtures).
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildMultiOrderPlan {
  input  source     : QuerySource
  input  projection : Projection
  input  filters    : Collection[FilterPredicate]
  input  limit      : Integer
  input  metadata   : Map[String, String]
  compute order_list = [
    { field: "dept", direction: "asc" },
    { field: "name", direction: "asc" }
  ]
  compute plan = {
    kind:       "select",
    source:     source,
    projection: projection,
    filters:    filters,
    order:      order_list,
    limit:      limit,
    metadata:   metadata
  }
  output plan : QueryPlanMultiOrder
}

-- ── Contract 2: BuildEmptyOrderPlan ──────────────────────────────────────────
-- Proves QueryPlanMultiOrder with an empty Collection[OrderBy].
-- Empty order list preserves input order (no-op semantics).
-- Empty array typed Collection[OrderBy] from record-field context
-- (LAB-TC-ARRAY-P1 empty-array-context + LAB-TC-ARRAY-P2 field-context combined).
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildEmptyOrderPlan {
  input  source     : QuerySource
  input  projection : Projection
  input  filters    : Collection[FilterPredicate]
  input  limit      : Integer
  input  metadata   : Map[String, String]
  compute order_list = []
  compute plan = {
    kind:       "select",
    source:     source,
    projection: projection,
    filters:    filters,
    order:      order_list,
    limit:      limit,
    metadata:   metadata
  }
  output plan : QueryPlanMultiOrder
}

-- ── Contract 3: BuildThreeKeyOrderPlan ───────────────────────────────────────
-- Proves QueryPlanMultiOrder with a 3-key inline Collection[OrderBy].
-- Demonstrates primary / secondary / tertiary sort key priority.
-- Mixed directions: asc / desc / asc.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildThreeKeyOrderPlan {
  input  source     : QuerySource
  input  projection : Projection
  input  filters    : Collection[FilterPredicate]
  input  limit      : Integer
  input  metadata   : Map[String, String]
  compute order_list = [
    { field: "dept",  direction: "asc"  },
    { field: "level", direction: "desc" },
    { field: "name",  direction: "asc"  }
  ]
  compute plan = {
    kind:       "select",
    source:     source,
    projection: projection,
    filters:    filters,
    order:      order_list,
    limit:      limit,
    metadata:   metadata
  }
  output plan : QueryPlanMultiOrder
}

-- ── Contract 4: BuildMultiOrderRowsResult ────────────────────────────────────
-- Proves QueryResult{kind:"rows"} for ordered rows returned.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildMultiOrderRowsResult {
  input  row_count : Integer
  input  metadata  : Map[String, String]
  compute result = { kind: "rows", count: row_count, message: "", metadata: metadata }
  output result : QueryResult
}

-- ── Contract 5: BuildMultiOrderEmptyResult ───────────────────────────────────
-- Proves QueryResult{kind:"empty"} for zero rows.
-- Sources: limit==0, or empty ordered/filtered result.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildMultiOrderEmptyResult {
  input  metadata : Map[String, String]
  compute result = { kind: "empty", count: 0, message: "", metadata: metadata }
  output result : QueryResult
}

-- ── Contract 6: BuildMultiOrderQueryErrorResult ──────────────────────────────
-- Proves QueryResult{kind:"query_error"} — malformed order specification.
-- Sources: unknown direction, missing order field, empty direction in entry.
-- "query_error" ≠ "denied": malformed plan (fix before retry), not access denial.
-- Note: 'reason' used as input name ('message' is a Ruby parser keyword).
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildMultiOrderQueryErrorResult {
  input  reason   : String
  input  metadata : Map[String, String]
  compute result = { kind: "query_error", count: 0, message: reason, metadata: metadata }
  output result : QueryResult
}

-- ── Contract 7: MultiOrderMetadataReader ─────────────────────────────────────
-- Proves map_get(result.metadata, key) + or_else on multi-order QueryResult.
-- Fragment: CORE (pure; no capability; no IO).

pure contract MultiOrderMetadataReader {
  input  result    : QueryResult
  input  query_key : String
  compute meta_opt = map_get(result.metadata, query_key)
  compute meta_str = or_else(meta_opt, "not-found")
  output meta_str : String
}
