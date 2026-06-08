module Rack.P4.PathParamExtract

-- Lab-only path parameter extraction contract.
-- CLOSED: lab-only, no canon claim, no stable-API surface.
--
-- Proves that :id-style path parameter extraction is expressible as a pure
-- contract using data-plane stdlib ops: split(path, "/") + last(segments).
--
-- split("/articles/42", "/") → ["", "articles", "42"]
-- last([...])                → "42"   (as Option[String] — last() returns Option)
--
-- Examples:
--   /articles/42  → "42"
--   /articles/99  → "99"

pure contract PathParamExtract {
  input path : String

  compute segments = split(path, "/")
  compute param_id = last(segments)

  output param_id : Option[String]
}
