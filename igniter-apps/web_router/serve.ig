module WebRouterServe
import WebRouterTypes
import stdlib.text.{ starts_with, byte_length }

-- ============================================================
-- Routing + response composition (pure data plane)
-- ============================================================

-- Route table (fixtures/rack_core/route_dispatch.ig):
--   GET  /              → Found "home"
--   GET  /articles/:id  → Found "article"        (any path under /articles/)
--   POST /articles      → Created "article created"
--   GET/POST wrong method on a known route → Denied-as-405 mapping (NotFound here)
--   unknown path        → NotFound
--
-- PRESSURE WR-P02: route + method matching uses stdlib.text `starts_with` and
-- `byte_length` (== works for String) — there is no real path-param parser
-- (`split` does not infer `Collection[String]`, WR-P04), so ":id" routes match
-- by prefix only.
pure contract Handle {
  input req : HttpRequest

  compute result : ContractResult =
    if starts_with(req.path, "/articles/") {
      if req.method == "GET" {
        Found { body: "article" }
      } else {
        NotFound { }
      }
    } else {
      if req.path == "/articles" {
        if req.method == "POST" {
          Created { body: "article created" }
        } else {
          NotFound { }
        }
      } else {
        if byte_length(req.path) > 1 {
          NotFound { }
        } else {
          Found { body: "home" }
        }
      }
    }
  output result : ContractResult
}

-- Compose the handler outcome into an HTTP response.
-- PRESSURE WR-P01 (relieved): a single exhaustive `match`, not a nested
-- if-chain over a stringly kind.
pure contract Respond {
  input result : ContractResult
  compute resp : HttpResponse = match result {
    Found       { body } => { status: 200, body: body }
    Created     { body } => { status: 201, body: body }
    NotFound    {}       => { status: 404, body: "Not Found" }
    Denied      {}       => { status: 403, body: "Forbidden" }
    UpstreamErr {}       => { status: 502, body: "Bad Gateway" }
    Unavailable {}       => { status: 503, body: "Service Unavailable" }
  }
  output resp : HttpResponse
}

-- Full pipeline: request → response.
pure contract Serve {
  input req : HttpRequest
  compute result = call_contract("Handle", req)
  compute resp = call_contract("Respond", result)
  output resp : HttpResponse
}
