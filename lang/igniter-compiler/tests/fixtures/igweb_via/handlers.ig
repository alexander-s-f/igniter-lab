-- LAB-IGNITER-WEB-ROUTING-VIA-P20 fixture — route-level guard/context pipeline (pure; routing pressure
-- only). The guard returns the built-in sealed `Result[Option[String], Decision]`, constructed with
-- `ok(...)` / `err(...)`: the `Ok { value }` arm carries the loaded context, the `Err { error }` arm
-- carries the short-circuit `Decision`. Handlers receive the loaded context positionally (after `req`),
-- then any unconsumed path captures. (The context type is `Option[String]` to keep the fixture about the
-- guard-match lowering, not record construction.)
module ViaHandlers

import IgWebPrelude

pure contract LoadAccount {
  input req        : Request
  input account_id : Option[String]
  compute r : Result[Option[String], Decision] = ok(account_id)
  output r : Result[Option[String], Decision]
}

pure contract AccountTodosIndex {
  input req     : Request
  input account : Option[String]
  compute d : Decision = Respond { status: 200, body: "[]" }
  output d : Decision
}

pure contract AccountTodoShow {
  input req     : Request
  input account : Option[String]
  input todo_id : Option[String]
  compute d : Decision = Respond { status: 200, body: "todo" }
  output d : Decision
}

pure contract AccountTodoCreate {
  input req     : Request
  input account : Option[String]
  compute d : Decision = InvokeEffect { target: "account-todo-create", input: req.body, idempotency_key: req.idempotency_key }
  output d : Decision
}
