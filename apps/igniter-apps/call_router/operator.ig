module CallRouterOperator
import CallRouterTypes

-- ============================================================
-- Channel → behaviour, and the operator state machine
-- ============================================================
-- "звонок-канал определяют поведение оператора": the (call, channel)
-- pair decides the operator's context and what is available for orders.

-- ── Channel flow from the CallRail company kind ─────────────
pure contract ChannelFlowOf {
  input company : CallrailCompany
  compute f = if company.status == "active" {
    if company.kind == "call_center" { CallCenter { } } else { Marketing { } }
  } else {
    Inactive { }
  }
  output f : ChannelFlow
}

-- ── Behaviour the flow grants (marketing vs call_center) ────
-- Marketing channels are disputable and bid for orders; call_center
-- channels take orders directly; inactive channels grant nothing.
-- factory: inline records inside match arms infer to Unknown in Rust
-- (same record-literal pressure, CR-P05).
pure contract MakeBehavior {
  input flow_label : String
  input available_for_orders : Integer
  input disputable : Integer
  compute b = { flow_label: flow_label, available_for_orders: available_for_orders, disputable: disputable }
  output b : ChannelBehavior
}

pure contract ChannelBehaviorOf {
  input f : ChannelFlow
  compute b = match f {
    Marketing  { } => call_contract("MakeBehavior", "marketing",   1, 1)
    CallCenter { } => call_contract("MakeBehavior", "call_center",  1, 0)
    Inactive   { } => call_contract("MakeBehavior", "inactive",     0, 0)
  }
  output b : ChannelBehavior
}

-- ── Operator context factories (entity state threading) ─────
-- PRESSURE CR-P04: setting/clearing context rebuilds the whole Operator
-- record by hand — the entity/state-threading pain (compose territory).
pure contract SetContext {
  input op : Operator
  input company_id : Integer
  input trade_name : String
  input trade_id : Integer
  input inbound_call_id : Integer
  compute n = {
    id: op.id, extension_id: op.extension_id, status: "call_connected",
    current_callrail_company_id: company_id, current_trade_name: trade_name,
    current_trade_id: trade_id, callrail_inbound_call_id: inbound_call_id
  }
  output n : Operator
}

pure contract ClearContext {
  input op : Operator
  input status : String
  compute n = {
    id: op.id, extension_id: op.extension_id, status: status,
    current_callrail_company_id: 0, current_trade_name: "",
    current_trade_id: 0, callrail_inbound_call_id: 0
  }
  output n : Operator
}

-- ── The operator state machine (the heart) ──────────────────
-- Telephony drives the transition; on CallConnected+Matched the operator
-- gets the (call, channel) context; otherwise context is cleared.
-- PRESSURE CR-P01: variant + match expresses the telephony state machine
-- cleanly (the standout capability). The resolved context (company_id /
-- trade / inbound_call_id) is precomputed by the service from the match.
pure contract OperatorStep {
  input op : Operator
  input t : Telephony
  input matched : Integer
  input company_id : Integer
  input trade_name : String
  input trade_id : Integer
  input inbound_call_id : Integer
  compute n = match t {
    CallConnected { customer_phone, direction, started_at_min } => if matched == 1 {
      call_contract("SetContext", op, company_id, trade_name, trade_id, inbound_call_id)
    } else {
      call_contract("ClearContext", op, "call_connected")
    }
    Ringing { } => call_contract("ClearContext", op, "ringing")
    NoCall  { } => call_contract("ClearContext", op, "no_call")
  }
  output n : Operator
}
