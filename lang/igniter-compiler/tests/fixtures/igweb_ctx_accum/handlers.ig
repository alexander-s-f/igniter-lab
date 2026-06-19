-- LAB-IGNITER-WEB-CONTEXT-ACCUMULATION-P27 fixture — depth-2 same-name `guard ctx` accumulation. Each
-- guard takes the prior `Ctx` and returns an enriched `Ctx` (bare `{ field: value }` records under the
-- typed annotation), so the handler sees the latest accumulated context. P24-safe `if { ok } else { err }`.
module ContextAccumHandlers

import IgWebPrelude

type Ctx {
  req_info   : String
  user_id    : String
  account_id : String
}

pure contract ReqInfo {
  input req : Request
  compute info : String = "req"
  output info : String
}

pure contract RequireUserContext {
  input req      : Request
  input req_info : String
  compute ctx : Ctx = { req_info: req_info, user_id: "u1", account_id: "" }
  compute r : Result[Ctx, Decision] = ok(ctx)
  output r : Result[Ctx, Decision]
}

pure contract LoadAccountContext {
  input req        : Request
  input ctx        : Ctx
  input account_id : Option[String]
  compute ok_account : Bool = if or_else(account_id, "") == "" { false } else { true }
  compute enriched : Ctx = { req_info: ctx.req_info, user_id: ctx.user_id, account_id: or_else(account_id, "none") }
  compute r : Result[Ctx, Decision] = if ok_account {
    ok(enriched)
  } else {
    err(Respond { status: 404, body: "missing account" })
  }
  output r : Result[Ctx, Decision]
}

pure contract TodoIndex {
  input req : Request
  input ctx : Ctx
  compute d : Decision = Respond { status: 200, body: ctx.account_id }
  output d : Decision
}

pure contract TodoShow {
  input req     : Request
  input ctx     : Ctx
  input todo_id : Option[String]
  compute d : Decision = Respond { status: 200, body: or_else(todo_id, "none") }
  output d : Decision
}

pure contract TodoCreate {
  input req : Request
  input ctx : Ctx
  compute d : Decision = InvokeEffect { target: "todo-create", input: ctx.account_id, idempotency_key: req.idempotency_key }
  output d : Decision
}
