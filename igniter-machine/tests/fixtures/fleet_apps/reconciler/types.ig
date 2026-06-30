module ReconcilerTypes

-- ============================================================
-- reconciler — epistemic reconciliation service (pure core)
-- ============================================================
-- Distributed-outcome reconciliation under the "unknown external state"
-- doctrine (Covenant P15): a TIMEOUT is not a FAILURE, a lost confirmation
-- is not a SUCCESS, and MODEL confidence is not REAL confirmation.
--
-- A request is dispatched to an external system; the reply may be acked,
-- 5xx, or LOST. The core CLASSIFIES the raw signal into an epistemic
-- `Outcome`, then ROUTES it to an action — retrying only when it is SAFE,
-- reconciling while budget remains, and refusing to upgrade model evidence
-- to real success ("no upward coercion").
--
-- Sources (lab fixtures): epistemic_outcome/, outcome_variant/,
-- failure_taxonomy/network_timeout_unknown_state.ig.
--
-- PURE CORE only. Every external probe result is INJECTED as a
-- `DispatchSignal`; metadata arrives as `Map[String,String]`. No clock,
-- no network, no retries actually performed. See PRESSURE_REGISTRY.md.

-- ── The raw result of one dispatch attempt (injected) ───────
-- dispatch_started: 1 once the request left our process.
-- ack_received:     1 if the external system replied at all.
-- status_code:      HTTP-ish reply code (only meaningful if acked).
-- evidence_kind:    "real" (observed at the source of truth) |
--                   "model" (inferred by our side, not confirmed) | "none".
type DispatchSignal {
  dispatch_started : Integer
  ack_received     : Integer
  status_code      : Integer
  evidence_kind    : String
  resource         : String
}

-- ── The reconciliation context (threaded across attempts) ───
type ReconContext {
  request_id      : String
  idempotency_key : String   -- "" if absent
  attempt         : Integer
  max_attempts    : Integer
}

-- ── The epistemic outcome (the heart — a sealed sum of truths) ──
-- PRESSURE RC-P01: these arms CANNOT be a stringly `kind : String`.
-- Each is a distinct epistemic state with distinct routing and distinct
-- payload. variant + match is load-bearing, not optional.
variant Outcome {
  SucceededReal      { request_id : String, resource : String }
  SucceededModel     { request_id : String, resource : String }
  FailedRetryable    { request_id : String, idempotency_key : String, attempt : Integer }
  UnknownWithBudget  { request_id : String, attempt : Integer, budget_remaining : Integer }
  UnknownNoBudget    { request_id : String, attempt : Integer }
  UpstreamUnavailable{ request_id : String }
  Denied             { request_id : String, reason : String }
}

-- ── A reconciliation receipt (the audit record) ─────────────
type ReconReceipt {
  request_id : String
  action     : String   -- accept | retry | reconcile_again | escalate_human | needs_human_review | hold
  outcome_kind : String -- a flattened label for logging (NOT the routing key)
  attempt    : Integer
  trace_id   : String
}
