module Lab.StorageCapability.ExecutionBoundary

-- LAB-STORAGE-CAPABILITY-P2: IO.StorageCapability mocked execution boundary proof.
-- Track: lab-storage-capability-policy-gates-and-query-execution-receipt-v0
--
-- Proves IO.StorageCapability as a mocked query execution boundary:
--   6-gate denial sequence (G1–G6), row-limit clamp (not denial),
--   include_all as query_error, denial-as-data, QueryExecutionReceipt shape,
--   and separation from TBackend/TEMPORAL.
--
-- Contracts (8):
--   ExecuteQuery         -- effect contract (COMPILE PROOF ONLY — Layer A + Layer B)
--   BuildGrantedReceipt  -- proves receipt shape when cap_granted (no clamp)
--   BuildDeniedReceipt   -- proves receipt shape for G1/G2/G3 denial gates
--   BuildClampedReceipt  -- proves receipt shape when row_limit clamped (G4)
--   ReadReceiptFields    -- proves field access on 15-field QueryExecutionReceipt
--   DeniedResult         -- proves QueryResult{kind:"denied"} (denial-as-data)
--   QueryErrorResult     -- proves QueryResult{kind:"query_error"} (G5 — != denied)
--   RowsResult           -- proves QueryResult{kind:"rows"} (G6 mocked execution)
--
-- Core formula:
--   QueryPlan         = pure typed intent data (CORE; no capability needed)
--   StorageCapability = execution authority gate (ESCAPE/STORAGE; not DB connection)
--   QueryResult       = typed outcome/denial data (5-kind KDR vocabulary)
--   StorageCapability != TBackend  (orthogonal tracks)
--   StorageCapability != database connection, ORM, SQL runtime, ActiveRecord
--
-- Layer A (Ruby TypeChecker): all 8 contracts accepted; type shapes correct.
-- Layer B (Rust VM): 7 pure contracts VM-executable; effect contract compile-only.
-- Layer C (proof-local sim): 6-gate StorageCapabilityGates + receipt invariants.
--
-- Depends: LAB-QUERY-P3 (QueryPlan v1 shape), PROP-035 (capability grammar),
--          LAB-STORAGE-CAPABILITY-P1 (schema + gate design), PROP-046 (boundary proposal)
--
-- Authority: LAB-ONLY. No canon claim. No real DB. No SQL. No ORM.
-- No stable surface. No public API.

-- ── Types ──────────────────────────────────────────────────────────────────────
-- Re-declared locally from LAB-QUERY-P3 for lab independence.

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

-- QueryExecutionReceipt: evidence-only; does not confer authority.
-- 15 fields. cap_granted=false iff result_kind in {"denied","query_error"}.
-- rows_returned=0 whenever cap_granted=false.
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

-- ── ExecuteQuery effect contract ───────────────────────────────────────────────
-- COMPILE PROOF ONLY. Layer A + Layer B accept. VM cannot execute effect contracts.
-- Stage 2+ required for live execution (STORAGE fragment class; ch4 amendment).
-- Stub compute returns "denied" conservatively — no real execution in v0.

effect contract ExecuteQuery {
  capability storage : IO.StorageCapability
  effect read_file using storage
  input  plan   : QueryPlan
  compute result = { kind: "denied", count: 0, message: "execution-not-v0", metadata: plan.metadata }
  output result : QueryResult
}

-- ── Contract 2: BuildGrantedReceipt ───────────────────────────────────────────
-- Proves receipt shape for a granted, non-clamped execution.
-- effective_limit = plan_limit (cap not reached).
-- cap_granted=true, row_limit_clamped=false, result_kind="rows".

pure contract BuildGrantedReceipt {
  input  cap_id:        String
  input  source_table:  String
  input  plan_limit:    Integer
  input  row_limit_cap: Integer
  input  rows_returned: Integer
  input  metadata:      Map[String, String]
  compute receipt = {
    cap_id: cap_id,
    plan_kind: "select",
    source_table: source_table,
    op_requested: "read",
    cap_checked: true,
    cap_granted: true,
    denial_gate: "",
    deny_reason: "",
    plan_limit: plan_limit,
    row_limit_cap: row_limit_cap,
    effective_limit: plan_limit,
    row_limit_clamped: false,
    rows_returned: rows_returned,
    result_kind: "rows",
    metadata: metadata
  }
  output receipt : QueryExecutionReceipt
}

-- ── Contract 3: BuildDeniedReceipt ────────────────────────────────────────────
-- Proves receipt shape for G1/G2/G3 denial gates.
-- cap_granted=false, effective_limit=0, rows_returned=0, result_kind="denied".

pure contract BuildDeniedReceipt {
  input  cap_id:        String
  input  source_table:  String
  input  denial_gate:   String
  input  deny_reason:   String
  input  plan_limit:    Integer
  input  row_limit_cap: Integer
  input  metadata:      Map[String, String]
  compute receipt = {
    cap_id: cap_id,
    plan_kind: "select",
    source_table: source_table,
    op_requested: "read",
    cap_checked: true,
    cap_granted: false,
    denial_gate: denial_gate,
    deny_reason: deny_reason,
    plan_limit: plan_limit,
    row_limit_cap: row_limit_cap,
    effective_limit: 0,
    row_limit_clamped: false,
    rows_returned: 0,
    result_kind: "denied",
    metadata: metadata
  }
  output receipt : QueryExecutionReceipt
}

-- ── Contract 4: BuildClampedReceipt ───────────────────────────────────────────
-- Proves receipt shape when row_limit clamped (G4).
-- effective_limit = row_limit_cap (the cap overrides plan_limit).
-- row_limit_clamped=true, cap_granted=true (no denial — clamp is not denial).

pure contract BuildClampedReceipt {
  input  cap_id:        String
  input  source_table:  String
  input  plan_limit:    Integer
  input  row_limit_cap: Integer
  input  rows_returned: Integer
  input  metadata:      Map[String, String]
  compute receipt = {
    cap_id: cap_id,
    plan_kind: "select",
    source_table: source_table,
    op_requested: "read",
    cap_checked: true,
    cap_granted: true,
    denial_gate: "",
    deny_reason: "",
    plan_limit: plan_limit,
    row_limit_cap: row_limit_cap,
    effective_limit: row_limit_cap,
    row_limit_clamped: true,
    rows_returned: rows_returned,
    result_kind: "rows",
    metadata: metadata
  }
  output receipt : QueryExecutionReceipt
}

-- ── Contract 5: ReadReceiptFields ─────────────────────────────────────────────
-- Proves field access on a 15-field QueryExecutionReceipt record.
-- Outputs cap_granted (Bool) as the primary output; all other accesses computed.

pure contract ReadReceiptFields {
  input  receipt : QueryExecutionReceipt
  compute cap_granted       = receipt.cap_granted
  compute denial_gate       = receipt.denial_gate
  compute effective_limit   = receipt.effective_limit
  compute row_limit_clamped = receipt.row_limit_clamped
  compute result_kind       = receipt.result_kind
  output cap_granted : Bool
}

-- ── Contract 6: DeniedResult ──────────────────────────────────────────────────
-- Proves QueryResult{kind:"denied"} — denial-as-data from G1/G2/G3 gates.
-- denial_gate is encoded in message by the caller; QueryResult itself has no gate field.

pure contract DeniedResult {
  input  reason   : String
  input  metadata : Map[String, String]
  compute result = { kind: "denied", count: 0, message: reason, metadata: metadata }
  output result : QueryResult
}

-- ── Contract 7: QueryErrorResult ─────────────────────────────────────────────
-- Proves QueryResult{kind:"query_error"} — G5 gate (include_all restricted).
-- "query_error" != "denied": malformed plan, not access denial.

pure contract QueryErrorResult {
  input  reason   : String
  input  metadata : Map[String, String]
  compute result = { kind: "query_error", count: 0, message: reason, metadata: metadata }
  output result : QueryResult
}

-- ── Contract 8: RowsResult ────────────────────────────────────────────────────
-- Proves QueryResult{kind:"rows"} — G6 mocked execution, cap granted.

pure contract RowsResult {
  input  count    : Integer
  input  reason   : String
  input  metadata : Map[String, String]
  compute result = { kind: "rows", count: count, message: reason, metadata: metadata }
  output result : QueryResult
}
