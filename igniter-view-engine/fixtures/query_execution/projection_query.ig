module Lab.Query.ProjectionSemantics

-- LAB-QUERY-PROJECTION-P1: Projection and include_all row-shaping semantics over mocked rows.
-- Track: lab-query-projection-and-include-all-over-mocked-rows-v0
-- Route: LAB PROOF / QUERY SEMANTICS / NO DB
--
-- Extends the query pipeline (LAB-EXECUTE-QUERY-P2, LAB-QUERY-MULTI-ORDER-P1) with
-- projection semantics: given a filtered/ordered/limited row set, what does
-- Projection do to each row?
--
-- Core formula:
--   Projection v0  =  mocked rows  +  Projection{fields,include_all}
--                  →  shaped rows (field-subset or full row) + QueryResult
--   Projection v0  ≠  SQL SELECT column list  ≠  DB schema introspection
--   Projection v0  ≠  typed Row[T]  ≠  Collection[String] field list (deferred)
--   ProjectionSim  =  PROOF-LOCAL ONLY  ≠  production projection evaluation runtime
--
-- v0 projection semantics (Layer C):
--   include_all == true  → return all row fields unchanged (full passthrough)
--     subject to capability policy: allow_include_all==false → query_error before projection
--   include_all == false → use fields as comma-separated explicit field list
--     parse: split(","), strip whitespace, reject empty tokens
--     empty after parsing      → query_error (accidental empty projection = malformed plan)
--     field absent in row      → query_error (fail-closed)
--     duplicate field requests → de-duplicate preserving first occurrence (not query_error)
--     field order              → projected row follows request order (v0 best-effort;
--                                 row keys are unordered in Ruby Hash/JSON objects)
--   projection does not change row count
--   projection applied AFTER filter → order → limit
--   query_error ≠ denied throughout pipeline
--
-- Pipeline position (integrated):
--   G1/G2/G3 denial → G4 clamp → G5 include_all policy → G6 filter+order+limit → projection
--   G5: include_all==true && allow_include_all==false → query_error (NOT denied)
--       This gate fires before projection is evaluated
--
-- Contracts (7 — all pure CORE):
--   BuildIncludeAllPlan          — QueryPlanProjection with include_all=true, empty order
--   BuildFieldsProjectionPlan    — QueryPlanProjection with include_all=false, "name,status"; 2-key order
--   BuildSingleFieldPlan         — QueryPlanProjection with include_all=false, "name"; no order
--   BuildProjectionRowsResult    — QueryResult{kind:"rows"}
--   BuildProjectionEmptyResult   — QueryResult{kind:"empty"}
--   BuildProjectionQueryErrorResult — QueryResult{kind:"query_error"}
--   ProjectionMetadataReader     — map_get + or_else on QueryResult.metadata
--
-- Three-layer proof:
--   Layer A — Ruby TypeChecker: 7 contracts accepted; Projection{fields,include_all} in type_env;
--             QueryPlanProjection.projection: Projection.
--   Layer B — Rust compiler + VM: fixture compiles; Rust SIR:
--             BuildFieldsProjectionPlan.order_list = Collection[OrderBy] from record-field context
--             (LAB-TC-ARRAY-P2 mechanism — 7th confirmation across fixtures);
--             all 7 contracts VM-executable.
--   Layer C — Proof-local ProjectionSim: include_all passthrough; comma-split field list;
--             missing field → query_error; duplicate de-duplication; row count preserved;
--             projection AFTER filter/order/limit in ProjectionQuerySim.
--
-- Note on types: QueryPlanProjection is a new type with projection: Projection explicitly typed.
-- It does not mutate the existing QueryPlan or QueryPlanMultiOrder from prior fixtures.
-- The fields: String encoding is v0 primitive; Collection[String] deferred to a future card.
--
-- TypeChecker boundary (B9): nested record literals inside outer record literals do not
-- propagate inner field type context in the Ruby TypeChecker. The inner literal
-- { fields: "...", include_all: false } is not checked against Projection when embedded
-- directly in the plan record literal. Workaround: pass projection as an input to contracts
-- that need it (same pattern as execute_query_integrated.ig). Specific projection shapes
-- (include_all=true/false, field lists) are verified at Layer B (VM) and Layer C (ProjectionSim).
--
-- Authority: LAB-ONLY. No canon claim. No real db. No sql. No ORM.
-- No stable surface. No public API. No StorageCapability authority execution.

-- ── Types ──────────────────────────────────────────────────────────────────────

type Projection {
  fields:      String,
  include_all: Bool
}

type QuerySource {
  table:  String,
  schema: String
}

type FilterPredicate {
  field: String,
  op:    String,
  value: String
}

type OrderBy {
  field:     String,
  direction: String
}

-- QueryPlanProjection: pipeline plan with explicit Projection shape.
-- Differs from QueryPlan (single OrderBy) and QueryPlanMultiOrder (Collection[OrderBy])
-- only in annotation intent; uses Collection[OrderBy] for full pipeline compatibility.
-- Does not mutate existing QueryPlan or QueryPlanMultiOrder from prior fixtures.
type QueryPlanProjection {
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

-- ── Contract 1: BuildIncludeAllPlan ──────────────────────────────────────────
-- Proves QueryPlanProjection with include_all=true.
-- include_all=true semantics: return all row fields unchanged (full passthrough).
-- Subject to capability policy: allow_include_all==false → query_error before projection.
-- fields="" because include_all=true makes the fields string irrelevant.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildIncludeAllPlan {
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
  output plan : QueryPlanProjection
}

-- ── Contract 2: BuildFieldsProjectionPlan ────────────────────────────────────
-- Proves QueryPlanProjection with include_all=false and explicit comma-separated fields.
-- v0 fields encoding: comma-separated string, e.g. "name,status".
-- Two-key order demonstrates Collection[OrderBy] from record-field context
-- (LAB-TC-ARRAY-P2 mechanism — 7th confirmation across fixtures).
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildFieldsProjectionPlan {
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
  output plan : QueryPlanProjection
}

-- ── Contract 3: BuildSingleFieldPlan ─────────────────────────────────────────
-- Proves QueryPlanProjection with include_all=false and a single field ("name").
-- Single-field projection: projected rows have exactly one field.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildSingleFieldPlan {
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
  output plan : QueryPlanProjection
}

-- ── Contract 4: BuildProjectionRowsResult ────────────────────────────────────
-- Proves QueryResult{kind:"rows"} for successfully projected rows.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildProjectionRowsResult {
  input  row_count : Integer
  input  metadata  : Map[String, String]
  compute result = { kind: "rows", count: row_count, message: "", metadata: metadata }
  output result : QueryResult
}

-- ── Contract 5: BuildProjectionEmptyResult ───────────────────────────────────
-- Proves QueryResult{kind:"empty"} for zero rows after projection pipeline.
-- Sources: limit==0, empty filtered result, projection applied to empty row set.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildProjectionEmptyResult {
  input  metadata : Map[String, String]
  compute result = { kind: "empty", count: 0, message: "", metadata: metadata }
  output result : QueryResult
}

-- ── Contract 6: BuildProjectionQueryErrorResult ──────────────────────────────
-- Proves QueryResult{kind:"query_error"} — malformed projection or policy violation.
-- Sources:
--   - Empty fields string with include_all==false
--   - Requested field absent in row
--   - include_all==true with allow_include_all==false (G5 gate in integrated pipeline)
-- "query_error" ≠ "denied": malformed plan (fix before retry), not access denial.
-- Note: 'reason' used as input name ('message' is a Ruby parser keyword).
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildProjectionQueryErrorResult {
  input  reason   : String
  input  metadata : Map[String, String]
  compute result = { kind: "query_error", count: 0, message: reason, metadata: metadata }
  output result : QueryResult
}

-- ── Contract 7: ProjectionMetadataReader ─────────────────────────────────────
-- Proves map_get(result.metadata, key) + or_else on projection QueryResult.
-- Fragment: CORE (pure; no capability; no IO).

pure contract ProjectionMetadataReader {
  input  result    : QueryResult
  input  query_key : String
  compute meta_opt = map_get(result.metadata, query_key)
  compute meta_str = or_else(meta_opt, "not-found")
  output meta_str : String
}
