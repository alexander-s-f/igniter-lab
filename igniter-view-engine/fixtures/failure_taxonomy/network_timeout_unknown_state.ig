module Lab.FailureTaxonomy.NetworkTimeout

-- LAB-FAILURE-TAXONOMY-P2: Network Timeout / Unknown External State Proof.
--
-- Provides the second-domain evidence requested by LAB-FAILURE-TAXONOMY-P1:
-- proves in the HTTP client / upstream-call domain that timeout and
-- lost-acknowledgement after dispatch MUST route to `unknown_external_state`,
-- not `system_error`, `upstream_error`, `upstream_unavailable`, or any failure kind.
--
-- Core claim (Covenant P15 — Timeout Is Not Failure):
--   dispatch_started == true  AND  ack_received == false
--     => kind: "unknown_external_state"
--
--   dispatch_started == false
--     => NOT unknown_external_state (capability denial or infrastructure fault)
--
-- Outcome kind vocabulary:
--   "ok"                     -- dispatched + ack + success response (confirmed)
--   "denied"                 -- capability policy refused BEFORE dispatch; deterministic
--   "upstream_error"         -- dispatched + ack + server error (known failure)
--   "not_found"              -- dispatched + ack + client error (known failure)
--   "upstream_unavailable"   -- dispatch NOT started; upstream unreachable pre-wire
--   "unknown_external_state" -- dispatched + NO ack; external state indeterminate
--
-- transport_kind field (transport-layer signal; not an epistemic kind):
--   "ok"           -- transport received a success response
--   "server_error" -- transport received a 5xx response
--   "client_error" -- transport received a 4xx response
--   "blocked"      -- capability policy blocked before dispatch
--   "unavailable"  -- upstream unreachable before dispatch
--   "timeout"      -- time limit elapsed (may be pre- or post-dispatch)
--
-- This fixture does NOT import reconciliation arm names from the epistemic domain.
-- It proves the same semantic distinction independently, in the network domain.
--
-- Authority: LAB-ONLY. No canon claim. No formal taxonomy authority.
-- No real network I/O, sockets, DNS, HTTP library, retry scheduler.
-- Pure contracts only. KDR records (no variant/match).
-- Depends: PROP-043-P5 (Map[String,String]), LAB-VM-MAP-P1 (map_get VM runtime),
--          LAB-FAILURE-TAXONOMY-P1 (HOLD recommendation), Covenant P15.

-- ── Types ──────────────────────────────────────────────────────────────────────

-- NetworkCallSignal: what the transport layer observes.
-- The classifier contract uses dispatch_started + ack_received + transport_kind
-- to produce the correct epistemic outcome kind.
-- status_code: HTTP status if ack received; 0 otherwise.
type NetworkCallSignal {
  ack_received:     Bool,
  detail:           String,
  dispatch_started: Bool,
  host:             String,
  idempotency_key:  String,
  metadata:         Map[String, String],
  request_id:       String,
  status_code:      Integer,
  transport_kind:   String
}

-- NetworkCallOutcome: epistemic outcome for an HTTP upstream call.
-- Preserves request_id and idempotency_key for downstream reconciliation (P16).
-- dispatch_started and ack_received are carried forward so consumers can inspect
-- the epistemic basis without re-reading transport state.
type NetworkCallOutcome {
  ack_received:     Bool,
  detail:           String,
  dispatch_started: Bool,
  idempotency_key:  String,
  kind:             String,
  metadata:         Map[String, String],
  request_id:       String
}

-- ── Scenario 1: CapabilityDenied ─────────────────────────────────────────────
-- Capability policy refused the request BEFORE dispatch.
-- dispatch_started=false → NOT unknown_external_state.
-- denial-as-data: deterministic; no retry changes this; idempotency_key not relevant.

pure contract CapabilityDenied {
  input  request_id :       String
  input  detail     :       String
  input  metadata   :       Map[String, String]
  compute outcome = {
    kind:             "denied",
    request_id:       request_id,
    idempotency_key:  "",
    dispatch_started: false,
    ack_received:     false,
    detail:           detail,
    metadata:         metadata
  }
  output outcome : NetworkCallOutcome
}

-- ── Scenario 2: UpstreamServerError ──────────────────────────────────────────
-- Dispatch completed; upstream returned 5xx.
-- dispatch_started=true, ack_received=true → known outcome; not unknown state.
-- Consumer may retry (transport reached, failure is from upstream, not from us).

pure contract UpstreamServerError {
  input  request_id      : String
  input  idempotency_key : String
  input  detail          : String
  input  metadata        : Map[String, String]
  compute outcome = {
    kind:             "upstream_error",
    request_id:       request_id,
    idempotency_key:  idempotency_key,
    dispatch_started: true,
    ack_received:     true,
    detail:           detail,
    metadata:         metadata
  }
  output outcome : NetworkCallOutcome
}

-- ── Scenario 3: UpstreamUnavailablePreDispatch ────────────────────────────────
-- Upstream unreachable; dispatch never started (connection refused, DNS failure, etc.)
-- dispatch_started=false → NOT unknown_external_state (no request in flight).

pure contract UpstreamUnavailablePreDispatch {
  input  request_id : String
  input  detail     : String
  input  metadata   : Map[String, String]
  compute outcome = {
    kind:             "upstream_unavailable",
    request_id:       request_id,
    idempotency_key:  "",
    dispatch_started: false,
    ack_received:     false,
    detail:           detail,
    metadata:         metadata
  }
  output outcome : NetworkCallOutcome
}

-- ── Scenario 4: TimeoutBeforeDispatch ────────────────────────────────────────
-- Time limit elapsed BEFORE the request reached the wire (e.g. connection pool
-- stalled, DNS resolution timed out, TLS handshake exceeded budget).
-- dispatch_started=false → NOT unknown_external_state.
-- Correct kind: "upstream_unavailable" (infrastructure could not be reached).
-- Do NOT route to unknown_external_state: no request was in flight.

pure contract TimeoutBeforeDispatch {
  input  request_id : String
  input  detail     : String
  input  metadata   : Map[String, String]
  compute outcome = {
    kind:             "upstream_unavailable",
    request_id:       request_id,
    idempotency_key:  "",
    dispatch_started: false,
    ack_received:     false,
    detail:           detail,
    metadata:         metadata
  }
  output outcome : NetworkCallOutcome
}

-- ── Scenario 5: DispatchedNoAck (PRIMARY CASE) ────────────────────────────────
-- Request was sent to the upstream; time limit elapsed before any response.
-- THE CRUCIAL CASE: dispatch_started=true, ack_received=false.
-- Correct kind: "unknown_external_state" (Covenant P15).
-- The upstream MAY have processed the request. We MUST NOT infer success.
-- We MUST NOT infer failure. Reconciliation is required.
-- idempotency_key preserved: consumer needs it to gate any post-reconciliation retry (P16).

pure contract DispatchedNoAck {
  input  request_id      : String
  input  idempotency_key : String
  input  detail          : String
  input  metadata        : Map[String, String]
  compute outcome = {
    kind:             "unknown_external_state",
    request_id:       request_id,
    idempotency_key:  idempotency_key,
    dispatch_started: true,
    ack_received:     false,
    detail:           detail,
    metadata:         metadata
  }
  output outcome : NetworkCallOutcome
}

-- ── Scenario 6: DispatchedLostResponseBody ────────────────────────────────────
-- Request dispatched and a response header was received (connection alive), but
-- the response body was lost or truncated before completion.
-- dispatch_started=true, ack_received=false (body not received = no confirmed ack).
-- Correct kind: "unknown_external_state".
-- The upstream completed its processing (header arrived), but the result is unconfirmed.

pure contract DispatchedLostResponseBody {
  input  request_id      : String
  input  idempotency_key : String
  input  detail          : String
  input  metadata        : Map[String, String]
  compute outcome = {
    kind:             "unknown_external_state",
    request_id:       request_id,
    idempotency_key:  idempotency_key,
    dispatch_started: true,
    ack_received:     false,
    detail:           detail,
    metadata:         metadata
  }
  output outcome : NetworkCallOutcome
}

-- ── Scenario 7: ConfirmedSuccess ─────────────────────────────────────────────
-- Request dispatched; upstream returned a 2xx response.
-- dispatch_started=true, ack_received=true → confirmed success.
-- Correct kind: "ok". Not unknown_external_state.

pure contract ConfirmedSuccess {
  input  request_id      : String
  input  idempotency_key : String
  input  detail          : String
  input  metadata        : Map[String, String]
  compute outcome = {
    kind:             "ok",
    request_id:       request_id,
    idempotency_key:  idempotency_key,
    dispatch_started: true,
    ack_received:     true,
    detail:           detail,
    metadata:         metadata
  }
  output outcome : NetworkCallOutcome
}

-- ── NetworkOutcomeClassifier (core classifier) ───────────────────────────────
-- Applies the dispatch_started / ack_received logic over a NetworkCallSignal
-- to produce the correct epistemic kind (Covenant P15 enforced structurally).
--
-- Routing table:
--   dispatch_started=false                                     → denied / upstream_unavailable
--   dispatch_started=true  + ack_received=true  + ok          → "ok"
--   dispatch_started=true  + ack_received=true  + client_err  → "not_found"
--   dispatch_started=true  + ack_received=true  + server_err  → "upstream_error"
--   dispatch_started=true  + ack_received=false               → "unknown_external_state"
--
-- Note: dispatch_started=false + transport_kind="timeout" routes to "upstream_unavailable",
-- NOT "unknown_external_state" — pre-dispatch timeout is an infrastructure failure,
-- not a lost-ack scenario. Only post-dispatch no-ack produces unknown_external_state.

pure contract NetworkOutcomeClassifier {
  input signal : NetworkCallSignal

  compute is_dispatched  = signal.dispatch_started
  compute has_ack        = signal.ack_received

  compute is_blocked     = signal.transport_kind == "blocked"
  compute is_ok          = signal.transport_kind == "ok"
  compute is_client_err  = signal.transport_kind == "client_error"

  compute kind =
    if is_dispatched {
      if has_ack {
        if is_ok { "ok" } else {
          if is_client_err { "not_found" } else { "upstream_error" }
        }
      } else {
        "unknown_external_state"
      }
    } else {
      if is_blocked { "denied" } else { "upstream_unavailable" }
    }

  compute outcome = {
    kind:             kind,
    request_id:       signal.request_id,
    idempotency_key:  signal.idempotency_key,
    dispatch_started: signal.dispatch_started,
    ack_received:     signal.ack_received,
    detail:           signal.detail,
    metadata:         signal.metadata
  }

  output outcome : NetworkCallOutcome
}

-- ── ReconciliationDataCheck ───────────────────────────────────────────────────
-- Proves that an unknown_external_state outcome carries the data required for
-- a downstream reconciliation pass: request_id (correlation), idempotency_key
-- (retry gate, P16), host/context metadata (where to reconcile).
-- This mirrors the reconciliation-consumer boundary in the epistemic domain
-- without importing reconciliation arm names.

pure contract ReconciliationDataCheck {
  input  outcome : NetworkCallOutcome
  compute request_id_ok  = or_else(map_get(outcome.metadata, "resource"), outcome.request_id)
  compute reconcile_hint = or_else(map_get(outcome.metadata, "reconcile_hint"), "verify call against upstream log")
  compute has_idem_key   = outcome.idempotency_key == ""
  output request_id_ok : String
}

-- ── MetadataPassthrough ───────────────────────────────────────────────────────
-- Proves Map[String,String] metadata is preserved end-to-end through
-- NetworkCallOutcome, mirroring the Sidekiq/Rack map-chain patterns.

pure contract MetadataPassthrough {
  input  outcome    : NetworkCallOutcome
  input  query_key  : String
  compute val_opt   = map_get(outcome.metadata, query_key)
  compute val       = or_else(val_opt, "absent")
  output val : String
}
