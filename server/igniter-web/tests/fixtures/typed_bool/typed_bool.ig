-- LAB-TODOAPP-VIEW-TYPED-BOOL-PROJECTION-P53 fixture — the typed-`Bool` `done` lane (DB-free harness).
--
-- Proves: a host `Boolean` decode-kind crosses into an `.ig` `Bool` field, and app logic branches on it with
-- REAL Bool semantics (`filter(t -> t.done == false/true)`), not a string compare. Returns a typed JSON
-- summary via `RespondJson` (the P50 generic arm). This lane is NOT product-configurable yet — `host.toml`
-- allowlists fields untyped (→ Text), so the Boolean kind is supplied via `allow_source_typed` in the test
-- harness only; the shipped list/show API stays `done : String`. No DB, no Bool-string parsing, no truthy
-- coercion — `done` is a real `Bool`.
module TypedBool

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

-- The app row declares `done : Bool` — the host `Boolean` kind must be assignable to it (else drift).
type TodoBoolRow {
  id         : String
  account_id : String
  title      : String
  done       : Bool
}

type DatasetMeta {
  source    : String
  count     : Integer
  truncated : Bool
}

-- A typed JSON summary the digest returns as the response body root (RespondJson).
type TodoBoolSummary {
  total       : Integer
  pending     : Integer
  done_count  : Integer
  all_done    : Bool
}

pure contract MakeFilter {
  input field : String
  input op    : String
  input value : String
  compute f = { field: field, op: op, value: value }
  output f : QueryFilter
}

pure contract ListBoolTodos {
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

-- Entry → ReadThen → typed Bool continuation (through the normal runner contour).
pure contract FetchBoolTodos {
  input req : Request
  compute account_id : String = req.path
  compute plan = call_contract("ListBoolTodos", account_id)
  compute d : Decision = ReadThen { plan: plan, then: "TodoBoolDigest", carry: "" }
  output d : Decision
}

-- The typed Bool digest: `filter` on a real `Bool` field in BOTH directions, returned as a typed summary.
-- `all_done = (pending == 0) AND (total > 0)` — proves a Bool computed from Integer compares crosses cleanly.
pure contract TodoBoolDigest {
  input req  : Request
  input rows : Collection[TodoBoolRow]
  input meta : DatasetMeta
  compute total       : Integer = count(rows)
  compute pending_rows = filter(rows, t -> t.done == false)
  compute done_rows    = filter(rows, t -> t.done == true)
  compute pending     : Integer = count(pending_rows)
  compute done_count  : Integer = count(done_rows)
  compute all_done : Bool = if total == 0 {
    false
  } else {
    pending == 0
  }
  compute summary : TodoBoolSummary = {
    total: total, pending: pending, done_count: done_count, all_done: all_done
  }
  compute d : Decision = RespondJson { status: 200, body: summary }
  output d : Decision
}
