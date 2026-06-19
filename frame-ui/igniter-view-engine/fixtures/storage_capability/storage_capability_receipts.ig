module Lab.StorageCapability.ReceiptBuilders

-- LAB-STORAGE-CAPABILITY-P2: Receipt builders — pure contracts only.
-- VM-executable companion to storage_capability_exec.ig.
-- All contracts are CORE (pure; no capability; no IO).
--
-- Types duplicated from storage_capability_exec.ig for VM-layer independence.
-- The effect contract ExecuteQuery lives in storage_capability_exec.ig (compile-only).
--
-- Authority: LAB-ONLY. No canon claim. No real DB. No SQL. No ORM.

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

-- ── Contract 1: BuildGrantedReceipt ───────────────────────────────────────────

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

-- ── Contract 2: BuildDeniedReceipt ────────────────────────────────────────────

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

-- ── Contract 3: BuildClampedReceipt ───────────────────────────────────────────

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

-- ── Contract 4: ReadReceiptFields ─────────────────────────────────────────────

pure contract ReadReceiptFields {
  input  receipt : QueryExecutionReceipt
  compute cap_granted       = receipt.cap_granted
  compute denial_gate       = receipt.denial_gate
  compute effective_limit   = receipt.effective_limit
  compute row_limit_clamped = receipt.row_limit_clamped
  compute result_kind       = receipt.result_kind
  output cap_granted : Bool
}

-- ── Contract 5: DeniedResult ──────────────────────────────────────────────────

pure contract DeniedResult {
  input  reason   : String
  input  metadata : Map[String, String]
  compute result = { kind: "denied", count: 0, message: reason, metadata: metadata }
  output result : QueryResult
}

-- ── Contract 6: QueryErrorResult ─────────────────────────────────────────────

pure contract QueryErrorResult {
  input  reason   : String
  input  metadata : Map[String, String]
  compute result = { kind: "query_error", count: 0, message: reason, metadata: metadata }
  output result : QueryResult
}

-- ── Contract 7: RowsResult ────────────────────────────────────────────────────

pure contract RowsResult {
  input  count    : Integer
  input  reason   : String
  input  metadata : Map[String, String]
  compute result = { kind: "rows", count: count, message: reason, metadata: metadata }
  output result : QueryResult
}
