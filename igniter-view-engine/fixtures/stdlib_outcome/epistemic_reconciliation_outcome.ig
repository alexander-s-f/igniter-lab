module Lab.StdlibOutcome.Epistemic

-- LAB-STDLIB-OUTCOME-P1: Outcome Helpers Stdlib Pressure Proof.
--
-- Domain: Epistemic / Reconciliation (cross-domain inventory anchor 3 of 3).
--
-- Purpose: Demonstrates KDR outcome patterns in the epistemic domain, showing
-- that the same six PROP-047 stable terms appear here too, alongside rich
-- domain-local reconciliation-outcome kinds that generic helpers must not absorb.
--
-- PROP-047 stable terms present in this domain:
--   "denied"                 -- reconciliation window closed; capability refused
--   "timed_out"              -- reconciliation attempt clock elapsed
--   "unknown_external_state" -- original request in unknown state (Covenant P15)
--   "system_error"           -- state store unavailable; infrastructure fault
--   "partial_success"        -- some items confirmed; others still unresolved
--
-- Epistemic-domain-local kinds (must NOT be collapsed by generic helpers):
--   "confirmed_succeeded"    -- real/model/human evidence confirms success
--   "confirmed_failed"       -- evidence confirms failure; compensation or retry
--   "still_unknown"          -- bounded re-check; budget_remaining drives next step
--   "reconciliation_denied"  -- stale window or authority refused reconciliation
--   "reconciliation_error"   -- state machine fault during reconciliation itself
--
-- Key distinction (No-Upward-Coercion, Covenant P13):
--   "confirmed_succeeded" with evidence_kind="model" ≠ evidence_kind="real"
--   Generic helpers do NOT discriminate evidence_kind — that is the point.
--   Only variant/match arms (LAB-OUTCOME-VARIANT-P1) carry evidence_kind.
--
-- KDR / variant boundary:
--   This fixture uses the KDR convention (LAB-EPISTEMIC-OUTCOME-P2):
--   kind: String field, Map[String,String]-compatible.
--   The variant form (LAB-OUTCOME-VARIANT-P1) is separate; helpers operate
--   on KDR only.
--
-- Authority: LAB-ONLY.  No canon implementation.  No stdlib entry created.
-- No compiler/VM/parser/TypeChecker change.
-- Depends: PROP-047-P2, LAB-EPISTEMIC-OUTCOME-P1..P4, LAB-OUTCOME-VARIANT-P1..P3.

-- ── Outcome record type ────────────────────────────────────────────────────────

-- ReconciliationOutcomeKdr: KDR-like record for epistemic reconciliation results.
--   kind:              PROP-047 stable term or epistemic-domain-local kind
--   evidence_kind:     "real" | "model" | "human" (Covenant P13; load-bearing)
--   idempotency_key:   retry guard (Covenant P16)
--   attempt:           ordinal count for budget reasoning
--   budget_remaining:  Integer-as-String for still_unknown routing
--   detail:            free-text (not routed on)
type ReconciliationOutcomeKdr {
  attempt:           String,
  budget_remaining:  String,
  compensation:      String,
  detail:            String,
  evidence_kind:     String,
  idempotency_key:   String,
  kind:              String,
  observed_at:       String,
  request_id:        String
}

-- ── Stringly kind contract (what helpers would replace) ────────────────────────

-- Extract the outcome kind.
-- Current stringly pattern — stdlib.outcome.kind(outcome) would replace this.
pure contract reconciliation_outcome_kind(outcome: ReconciliationOutcomeKdr) -> String {
  outcome.kind
}
