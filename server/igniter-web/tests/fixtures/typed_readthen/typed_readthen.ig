-- LAB-IGNITER-DATA-PROJECTION-BOOT-RECONCILIATION-P7 fixture — typed + legacy ReadThen in ONE app.
--
-- P6 proved the typed crossing as a direct harness call. P7 lifts it into the normal `ReadThen` runner
-- contour: an entry contract returns `ReadThen { plan, then, carry }`, and the HOST inspects the named
-- continuation's COMPILED inputs to choose the crossing — typed `rows : Collection[TodoRow]` (+
-- `meta : DatasetMeta`) or legacy `rows_json : String` — then reconciles the host read policy against the
-- app row type before dispatch. Both continuations live here so one loaded app proves the host routes each
-- correctly from metadata alone. No capability id / scope / DSN / SQL — only a logical `source`.
module TypedReadThen

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

type TodoRow {
  id         : String
  account_id : String
  title      : String
  done       : Bool
  rank       : Integer
}

type DatasetMeta {
  source    : String
  count     : Integer
  truncated : Bool
}

pure contract MakeFilter {
  input field : String
  input op    : String
  input value : String
  compute f = { field: field, op: op, value: value }
  output f : QueryFilter
}

-- Query intent: list this account's todos → a structural QueryPlan naming the typed columns.
pure contract ListTypedTodos {
  input account_id : String
  compute projection : Collection[String] = ["id", "account_id", "title", "done", "rank"]
  compute f_acct = call_contract("MakeFilter", "account_id", "eq", account_id)
  compute filters : Collection[QueryFilter] = [f_acct]
  compute plan : QueryPlan = {
    source: "todos", op: "select",
    projection: projection, filters: filters, limit: 50
  }
  output plan : QueryPlan
}

pure contract TodoRowItem {
  input r : TodoRow
  compute item : ViewItem = { key: r.id, label: r.title }
  output item : ViewItem
}

-- ── Typed lane: entry → ReadThen → typed continuation ───────────────────────────────────────────
-- Entry: build the plan and hand off to the host typed read. The host routes to the typed crossing because
-- `TypedTodoIndexFromRows` declares `rows : Collection[TodoRow]` (+ `meta : DatasetMeta`).
pure contract FetchTypedTodos {
  input req : Request
  compute account_id : String = req.path
  compute plan = call_contract("ListTypedTodos", account_id)
  compute d : Decision = ReadThen { plan: plan, then: "TypedTodoIndexFromRows", carry: "" }
  output d : Decision
}

-- Typed continuation: the host re-enters with materialized typed rows + meta. App owns not-found over the
-- typed collection (empty → 404); a found set maps the PENDING rows to a typed View tagged with the source.
pure contract TypedTodoIndexFromRows {
  input req  : Request
  input rows : Collection[TodoRow]
  input meta : DatasetMeta
  compute total   : Integer = count(rows)
  compute pending = filter(rows, r -> r.done == false)
  compute items : Collection[ViewItem] = map(pending, r -> call_contract("TodoRowItem", r))
  compute v : View = { kind: meta.source, title: "todos", items: items }
  compute d : Decision = if total == 0 {
    Respond { status: 404, body: "no todos" }
  } else {
    RespondView { status: 200, view: v }
  }
  output d : Decision
}

-- ── Legacy lane: entry → ReadThen → stringly continuation (must still route to the rows_json path) ─
pure contract FetchLegacyTodos {
  input req : Request
  compute account_id : String = req.path
  compute plan = call_contract("ListTypedTodos", account_id)
  compute d : Decision = ReadThen { plan: plan, then: "LegacyTodoIndexFromRows", carry: "" }
  output d : Decision
}

-- Legacy continuation: the host re-enters with the read rows as a JSON string (the pre-P6 boundary).
pure contract LegacyTodoIndexFromRows {
  input req       : Request
  input rows_json : String
  compute d : Decision = if rows_json == "[]" {
    Respond { status: 404, body: "no todos" }
  } else {
    Respond { status: 200, body: rows_json }
  }
  output d : Decision
}
