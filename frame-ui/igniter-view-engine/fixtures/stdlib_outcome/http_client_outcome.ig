module Lab.StdlibOutcome.Http

-- LAB-STDLIB-OUTCOME-P1: Outcome Helpers Stdlib Pressure Proof.
--
-- Domain: Network / HTTP client (cross-domain inventory anchor 1 of 3).
--
-- Purpose: Demonstrates the stringly `kind` classification pattern that
-- stdlib.outcome helpers are designed to reduce.  Every KDR record in this
-- domain carries a `kind: String` field drawn from the PROP-047 stable-term
-- vocabulary and from HTTP-domain-local kinds.
--
-- PROP-047 stable terms present in this domain:
--   "denied"                 -- auth/capability gate refused before dispatch
--   "timed_out"              -- clock elapsed (pre- or post-dispatch; Covenant P15)
--   "unknown_external_state" -- dispatch confirmed, no acknowledgement received
--   "system_error"           -- infrastructure fault (connection refused, DNS fail)
--   "query_error"            -- malformed request (bad URL scheme, invalid header)
--
-- HTTP-domain-local kinds (must NOT be falsely collapsed by generic helpers):
--   "ok"                     -- 2xx response received
--   "redirect"               -- 3xx; location metadata required
--   "rate_limited"           -- 429; retry_after field valid
--
-- Authority: LAB-ONLY.  No canon implementation.  No stdlib entry created.
-- No compiler/VM/parser/TypeChecker change.
-- Depends: PROP-047-P2, LAB-EPISTEMIC-OUTCOME-P2, LAB-FAILURE-TAXONOMY-P4.

-- ── Outcome record type ────────────────────────────────────────────────────────

-- HttpOutcome: KDR-like record for HTTP client results.
--   kind:             PROP-047 stable term or HTTP-domain-local kind
--   request_id:       opaque reference (for reconciliation gate)
--   dispatch_started: "true" when request was sent; "false" when timed out pre-send
--   message:          human-readable detail (not used for routing)
type HttpOutcome {
  dispatch_started: String,
  kind:             String,
  message:          String,
  request_id:       String,
  retry_after:      String,
  status_code:      String
}

-- ── Stringly kind contracts (what helpers would replace) ───────────────────────

-- Extract the outcome kind as-is — current stringly pattern.
-- stdlib.outcome.kind(outcome) would replace this.
pure contract http_outcome_kind(outcome: HttpOutcome) -> String {
  outcome.kind
}

-- Classify for routing — current stringly pattern across all HTTP outcomes.
-- Shows the verbosity and duplication that helpers address.
pure contract http_classify_for_route(outcome: HttpOutcome) -> String {
  outcome.kind
}
