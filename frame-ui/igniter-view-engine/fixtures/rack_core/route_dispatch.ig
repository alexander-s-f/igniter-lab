module Rack.P4.RouteDispatch

-- Lab-only static route dispatch contract.
-- CLOSED: lab-only, no canon claim, no stable-API surface, no network I/O.
--
-- Proves that Rack-like route dispatch is expressible as a single pure contract
-- using data-plane logic only (nested if/else + starts_with + length).
-- No ContractRef runtime dispatch, no VM call-frame dispatch, no accept-loop.
--
-- TypeChecker gap note: == and < are not supported operators in current lab
-- compiler (OOF-TY0). Route and method dispatch uses starts_with and > instead:
--   starts_with(path,  "/articles/") → /articles/:id routes
--   starts_with(path,  "/articles")  → /articles exact (in else branch of above)
--   byte_length(path) > 1            → non-root path (byte_length("/") == 1; else → 404)
--   starts_with(method, "GET")       → GET method
--   starts_with(method, "POST")      → POST method
--
-- Note: byte_length is the canonical Text stdlib op (not legacy length).
-- byte_length("/") == 1; any longer path returns byte_length > 1.
--
-- Route table:
--   GET  /              → 200
--   GET  /articles/:id  → 200  (any path under /articles/)
--   POST /articles      → 201
--   *    /missing       → 404  (unknown path with byte_length > 1)
--   POST /articles/:id  → 405  (route exists, wrong method)

pure contract RouteDispatch {
  input method : String
  input path   : String

  compute status_code =
    if starts_with(path, "/articles/") {
      if starts_with(method, "GET") { 200 } else { 405 }
    } else {
      if starts_with(path, "/articles") {
        if starts_with(method, "POST") { 201 } else { 405 }
      } else {
        if byte_length(path) > 1 { 404 } else { 200 }
      }
    }

  output status_code : Integer
}
