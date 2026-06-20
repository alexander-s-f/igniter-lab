-- LAB-IGNITER-WEB-READ-GUARD-HOST-P6 fixture — the authored `.ig` read half (pure; no DB, no SQL).
--
-- A real query contract (`ListTodosByAccount -> QueryPlan`, the P2/P3 relational shape) and a real
-- continuation (`TodoIndexFromRows(req, rows_json) -> Decision`). The HOST harness runs the QueryPlan
-- through the fake `PostgresReadExecutor` and feeds the rows back as `rows_json` (P5's humble v0: rows as a
-- JSON string — typed row destructuring is deferred). The continuation owns not-found: empty rows → 404.
-- No capability id, scope, DSN, raw SQL, or DB handle here — only a logical `source` in the QueryPlan.
module ReadHarness

import IgWebPrelude

type QueryFilter {
  field : String
  op    : String
  value : String
}

type QueryPlan {
  source     : String
  op         : String
  projection : Collection[String]
  filters    : Collection[QueryFilter]
  limit      : Integer
}

pure contract MakeFilter {
  input field : String
  input op    : String
  input value : String
  compute f = { field: field, op: op, value: value }
  output f : QueryFilter
}

-- Query intent: "list this account's todos" → a structural QueryPlan (host executes it; no SQL here).
pure contract ListTodosByAccount {
  input account_id : String
  compute projection : Collection[String] = ["id", "account_id", "title", "done"]
  compute f_acct = call_contract("MakeFilter", "account_id", "eq", account_id)
  compute filters : Collection[QueryFilter] = [f_acct]
  compute plan : QueryPlan = {
    source: "todos", op: "select",
    projection: projection, filters: filters, limit: 50
  }
  output plan : QueryPlan
}

-- Continuation: the host re-enters here with the read rows as a JSON string. Not-found (empty rows) is
-- the APP's product decision (404); a found set returns 200 carrying the rows. No machine internals here.
pure contract TodoIndexFromRows {
  input req       : Request
  input rows_json : String
  compute d : Decision = if rows_json == "[]" {
    Respond { status: 404, body: "no todos" }
  } else {
    Respond { status: 200, body: rows_json }
  }
  output d : Decision
}
