module Rack.P3.DirectCall

-- Lab-only gap-characterization fixture.
-- CLOSED: lab-only, gap-characterization only, no canon claim, no stable API.
--
-- Dispatcher attempts to call HelloHandler as a function.
-- This is NOT valid Igniter syntax for cross-contract dispatch.
-- Expected: TypeChecker gap at call resolution (OOF-TY0 or similar).
-- A PASS in LAB-RACK-P3 means the gap is precisely confirmed, not that it works.

pure contract HelloHandler {
  input  method : String
  input  path   : String
  compute status_code = 200
  output status_code  : Integer
}

pure contract Dispatcher {
  input  method : String
  input  path   : String
  compute result = HelloHandler(method, path)
  output result : Integer
}
