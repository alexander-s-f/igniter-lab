module QueryEngineExample
import QueryEngineTypes
import QueryEngineExecute

-- ============================================================
-- Example: SELECT active customers in Miami older than 30
-- ============================================================
-- Rows, predicates, and the plan are built via factories (inline/array
-- record literals infer to Unknown in the Rust TC — the MakeXxx pattern).
-- The capability decision is injected (1 = granted).

pure contract MakeRow {
  input id : Integer
  input age : Integer
  input city : String
  input active : Integer
  compute r = { id: id, age: age, city: city, active: active }
  output r : Row
}

pure contract MakePred {
  input field : String
  input op : String
  input num : Integer
  input str : String
  compute p = { field: field, op: op, num: num, str: str }
  output p : FilterPredicate
}

pure contract MakeOrder {
  input field : String
  input direction : String
  compute o = { field: field, direction: direction }
  output o : OrderBy
}

-- ── ACTIVE customers in Miami, age > 30 (granted) ───────────
contract RunQuery {
  compute r1 = call_contract("MakeRow", 1, 42, "Miami",  1)
  compute r2 = call_contract("MakeRow", 2, 25, "Miami",  1)   -- too young
  compute r3 = call_contract("MakeRow", 3, 51, "Austin", 1)   -- wrong city
  compute r4 = call_contract("MakeRow", 4, 38, "Miami",  0)   -- inactive
  compute r5 = call_contract("MakeRow", 5, 60, "Miami",  1)
  compute rows = [r1, r2, r3, r4, r5]

  compute f_city   = call_contract("MakePred", "city",   "eq", 0, "Miami")
  compute f_age    = call_contract("MakePred", "age",    "gt", 30, "")
  compute f_active = call_contract("MakePred", "active", "eq", 1, "")
  compute preds = [f_city, f_age, f_active]

  compute order = call_contract("MakeOrder", "age", "desc")
  compute plan : QueryPlan = {
    source_table: "customers",
    filters: preds,
    order: order,
    limit: 10
  }

  -- expect: r1 and r5 match → Rows { matched: 2, returned: 2 }
  compute result = call_contract("ExecuteQuery", plan, rows, 1)
  output result : QueryResult
}

-- ── DENIED: capability not granted ──────────────────────────
contract RunDenied {
  compute r1 = call_contract("MakeRow", 1, 42, "Miami", 1)
  compute rows = [r1]
  compute f = call_contract("MakePred", "active", "eq", 1, "")
  compute preds = [f]
  compute order = call_contract("MakeOrder", "id", "asc")
  compute plan : QueryPlan = { source_table: "customers", filters: preds, order: order, limit: 10 }
  compute result = call_contract("ExecuteQuery", plan, rows, 0)
  output result : QueryResult
}

entrypoint RunQuery
