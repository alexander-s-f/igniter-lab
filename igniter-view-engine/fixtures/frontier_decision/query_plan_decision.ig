module Lab.Frontier.QueryPlanDecision

-- FRONTIER-DECISION-P2: Query-plan selection Decision KDR proof.
--
-- P1 (frontier-decision-honesty-surface-gap-j-boundary-v0) designed the
-- DecisionReceipt KDR for Gap-J / Covenant P24/P25. This fixture proves the
-- surface is producible, carriable, and routable in the lab VM, in the domain
-- of choosing between QueryPlans under resource and policy/safety constraints:
--   row_budget      (kind: resource)
--   no_include_all  (kind: policy/safety)
--
-- Decision kinds (separate namespace from PROP-047 outcome kinds):
--   "decided"            -- one option chosen; approval present; rationale non-empty
--   "decision_deferred"  -- choice postponed pending evidence; NOT consumable as decided
--   "decision_escalated" -- routed to higher authority (incl. model-evidence + non-human approval)
--   "no_viable_option"   -- all options constraint-blocked; honest fail-closed terminal
--                           (decision analog of denial-as-data; NOT failure, NOT a default pick)
--
-- v0-conservative escalation rule (P1 §6 + FC-D6): over model-kind evidence only a
-- HUMAN approval may yield "decided"; agent OR system approval escalates. Relaxing
-- this for pre-authorized system policy is FRONTIER-HUMAN-GATE territory.
--
-- Capability authority vs decision authority: a capability-DENIED option is
-- classified "denied_upstream" and never appears in `rejected` (FC-D3);
-- `rejected` holds only viable-but-not-chosen options.
--
-- KDR CONVENTION ONLY. No constraints{} grammar. No StrategyDecision canon type.
-- No variant/match. No real storage/SQL/DB/network I/O. decided_at is an explicit
-- input (no ambient now() — Covenant Law 6). audit_obligation is a carrier field
-- only (Gap-N semantics deferred).
--
-- Authority: LAB-ONLY. No canon claim. No public/stable API. No PROP.
-- Depends: FRONTIER-DECISION-P1, LAB-EPISTEMIC-OUTCOME-P4 (routing pattern),
--          LAB-QUERY-P3 / LAB-TC-ARRAY-P1/P2 (Collection[Record] substrate).

-- ── Types ──────────────────────────────────────────────────────────────────────

type EvidenceRef {
  evidence_kind: String,
  ref:           String
}

type AuthorityLink {
  action:     String,
  actor_id:   String,
  actor_kind: String,
  basis:      String,
  role:       String
}

type ConstraintApplication {
  constraint_hash:  String,
  kind:             String,
  name:             String,
  priority:         String,
  statement:        String,
  status:           String,
  waiver_authority: String
}

type RejectedAlternative {
  conflicting_constraint: String,
  disposition:            String,
  evidence_refs:          Collection[String],
  expected_outcome:       String,
  option_id:              String,
  rejection_reason:       String
}

type ChosenAction {
  evidence_refs:    Collection[String],
  expected_outcome: String,
  option_id:        String,
  uncompensatable:  String
}

type DecisionReceipt {
  assumption_refs:  Collection[String],
  audit_obligation: String,
  authority_chain:  Collection[AuthorityLink],
  chosen:           ChosenAction,
  constraints:      Collection[ConstraintApplication],
  decided_at:       String,
  decision_id:      String,
  evidence_refs:    Collection[EvidenceRef],
  kind:             String,
  metadata:         Map[String, String],
  rationale:        String,
  rejected:         Collection[RejectedAlternative]
}

-- ── Producer: build a DecisionReceipt (nested record + collections, in VM) ─────

pure contract MakeDecisionReceipt {
  input  kind             : String
  input  decision_id      : String
  input  chosen           : ChosenAction
  input  rejected         : Collection[RejectedAlternative]
  input  constraints      : Collection[ConstraintApplication]
  input  authority_chain  : Collection[AuthorityLink]
  input  evidence_refs    : Collection[EvidenceRef]
  input  assumption_refs  : Collection[String]
  input  rationale        : String
  input  decided_at       : String
  input  audit_obligation : String
  input  metadata         : Map[String, String]
  compute receipt = {
    assumption_refs:  assumption_refs,
    audit_obligation: audit_obligation,
    authority_chain:  authority_chain,
    chosen:           chosen,
    constraints:      constraints,
    decided_at:       decided_at,
    decision_id:      decision_id,
    evidence_refs:    evidence_refs,
    kind:             kind,
    metadata:         metadata,
    rationale:        rationale,
    rejected:         rejected
  }
  output receipt : DecisionReceipt
}

-- ── Guard: compute the decision kind in the VM ─────────────────────────────────
-- Encodes the P1 kind rules as executable branching:
--   viable_count == 0                  -> no_viable_option   (never a default pick)
--   pending_evidence == "yes"          -> decision_deferred
--   approval_actor_kind == "none"      -> decision_escalated (chosen != authorized, FC-D1)
--   evidence_kind == "model":
--     human approval                   -> decided
--     agent/system approval            -> decision_escalated (FC-D6; v0-conservative)
--   otherwise (real/human evidence + approval) -> decided

pure contract DecideKindGuard {
  input  viable_count        : Integer
  input  pending_evidence    : String
  input  evidence_kind       : String
  input  approval_actor_kind : String

  compute no_viable  = viable_count == 0
  compute pending    = pending_evidence == "yes"
  compute ev_model   = evidence_kind == "model"
  compute appr_human = approval_actor_kind == "human"
  compute appr_none  = approval_actor_kind == "none"

  compute kind =
    if no_viable { "no_viable_option" } else {
      if pending { "decision_deferred" } else {
        if appr_none { "decision_escalated" } else {
          if ev_model {
            if appr_human { "decided" } else { "decision_escalated" }
          } else { "decided" }
        }
      }
    }

  output kind : String
}

-- ── Guard: waiver validity (FC-D4: waived != absent; invalid waiver fails closed)
-- A waived constraint must carry a non-empty waiver_authority. A waiver with no
-- named authority is an AUTHORITY question, so it escalates — it never silently
-- drops the constraint and never silently proceeds.

pure contract WaiverGuard {
  input  status           : String
  input  waiver_authority : String
  compute is_waived = status == "waived"
  compute no_auth   = waiver_authority == ""
  compute result =
    if is_waived {
      if no_auth { "invalid_waiver_escalate" } else { "waiver_recorded" }
    } else { "no_waiver" }
  output result : String
}

-- ── Guard: score is input, not justification (FC-D5) ──────────────────────────
-- The highest-scoring option still requires a non-empty rationale to be decided.

pure contract JustificationGuard {
  input  top_score_option : String
  input  rationale        : String
  compute no_rationale = rationale == ""
  compute result =
    if no_rationale { "insufficient_justification" } else { "justified" }
  output result : String
}

-- ── Guard: capability authority vs decision authority (FC-D3) ─────────────────
-- A capability-denied option is denied UPSTREAM (denial-as-data) and is excluded
-- from the viable option set; it must never be recorded as a rejected alternative.

pure contract ClassifyOption {
  input  option_id          : String
  input  capability_allowed : String
  compute denied = capability_allowed == "no"
  compute disposition =
    if denied { "denied_upstream" } else { "viable" }
  output disposition : String
}

-- ── Consumer: route on DecisionReceipt.kind (in VM) ───────────────────────────
--   decided            -> execute_plan   (Act stage still passes capability gates)
--   decision_deferred  -> wait           (FC-D8: deferred != decided)
--   decision_escalated -> human_review
--   no_viable_option   -> stop           (FC-D9: not failure, not default-pick)
--   unrecognised kind  -> hold           (fail closed; never execute)

pure contract RouteDecision {
  input  receipt : DecisionReceipt

  compute k_dec = receipt.kind == "decided"
  compute k_def = receipt.kind == "decision_deferred"
  compute k_esc = receipt.kind == "decision_escalated"
  compute k_nvo = receipt.kind == "no_viable_option"

  compute action =
    if k_dec { "execute_plan" } else {
      if k_def { "wait" } else {
        if k_esc { "human_review" } else {
          if k_nvo { "stop" } else { "hold" }
        }
      }
    }

  output action : String
}

-- ── Inspector: map chain over receipt metadata (VM map_get proof) ──────────────

pure contract ReceiptInspector {
  input  receipt   : DecisionReceipt
  compute hint_opt = map_get(receipt.metadata, "review_hint")
  compute hint     = or_else(hint_opt, "no review hint recorded")
  output  hint     : String
}
