module Lab.OutcomeVariant.Rich

-- LAB-OUTCOME-VARIANT-P2: Richer payload-bearing ReconciliationOutcome.
--
-- Extends the 11-arm P1 model with a focused 5-arm variant that carries
-- richer domain payloads: evidence_kind + observed_at (String), attempt +
-- budget_remaining (Integer), and metadata: Map[String,String].
--
-- New territory vs P1:
--   - Payload bindings in match arms flow to outputs (not just arm-label routing)
--   - Integer payload fields (attempt, budget_remaining) bind and round-trip
--   - Map[String,String] payload field binds via match arm; map_get works on it
--   - No-Upward-Coercion: Real vs Model arms carry distinct evidence_kind values
--
-- Authority: LAB-ONLY. Not canon. Not production. No Outcome[T,E]. No taxonomy.
-- Depends: PROP-044-P8, PROP-044-P9, LAB-OUTCOME-VARIANT-P1.

variant ReconciliationOutcomeRich {
  ConfirmedSucceededReal    { request_id: String, resource: String, evidence_kind: String, observed_at: String }
  ConfirmedSucceededModel   { request_id: String, resource: String, evidence_kind: String, observed_at: String }
  ConfirmedFailed           { request_id: String, idempotency_key: String, attempt: Integer }
  StillUnknown              { request_id: String, attempt: Integer, budget_remaining: Integer }
  ReconciliationError       { request_id: String, detail: String, metadata: Map[String,String] }
}

-- ── Build contracts ─────────────────────────────────────────────────────────

contract BuildSucceededReal {
  input request_id: String
  input resource: String
  input evidence_kind: String
  input observed_at: String
  compute outcome: ReconciliationOutcomeRich = ConfirmedSucceededReal {
    request_id: request_id,
    resource: resource,
    evidence_kind: evidence_kind,
    observed_at: observed_at
  }
  output outcome: ReconciliationOutcomeRich
}

contract BuildSucceededModel {
  input request_id: String
  input resource: String
  input evidence_kind: String
  input observed_at: String
  compute outcome: ReconciliationOutcomeRich = ConfirmedSucceededModel {
    request_id: request_id,
    resource: resource,
    evidence_kind: evidence_kind,
    observed_at: observed_at
  }
  output outcome: ReconciliationOutcomeRich
}

contract BuildFailed {
  input request_id: String
  input idempotency_key: String
  input attempt: Integer
  compute outcome: ReconciliationOutcomeRich = ConfirmedFailed {
    request_id: request_id,
    idempotency_key: idempotency_key,
    attempt: attempt
  }
  output outcome: ReconciliationOutcomeRich
}

contract BuildUnknown {
  input request_id: String
  input attempt: Integer
  input budget_remaining: Integer
  compute outcome: ReconciliationOutcomeRich = StillUnknown {
    request_id: request_id,
    attempt: attempt,
    budget_remaining: budget_remaining
  }
  output outcome: ReconciliationOutcomeRich
}

contract BuildError {
  input request_id: String
  input detail: String
  input metadata: Map[String,String]
  compute outcome: ReconciliationOutcomeRich = ReconciliationError {
    request_id: request_id,
    detail: detail,
    metadata: metadata
  }
  output outcome: ReconciliationOutcomeRich
}

-- ── Routing by arm label ─────────────────────────────────────────────────────
-- Exhaustive match; no wildcard. No-Upward-Coercion: Real and Model are
-- distinct arms with distinct routing actions.

contract RouteRich {
  input outcome: ReconciliationOutcomeRich
  compute action: String = match outcome {
    ConfirmedSucceededReal {}  => "accept"
    ConfirmedSucceededModel {} => "needs_human_review"
    ConfirmedFailed {}         => "retry"
    StillUnknown {}            => "reconcile_again"
    ReconciliationError {}     => "hold"
  }
  output action: String
}

-- ── Payload binding: String fields ──────────────────────────────────────────

-- Binds evidence_kind from succeeded arms.
-- No-Upward-Coercion pressure: Real and Model yield distinct evidence_kind
-- values because they are distinct arm names.
contract ExtractEvidenceKind {
  input outcome: ReconciliationOutcomeRich
  compute evidence: String = match outcome {
    ConfirmedSucceededReal  { evidence_kind } => evidence_kind
    ConfirmedSucceededModel { evidence_kind } => evidence_kind
    ConfirmedFailed {}                         => "none"
    StillUnknown {}                            => "none"
    ReconciliationError {}                     => "none"
  }
  output evidence: String
}

-- Binds observed_at from succeeded arms.
-- Compute node named `ts` (not `observed_at`) to avoid name collision with binding.
contract ExtractObservedAt {
  input outcome: ReconciliationOutcomeRich
  compute ts: String = match outcome {
    ConfirmedSucceededReal  { observed_at } => observed_at
    ConfirmedSucceededModel { observed_at } => observed_at
    ConfirmedFailed {}                       => "not_applicable"
    StillUnknown {}                          => "not_applicable"
    ReconciliationError {}                   => "not_applicable"
  }
  output ts: String
}

-- Binds request_id from all five arms. Proves String binding works regardless
-- of which arm is matched.
-- Compute node named `rid` to avoid name collision with binding `request_id`.
contract ExtractRequestId {
  input outcome: ReconciliationOutcomeRich
  compute rid: String = match outcome {
    ConfirmedSucceededReal  { request_id } => request_id
    ConfirmedSucceededModel { request_id } => request_id
    ConfirmedFailed         { request_id } => request_id
    StillUnknown            { request_id } => request_id
    ReconciliationError     { request_id } => request_id
  }
  output rid: String
}

-- ── Payload binding: Integer fields ─────────────────────────────────────────

-- Binds attempt (Integer) from ConfirmedFailed and StillUnknown arms.
-- Returns 0 for arms that do not carry an attempt field.
-- Compute node named `n_attempt` to avoid name collision with binding `attempt`.
contract ExtractAttempt {
  input outcome: ReconciliationOutcomeRich
  compute n_attempt: Integer = match outcome {
    ConfirmedSucceededReal {}         => 0
    ConfirmedSucceededModel {}        => 0
    ConfirmedFailed { attempt }       => attempt
    StillUnknown    { attempt }       => attempt
    ReconciliationError {}            => 0
  }
  output n_attempt: Integer
}

-- Binds budget_remaining (Integer) from StillUnknown arm only.
-- Returns 0 for all other arms.
contract ExtractBudget {
  input outcome: ReconciliationOutcomeRich
  compute budget: Integer = match outcome {
    ConfirmedSucceededReal {}                  => 0
    ConfirmedSucceededModel {}                 => 0
    ConfirmedFailed {}                         => 0
    StillUnknown { budget_remaining }          => budget_remaining
    ReconciliationError {}                     => 0
  }
  output budget: Integer
}

-- ── Payload binding: Map[String,String] field ────────────────────────────────

-- Binds metadata (Map[String,String]) from ReconciliationError and calls
-- map_get on the bound map. Proves that Map payload fields survive through
-- variant_construct → Path B Record → match binding → map_get.
contract ExtractTraceId {
  input outcome: ReconciliationOutcomeRich
  compute trace_id: String = match outcome {
    ConfirmedSucceededReal  {}                                              => "none"
    ConfirmedSucceededModel {}                                              => "none"
    ConfirmedFailed         {}                                              => "none"
    StillUnknown            {}                                              => "none"
    ReconciliationError     { metadata }                                    => or_else(map_get(metadata, "trace_id"), "absent")
  }
  output trace_id: String
}
