-- igniter-web example app — handler contracts (authored product logic; pure, fixture data).
module TodoHandlers
import IgWebPrelude

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

pure contract TodoShow {
  input req : Request
  input id : Option[String]
  compute d : Decision = Respond { status: 200, body: or_else(id, "none") }
  output d : Decision
}

pure contract TodoDone {
  input req : Request
  input id : Option[String]
  compute d : Decision = InvokeEffect { target: "todo-done", input: or_else(id, "none"), idempotency_key: req.idempotency_key }
  output d : Decision
}
