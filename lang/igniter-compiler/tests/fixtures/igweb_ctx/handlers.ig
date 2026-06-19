-- LAB-IGNITER-WEB-CONTEXT-COMPOSITION-P26 fixture — `let`/`guard` context composition (pure; routing
-- pressure only). `ReqInfo` is an infallible `let`; `LoadAccount` is a fallible `guard` returning the
-- built-in `Result[String, Decision]` (P24-safe `if { ok } else { err }`). Handlers receive the hoisted
-- `req_info`, the guard's `account` value, and any unconsumed path captures — all by explicit name.
module ContextHandlers

import IgWebPrelude

pure contract ReqInfo {
  input req : Request
  compute info : String = "req"
  output info : String
}

pure contract LoadAccount {
  input req        : Request
  input req_info   : String
  input account_id : Option[String]
  compute ok_account : Bool = if or_else(account_id, "") == "" { false } else { true }
  compute account : String = or_else(account_id, "none")
  compute r : Result[String, Decision] = if ok_account {
    ok(account)
  } else {
    err(Respond { status: 404, body: "account not found" })
  }
  output r : Result[String, Decision]
}

pure contract TodoIndex {
  input req      : Request
  input req_info : String
  input account  : String
  compute d : Decision = Respond { status: 200, body: account }
  output d : Decision
}

pure contract TodoShow {
  input req      : Request
  input req_info : String
  input account  : String
  input todo_id  : Option[String]
  compute d : Decision = Respond { status: 200, body: or_else(todo_id, "none") }
  output d : Decision
}

pure contract TodoCreate {
  input req      : Request
  input req_info : String
  input account  : String
  compute d : Decision = InvokeEffect { target: "todo-create", input: account, idempotency_key: req.idempotency_key }
  output d : Decision
}
