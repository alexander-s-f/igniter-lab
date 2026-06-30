-- LAB-IGNITER-WEB-ROUTING-NESTED-P18 fixture — nested account/todo handlers (pure; routing pressure
-- only). Proves the two-capture nested case compiles: scoped `:account_id` + resource `:todo_id` arrive
-- as positional Option[String] params in path order (account_id first, todo_id second).
module AccountHandlers

import IgWebPrelude

pure contract AccountTodosIndex {
  input req : Request
  input account_id : Option[String]
  compute d : Decision = Respond { status: 200, body: "[]" }
  output d : Decision
}

pure contract AccountTodoCreate {
  input req : Request
  input account_id : Option[String]
  compute d : Decision = InvokeEffect { target: "account-todo-create", input: req.body, idempotency_key: req.idempotency_key }
  output d : Decision
}

pure contract AccountTodoShow {
  input req : Request
  input account_id : Option[String]
  input todo_id : Option[String]
  compute d : Decision = Respond { status: 200, body: "todo" }
  output d : Decision
}

pure contract AccountTodoDone {
  input req : Request
  input account_id : Option[String]
  input todo_id : Option[String]
  compute d : Decision = InvokeEffect { target: "account-todo-done", input: req.body, idempotency_key: req.idempotency_key }
  output d : Decision
}

pure contract AccountTodosOverdue {
  input req : Request
  input account_id : Option[String]
  compute d : Decision = Respond { status: 200, body: "[]" }
  output d : Decision
}
