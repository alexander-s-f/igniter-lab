module LeadRouterService
import LeadRouterTypes
import LeadRouterPipeline

-- ============================================================
-- Orchestration + vendor protocol + outbox (RequestService + controller)
-- ============================================================

-- ── Params factory ──────────────────────────────────────────
-- PRESSURE LR-P02: an inline record literal stays Unknown in the Rust
-- TC unless it is a typed contract output, so field access like
-- `params.vendor_key` fails. A factory pins the type (the MakeXxx
-- anti-pattern; same root as the fold-struct record-literal work).
pure contract MakeParams {
  input trade_query : String
  input vendor_key : String
  input zip : String
  compute p = { trade_query: trade_query, vendor_key: vendor_key, zip: zip }
  output p : Params
}

-- ── RunPipeline: the ExecutorService .bind chain, threaded ──
-- PRESSURE LR-P01: all effect results are injected here (trade_found,
-- vendor, slot_counts, upi). A real service would obtain them from
-- StorageCapability reads / clock / RNG between steps. The pure railway
-- only sequences and decides.
pure contract RunPipeline {
  input params       : Params
  input current_min  : Integer
  input trade_found  : Integer
  input trade_name   : String
  input vendor_found : Integer
  input vendor       : Vendor
  input zip_found    : Integer
  input slot_counts  : Collection[Integer]
  input upi          : String

  compute s1 = call_contract("Validate", params, current_min)
  compute s2 = call_contract("FindTrade", s1, trade_found, trade_name)
  compute s3 = call_contract("FindVendor", s2, vendor_found, vendor)
  compute s4 = call_contract("FindZip", s3, zip_found)
  compute s5 = call_contract("BusinessHours", s4)
  compute s6 = call_contract("ResolveMode", s5)
  compute s7 = call_contract("CheckAvailability", s6, slot_counts)
  compute s8 = call_contract("GenerateResults", s7, upi)
  output s8 : Pipe
}

-- ── Vendor protocol mapping (RequestService#elocal) ─────────
pure contract MakeAccept {
  input ctx : Ctx
  compute resp = {
    status: "accept", price: ctx.bid, phone: ctx.did, uid: ctx.upi,
    service: ctx.trade_name, duration: ctx.duration, message: ""
  }
  output resp : VendorResponse
}

pure contract MakeReject {
  input message : String
  compute resp = {
    status: "reject", price: 0, phone: "", uid: "",
    service: "", duration: 0, message: message
  }
  output resp : VendorResponse
}

pure contract ElocalResponse {
  input p : Pipe
  compute resp = match p {
    Reject  { stage, message } => call_contract("MakeReject", message)
    Proceed { ctx }            => call_contract("MakeAccept", ctx)
  }
  output resp : VendorResponse
}

-- inquirly aliases elocal in production (`def inquirly; elocal; end`)
pure contract InquirlyResponse {
  input p : Pipe
  compute resp = call_contract("ElocalResponse", p)
  output resp : VendorResponse
}

-- ── Static protocol dispatcher ──────────────────────────────
-- PRESSURE LR-P05: we WANT call_contract(vendor_key + "Response", p) to
-- pick the adapter by vendor name. A variable callee returns Unknown, so
-- we branch statically — the LAB-DYNAMIC-CONTRACT-DISPATCH-P2 discipline.
pure contract VendorProtocol {
  input vendor_key : String
  input p : Pipe
  compute resp = if vendor_key == "inquirly" {
    call_contract("InquirlyResponse", p)
  } else {
    call_contract("ElocalResponse", p)
  }
  output resp : VendorResponse
}

-- ── Outbox event (lead_signal) — the controller's OutboxEvent ──
-- PRESSURE LR-P08: building the payload is pure; the actual append to a
-- durable outbox is an effect (write capability + receipt), out of scope.
pure contract MakeSignalAccept {
  input ctx : Ctx
  input request_id : String
  input trace_id : String
  compute sig = {
    channel: "webhook", trade_name: ctx.trade_name, vendor_name: ctx.vendor.name,
    zip: ctx.params.zip, accepted: 1, bid: ctx.bid, did: ctx.did, upi: ctx.upi,
    eligibility_mode: ctx.availability_mode, eligibility_slots: ctx.available_slots,
    eligibility_threshold: ctx.vendor.availability_threshold,
    request_id: request_id, trace_id: trace_id
  }
  output sig : LeadSignal
}

pure contract MakeSignalReject {
  input params : Params
  input request_id : String
  input trace_id : String
  compute sig = {
    channel: "webhook", trade_name: params.trade_query, vendor_name: params.vendor_key,
    zip: params.zip, accepted: 0, bid: 0, did: "", upi: "",
    eligibility_mode: "", eligibility_slots: 0, eligibility_threshold: 0,
    request_id: request_id, trace_id: trace_id
  }
  output sig : LeadSignal
}

pure contract BuildLeadSignal {
  input p : Pipe
  input params : Params
  input request_id : String
  input trace_id : String
  compute sig = match p {
    Reject  { stage, message } => call_contract("MakeSignalReject", params, request_id, trace_id)
    Proceed { ctx }            => call_contract("MakeSignalAccept", ctx, request_id, trace_id)
  }
  output sig : LeadSignal
}
