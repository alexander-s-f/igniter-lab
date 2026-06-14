module WebRouterTypes

-- ============================================================
-- web_router — a pure HTTP router + response composer (Rack-shaped)
-- ============================================================
-- Pulled from `igniter-view-engine/fixtures/rack_core` (route_dispatch,
-- http_result_rack_composition). A request {method, path} is routed by pure
-- data-plane logic (stdlib.text starts_with / byte_length / ==) to a handler
-- OUTCOME, which is composed into an HTTP response.
--
-- IMPROVEMENT vs the fixture: the P14 fixture carried the handler outcome as a
-- stringly `kind : String` + a 6-way nested-if mapper. Here the outcome is a
-- sealed `ContractResult` variant + `match` — exhaustive and fail-closed. This
-- is the relief the fixture's KDR pressure was asking for.
--
-- PURE CORE only. No accept loop, no sockets, no IO. Headers (a Map) are NOT
-- modeled (Map construction gap) — response is {status, body}. See
-- PRESSURE_REGISTRY.md.

type HttpRequest {
  method : String   -- "GET" | "POST" | ...
  path   : String   -- "/", "/articles", "/articles/42", ...
}

type HttpResponse {
  status : Integer
  body   : String
}

-- ── Handler outcome (the KDR envelope, as a sealed variant) ──
-- PRESSURE WR-P01: the 6 Rack outcomes are a sealed sum, not a `kind:String`.
-- match forbids confusing a 404 with a 502.
variant ContractResult {
  Found       { body : String }
  Created     { body : String }
  NotFound    { }
  Denied      { }
  UpstreamErr { }
  Unavailable { }
}
