module QueryEngineTypes

-- ============================================================
-- query_engine — a pure query planner + executor (no DB, no SQL)
-- ============================================================
-- Pulled from `igniter-view-engine/fixtures` (query_plan / query_execution /
-- storage_adapter). A query is a typed intent AST: a source, a set of filter
-- predicates (AND-composed), an order clause, and a limit. Execution is a pure
-- transformation over INJECTED rows + a capability decision; the result is a
-- kind-discriminated envelope (denial-as-data). No ORM, no connection, no
-- persistence — the rows and the capability grant are injected at the boundary.
--
-- v0 row shape is a fixed "customer" record (heterogeneous rows / dynamic
-- field projection are documented pressure — see PRESSURE_REGISTRY.md).

-- ── A row (fixed schema in v0) ──────────────────────────────
type Row {
  id     : Integer
  age    : Integer
  city   : String
  active : Integer
}

-- ── A filter predicate (one AND clause) ─────────────────────
-- PRESSURE QE-P01: `op` and `field` are STRINGLY. A sealed `FilterOp`
-- variant (Eq|Neq|Gt|Gte|Lt|Lte) and typed value slots would make this
-- exhaustive and fail-closed instead of a string dispatch.
type FilterPredicate {
  field : String   -- "id" | "age" | "city" | "active"
  op    : String   -- "eq" | "neq" | "gt" | "gte" | "lt" | "lte"
  num   : Integer  -- comparison value for numeric fields
  str   : String   -- comparison value for string fields
}

-- ── Order clause ────────────────────────────────────────────
type OrderBy {
  field     : String
  direction : String  -- "asc" | "desc"
}

-- ── The query plan (flat intent AST) ────────────────────────
type QueryPlan {
  source_table : String
  filters      : Collection[FilterPredicate]
  order        : OrderBy
  limit        : Integer
}

-- ── Kind-discriminated result envelope ──────────────────────
-- PRESSURE QE-P02: denial-as-data + result kinds as a sealed variant
-- (not a stringly `kind`). Distinct arms forbid confusing a denial with
-- an empty result set.
variant QueryResult {
  Rows       { matched : Integer, returned : Integer }
  Denied     { reason : String }
  QueryError { detail : String }
}
