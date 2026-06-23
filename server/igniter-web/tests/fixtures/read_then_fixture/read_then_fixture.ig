-- LAB-IGNITER-WEB-READTHEN-DISPATCH-P11 fixture.
--
-- An explicit `.ig` staged-read app: entry emits `ReadThen`; host executes the read;
-- continuation decides based on rows. No new `.igweb` sugar — ReadThen authored directly.
-- Authority boundary: no cap-id, no connection string, no raw SQL, no DB handle here.
module ReadThenFixture

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

-- Entry: emits ReadThen so the host executes the read, then re-enters the continuation.
-- `req.path` stands in as the account_id (simplifies test wiring without route params).
pure contract FetchTodosEntry {
  input req : Request
  compute account_id = req.path
  compute projection : Collection[String] = ["id", "account_id", "title", "done"]
  compute f = { field: "account_id", op: "eq", value: account_id }
  compute filters : Collection[QueryFilter] = [f]
  compute plan = {
    source: "todos", op: "select",
    projection: projection, filters: filters, limit: 20
  }
  compute d : Decision = ReadThen { plan: plan, then: "FetchTodosContinuation", carry: "" }
  output d : Decision
}

-- Continuation: host re-enters here with rows_json; not-found (empty) is the app's product decision.
pure contract FetchTodosContinuation {
  input req       : Request
  input rows_json : String
  compute d : Decision = if rows_json == "[]" {
    Respond { status: 404, body: "not found" }
  } else {
    Respond { status: 200, body: rows_json }
  }
  output d : Decision
}

-- Pathological continuation that ALWAYS re-issues a ReadThen naming itself (P38 bound test): the host's
-- sequential-ReadThen loop must terminate it at MAX_READ_HOPS with a 500, never spin forever.
pure contract LoopForever {
  input req : Request
  compute projection : Collection[String] = ["id"]
  compute f = { field: "account_id", op: "eq", value: req.path }
  compute filters : Collection[QueryFilter] = [f]
  compute plan = {
    source: "todos", op: "select",
    projection: projection, filters: filters, limit: 1
  }
  compute d : Decision = ReadThen { plan: plan, then: "LoopForever", carry: "" }
  output d : Decision
}
