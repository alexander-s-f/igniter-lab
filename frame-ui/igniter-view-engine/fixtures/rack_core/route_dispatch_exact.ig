module Rack.P6.RouteDispatchExact

-- Lab-only exact route dispatch using idiomatic == equality.
-- CLOSED: lab-only, no canon claim, no stable-API surface, no network I/O.
--
-- LAB-RACK-P6: proves that the TypeChecker now accepts == for String types,
-- enabling idiomatic exact-match routing instead of starts_with workarounds.
--
-- Route table:
--   GET  /              → 200  (exact: path == "/")
--   GET  /articles/:id  → 200  (prefix: starts_with(path, "/articles/") + method == "GET")
--   POST /articles      → 201  (exact: path == "/articles" + method == "POST")
--   *    /missing       → 404  (no route matched)
--   POST /articles/:id  → 405  (prefix matched, method not allowed)
--
-- TypeChecker operators used:
--   ==  for String-to-String literal equality (path == "/", method == "GET", etc.)
--   starts_with for prefix match (still needed for :id param route)
--
-- No byte_length / < used here (proven separately in lt_integer_valid.ig).

pure contract RouteDispatchExact {
  input method : String
  input path   : String

  compute status_code =
    if path == "/" {
      200
    } else {
      if starts_with(path, "/articles/") {
        if method == "GET" { 200 } else { 405 }
      } else {
        if path == "/articles" {
          if method == "POST" { 201 } else { 405 }
        } else {
          404
        }
      }
    }

  output status_code : Integer
}
