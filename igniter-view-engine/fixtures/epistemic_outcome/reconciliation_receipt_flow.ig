module Lab.Epistemic.ReconciliationFlow

-- LAB-EPISTEMIC-OUTCOME-P4: VM KDR ReconciliationReceipt flow proof.
--
-- P2 proved OutcomeEnvelope (unknown state as data). P3 designed the
-- reconciliation-consumer transition rules. P4 proves a KDR ReconciliationReceipt
-- can be PRODUCED, CARRIED, INSPECTED, and ROUTED through the lab VM as ordinary
-- record data — implementing the P3 transition guards as in-VM branching — WITHOUT
-- any sealed Outcome[T,E], variant/match, or real storage/network I/O.
--
-- This is NOT a runtime reconciliation system. It is a VM proof that the receipt
-- shape the reconciliation-consumer boundary needs is executable KDR today.
--
-- Aligns to PROPOSED Ch12 Effect Surface + Covenant doctrine (P13 Observation Is
-- Typed; P15 Timeout Is Not Failure; P16 Idempotency Is Declared; P17 Compensation
-- Is Named; Epistemic State Machine / No Upward Coercion). Ch12 is treated as
-- PROPOSED, not accepted canon.
--
-- `attempt` is typed Integer (not String): it is an ordinal count that the budget
-- logic reasons about numerically alongside budget_remaining:Integer, matching the
-- Sidekiq RetryEnvelope precedent (attempt:Integer). No String→Int coercion needed.
--
-- Authority: LAB-ONLY. KDR convention only. No sealed Outcome[T,E]. No variant/match
-- runtime authority. No canon claim. No public/stable API.
-- Depends: PROP-043-P5 (Map), LAB-VM-MAP-P1 (map_get VM), LAB-RECORD-VM-P3 (nested
--          record field values), LAB-EPISTEMIC-OUTCOME-P2/P3.

-- ── Types ──────────────────────────────────────────────────────────────────────

type OutcomeEnvelope {
  kind:            String,
  message:         String,
  idempotency_key: String,
  metadata:        Map[String, String]
}

type ReconciliationReceipt {
  kind:            String,             -- confirmed_succeeded | confirmed_failed | still_unknown
                                       --  | partially_confirmed | reconciliation_denied | reconciliation_error
  request_id:      String,             -- correlates to the original unknown envelope (required)
  resource:        String,             -- the effect target reconciled (required)
  idempotency_key: String,             -- "" if absent; gates post-reconcile retry (P16)
  observed_at:     String,             -- when reconciliation observed the state; "" if n/a
  evidence_kind:   String,             -- real | human | model | absent (P13 — observation certainty)
  compensation:    String,             -- named compensation contract; "" | "no_compensation" (P17)
  attempt:         Integer,            -- prior attempt count (ordinal; numeric with budget)
  budget_remaining: Integer,           -- reconcile re-entry budget
  detail:          String,
  metadata:        Map[String, String] -- raw receipt fields or absence marker
}

-- ── Producer: build a ReconciliationReceipt from a lost-ack OutcomeEnvelope ──────
-- Proves the receipt is PRODUCED from the unknown envelope, preserving the
-- idempotency_key and pulling reconciliation evidence (request_id, resource) out of
-- the envelope metadata. evidence_kind is carried in from the reconciliation pass.

pure contract ReconcileFromLostAck {
  input  env              : OutcomeEnvelope
  input  determined_kind  : String
  input  evidence_kind    : String
  input  observed_at      : String
  input  compensation     : String
  input  attempt          : Integer
  input  budget_remaining : Integer
  compute req_id   = or_else(map_get(env.metadata, "request_id"), "no_request_id")
  compute resource = or_else(map_get(env.metadata, "resource"), "unknown_resource")
  compute receipt  = {
    kind:             determined_kind,
    request_id:       req_id,
    resource:         resource,
    idempotency_key:  env.idempotency_key,
    observed_at:      observed_at,
    evidence_kind:    evidence_kind,
    compensation:     compensation,
    attempt:          attempt,
    budget_remaining: budget_remaining,
    detail:           "reconciliation receipt for lost-ack",
    metadata:         env.metadata
  }
  output receipt : ReconciliationReceipt
}

-- ── Producer: general receipt builder (any reconciliation result) ───────────────

pure contract MakeReceipt {
  input  kind             : String
  input  request_id       : String
  input  resource         : String
  input  idempotency_key  : String
  input  observed_at      : String
  input  evidence_kind    : String
  input  compensation     : String
  input  attempt          : Integer
  input  budget_remaining : Integer
  input  metadata         : Map[String, String]
  compute receipt = {
    kind:             kind,
    request_id:       request_id,
    resource:         resource,
    idempotency_key:  idempotency_key,
    observed_at:      observed_at,
    evidence_kind:    evidence_kind,
    compensation:     compensation,
    attempt:          attempt,
    budget_remaining: budget_remaining,
    detail:           "reconciliation receipt",
    metadata:         metadata
  }
  output receipt : ReconciliationReceipt
}

-- ── Consumer/router: ReconciliationReceipt.kind drives the terminal action ───────
-- This is the heart of P4: the P3 transition guards, executed IN THE VM as nested
-- if-else branching over receipt fields. Every leaf is a String action.
--
--   confirmed_succeeded + (real|human)        → "accept"
--   confirmed_succeeded + model               → "needs_human_review"  (No Upward Coercion)
--   confirmed_failed   + idempotency present  → "retry"               (P16)
--   confirmed_failed   + named compensation   → "compensate"          (P17)
--   confirmed_failed   + neither              → "fail"                (honest terminal)
--   still_unknown      + budget_remaining > 0 → "reconcile_again"
--   still_unknown      + no budget            → "hold"                (escalate; never infer)
--   partially_confirmed                       → "reconcile_remainder"
--   reconciliation_denied                     → "hold"
--   reconciliation_error + budget > 0         → "reconcile_again"
--   reconciliation_error + no budget          → "hold"
--   any unrecognised kind                     → "hold"                (fail-closed)

pure contract RouteReceipt {
  input  receipt : ReconciliationReceipt

  compute k_cs = receipt.kind == "confirmed_succeeded"
  compute k_cf = receipt.kind == "confirmed_failed"
  compute k_su = receipt.kind == "still_unknown"
  compute k_pc = receipt.kind == "partially_confirmed"
  compute k_rd = receipt.kind == "reconciliation_denied"
  compute k_re = receipt.kind == "reconciliation_error"

  compute ev_real  = receipt.evidence_kind == "real"
  compute ev_human = receipt.evidence_kind == "human"

  compute idem_empty = receipt.idempotency_key == ""
  compute comp_empty = receipt.compensation == ""
  compute comp_none  = receipt.compensation == "no_compensation"
  compute has_budget = receipt.budget_remaining > 0

  compute action =
    if k_cs {
      if ev_real { "accept" } else {
        if ev_human { "accept" } else { "needs_human_review" }
      }
    } else {
      if k_cf {
        if idem_empty {
          if comp_empty { "fail" } else {
            if comp_none { "fail" } else { "compensate" }
          }
        } else { "retry" }
      } else {
        if k_su {
          if has_budget { "reconcile_again" } else { "hold" }
        } else {
          if k_pc { "reconcile_remainder" } else {
            if k_rd { "hold" } else {
              if k_re {
                if has_budget { "reconcile_again" } else { "hold" }
              } else { "hold" }
            }
          }
        }
      }
    }

  output action : String
}

-- ── Consumer/router: raw OutcomeEnvelope → entry routing ─────────────────────────
-- Proves direct unknown-to-terminal routing is ABSENT / fail-closed at the VM level.
-- unknown_external_state / timed_out / partial produce ONLY "reconcile_required" —
-- there is no branch turning them into "accept" or "fail". Unrecognised → "hold".

pure contract RouteEnvelope {
  input  env : OutcomeEnvelope

  compute is_unknown = env.kind == "unknown_external_state"
  compute is_timeout = env.kind == "timed_out"
  compute is_partial = env.kind == "partial"
  compute is_denied  = env.kind == "denied"
  compute is_cancel  = env.kind == "cancelled"
  compute is_comped  = env.kind == "compensated"
  compute is_succ    = env.kind == "succeeded"

  -- unknown / timed_out / partial ALL route to reconcile_required and nothing else:
  -- there is no branch turning them into a terminal accept/fail (fail-closed).
  compute action =
    if is_unknown { "reconcile_required" } else {
      if is_timeout { "reconcile_required" } else {
        if is_partial { "reconcile_required" } else {
          if is_denied { "deny" } else {
            if is_cancel { "cancel" } else {
              if is_comped { "record" } else {
                if is_succ { "accept" } else { "hold" }
              }
            }
          }
        }
      }
    }

  output action : String
}

-- ── Inspector: map chain over the receipt metadata (VM map_get proof) ────────────

pure contract ReceiptInspector {
  input  receipt    : ReconciliationReceipt
  compute hint_opt  = map_get(receipt.metadata, "reconcile_hint")
  compute hint      = or_else(hint_opt, "read-back resource state")
  output  hint      : String
}
