-- LAB-IGNITER-WEB-ROUTING-LOWERING-P4 fixture — Todo handlers (pure; routing pressure only).
-- Handlers return fixed Decisions; the point is route lowering, not application state. Param-carrying
-- handlers accept the captured id as Option[String] (capture returns Option[String]).
module TodoHandlers

import WebTypes

pure contract Health {
  input req : Request
  compute d : Decision = Respond { status: 200, body: "ok" }
  output d : Decision
}

pure contract TodoIndex {
  input req : Request
  compute d : Decision = Respond { status: 200, body: "[]" }
  output d : Decision
}

pure contract TodoCreate {
  input req : Request
  compute d : Decision = InvokeEffect { target: "todo-create", input: req.body, idempotency_key: req.idempotency_key }
  output d : Decision
}

pure contract TodoShow {
  input req : Request
  input id : Option[String]
  compute d : Decision = Respond { status: 200, body: "todo" }
  output d : Decision
}

pure contract TodoDone {
  input req : Request
  input id : Option[String]
  compute d : Decision = InvokeEffect { target: "todo-done", input: req.body, idempotency_key: req.idempotency_key }
  output d : Decision
}
