module Lab.FilterEval.MockedRowFilter

-- LAB-FILTER-EVAL-P1: Filter predicate evaluation over mocked in-memory rows.
-- Track: lab-query-filter-predicate-evaluation-over-mocked-rows-v0
--
-- Proves filter semantics as pure data transformation. No SQL, no DB, no ORM.
-- QueryPlan.filters is no longer just shape — it has a v0 meaning over mocked rows.
--
-- FilterEval v0 = Collection[FilterPredicate] + mocked rows → filtered count + QueryResult
-- FilterEval v0 ≠ SQL execution ≠ DB runtime ≠ ORM ≠ StorageCapability live execution
--
-- v0 operators: eq, neq, contains, prefix
-- v0 semantics: AND combination only; empty list returns all rows; unknown field → no match;
--               unknown operator → query_error (NOT denied); zero matches → kind:"empty"
--
-- Contracts (9):
--   BuildFilterEq            — eq FilterPredicate shape
--   BuildFilterNeq           — neq FilterPredicate shape
--   BuildFilterContains      — contains FilterPredicate shape
--   BuildFilterPrefix        — prefix FilterPredicate shape
--   BuildQueryPlanWithFilters — QueryPlan with inline filter array (LAB-TC-ARRAY-P2 pattern)
--   FilterResultRows         — QueryResult{kind:"rows", count:N}
--   FilterResultEmpty        — QueryResult{kind:"empty", count:0}
--   FilterResultQueryError   — QueryResult{kind:"query_error"} for unknown operator
--   FilterResultMetadataReader — map_get + or_else on QueryResult.metadata
--
-- Three-layer proof:
--   Layer A — Ruby TypeChecker: 9 contracts accepted; FilterPredicate / QueryPlan shapes.
--   Layer B — Rust compiler: fixture compiles; Rust SIR: BuildQueryPlanWithFilters.filters
--             typed Collection[FilterPredicate] from record-field context (P2 pattern).
--   Layer C — Proof-local FilterEvalSim: eq/neq/contains/prefix; AND composition;
--             empty-filter-list; missing-field; unknown-op → query_error.
--
-- Authority: LAB-ONLY. No canon claim. No real DB. No SQL. No ORM.
-- No stable surface. No public API. No StorageCapability execution authority.

-- ── Types ──────────────────────────────────────────────────────────────────────
-- Re-declared locally for lab independence (consistent with P1 two-fixture pattern).

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

-- ── Contract 1: BuildFilterEq ─────────────────────────────────────────────────
-- Proves eq FilterPredicate shape. op:"eq" = row field value exactly equals predicate value.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildFilterEq {
  input  field : String
  input  value : String
  compute pred = { field: field, op: "eq", value: value }
  output pred : FilterPredicate
}

-- ── Contract 2: BuildFilterNeq ────────────────────────────────────────────────
-- Proves neq FilterPredicate shape. op:"neq" = row field value does not equal predicate value.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildFilterNeq {
  input  field : String
  input  value : String
  compute pred = { field: field, op: "neq", value: value }
  output pred : FilterPredicate
}

-- ── Contract 3: BuildFilterContains ──────────────────────────────────────────
-- Proves contains FilterPredicate shape. op:"contains" = row field value contains predicate value
-- as a substring. String containment only — no SQL LIKE, no regex.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildFilterContains {
  input  field : String
  input  value : String
  compute pred = { field: field, op: "contains", value: value }
  output pred : FilterPredicate
}

-- ── Contract 4: BuildFilterPrefix ────────────────────────────────────────────
-- Proves prefix FilterPredicate shape. op:"prefix" = row field value starts with predicate value.
-- String prefix only — no SQL LIKE, no regex, no starts_with SQL extension.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildFilterPrefix {
  input  field : String
  input  value : String
  compute pred = { field: field, op: "prefix", value: value }
  output pred : FilterPredicate
}

-- ── Contract 5: BuildQueryPlanWithFilters ─────────────────────────────────────
-- Proves QueryPlan construction with inline filter array (LAB-TC-ARRAY-P2 pattern).
-- `filters` intermediate array types as Collection[FilterPredicate] from the
-- QueryPlan.filters record-field context — same mechanism as LAB-EXECUTE-QUERY-P1.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildQueryPlanWithFilters {
  input  source     : QuerySource
  input  projection : Projection
  input  order      : OrderBy
  input  limit      : Integer
  input  metadata   : Map[String, String]
  compute filters = [
    { field: "status", op: "eq",  value: "active" },
    { field: "role",   op: "neq", value: "guest"  }
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

-- ── Contract 6: FilterResultRows ─────────────────────────────────────────────
-- Proves QueryResult{kind:"rows"} when at least one row matches all predicates.
-- count = number of rows that passed ALL filter predicates (AND semantics in v0).
-- Fragment: CORE (pure; no capability; no IO).

pure contract FilterResultRows {
  input  count    : Integer
  input  metadata : Map[String, String]
  compute result = { kind: "rows", count: count, message: "", metadata: metadata }
  output result : QueryResult
}

-- ── Contract 7: FilterResultEmpty ────────────────────────────────────────────
-- Proves QueryResult{kind:"empty"} when zero rows satisfy all predicates.
-- "empty" ≠ "denied": evaluation succeeded; no rows matched the filter conjunction.
-- Fragment: CORE (pure; no capability; no IO).

pure contract FilterResultEmpty {
  input  metadata : Map[String, String]
  compute result = { kind: "empty", count: 0, message: "", metadata: metadata }
  output result : QueryResult
}

-- ── Contract 8: FilterResultQueryError ───────────────────────────────────────
-- Proves QueryResult{kind:"query_error"} for unknown or unsupported operator.
-- "query_error" ≠ "denied": malformed predicate (fix before retry), not access denial.
-- v0 known operators: eq, neq, contains, prefix. Any other op → query_error.
-- Consumer action: inspect predicate, correct op name, retry. NOT a capability decision.
-- Fragment: CORE (pure; no capability; no IO).

pure contract FilterResultQueryError {
  input  metadata : Map[String, String]
  compute result = { kind: "query_error", count: 0, message: "unknown operator", metadata: metadata }
  output result : QueryResult
}

-- ── Contract 9: FilterResultMetadataReader ────────────────────────────────────
-- Proves map_get(result.metadata, key) + or_else chain on filtered QueryResult.
-- Confirms metadata access pattern works on filter evaluation outputs.
-- Fragment: CORE (pure; no capability; no IO).

pure contract FilterResultMetadataReader {
  input  result    : QueryResult
  input  query_key : String
  compute meta_opt  = map_get(result.metadata, query_key)
  compute meta_str  = or_else(meta_opt, "not-found")
  output meta_str : String
}
