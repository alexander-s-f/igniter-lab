module LeadRouterExample
import LeadRouterTypes
import LeadRouterService

-- ============================================================
-- Example: the eLocal webhook, two scenarios (accept / reject)
-- ============================================================
-- Mirrors Webhooks::ElocalController#create: normalize → RequestService
-- → vendor protocol response + OutboxEvent(lead_signal). DB reads, the
-- clock, and the RNG token are injected (the effect-surface boundary).

pure contract DemoVendor {
  compute v = {
    key: "elocal", name: "eLocal HVAC Co", availability_mode: "same_day_and_tomorrow",
    availability_threshold: 3, start_min: 480, stop_min: 1080,
    did: "+18005551234", duration: 90, bid: 4500
  }
  output v : Vendor
}

-- ── ACCEPT path: everything resolves, slots 5 >= threshold 3 ──
contract RunAccept {
  compute params = call_contract("MakeParams", "HVAC", "elocal", "33101")
  compute vendor = call_contract("DemoVendor")
  compute slots = [2, 3]            -- two technicians' available slots

  compute result = call_contract("RunPipeline",
    params, 600,        -- current_min = 10:00 (within 08:00-18:00)
    1, "HVAC",          -- trade_found, trade_name
    1, vendor,          -- vendor_found, vendor
    1,                  -- zip_found
    slots,
    "A1B2C3D4"          -- injected RNG upi
  )

  compute response = call_contract("VendorProtocol", params.vendor_key, result)
  output response : VendorResponse
}

contract RunAcceptSignal {
  compute params = call_contract("MakeParams", "HVAC", "elocal", "33101")
  compute vendor = call_contract("DemoVendor")
  compute slots = [2, 3]
  compute result = call_contract("RunPipeline",
    params, 600, 1, "HVAC", 1, vendor, 1, slots, "A1B2C3D4")
  compute signal = call_contract("BuildLeadSignal", result, params, "req-001", "trace-001")
  output signal : LeadSignal
}

-- ── REJECT path: vendor not found → short-circuit at find_vendor ──
contract RunReject {
  compute params = call_contract("MakeParams", "Plumbing", "ghostvendor", "33101")
  compute vendor = call_contract("DemoVendor")
  compute slots = [0]

  compute result = call_contract("RunPipeline",
    params, 600,
    1, "Plumbing",
    0, vendor,          -- vendor_found = 0  →  Reject at find_vendor
    1,
    slots,
    "Z9Y8X7W6"
  )

  compute response = call_contract("VendorProtocol", params.vendor_key, result)
  output response : VendorResponse
}
