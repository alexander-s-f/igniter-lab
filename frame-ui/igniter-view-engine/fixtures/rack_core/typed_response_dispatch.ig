module Rack.P12.TypedResponseDispatch

-- ── Response type ─────────────────────────────────────────────────────────────
-- RackResponse: single structured output value for Rack-like handlers.
-- status:  HTTP status code (200, 404, etc.)
-- body:    response body as plain text / string
--
-- Headers are deferred — Map/Collection semantics for header pairs require
-- stronger type support (P13 work item).
type RackResponse {
  status: Integer,
  body: String
}

-- ── Handler contracts ──────────────────────────────────────────────────────────
-- Each handler takes method + path and returns a single RackResponse output.
-- P11: the module contract registry will store single_output_type = RackResponse
-- for each handler so dispatchers can resolve the type statically.

-- GetRootHandler: GET / → 200 OK
pure contract GetRootHandler {
  input  method : String
  input  path   : String
  compute status   = 200
  compute body_val = "OK"
  compute response = { status: status, body: body_val }
  output response : RackResponse
}

-- NotFoundHandler: catch-all → 404 Not Found
pure contract NotFoundHandler {
  input  method : String
  input  path   : String
  compute status   = 404
  compute body_val = "Not Found"
  compute response = { status: status, body: body_val }
  output response : RackResponse
}

-- MethodNotAllowedHandler: POST to GET-only route → 405
pure contract MethodNotAllowedHandler {
  input  method : String
  input  path   : String
  compute status   = 405
  compute body_val = "Method Not Allowed"
  compute response = { status: status, body: body_val }
  output response : RackResponse
}

-- ── Dispatcher contracts ───────────────────────────────────────────────────────

-- StaticGetDispatcher: literal callee dispatch — P11 resolves output to RackResponse.
-- Calls GetRootHandler via literal `call_contract("GetRootHandler", ...)`.
-- The TypeChecker (P11) resolves the compute node type to RackResponse rather than
-- Unknown, using the module contract registry.
pure contract StaticGetDispatcher {
  input  method : String
  input  path   : String
  compute response = call_contract("GetRootHandler", method, path)
  output response : RackResponse
}

-- StaticNotFoundDispatcher: literal callee dispatch for 404.
-- Proves P11 resolution works for multiple different literal callees.
pure contract StaticNotFoundDispatcher {
  input  method : String
  input  path   : String
  compute response = call_contract("NotFoundHandler", method, path)
  output response : RackResponse
}

-- DynamicDispatcher: dynamic callee (Tier 2) — compute node stays Unknown.
-- Proves the Tier 2 path still compiles and does not resolve to RackResponse.
pure contract DynamicDispatcher {
  input  method       : String
  input  path         : String
  input  handler_name : String
  compute response = call_contract(handler_name, method, path)
  output response : RackResponse
}
