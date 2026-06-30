module QueryEngineExecute
import QueryEngineTypes
import QueryEngineEval

-- ============================================================
-- Execution — plan + rows + capability → QueryResult (denial-as-data)
-- ============================================================
-- PRESSURE QE-P05: NO sort primitive exists, so `plan.order` is carried but
-- not applied (rows are returned in input order). Multi-key stable sort is
-- the deeper gap — it wants a `sort_by` stdlib over `Collection[T]`.

pure contract ClampLimit {
  input matched : Integer
  input limit : Integer
  compute returned = if matched > limit { limit } else { matched }
  output returned : Integer
}

pure contract ExecuteQuery {
  input plan : QueryPlan
  input rows : Collection[Row]
  input cap_granted : Integer

  compute kept = call_contract("FilterRows", rows, plan.filters)
  compute matched = call_contract("CountRows", kept)
  compute returned = call_contract("ClampLimit", matched, plan.limit)

  -- denial-as-data: a missing capability is a typed result, not an exception
  compute result : QueryResult = if cap_granted == 0 {
    Denied { reason: "storage capability not granted" }
  } else {
    Rows { matched: matched, returned: returned }
  }
  output result : QueryResult
}

-- Flattened result label (for logging only — NOT the routing key).
pure contract ResultKind {
  input r : QueryResult
  compute kind : String = match r {
    Rows {}       => "rows"
    Denied {}     => "denied"
    QueryError {} => "query_error"
  }
  output kind : String
}
