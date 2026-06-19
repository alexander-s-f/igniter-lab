module Rack.P13.NominalRecordTypeChecking

-- ── Named record type ──────────────────────────────────────────────────────────
-- RackResponse: the same type used in P12, re-declared here for isolation.
type RackResponse {
  status: Integer,
  body: String
}

-- ── Positive cases (compile cleanly; response resolves to RackResponse) ────────

-- Case 1: Valid literal using ref expressions.
-- status and body_val are typed (Integer, String) before response is built.
-- check_record_literal_shape validates both fields; upgrade → RackResponse.
pure contract OkHandler {
  input  method : String
  input  path   : String
  compute status   = 200
  compute body_val = "OK"
  compute response = { status: status, body: body_val }
  output response : RackResponse
}

-- Case 2: Valid literal with inline literal values (no intermediate compute nodes).
-- infer_field_expr_type returns Integer for `200`, String for `"Direct"`.
-- check_record_literal_shape validates; upgrade → RackResponse.
pure contract DirectLiteralHandler {
  input  method : String
  input  path   : String
  compute response = { status: 200, body: "Direct" }
  output response : RackResponse
}

-- Case 3: Complex field expression (status = code + 0).
-- infer_field_expr_type returns None for BinaryOp — field type check skipped.
-- No missing/extra field errors → upgrade → RackResponse.
-- Proves Unknown-compat for field expressions not resolvable to primitive types.
pure contract ComplexFieldHandler {
  input  method : String
  input  path   : String
  input  code   : Integer
  compute body_val = "Complex"
  compute response = { status: code + 0, body: body_val }
  output response : RackResponse
}

-- Case 4: Dispatcher using literal call_contract — P11 Tier 1 still resolves.
-- StaticGetDispatcher depends on OkHandler declared above.
pure contract StaticDispatcherP13 {
  input  method : String
  input  path   : String
  compute response = call_contract("OkHandler", method, path)
  output response : RackResponse
}

-- Case 5: Dynamic dispatcher — Tier 2 stays Unknown.
-- Proves nominal record checking does NOT interfere with Tier 2 call_contract.
pure contract DynamicDispatcherP13 {
  input  method       : String
  input  path         : String
  input  handler_name : String
  compute response = call_contract(handler_name, method, path)
  output response : RackResponse
}
