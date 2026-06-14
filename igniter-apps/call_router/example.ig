module CallRouterExample
import CallRouterTypes
import CallRouterService
import CallRouterWebhook

-- Program entry point — the connected+matched correlation is the default target.
-- PRESSURE CR-P11: RunConnectedMatched / RunNoCall / RunUpsert / RunChannel each
-- want a named PROP-029 run-profile; only one bare `entrypoint` is expressible today.
entrypoint RunConnectedMatched

-- ============================================================
-- Example: an inbound call correlated end-to-end
-- ============================================================
-- A customer dials a CallRail tracking number; CallRail forwards it to the
-- RingCentral main number. RingCentral fires a CallConnected presence
-- webhook for the operator's extension. We match the CallRail call and
-- set the operator's (call, channel) context. DB reads are injected.

-- ── Factories (inline records would infer to Unknown in Rust) ──
pure contract DemoOperator {
  compute op = {
    id: 7, extension_id: "ext-101", status: "no_call",
    current_callrail_company_id: 0, current_trade_name: "",
    current_trade_id: 0, callrail_inbound_call_id: 0
  }
  output op : Operator
}

pure contract DemoCall {
  compute c = {
    id: 555, call_id: "CR-abc", callrail_company_id: 9001,
    customer_phone: "3055551234", tracking_phone: "8005559999",
    answered: 1, started_at_min: 600, webhooks: ["pre_call"], operator_id: 0
  }
  output c : CallrailCall
}

pure contract DemoCompany {
  compute co = {
    id: 42, callrail_id: 9001, kind: "marketing", name: "eLocal HVAC", status: "active"
  }
  output co : CallrailCompany
}

pure contract DemoVendor {
  compute v = {
    did_phone: "8005559999", trade_name: "HVAC", trade_id: 3, vendor_id: 88
  }
  output v : TradeVendor
}

pure contract DemoInboundEvent {
  compute ev = {
    extension_id: "ext-101", telephony_status: "CallConnected", direction: "Inbound",
    from_phone: "3055551234", to_phone: "8009066027", started_at_min: 600
  }
  output ev : RcEvent
}

-- ── Scenario 1: inbound CallConnected, phone matches → context set ──
contract RunConnectedMatched {
  compute ev = call_contract("DemoInboundEvent")
  compute op = call_contract("DemoOperator")
  compute call = call_contract("DemoCall")
  compute company = call_contract("DemoCompany")
  compute vendor = call_contract("DemoVendor")
  compute candidates = [call]

  compute op2 = call_contract("HandleRingcentral", ev, op, candidates, call, company, vendor)
  output op2 : Operator
}

-- ── Scenario 2: NoCall → operator context cleared ───────────
pure contract DemoNoCallEvent {
  compute ev = {
    extension_id: "ext-101", telephony_status: "NoCall", direction: "Inbound",
    from_phone: "", to_phone: "", started_at_min: 0
  }
  output ev : RcEvent
}

contract RunNoCall {
  compute ev = call_contract("DemoNoCallEvent")
  compute op = call_contract("DemoOperator")
  compute call = call_contract("DemoCall")
  compute company = call_contract("DemoCompany")
  compute vendor = call_contract("DemoVendor")
  compute candidates = [call]
  compute op2 = call_contract("HandleRingcentral", ev, op, candidates, call, company, vendor)
  output op2 : Operator
}

-- ── Scenario 3: CallRail webhook lifecycle accumulation ─────
contract RunUpsert {
  compute call = call_contract("DemoCall")
  compute c2 = call_contract("AppendWebhook", call, "call_routing_complete")
  compute c3 = call_contract("AppendWebhook", c2, "post_call")
  output c3 : CallrailCall
}

-- ── Scenario 4: channel behaviour (marketing) ───────────────
contract RunChannel {
  compute company = call_contract("DemoCompany")
  compute behavior = call_contract("OperatorChannelBehavior", company)
  output behavior : ChannelBehavior
}
