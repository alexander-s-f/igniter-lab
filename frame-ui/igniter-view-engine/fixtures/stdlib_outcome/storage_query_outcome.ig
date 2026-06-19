module Lab.StdlibOutcome.Storage

-- LAB-STDLIB-OUTCOME-P1: Outcome Helpers Stdlib Pressure Proof.
--
-- Domain: Storage / Query (cross-domain inventory anchor 2 of 3).
--
-- Purpose: Demonstrates KDR outcome patterns in the storage domain, including
-- domain-local kinds that must NOT be collapsed by generic stdlib helpers.
--
-- PROP-047 stable terms present in this domain:
--   "denied"                 -- write capability missing; no items attempted
--   "system_error"           -- disk full, lock timeout, infrastructure fault
--   "query_error"            -- syntax error in query, type mismatch
--   "unknown_external_state" -- transaction dispatched, commit ack lost (Covenant P15)
--   "partial_success"        -- K items inserted; N-K failed (LAB-FAILURE-TAXONOMY-P4)
--
-- Storage-domain-local kinds (must NOT be falsely collapsed by generic helpers):
--   "rows"                   -- SELECT returned ≥1 rows; consume result set
--   "empty"                  -- SELECT returned 0 rows; not a failure
--   "found"                  -- GET by key returned a record
--   "created"                -- INSERT succeeded; new record_id available
--   "conflict"               -- unique constraint violated; caller must handle
--
-- Distinction axioms (from PROP-047 FC-rules):
--   "query_error" ≠ "denied"         (FC-1: malformed query vs capability refusal)
--   "system_error" ≠ "unknown_ext"   (FC-3: infra fault vs lost ack)
--   "partial_success" requires typed evidence (FC-4: succeeded_count AND failed_count)
--   "empty" ≠ "query_error"          (domain: empty result set is valid, not error)
--   "conflict" ≠ "denied"            (domain: constraint vs capability)
--
-- Authority: LAB-ONLY.  No canon implementation.  No stdlib entry created.
-- No compiler/VM/parser/TypeChecker change.
-- Depends: PROP-047-P2, LAB-FAILURE-TAXONOMY-P4, LAB-EPISTEMIC-OUTCOME-P2.

-- ── Outcome record types ───────────────────────────────────────────────────────

-- QueryOutcome: KDR-like record for storage query results.
--   kind:           PROP-047 stable term or storage-domain-local kind
--   record_id:      populated when kind = "found" or "created"
--   row_count:      populated when kind = "rows" or "empty"
--   message:        error detail when kind is failure-axis
--   transaction_id: populated when kind = "unknown_external_state"
type QueryOutcome {
  failed_count:   String,
  kind:           String,
  message:        String,
  query_id:       String,
  record_id:      String,
  row_count:      String,
  succeeded_count: String,
  transaction_id: String
}

-- ── Stringly kind contracts (what helpers would replace) ───────────────────────

-- Extract the outcome kind.
-- Current stringly pattern — stdlib.outcome.kind(outcome) would replace this.
pure contract storage_outcome_kind(outcome: QueryOutcome) -> String {
  outcome.kind
}
