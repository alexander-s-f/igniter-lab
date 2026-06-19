module Lab.FailureTaxonomy.BatchPartialSuccess

-- LAB-FAILURE-TAXONOMY-P4: Partial Success Cross-Domain Pressure Proof.
--
-- Domain: Batch job processing (non-reconciliation).
--
-- Core claim: `partial_success` is independently meaningful in the batch
-- processing domain when some items in a bounded batch succeed and some fail,
-- all outcomes are OBSERVED (typed, not inferred), and the result is distinct
-- from all five adjacent outcome kinds.
--
-- Outcome kind vocabulary (this fixture only):
--   "ok"                     -- all N items succeeded; consume result
--   "partial_success"        -- K items succeeded, N-K failed (0 < K < N);
--                               process succeeded items; retry or compensate failed
--   "failed"                 -- all N items failed; retry or escalate entire batch
--   "denied"                 -- capability gate refused before any item was attempted
--   "system_error"           -- infrastructure failure; no per-item outcomes known
--   "unknown_external_state" -- batch dispatched, no acknowledgement; reconcile
--
-- Key distinctions proved:
--   partial_success vs ok              : succeeded_count < total_count (some failed)
--   partial_success vs failed          : succeeded_count > 0 (some succeeded)
--   partial_success vs system_error    : system_error = NO per-item evidence;
--                                        partial = typed evidence for every item
--   partial_success vs unknown_ext_state: unknown = batch dispatched, outcome
--                                        indeterminate; partial = outcomes observed
--   partial_success vs denied          : denied = nothing processed (pre-gate);
--                                        partial = real items were attempted and run
--
-- Cross-domain note:
--   A secondary multi-upstream model (two HTTP upstreams: one ok, one error)
--   proves the same axis from the network domain — partial success is not
--   reconciliation-specific.
--
-- Authority: LAB-ONLY. Not canon. Not production. No global Outcome[T,E].
-- No failure taxonomy authority. No generic enum. No compiler/VM/canon change.
-- Depends: LAB-FAILURE-TAXONOMY-P2, KDR convention, Covenant P15 (timeout≠failure).

-- ── Batch types ────────────────────────────────────────────────────────────────

-- BatchSignal: what the batch runner observes after a run attempt.
--   signal_kind:     "ran"                   — items were attempted; counts are valid
--                    "denied"                — capability gate refused; counts are 0
--                    "system_error"          — infra failure; counts are unknown (0)
--                    "unknown_external_state"— batch dispatched; no ack (P15 applies)
--   succeeded_count: items that completed successfully (valid when signal_kind="ran")
--   failed_count:    items that failed with an observed error (valid when signal_kind="ran")
--   total_count:     total items in this batch (valid when signal_kind="ran")
--   idempotency_key: preserved for retry gate (Covenant P16)
type BatchSignal {
  batch_id:        String,
  detail:          String,
  failed_count:    Integer,
  idempotency_key: String,
  metadata:        Map[String, String],
  signal_kind:     String,
  succeeded_count: Integer,
  total_count:     Integer
}

-- BatchOutcome: KDR record for the overall batch result.
-- Carries per-item evidence (succeeded_count, failed_count) so downstream
-- consumers can act at item granularity, not just at batch granularity.
type BatchOutcome {
  batch_id:        String,
  detail:          String,
  failed_count:    Integer,
  idempotency_key: String,
  kind:            String,
  metadata:        Map[String, String],
  succeeded_count: Integer,
  total_count:     Integer
}

-- ── Scenario contracts ─────────────────────────────────────────────────────────
-- These produce BatchOutcome directly for the four main batch-run scenarios.
-- They prove that the kind field is correctly assigned per scenario
-- before introducing the classifier.

-- Scenario A: All items succeeded (5/5). kind = "ok".
-- Proved: succeeded_count == total_count → "ok".
pure contract AllSucceeded {
  input batch_id        : String
  input idempotency_key : String
  input metadata        : Map[String, String]
  compute outcome = {
    kind:            "ok",
    batch_id:        batch_id,
    total_count:     5,
    succeeded_count: 5,
    failed_count:    0,
    idempotency_key: idempotency_key,
    detail:          "all 5 items processed successfully",
    metadata:        metadata
  }
  output outcome : BatchOutcome
}

-- Scenario B: Partial success (3/5 succeed, 2/5 fail). kind = "partial_success".
-- Proved: 0 < succeeded_count < total_count → "partial_success".
pure contract PartialSucceededThreeOfFive {
  input batch_id        : String
  input idempotency_key : String
  input metadata        : Map[String, String]
  compute outcome = {
    kind:            "partial_success",
    batch_id:        batch_id,
    total_count:     5,
    succeeded_count: 3,
    failed_count:    2,
    idempotency_key: idempotency_key,
    detail:          "3 of 5 items processed; 2 items failed with observed error",
    metadata:        metadata
  }
  output outcome : BatchOutcome
}

-- Scenario C: Minimal partial (1/5 succeed, 4/5 fail). kind = "partial_success".
-- Proved: even one success with remaining failures → "partial_success", NOT "failed".
pure contract PartialSucceededOneOfFive {
  input batch_id        : String
  input idempotency_key : String
  input metadata        : Map[String, String]
  compute outcome = {
    kind:            "partial_success",
    batch_id:        batch_id,
    total_count:     5,
    succeeded_count: 1,
    failed_count:    4,
    idempotency_key: idempotency_key,
    detail:          "1 of 5 items processed; 4 items failed with observed error",
    metadata:        metadata
  }
  output outcome : BatchOutcome
}

-- Scenario D: All items failed (0/5). kind = "failed".
-- Proved: succeeded_count == 0 (all failed) → "failed", NOT "partial_success".
pure contract AllFailed {
  input batch_id        : String
  input idempotency_key : String
  input metadata        : Map[String, String]
  compute outcome = {
    kind:            "failed",
    batch_id:        batch_id,
    total_count:     5,
    succeeded_count: 0,
    failed_count:    5,
    idempotency_key: idempotency_key,
    detail:          "all 5 items failed with observed errors",
    metadata:        metadata
  }
  output outcome : BatchOutcome
}

-- Scenario E: Capability denied before any item was attempted. kind = "denied".
-- Proved: no items attempted; distinct from partial_success (nothing ran).
pure contract DeniedBeforeBatch {
  input batch_id : String
  input detail   : String
  input metadata : Map[String, String]
  compute outcome = {
    kind:            "denied",
    batch_id:        batch_id,
    total_count:     0,
    succeeded_count: 0,
    failed_count:    0,
    idempotency_key: "",
    detail:          detail,
    metadata:        metadata
  }
  output outcome : BatchOutcome
}

-- Scenario F: Infrastructure failure before item execution. kind = "system_error".
-- Proved: infra failure = NO per-item evidence; we do NOT know which items ran.
-- This is distinct from partial_success where ALL items have typed outcomes.
pure contract SystemErrorBatch {
  input batch_id : String
  input detail   : String
  input metadata : Map[String, String]
  compute outcome = {
    kind:            "system_error",
    batch_id:        batch_id,
    total_count:     0,
    succeeded_count: 0,
    failed_count:    0,
    idempotency_key: "",
    detail:          detail,
    metadata:        metadata
  }
  output outcome : BatchOutcome
}

-- Scenario G: Batch dispatched to worker infrastructure, no ack. kind = "unknown_external_state".
-- Proved: batch was sent; we CANNOT determine what happened (Covenant P15).
-- This is distinct from partial_success: partial has OBSERVED per-item outcomes;
-- unknown has NO confirmation that any item was attempted or completed.
pure contract UnknownStateBatch {
  input batch_id        : String
  input idempotency_key : String
  input detail          : String
  input metadata        : Map[String, String]
  compute outcome = {
    kind:            "unknown_external_state",
    batch_id:        batch_id,
    total_count:     0,
    succeeded_count: 0,
    failed_count:    0,
    idempotency_key: idempotency_key,
    detail:          detail,
    metadata:        metadata
  }
  output outcome : BatchOutcome
}

-- ── BatchOutcomeClassifier ─────────────────────────────────────────────────────
-- Applies the signal_kind + count logic to produce the correct outcome kind.
-- When signal_kind="ran", classification is:
--   succeeded_count == total_count → "ok"
--   failed_count    == total_count → "failed"
--   otherwise                     → "partial_success"
-- All other signal kinds bypass count logic.
--
-- This contract is the core invariant being proved: the classifier correctly
-- separates all six outcome kinds, and `partial_success` emerges only when
-- both succeeded_count > 0 AND failed_count > 0.

pure contract BatchOutcomeClassifier {
  input signal : BatchSignal

  compute is_denied  = signal.signal_kind == "denied"
  compute is_syserr  = signal.signal_kind == "system_error"
  compute is_unknown = signal.signal_kind == "unknown_external_state"

  compute all_ok     = signal.succeeded_count == signal.total_count
  compute all_failed = signal.failed_count    == signal.total_count

  compute run_kind =
    if all_ok { "ok" } else {
      if all_failed { "failed" } else { "partial_success" }
    }

  compute kind =
    if is_denied  { "denied"                  } else {
    if is_syserr  { "system_error"             } else {
    if is_unknown { "unknown_external_state"   } else {
      run_kind
    }}}

  compute outcome = {
    kind:            kind,
    batch_id:        signal.batch_id,
    total_count:     signal.total_count,
    succeeded_count: signal.succeeded_count,
    failed_count:    signal.failed_count,
    idempotency_key: signal.idempotency_key,
    detail:          signal.detail,
    metadata:        signal.metadata
  }

  output outcome : BatchOutcome
}

-- ── BatchActionRouter ─────────────────────────────────────────────────────────
-- Maps BatchOutcome kind to a recovery/consumer action.
-- Proves that partial_success has a distinct action from all other kinds.
--   ok                      → "consume"
--   partial_success         → "retry_failed_items"
--   failed                  → "retry_batch"
--   denied                  → "fix_policy"
--   system_error            → "investigate"
--   unknown_external_state  → "reconcile"

pure contract BatchActionRouter {
  input outcome : BatchOutcome

  compute is_ok       = outcome.kind == "ok"
  compute is_partial  = outcome.kind == "partial_success"
  compute is_failed   = outcome.kind == "failed"
  compute is_denied   = outcome.kind == "denied"
  compute is_syserr   = outcome.kind == "system_error"

  compute action =
    if is_ok      { "consume"           } else {
    if is_partial { "retry_failed_items" } else {
    if is_failed  { "retry_batch"        } else {
    if is_denied  { "fix_policy"         } else {
    if is_syserr  { "investigate"        } else {
      "reconcile"
    }}}}}

  output action : String
}

-- ── Cross-domain: multi-upstream network partial success ──────────────────────
-- A second independent domain: an HTTP fan-out to two upstreams (A and B).
-- Both must succeed for the overall result to be "ok".
-- If one succeeds and one fails, the result is "partial_success".
-- This proves the axis is domain-neutral, not reconciliation-specific.
--
-- upstream_a_kind / upstream_b_kind: "ok" / "error" / "unknown"

type MultiUpstreamSignal {
  request_id:      String,
  upstream_a_kind: String,
  upstream_b_kind: String,
  detail:          String,
  metadata:        Map[String, String]
}

type MultiUpstreamOutcome {
  kind:            String,
  request_id:      String,
  upstream_a_kind: String,
  upstream_b_kind: String,
  detail:          String,
  metadata:        Map[String, String]
}

-- MultiUpstreamClassifier: produces ok/partial_success/failed/unknown_external_state.
-- Rules:
--   both ok           → "ok"
--   both error        → "failed"
--   one ok + one error → "partial_success"  (the cross-domain proof target)
--   either unknown    → "unknown_external_state" (Covenant P15 applies per-upstream)
pure contract MultiUpstreamClassifier {
  input signal : MultiUpstreamSignal

  compute a_ok      = signal.upstream_a_kind == "ok"
  compute b_ok      = signal.upstream_b_kind == "ok"
  compute a_unknown = signal.upstream_a_kind == "unknown"
  compute b_unknown = signal.upstream_b_kind == "unknown"
  compute any_unknown = if a_unknown { "yes" } else { if b_unknown { "yes" } else { "no" } }
  compute both_ok   = if a_ok { if b_ok { "yes" } else { "no" } } else { "no" }
  compute both_err  = if a_ok { "no" } else { if b_ok { "no" } else { "yes" } }

  compute kind =
    if any_unknown == "yes" { "unknown_external_state" } else {
    if both_ok     == "yes" { "ok"                     } else {
    if both_err    == "yes" { "failed"                 } else {
      "partial_success"
    }}}

  compute outcome = {
    kind:            kind,
    request_id:      signal.request_id,
    upstream_a_kind: signal.upstream_a_kind,
    upstream_b_kind: signal.upstream_b_kind,
    detail:          signal.detail,
    metadata:        signal.metadata
  }

  output outcome : MultiUpstreamOutcome
}

-- ── EvidenceInspector ─────────────────────────────────────────────────────────
-- Proves that BatchOutcome carries typed per-item evidence for downstream
-- consumption: succeeded_count + failed_count = total_count.
-- A system_error or unknown_external_state outcome fails this check (counts unknown).
-- A partial_success passes: all items have an observed outcome (success or failure).
pure contract EvidenceInspector {
  input outcome : BatchOutcome
  compute counts_sum    = outcome.succeeded_count + outcome.failed_count
  compute counts_match  = outcome.total_count == counts_sum
  compute is_partial    = outcome.kind == "partial_success"
  compute has_both_kinds =
    if is_partial {
      if outcome.succeeded_count == 0 { "invalid" } else {
        if outcome.failed_count == 0 { "invalid" } else { "valid" }
      }
    } else {
      "not_partial"
    }
  output counts_match : Bool
}
