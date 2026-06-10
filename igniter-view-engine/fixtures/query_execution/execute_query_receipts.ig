module Lab.ExecuteQuery.MockedExecution

-- LAB-EXECUTE-QUERY-P1: Pure VM-executable contracts for mocked query execution.
-- Track: lab-execute-query-effect-contract-and-storage-capability-injection-v0
--
-- VM-executable companion to execute_query_capability.ig.
-- All contracts CORE (pure; no capability; no IO).
--
-- Types duplicated from execute_query_capability.ig + StorageCapability for lab independence.
-- StorageCapability is declared as a named Record here (schema-shaped; not IO.StorageCapability).
--
-- Contracts (12):
--   BuildStorageCapability    -- proves StorageCapability record shape (8 fields)
--   BuildQueryPlanInline      -- proves full QueryPlan with inline filters (LAB-TC-ARRAY-P2)
--   ExecuteQueryRows          -- proves QueryResult{kind:"rows"} — G6 mocked rows
--   ExecuteQueryEmpty         -- proves QueryResult{kind:"empty"} — G6 zero rows
--   ExecuteQueryDeniedSource  -- proves QueryResult{kind:"denied"} — G1 denial-as-data
--   ExecuteQueryQueryError    -- proves QueryResult{kind:"query_error"} — G5 (!=denied)
--   ExecuteQuerySystemError   -- proves QueryResult{kind:"system_error"} — G6 error
--   BuildAllowedReceipt       -- proves receipt when cap_granted + no clamp
--   BuildDeniedGateReceipt    -- proves receipt when cap_granted=false + denial_gate
--   BuildClampedReceipt       -- proves receipt when row_limit_clamped=true (G4 clamp)
--   QueryReceiptReader        -- proves field access on 15-field QueryExecutionReceipt
--   QueryMetadataChain        -- proves map_get(result.metadata, key) + or_else
--
-- Gate invariants proved:
--   G4: clamp ≠ denial — row_limit_clamped=true but cap_granted=true
--   G5: query_error ≠ denied — different consumer action
--   denial-as-data: all gate failures return typed result; no raise/exception
--
-- Authority: LAB-ONLY. No canon claim. No real DB. No SQL. No ORM.
-- No stable surface. No public API. No StorageCapability execution authority.

-- ── Types ──────────────────────────────────────────────────────────────────────

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

-- StorageCapability: schema-shaped record for passing capability parameters.
-- 8 fields — mirrors the IO.StorageCapability schema from LAB-STORAGE-CAPABILITY-P1.
-- This is NOT IO.StorageCapability (the capability authority reference).
-- It is a plain record that models the capability's gate parameters.
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

-- ── Contract 1: BuildStorageCapability ────────────────────────────────────────
-- Proves the StorageCapability record shape.
-- allowed_sources and allowed_ops are passed as Collection[String] inputs (not
-- constructed inline — avoids array_literal context requirement at assignment level).
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildStorageCapability {
  input cap_id:            String
  input allowed_sources:   Collection[String]
  input allowed_ops:       Collection[String]
  input row_limit:         Integer
  input allow_include_all: Bool
  input read_allowed:      Bool
  input write_allowed:     Bool
  input deny_reason:       String
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

-- ── Contract 2: BuildQueryPlanInline ──────────────────────────────────────────
-- Proves full QueryPlan construction with inline filter array (LAB-TC-ARRAY-P2 pattern).
-- `filters` intermediate array typed as Collection[FilterPredicate] from the
-- QueryPlan.filters field context (P2 record-field context typing).
-- Closes the LAB-QUERY-P3 workaround for the Stage 2+ execute path.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildQueryPlanInline {
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

-- ── Contract 3: ExecuteQueryRows ──────────────────────────────────────────────
-- Proves QueryResult{kind:"rows"} — G6 mocked execute (rows > 0).
-- cap_granted=true at this stage (gates G1-G5 passed).
-- Note: input named 'row_count' (not 'count') to avoid future keyword conflicts.
-- Fragment: CORE (pure; no capability; no IO).

pure contract ExecuteQueryRows {
  input  row_count : Integer
  input  metadata  : Map[String, String]
  compute result = { kind: "rows", count: row_count, message: "", metadata: metadata }
  output result : QueryResult
}

-- ── Contract 4: ExecuteQueryEmpty ─────────────────────────────────────────────
-- Proves QueryResult{kind:"empty"} — G6 mocked execute (rows == 0).
-- "empty" ≠ "denied": the query ran successfully, no rows matched the filters.
-- Fragment: CORE (pure; no capability; no IO).

pure contract ExecuteQueryEmpty {
  input  metadata : Map[String, String]
  compute result = { kind: "empty", count: 0, message: "", metadata: metadata }
  output result : QueryResult
}

-- ── Contract 5: ExecuteQueryDeniedSource ──────────────────────────────────────
-- Proves QueryResult{kind:"denied"} — G1 source not in allowed_sources.
-- Denial-as-data: no exception; typed result with message.
-- 10th proof of denial-as-data pattern across the Igniter lab corpus.
-- Note: 'deny_reason' used as input name ('message' is a Ruby parser keyword).
-- Fragment: CORE (pure; no capability; no IO).

pure contract ExecuteQueryDeniedSource {
  input  deny_reason : String
  input  metadata    : Map[String, String]
  compute result = { kind: "denied", count: 0, message: deny_reason, metadata: metadata }
  output result : QueryResult
}

-- ── Contract 6: ExecuteQueryQueryError ────────────────────────────────────────
-- Proves QueryResult{kind:"query_error"} — G5 include_all restricted.
-- "query_error" ≠ "denied": malformed plan (fix before retry), not access denial.
-- Consumer action: fix plan first; do not retry same plan.
-- Fragment: CORE (pure; no capability; no IO).

pure contract ExecuteQueryQueryError {
  input  metadata : Map[String, String]
  compute result = { kind: "query_error", count: 0, message: "include_all not permitted by capability", metadata: metadata }
  output result : QueryResult
}

-- ── Contract 7: ExecuteQuerySystemError ───────────────────────────────────────
-- Proves QueryResult{kind:"system_error"} — G6 infrastructure failure (mocked).
-- cap_granted=false despite passing G1-G5 gates.
-- Consumer action: retry later (infrastructure, not policy).
-- Fragment: CORE (pure; no capability; no IO).

pure contract ExecuteQuerySystemError {
  input  metadata : Map[String, String]
  compute result = { kind: "system_error", count: 0, message: "infrastructure failure", metadata: metadata }
  output result : QueryResult
}

-- ── Contract 8: BuildAllowedReceipt ───────────────────────────────────────────
-- Proves receipt shape for a granted, non-clamped execution.
-- effective_limit = plan_limit (cap not reached: plan_limit <= row_limit_cap).
-- cap_granted=true, row_limit_clamped=false, result_kind="rows".
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildAllowedReceipt {
  input  cap_id:        String
  input  source_table:  String
  input  plan_limit:    Integer
  input  row_limit_cap: Integer
  input  rows_returned: Integer
  input  metadata:      Map[String, String]
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
    effective_limit:   plan_limit,
    row_limit_clamped: false,
    rows_returned:     rows_returned,
    result_kind:       "rows",
    metadata:          metadata
  }
  output receipt : QueryExecutionReceipt
}

-- ── Contract 9: BuildDeniedGateReceipt ────────────────────────────────────────
-- Proves receipt shape for G1/G2/G3 gate denials.
-- cap_granted=false; effective_limit=0; rows_returned=0; denial_gate populated.
-- Invariant: cap_granted=false iff result_kind in {"denied","query_error"}.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildDeniedGateReceipt {
  input  cap_id:        String
  input  source_table:  String
  input  denial_gate:   String
  input  deny_reason:   String
  input  plan_limit:    Integer
  input  row_limit_cap: Integer
  input  metadata:      Map[String, String]
  compute receipt = {
    cap_id:            cap_id,
    plan_kind:         "select",
    source_table:      source_table,
    op_requested:      "read",
    cap_checked:       true,
    cap_granted:       false,
    denial_gate:       denial_gate,
    deny_reason:       deny_reason,
    plan_limit:        plan_limit,
    row_limit_cap:     row_limit_cap,
    effective_limit:   0,
    row_limit_clamped: false,
    rows_returned:     0,
    result_kind:       "denied",
    metadata:          metadata
  }
  output receipt : QueryExecutionReceipt
}

-- ── Contract 10: BuildClampedReceipt ──────────────────────────────────────────
-- Proves receipt shape when G4 row_limit clamped.
-- effective_limit = row_limit_cap (cap overrides plan_limit; plan_limit > row_limit_cap).
-- row_limit_clamped=true; cap_granted=true (G4 is NOT a denial — clamp only).
-- Invariant: G4 clamp ≠ denied; consumer still receives rows under effective_limit.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildClampedReceipt {
  input  cap_id:        String
  input  source_table:  String
  input  plan_limit:    Integer
  input  row_limit_cap: Integer
  input  rows_returned: Integer
  input  metadata:      Map[String, String]
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
    effective_limit:   row_limit_cap,
    row_limit_clamped: true,
    rows_returned:     rows_returned,
    result_kind:       "rows",
    metadata:          metadata
  }
  output receipt : QueryExecutionReceipt
}

-- ── Contract 11: QueryReceiptReader ──────────────────────────────────────────
-- Proves field access on 15-field QueryExecutionReceipt.
-- Outputs cap_granted (Bool) as primary; all other fields verified via compute.
-- Fragment: CORE (pure; no capability; no IO).

pure contract QueryReceiptReader {
  input  receipt : QueryExecutionReceipt
  compute cap_granted       = receipt.cap_granted
  compute denial_gate       = receipt.denial_gate
  compute effective_limit   = receipt.effective_limit
  compute row_limit_clamped = receipt.row_limit_clamped
  compute result_kind       = receipt.result_kind
  compute source_table      = receipt.source_table
  output cap_granted : Bool
}

-- ── Contract 12: QueryMetadataChain ──────────────────────────────────────────
-- Proves map_get(result.metadata, key) + or_else chain on QueryResult.
-- result.metadata is a direct field access giving Map[String,String];
-- map_get returns Option[String]; or_else degrades to String default.
-- Fragment: CORE (pure; no capability; no IO).

pure contract QueryMetadataChain {
  input  result    : QueryResult
  input  query_key : String
  compute meta_opt  = map_get(result.metadata, query_key)
  compute meta_str  = or_else(meta_opt, "not-found")
  output meta_str : String
}
