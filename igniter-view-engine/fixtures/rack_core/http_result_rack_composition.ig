module Rack.P14.HttpResultComposition

-- LAB-RACK-P14: Rack-shaped upstream HttpResult / ContractResult composition proof
--
-- Proves that Rack-shaped handler contracts can map a typed ContractResult envelope
-- (kind: String, data_body: String, resp_headers: Map[String,String]) into a typed
-- FullRackResponse { status: Integer, headers: Map[String,String], body: String }
-- across all 6 ContractResult branch outcomes.
--
-- Uses:
--   map_get(Map[String,String], key) → Option[String]    (TypeChecker: proved in LAB-MAP-RUST-P1)
--   or_else(Option[String], default) → String             (TypeChecker: proved in LAB-MAP-RUST-P1)
--   P13 nominal record type checking: RecordLiteral → FullRackResponse
--   P11 two-tier dispatch policy: Tier 1 → FullRackResponse, Tier 2 → Unknown
--
-- ContractResult kinds:
--   found              → 200 OK
--   created            → 201 Created
--   not_found          → 404 Not Found
--   capability_denied  → 403 Forbidden
--   upstream_error     → 502 Bad Gateway
--   upstream_unavailable → 503 Service Unavailable
--
-- VM gap: map_get bytecode not implemented. VM execution covers non-map_get paths.
-- lab-only. No Rack compatibility claim. No production runtime claim.

-- ── Response type ─────────────────────────────────────────────────────────────

type FullRackResponse {
  body    : String,
  headers : Map[String, String],
  status  : Integer
}

-- ── Per-branch response builder contracts ─────────────────────────────────────
-- Each builder is a pure contract that constructs a FullRackResponse for
-- one ContractResult outcome. Provides Tier 1 call_contract targets.

pure contract FoundResponseBuilder {
  input  data_body    : String
  input  resp_headers : Map[String, String]
  compute body     = data_body
  compute hdrs     = resp_headers
  compute code     = 200
  compute response = { body: body, headers: hdrs, status: code }
  output response : FullRackResponse
}

pure contract CreatedResponseBuilder {
  input  data_body    : String
  input  resp_headers : Map[String, String]
  compute body     = data_body
  compute hdrs     = resp_headers
  compute code     = 201
  compute response = { body: body, headers: hdrs, status: code }
  output response : FullRackResponse
}

pure contract NotFoundResponseBuilder {
  input  resp_headers : Map[String, String]
  compute body     = "Not Found"
  compute hdrs     = resp_headers
  compute code     = 404
  compute response = { body: body, headers: hdrs, status: code }
  output response : FullRackResponse
}

pure contract DeniedResponseBuilder {
  input  resp_headers : Map[String, String]
  compute body     = "Forbidden"
  compute hdrs     = resp_headers
  compute code     = 403
  compute response = { body: body, headers: hdrs, status: code }
  output response : FullRackResponse
}

pure contract UpstreamErrorBuilder {
  input  resp_headers : Map[String, String]
  compute body     = "Bad Gateway"
  compute hdrs     = resp_headers
  compute code     = 502
  compute response = { body: body, headers: hdrs, status: code }
  output response : FullRackResponse
}

pure contract UnavailableBuilder {
  input  resp_headers : Map[String, String]
  compute body     = "Service Unavailable"
  compute hdrs     = resp_headers
  compute code     = 503
  compute response = { body: body, headers: hdrs, status: code }
  output response : FullRackResponse
}

-- ── Branch mapper: ContractResult envelope → FullRackResponse ─────────────────
-- Maps all 6 ContractResult kind values to their corresponding HTTP status codes
-- and body strings via nested if-then-else. P13 upgrades the output RecordLiteral
-- to FullRackResponse when all fields type-check.

pure contract ContractResultBranchMapper {
  input  kind         : String
  input  data_body    : String
  input  resp_headers : Map[String, String]

  -- Condition flags (String==String → Bool)
  compute is_found      = kind == "found"
  compute is_created    = kind == "created"
  compute is_nf         = kind == "not_found"
  compute is_denied     = kind == "capability_denied"
  compute is_error      = kind == "upstream_error"

  -- Status code branch (nested if-else; TypeChecker infers Integer from each leaf)
  compute resp_status =
    if is_found { 200 } else {
      if is_created { 201 } else {
        if is_nf { 404 } else {
          if is_denied { 403 } else {
            if is_error { 502 } else { 503 }
          }
        }
      }
    }

  -- Body branch (nested if-else; TypeChecker infers String from each leaf)
  compute resp_body =
    if is_found { data_body } else {
      if is_created { data_body } else {
        if is_nf { "Not Found" } else {
          if is_denied { "Forbidden" } else {
            if is_error { "Bad Gateway" } else { "Service Unavailable" }
          }
        }
      }
    }

  -- RecordLiteral: all fields typed → P13 upgrades to FullRackResponse
  compute response = {
    body:    resp_body,
    headers: resp_headers,
    status:  resp_status
  }

  output response : FullRackResponse
}

-- ── Headers-aware handler: map_get + or_else ──────────────────────────────────
-- Uses map_get to read the Content-Type header from resp_headers, falling back
-- to a caller-supplied default via or_else. Proves map_get → Option[String] and
-- or_else(Option[String], String) → String at TypeChecker level.
-- VM gap: map_get bytecode is not yet implemented; VM execution deferred.

pure contract HeadersAwareHandler {
  input  resp_headers : Map[String, String]
  input  fallback_ct  : String
  input  resp_body    : String

  -- map_get: Map[String,String] × String → Option[String]
  compute content_type_opt = map_get(resp_headers, "Content-Type")
  -- or_else: Option[String] × String → String
  compute content_type     = or_else(content_type_opt, fallback_ct)
  compute resp_status      = 200
  compute response         = {
    body:    content_type,
    headers: resp_headers,
    status:  resp_status
  }

  output response : FullRackResponse
}

-- ── Tier 1 dispatcher (static call_contract target) ───────────────────────────
-- Calls ContractResultBranchMapper by literal name. P11 Tier 1 policy resolves
-- the return type to FullRackResponse (registry lookup).

pure contract Tier1BranchDispatcher {
  input  kind         : String
  input  data_body    : String
  input  resp_headers : Map[String, String]

  compute response = call_contract("ContractResultBranchMapper", kind, data_body, resp_headers)

  output response : FullRackResponse
}

-- ── Tier 2 dispatcher (dynamic call_contract target) ──────────────────────────
-- Calls a contract by runtime-variable name. P11 Tier 2 policy: return type is
-- Unknown (callee name not known at compile time → no registry lookup).

pure contract Tier2BranchDispatcher {
  input  callee_name  : String
  input  kind         : String
  input  data_body    : String
  input  resp_headers : Map[String, String]

  compute response = call_contract(callee_name, kind, data_body, resp_headers)

  output response : FullRackResponse
}
