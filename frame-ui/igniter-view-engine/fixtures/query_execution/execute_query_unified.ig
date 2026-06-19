module Lab.ExecuteQuery.UnifiedMockedExecution

-- LAB-EXECUTE-QUERY-P3: Unified mocked query execution receipt.
-- Track: lab-execute-query-unified-filter-multiorder-projection-receipt-v0
--
-- Unifies query semantics proven across P2 + MULTI-ORDER + PROJECTION into one
-- complete proof-local ExecuteQuery pipeline:
--
--   StorageCapability-shaped gates
--   → filters
--   → multi-column order (Collection[OrderBy])
--   → limit / row-limit clamp
--   → projection
--   → QueryResult + QueryExecutionReceipt
--
-- Core formula:
--   UnifiedQuery v0  =  QueryPlanUnified + StorageCapability-shaped policy + mocked rows
--                    →  gated / filtered / ordered / limited / projected QueryResult
--                    +  QueryExecutionReceipt
--   UnifiedQuery v0  ≠  SQL execution  ≠  DB runtime  ≠  ORM  ≠  production StorageCapability
--   UnifiedQuery v0  ≠  query optimizer  ≠  index-backed sorting
--   UnifiedQuerySim  =  PROOF-LOCAL ONLY  ≠  production unified query runtime
--
-- Pipeline order (Layer C UnifiedQuerySim):
--   1.  G1: source allowlist          → denied
--   2.  G2: op allowlist              → denied
--   3.  G3: read_allowed master       → denied
--   4.  G4: row-limit clamp           → effective_limit = min(plan.limit, cap.row_limit); NOT denial
--   5.  G5: include_all policy        → query_error (NOT denied)
--   6.  Apply filters                 → rows / empty / query_error (bad op)
--   7.  Apply multi-column order      → sorted rows / query_error (bad dir / missing field)
--   8.  Apply effective_limit         → limited rows / empty / query_error (negative)
--   9.  Apply projection              → shaped rows / query_error (empty fields / missing field)
--   10. Build QueryResult + QueryExecutionReceipt
--
-- Contracts (8 — all pure CORE):
--   BuildUnifiedPlan              — QueryPlanUnified (inline filters + 2-key order; 8th P2 confirmation)
--   BuildUnifiedCapability        — StorageCapability schema-shaped record
--   BuildUnifiedRowsResult        — QueryResult{kind:"rows"}
--   BuildUnifiedEmptyResult       — QueryResult{kind:"empty"}
--   BuildUnifiedDeniedResult      — QueryResult{kind:"denied"}
--   BuildUnifiedQueryErrorResult  — QueryResult{kind:"query_error"}
--   BuildUnifiedReceipt           — QueryExecutionReceipt (15 fields) for allowed execution
--   UnifiedMetadataReader         — map_get(result.metadata, key) + or_else
--
-- Three-layer proof:
--   Layer A — Ruby TypeChecker: all 8 contracts accepted; zero type_errors;
--             QueryPlanUnified.filters: Collection[FilterPredicate];
--             QueryPlanUnified.order:   Collection[OrderBy];
--             QueryPlanUnified.projection: Projection.
--   Layer B — Rust compiler + VM: fixture compiles; Rust SIR:
--             BuildUnifiedPlan.filters = Collection[FilterPredicate] from record-field context
--             (LAB-TC-ARRAY-P2 mechanism — 8th confirmation across fixtures);
--             all 8 contracts VM-executable.
--   Layer C — Proof-local UnifiedQuerySim:
--             full pipeline: G1–G6 gates + filter + multi-column order + limit + projection + receipt.
--             G1/G2/G3 short-circuit before filter/order/limit/projection evaluation.
--             G4 clamp does NOT deny (cap_granted stays true after clamp).
--             G5 → query_error (NOT denied).
--             Projection is the final step — AFTER filter+multi-order+limit.
--             Projection does not change row count.
--             query_error ≠ denied throughout.
--
-- TypeChecker boundary (B9 from PROJECTION-P1): nested record literals inside outer record
-- literals do not propagate inner field type context. `projection: { fields: "...", include_all: false }`
-- embedded directly in the plan record literal fails OOF-TY0. Workaround: pass projection as input.
-- This card does not fix the TypeChecker; the boundary is documented and deferred.
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

-- QueryPlanUnified: unified plan shape with Collection[OrderBy] (multi-column) + explicit Projection.
-- Differs from QueryPlan (P2, single OrderBy) and is the canonical multi-order+projection form.
-- Does not mutate existing QueryPlan, QueryPlanMultiOrder, or QueryPlanProjection from prior fixtures.
type QueryPlanUnified {
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

-- StorageCapability: schema-shaped Record for passing gate parameters.
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

-- ── Contract 1: BuildUnifiedPlan ─────────────────────────────────────────────
-- Proves QueryPlanUnified with inline filter array (LAB-TC-ARRAY-P2 mechanism) and
-- 2-key order list (Collection[OrderBy] from record-field context).
-- filters compute: Collection[FilterPredicate] from QueryPlanUnified.filters field context
-- (LAB-TC-ARRAY-P2 mechanism — 8th confirmation across fixtures).
-- projection passed as input: TypeChecker nested-record-literal boundary (B9 from PROJECTION-P1).
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildUnifiedPlan {
  input  source     : QuerySource
  input  projection : Projection
  input  limit      : Integer
  input  metadata   : Map[String, String]
  compute filters = [
    { field: "status", op: "eq", value: "active" },
    { field: "dept",   op: "eq", value: "eng"    }
  ]
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
  output plan : QueryPlanUnified
}

-- ── Contract 2: BuildUnifiedCapability ───────────────────────────────────────
-- Proves StorageCapability record shape.
-- allowed_sources and allowed_ops passed as Collection[String] inputs.
-- Row-limit clamp semantics (G4) and policy gates (G1–G5) proven at Layer C.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildUnifiedCapability {
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

-- ── Contract 3: BuildUnifiedRowsResult ───────────────────────────────────────
-- Proves QueryResult{kind:"rows"} — full pipeline ran; rows returned after projection.
-- count = rows after gates + filter + multi-order + limit + projection.
-- Projection does not change row count — it is a column selector, not a row filter.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildUnifiedRowsResult {
  input  row_count : Integer
  input  metadata  : Map[String, String]
  compute result = { kind: "rows", count: row_count, message: "", metadata: metadata }
  output result : QueryResult
}

-- ── Contract 4: BuildUnifiedEmptyResult ──────────────────────────────────────
-- Proves QueryResult{kind:"empty"} — zero rows after full pipeline.
-- "empty" ≠ "denied": pipeline ran; no rows matched filters or effective_limit was zero.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildUnifiedEmptyResult {
  input  metadata : Map[String, String]
  compute result = { kind: "empty", count: 0, message: "", metadata: metadata }
  output result : QueryResult
}

-- ── Contract 5: BuildUnifiedDeniedResult ─────────────────────────────────────
-- Proves QueryResult{kind:"denied"} — G1/G2/G3 gate denial.
-- Denial-as-data: typed result; no exception raised; pipeline short-circuits before
-- filter/order/limit/projection evaluation.
-- "denied" ≠ "query_error": access denial vs malformed plan.
-- Note: 'deny_reason' used as input name ('message' is a Ruby parser keyword).
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildUnifiedDeniedResult {
  input  deny_reason : String
  input  metadata    : Map[String, String]
  compute result = { kind: "denied", count: 0, message: deny_reason, metadata: metadata }
  output result : QueryResult
}

-- ── Contract 6: BuildUnifiedQueryErrorResult ─────────────────────────────────
-- Proves QueryResult{kind:"query_error"} — malformed plan field.
-- Sources: G5 include_all policy; unknown filter op; unknown order direction;
--          order field absent in row; negative limit; empty projection fields;
--          projection field absent in row.
-- "query_error" ≠ "denied": malformed plan (fix before retry), not access denial.
-- Note: 'reason' used as input name ('message' is a Ruby parser keyword).
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildUnifiedQueryErrorResult {
  input  reason   : String
  input  metadata : Map[String, String]
  compute result = { kind: "query_error", count: 0, message: reason, metadata: metadata }
  output result : QueryResult
}

-- ── Contract 7: BuildUnifiedReceipt ──────────────────────────────────────────
-- Proves QueryExecutionReceipt (15 fields) for a successful allowed execution.
-- cap_granted=true; denial_gate=""; deny_reason=""; row_limit_clamped=false; result_kind="rows".
-- rows_returned = count after full pipeline including projection.
-- Projection does not change row count; rows_returned reflects post-projection count.
-- Receipt shape is identical to P2 (no new fields required for v0 unified pipeline).
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildUnifiedReceipt {
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

-- ── Contract 8: UnifiedMetadataReader ────────────────────────────────────────
-- Proves map_get(result.metadata, key) + or_else on unified QueryResult.
-- Fragment: CORE (pure; no capability; no IO).

pure contract UnifiedMetadataReader {
  input  result    : QueryResult
  input  query_key : String
  compute meta_opt = map_get(result.metadata, query_key)
  compute meta_str = or_else(meta_opt, "not-found")
  output meta_str : String
}
