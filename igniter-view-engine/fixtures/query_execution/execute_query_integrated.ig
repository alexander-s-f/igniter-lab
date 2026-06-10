module Lab.ExecuteQuery.IntegratedMockedExecution

-- LAB-EXECUTE-QUERY-P2: Integrated mocked query execution.
-- Track: lab-execute-query-integrated-gates-filter-order-limit-receipt-v0
--
-- First complete mocked ExecuteQuery pipeline:
--   StorageCapability gates + filter evaluation + order/limit semantics + QueryExecutionReceipt
--
-- Core formula:
--   ExecuteQueryMock v0 = QueryPlan + StorageCapability-shaped policy + mocked rows
--                       → gated / filtered / ordered / limited QueryResult + QueryExecutionReceipt
--   ExecuteQueryMock v0 ≠ sql execution ≠ db runtime ≠ ORM ≠ production StorageCapability execution
--   ExecuteQueryMock v0 ≠ query optimizer ≠ index-backed sorting
--
-- Pipeline order (Layer C IntegratedQuerySim):
--   1. Capability gates (G1–G6)
--      G1: source allowlist        → denied if not in allowed_sources
--      G2: op allowlist            → denied if "read" not in allowed_ops
--      G3: read_allowed master     → denied if false
--      G4: row-limit clamp         → effective_limit = min(plan.limit, cap.row_limit); NOT denial
--      G5: include_all restricted  → query_error (not denied)
--      G6: evaluate (filter → order → limit)
--   2. Filter evaluation (Layer C): AND-only; eq/neq/contains/prefix; unknown op → query_error
--   3. Order semantics (Layer C): asc/desc lexicographic; unknown direction → query_error
--   4. Limit semantics (Layer C): applied after filter+order; limit==0 → empty; limit<0 → query_error
--   5. Result + receipt
--
-- Contracts (8 — all pure CORE):
--   BuildIntegratedPlan            — QueryPlan with inline filter array (LAB-TC-ARRAY-P2 pattern)
--   BuildIntegratedCapability      — StorageCapability schema-shaped record (plain Record, NOT io authority)
--   BuildIntegratedRowsResult      — QueryResult{kind:"rows"} — rows returned
--   BuildIntegratedEmptyResult     — QueryResult{kind:"empty"} — no rows
--   BuildIntegratedDeniedResult    — QueryResult{kind:"denied"} — gate denial (≠ query_error)
--   BuildIntegratedQueryErrorResult — QueryResult{kind:"query_error"} — malformed plan field
--   BuildIntegratedReceipt         — QueryExecutionReceipt (15 fields) — allowed execution
--   IntegratedMetadataReader       — map_get(result.metadata, key) + or_else
--
-- Three-layer proof:
--   Layer A — Ruby TypeChecker: all 8 contracts accepted; OrderBy / QueryPlan / StorageCapability shapes.
--   Layer B — Rust compiler + VM: fixture compiles; Rust SIR:
--             BuildIntegratedPlan.filters = Collection[FilterPredicate] from record-field context
--             (LAB-TC-ARRAY-P2 mechanism — 5th confirmation); VM executes all 8 contracts.
--   Layer C — Proof-local IntegratedQuerySim:
--             G1–G6 gate sequence; filter evaluation; asc/desc lexicographic sort;
--             stable sort; limit-after-order; limit==0 → empty; limit<0 → query_error;
--             all gate failures short-circuit before filter/order/limit evaluation.
--
-- Denial-as-data invariant:
--   G1/G2/G3 → kind:"denied"; G5 → kind:"query_error" (NOT denied); G6-filter/order → kind:"query_error"
--   All failures return typed QueryResult — no exceptions raised.
--
-- Authority: LAB-ONLY. No canon claim. No real db. No sql. No ORM.
-- No stable surface. No public API. No StorageCapability authority execution.

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

-- StorageCapability: schema-shaped Record for passing gate parameters.
-- 8 fields — models the IO capability gate parameters.
-- This is NOT the IO capability authority reference. It is a plain named Record.
type StorageCapability {
  cap_id:            String,
  allowed_sources:   Collection[String],
  allowed_ops:       Collection[String],
  row_limit:         Integer,
  allow_include_all: Bool,
  read_allowed:      Bool,
  write_allowed:     Bool,
  deny_reason:       String
}

type QueryExecutionReceipt {
  cap_id:            String,
  plan_kind:         String,
  source_table:      String,
  op_requested:      String,
  cap_checked:       Bool,
  cap_granted:       Bool,
  denial_gate:       String,
  deny_reason:       String,
  plan_limit:        Integer,
  row_limit_cap:     Integer,
  effective_limit:   Integer,
  row_limit_clamped: Bool,
  rows_returned:     Integer,
  result_kind:       String,
  metadata:          Map[String, String]
}

-- ── Contract 1: BuildIntegratedPlan ──────────────────────────────────────────
-- Proves full QueryPlan with inline filter array (LAB-TC-ARRAY-P2 mechanism).
-- `filters` compute array typed Collection[FilterPredicate] from QueryPlan.filters
-- record-field context — 5th confirmation of the record-field-context mechanism.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildIntegratedPlan {
  input  source     : QuerySource
  input  projection : Projection
  input  order      : OrderBy
  input  limit      : Integer
  input  metadata   : Map[String, String]
  compute filters = [
    { field: "status", op: "eq", value: "active" },
    { field: "role",   op: "eq", value: "admin"  }
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

-- ── Contract 2: BuildIntegratedCapability ────────────────────────────────────
-- Proves StorageCapability record shape.
-- allowed_sources and allowed_ops passed as Collection[String] inputs.
-- Row-limit clamp semantics (G4) proven at Layer C via IntegratedQuerySim.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildIntegratedCapability {
  input  cap_id:            String
  input  allowed_sources:   Collection[String]
  input  allowed_ops:       Collection[String]
  input  row_limit:         Integer
  input  allow_include_all: Bool
  input  read_allowed:      Bool
  input  write_allowed:     Bool
  input  deny_reason:       String
  compute cap = {
    cap_id:            cap_id,
    allowed_sources:   allowed_sources,
    allowed_ops:       allowed_ops,
    row_limit:         row_limit,
    allow_include_all: allow_include_all,
    read_allowed:      read_allowed,
    write_allowed:     write_allowed,
    deny_reason:       deny_reason
  }
  output cap : StorageCapability
}

-- ── Contract 3: BuildIntegratedRowsResult ────────────────────────────────────
-- Proves QueryResult{kind:"rows"} — gates passed; filter+order+limit produced rows.
-- count = number of rows returned after the full pipeline.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildIntegratedRowsResult {
  input  row_count : Integer
  input  metadata  : Map[String, String]
  compute result = { kind: "rows", count: row_count, message: "", metadata: metadata }
  output result : QueryResult
}

-- ── Contract 4: BuildIntegratedEmptyResult ───────────────────────────────────
-- Proves QueryResult{kind:"empty"} — zero rows after filter+order+limit.
-- "empty" ≠ "denied": pipeline ran; filters matched zero rows or limit was zero.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildIntegratedEmptyResult {
  input  metadata : Map[String, String]
  compute result = { kind: "empty", count: 0, message: "", metadata: metadata }
  output result : QueryResult
}

-- ── Contract 5: BuildIntegratedDeniedResult ──────────────────────────────────
-- Proves QueryResult{kind:"denied"} — G1/G2/G3 gate denial.
-- Denial-as-data: typed result; no exception raised; consumer does not retry same plan+cap.
-- "denied" ≠ "query_error": access denial vs malformed plan field.
-- Note: 'deny_reason' used as input name ('message' is a Ruby parser keyword).
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildIntegratedDeniedResult {
  input  deny_reason : String
  input  metadata    : Map[String, String]
  compute result = { kind: "denied", count: 0, message: deny_reason, metadata: metadata }
  output result : QueryResult
}

-- ── Contract 6: BuildIntegratedQueryErrorResult ──────────────────────────────
-- Proves QueryResult{kind:"query_error"} — malformed plan field.
-- Sources: G5 include_all; unknown filter op; unknown order direction; negative limit.
-- "query_error" ≠ "denied": malformed plan (fix before retry), not access denial.
-- Note: 'reason' used as input name ('message' is a Ruby parser keyword).
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildIntegratedQueryErrorResult {
  input  reason   : String
  input  metadata : Map[String, String]
  compute result = { kind: "query_error", count: 0, message: reason, metadata: metadata }
  output result : QueryResult
}

-- ── Contract 7: BuildIntegratedReceipt ───────────────────────────────────────
-- Proves QueryExecutionReceipt (15 fields) for a successful allowed execution.
-- cap_granted=true; denial_gate=""; row_limit_clamped=false; result_kind="rows".
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildIntegratedReceipt {
  input  cap_id:          String
  input  source_table:    String
  input  plan_limit:      Integer
  input  row_limit_cap:   Integer
  input  effective_limit: Integer
  input  rows_returned:   Integer
  input  metadata:        Map[String, String]
  compute receipt = {
    cap_id:            cap_id,
    plan_kind:         "select",
    source_table:      source_table,
    op_requested:      "read",
    cap_checked:       true,
    cap_granted:       true,
    denial_gate:       "",
    deny_reason:       "",
    plan_limit:        plan_limit,
    row_limit_cap:     row_limit_cap,
    effective_limit:   effective_limit,
    row_limit_clamped: false,
    rows_returned:     rows_returned,
    result_kind:       "rows",
    metadata:          metadata
  }
  output receipt : QueryExecutionReceipt
}

-- ── Contract 8: IntegratedMetadataReader ─────────────────────────────────────
-- Proves map_get(result.metadata, key) + or_else on integrated QueryResult.
-- Confirms metadata access pattern works on results from the integrated pipeline.
-- Fragment: CORE (pure; no capability; no IO).

pure contract IntegratedMetadataReader {
  input  result    : QueryResult
  input  query_key : String
  compute meta_opt  = map_get(result.metadata, query_key)
  compute meta_str  = or_else(meta_opt, "not-found")
  output meta_str : String
}
