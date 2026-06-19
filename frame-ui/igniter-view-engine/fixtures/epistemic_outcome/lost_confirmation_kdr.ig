module Lab.Epistemic.LostConfirmation

-- LAB-EPISTEMIC-OUTCOME-P2: Unknown-state KDR convention proof.
-- Domain: Storage write commit-acknowledgement loss (open-world ESCAPE/STORAGE pressure).
--
-- Proves the v0 Kind-Discriminated Record convention for EPISTEMIC OUTCOME:
-- a lost-confirmation / timeout scenario produces data shaped as
-- "unknown_external_state" or "timed_out" — NOT "failed", NOT "system_error",
-- NOT "upstream_unavailable". The system must not infer success and must not
-- infer failure; it must preserve unknown external state and route the consumer
-- toward reconciliation.
--
-- Aligns to PROPOSED Ch12 Effect Surface outcome vocabulary + Covenant doctrine
-- (Postulate 15 — Timeout Is Not Failure: a timeout is UnknownExternalOutcome,
-- not ObservedFailure; the response is reconciliation, not retry). Ch12 is NOT
-- accepted canon here — it is proposed Ch12 + Covenant doctrine under lab pressure.
--
-- OutcomeEnvelope: a seven-kind epistemic-outcome envelope (KDR convention only).
--   "succeeded"              -- effect completed; confirmation received
--   "denied"                 -- effect NOT attempted; capability refused before dispatch
--   "timed_out"              -- time limit exceeded; outcome UNKNOWN (subtype of unknown)
--   "unknown_external_state" -- request sent; no confirmation; external state indeterminate
--   "partial"               -- effect partially completed; some sub-effects unconfirmed
--   "cancelled"             -- effect cancelled before completion
--   "compensated"           -- a prior failure/unknown triggered its named compensation
--
-- idempotency_key: String. "" when absent. Presence is the precondition the
-- consumer checks before authorizing any retry (Covenant P16 — Idempotency Is
-- Declared). This fixture only CARRIES the key as data; the retry-authorization
-- DECISION lives in the proof-local consumer (no control-flow magic in the envelope).
--
-- metadata: Map[String, String] for reconciliation context (resource, request_id,
-- sent_at, reconcile_hint, etc.).
--
-- This is KDR CONVENTION ONLY. No sealed Outcome[T,E] variant. No variant/match.
-- No real storage write, SQL, DB, socket, worker, or runtime I/O. Pure contracts.
--
-- Authority: LAB-ONLY. No canon claim. No framework compat. No public/stable API.
-- Depends: PROP-043-P5 (Map[String,String]), LAB-VM-MAP-P1 (map_get VM runtime),
--          LAB-RESULT-ENVELOPE-P2 (kind-discriminant 3-domain proof).

-- ── Types ──────────────────────────────────────────────────────────────────────

type OutcomeEnvelope {
  kind:            String,
  message:         String,
  idempotency_key: String,
  metadata:        Map[String, String]
}

-- ── Kind: "succeeded" ─────────────────────────────────────────────────────────
-- Commit acknowledgement received. The effect is confirmed. Normal value path.

pure contract CommitWriteAcked {
  input  resource : String
  input  metadata : Map[String, String]
  compute result  = { kind: "succeeded", message: "commit acknowledged", idempotency_key: "", metadata: metadata }
  output  result  : OutcomeEnvelope
}

-- ── Kind: "denied" ────────────────────────────────────────────────────────────
-- Capability refused the write BEFORE dispatch. Nothing was sent to the store.
-- Denial-as-data: deterministic, no retry, distinct from unknown state.

pure contract CommitWriteDenied {
  input  reason   : String
  input  metadata : Map[String, String]
  compute result  = { kind: "denied", message: reason, idempotency_key: "", metadata: metadata }
  output  result  : OutcomeEnvelope
}

-- ── Kind: "timed_out" ─────────────────────────────────────────────────────────
-- Time limit exceeded waiting for commit ack. Outcome is UNKNOWN (a labeled
-- subtype of unknown_external_state). NOT a failure (Covenant P15). Carries the
-- idempotency_key so the consumer can decide whether a post-reconciliation retry
-- is even permitted.

pure contract CommitWriteTimedOut {
  input  resource        : String
  input  idempotency_key : String
  input  metadata        : Map[String, String]
  compute result = { kind: "timed_out", message: "no commit ack within time budget; outcome unknown", idempotency_key: idempotency_key, metadata: metadata }
  output  result : OutcomeEnvelope
}

-- ── Kind: "unknown_external_state" — PRIMARY SCENARIO ────────────────────────
-- The write request was sent, but the commit acknowledgement was lost. The store
-- may have committed or may not have. The system MUST NOT infer success and MUST
-- NOT infer failure. It returns unknown_external_state and routes to reconciliation.
-- This is the canonical lost-ack case the prior lab envelopes flattened into
-- system_error (QueryResult) or upstream_unavailable (ContractResult).

pure contract CommitWriteLostAck {
  input  resource        : String
  input  idempotency_key : String
  input  metadata        : Map[String, String]
  compute result = { kind: "unknown_external_state", message: "write sent; commit ack lost; external state indeterminate", idempotency_key: idempotency_key, metadata: metadata }
  output  result : OutcomeEnvelope
}

-- ── Kind: "partial" ───────────────────────────────────────────────────────────
-- A multi-row write was half-applied: some rows confirmed, others unconfirmed.
-- Distinct from unknown state — here SOME effect is confirmed. Consumer must
-- handle the mixed set explicitly and reconcile the unconfirmed remainder.

pure contract CommitWritePartial {
  input  resource        : String
  input  idempotency_key : String
  input  metadata        : Map[String, String]
  compute result = { kind: "partial", message: "batch half-applied; some rows unconfirmed", idempotency_key: idempotency_key, metadata: metadata }
  output  result : OutcomeEnvelope
}

-- ── Kind: "cancelled" ─────────────────────────────────────────────────────────
-- The write was cancelled before completion (e.g. service-loop shutdown).
-- Distinct from failure and from denial.

pure contract CommitWriteCancelled {
  input  resource : String
  input  metadata : Map[String, String]
  compute result  = { kind: "cancelled", message: "write cancelled before completion", idempotency_key: "", metadata: metadata }
  output  result  : OutcomeEnvelope
}

-- ── Kind: "compensated" ───────────────────────────────────────────────────────
-- A prior unknown/failed write triggered its named compensation (Covenant P17),
-- and the compensation ran. Terminal resolved state; do not re-compensate.

pure contract CompensatedWrite {
  input  resource : String
  input  metadata : Map[String, String]
  compute result  = { kind: "compensated", message: "prior write compensated", idempotency_key: "", metadata: metadata }
  output  result  : OutcomeEnvelope
}

-- ── Low-level storage signal → epistemic outcome mapper ──────────────────────
-- Three-layer composition (mapper role): a raw storage-driver signal carries a
-- raw kind and a context Map. The mapper projects it into the epistemic outcome
-- vocabulary and strips raw transport detail. Critically, a lost-ack raw signal
-- maps to "unknown_external_state", NOT to "system_error". The mapper never
-- fabricates "succeeded" or "failed" from missing confirmation.

pure contract StorageOutcomeMapper {
  input  raw_kind        : String
  input  resource        : String
  input  idempotency_key : String
  input  context         : Map[String, String]
  compute reason  = or_else(map_get(context, "reconcile_hint"), "reconcile against store before any retry")
  compute result  = { kind: raw_kind, message: reason, idempotency_key: idempotency_key, metadata: context }
  output  result  : OutcomeEnvelope
}

-- ── Reconciliation hint reader (VM map-chain proof) ──────────────────────────
-- Proves map_get(env.metadata, key) → Option[String] + or_else → String over an
-- OutcomeEnvelope named-record input. The consumer reads a reconciliation hint
-- and the original request_id needed to reconcile unknown external state.

pure contract ReconciliationHint {
  input  env          : OutcomeEnvelope
  compute hint_opt    = map_get(env.metadata, "reconcile_hint")
  compute hint        = or_else(hint_opt, "read-back resource state to determine commit")
  compute req_opt     = map_get(env.metadata, "request_id")
  compute request_id  = or_else(req_opt, "no_request_id")
  output  hint        : String
}
