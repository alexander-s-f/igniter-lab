-- LAB-IGNITER-WEB-ROUTING-LOWERING-P4 fixture — generic web request/decision types.
-- No SparkCRM, no persistence, no live effects. The Decision variant maps 1:1 to ServerDecision.
module WebTypes

type Request {
  method          : String
  path            : String
  body            : String
  correlation_id  : String
  idempotency_key : String
}

variant Decision {
  Respond      { status : Integer, body : String }
  InvokeEffect { target : String, input : String, idempotency_key : String }
}
