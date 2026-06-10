module Lab.ExecuteQuery.CapabilityBoundary

-- LAB-EXECUTE-QUERY-P1: ExecuteQuery Stage 2+ effect contract boundary proof.
-- Track: lab-execute-query-effect-contract-and-storage-capability-injection-v0
--
-- Proves that an `ExecuteQuery` effect contract receiving a `QueryPlan` and an
-- `IO.StorageCapability` authority is expressible with current PROP-035 grammar.
--
-- Contracts (5):
--   ExecuteQuery         -- effect contract (COMPILE PROOF ONLY — Layer A + Layer B)
--   ReadPlanSource       -- proves plan.source.table nested field access (Layer A + B)
--   ReadPlanProjection   -- proves plan.projection.include_all nested field access
--   BuildDeniedResult    -- proves QueryResult{kind:"denied"} denial-as-data form
--   ReadPlanMeta         -- proves map_get(plan.metadata, key) + or_else chain
--
-- Core formula:
--   ExecuteQuery v0 = QueryPlan + IO.StorageCapability authority → QueryResult
--   ExecuteQuery v0 ≠ SQL execution / ORM / database runtime
--   IO.StorageCapability (ESCAPE class) requires capability injection for VM execution.
--   Stage 2+ STORAGE class required for live execution.
--
-- Layer A (Ruby TypeChecker): 5 contracts accepted; effect + pure all clean.
-- Layer B (Rust compiler): exec fixture compiles; effect contract compile boundary confirmed.
-- VM Note: effect contracts require capability passport injection — compile-only Layer A + B.
--
-- Depends: LAB-QUERY-P3 (QueryPlan v1 nested records), PROP-035 (capability grammar),
--          LAB-STORAGE-CAPABILITY-P1/P2 (gate design + receipt proof), PROP-046-P1 (boundary).
--
-- Authority: LAB-ONLY. No canon claim. No real DB. No SQL. No ORM. No runtime.
-- No stable surface. No public API. No STORAGE class implementation.

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
-- COMPILE PROOF ONLY. Layer A + Layer B accept. VM requires capability injection.
-- Stage 2+ STORAGE fragment class required for live execution.
-- Stub compute: returns denied conservatively — no execution in v0.
-- IO.StorageCapability = ESCAPE authority gate (not a database connection).

effect contract ExecuteQuery {
  capability storage : IO.StorageCapability
  effect read_file using storage
  input  plan : QueryPlan
  compute result = { kind: "denied", count: 0, message: "execution-not-v0", metadata: plan.metadata }
  output result : QueryResult
}

-- ── Contract 2: ReadPlanSource ────────────────────────────────────────────────
-- Proves nested field access: plan.source.table (two-hop OP_GET_FIELD).
-- Source table is the G1 gate input; preserved in QueryExecutionReceipt.source_table.
-- Fragment: CORE (pure; no capability; no IO).

pure contract ReadPlanSource {
  input  plan   : QueryPlan
  compute table  = plan.source.table
  compute schema = plan.source.schema
  output table : String
}

-- ── Contract 3: ReadPlanProjection ────────────────────────────────────────────
-- Proves nested field access: plan.projection.include_all (G5 gate input).
-- Bool result from nested field; same two-hop OP_GET_FIELD path as plan.source.table.
-- Fragment: CORE (pure; no capability; no IO).

pure contract ReadPlanProjection {
  input  plan        : QueryPlan
  compute include_all = plan.projection.include_all
  compute fields      = plan.projection.fields
  output include_all : Bool
}

-- ── Contract 4: BuildDeniedResult ─────────────────────────────────────────────
-- Proves denial-as-data: QueryResult{kind:"denied"} — 10th proof overall.
-- Gate G1/G2/G3 produce "denied"; this contract proves the QueryResult shape.
-- Note: input named 'deny_reason' (not 'message') — 'message' is a parser keyword.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildDeniedResult {
  input  deny_reason : String
  input  metadata    : Map[String, String]
  compute result = { kind: "denied", count: 0, message: deny_reason, metadata: metadata }
  output result : QueryResult
}

-- ── Contract 5: ReadPlanMeta ──────────────────────────────────────────────────
-- Proves map_get(plan.metadata, key) + or_else chain on QueryPlan.
-- plan.metadata is a Map[String,String]; C1 chain (map_get+or_else) proven here.
-- Fragment: CORE (pure; no capability; no IO).

pure contract ReadPlanMeta {
  input  plan      : QueryPlan
  input  meta_key  : String
  compute meta_opt  = map_get(plan.metadata, meta_key)
  compute meta_str  = or_else(meta_opt, "not-found")
  output meta_str : String
}
