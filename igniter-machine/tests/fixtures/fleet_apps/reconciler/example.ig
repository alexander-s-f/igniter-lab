module ReconcilerExample
import ReconcilerTypes
import ReconcilerClassify
import ReconcilerRoute
import ReconcilerEngine

-- ============================================================
-- Example: reconcile a charge whose confirmation may be lost
-- ============================================================
-- A payment charge is dispatched; the gateway may ack 2xx (real), reply
-- with only model-level confidence, fail 5xx, or go SILENT (the unknown
-- external state). We reconcile while budget remains.
--
-- Records are pinned with `compute x : T = { … }` annotations. Metadata is
-- a `Map[String,String]` — constructible only at the injection boundary, so
-- the full-receipt scenario takes it as an input (a PROP-029-style arg).

-- ── Signals (annotated record literals) ─────────────────────
pure contract SigRealOk {
  compute s : DispatchSignal = { dispatch_started: 1, ack_received: 1, status_code: 200, evidence_kind: "real", resource: "charge-001" }
  output s : DispatchSignal
}
pure contract SigModelOk {
  compute s : DispatchSignal = { dispatch_started: 1, ack_received: 1, status_code: 200, evidence_kind: "model", resource: "charge-001" }
  output s : DispatchSignal
}
pure contract SigSilent {
  compute s : DispatchSignal = { dispatch_started: 1, ack_received: 0, status_code: 0, evidence_kind: "none", resource: "charge-001" }
  output s : DispatchSignal
}

pure contract DemoCtx {
  input attempt : Integer
  compute c : ReconContext = { request_id: "req-001", idempotency_key: "idem-001", attempt: attempt, max_attempts: 3 }
  output c : ReconContext
}

-- ── ACCEPT: real 2xx confirmation ───────────────────────────
contract RunAccept {
  compute ctx = call_contract("DemoCtx", 1)
  compute sig = call_contract("SigRealOk")
  compute o = call_contract("ReconcileStep", ctx, sig)
  compute action = call_contract("RouteOutcome", o)
  output action : String
}

-- ── MODEL: 2xx but only model evidence → human review ───────
contract RunModelReview {
  compute ctx = call_contract("DemoCtx", 1)
  compute sig = call_contract("SigModelOk")
  compute o = call_contract("ReconcileStep", ctx, sig)
  compute action = call_contract("RouteOutcome", o)
  output action : String
}

-- ── RECONCILE LOOP: silent, silent, then real 2xx ───────────
-- attempts 1 and 2 are silent (unknown, budget remains → reconcile);
-- attempt 3 finally acks 2xx-real → SucceededReal.
contract RunReconcileLoop {
  compute ctx0 = call_contract("DemoCtx", 1)
  compute s1 = call_contract("SigSilent")
  compute s2 = call_contract("SigSilent")
  compute s3 = call_contract("SigRealOk")
  compute final = call_contract("Reconcile3", ctx0, s1, s2, s3)
  output final : Outcome
}

-- ── FULL RECEIPT: demonstrates BuildReceipt + injected metadata ──
-- PRESSURE RC-P06: metadata (Map) must be injected; trace_id is read via
-- or_else(map_get(...)). The contract input is the PROP-029 "args" surface.
contract RunReceipt {
  input metadata : Map[String,String]
  compute ctx = call_contract("DemoCtx", 1)
  compute sig = call_contract("SigSilent")
  compute o = call_contract("ReconcileStep", ctx, sig)
  compute receipt = call_contract("BuildReceipt", o, 1, metadata)
  output receipt : ReconReceipt
}

-- The reconcile loop is the program's default run target.
entrypoint RunReconcileLoop
