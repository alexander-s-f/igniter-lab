module CallRouterService
import CallRouterTypes
import CallRouterCorrelate
import CallRouterOperator

-- ============================================================
-- Orchestration (Ringcentral::WebhookService#call)
-- ============================================================
-- Ties correlation + the operator state machine together. All DB reads
-- are INJECTED: the operator (by extension_id), the candidate CallRail
-- calls + the resolved `matched_call` (the `.first` of the LIKE query),
-- the CallRail company (the channel), and the trade vendor (by DID).

pure contract HandleRingcentral {
  input ev           : RcEvent
  input op           : Operator
  input candidates   : Collection[CallrailCall]
  input matched_call : CallrailCall
  input company      : CallrailCompany
  input vendor       : TradeVendor

  -- classify telephony + extract the customer phone
  compute t = call_contract("ClassifyTelephony", ev)
  compute cust = call_contract("CustomerPhoneOf", t)

  -- correlate the CallRail call by phone (pure scan + injected .first)
  compute m = call_contract("MatchCall", cust, candidates, matched_call)
  compute matched = match m {
    Matched   { call } => 1
    Unmatched { }      => 0
  }

  -- drive the operator state machine; (call, channel) → context
  compute op2 = call_contract("OperatorStep", op, t, matched,
    company.id, vendor.trade_name, vendor.trade_id, matched_call.id)
  output op2 : Operator
}

-- The resolved channel behaviour for an operator's current call.
pure contract OperatorChannelBehavior {
  input company : CallrailCompany
  compute flow = call_contract("ChannelFlowOf", company)
  compute behavior = call_contract("ChannelBehaviorOf", flow)
  output behavior : ChannelBehavior
}

-- Build the audit log row (RingcentralLog).
pure contract BuildLog {
  input ev : RcEvent
  input op : Operator
  compute cust = if ev.direction == "Inbound" { ev.from_phone } else { ev.to_phone }
  compute log = {
    operator_id: op.id, extension_id: ev.extension_id,
    telephony_status: ev.telephony_status, direction: ev.direction,
    customer_phone: cust, callrail_inbound_call_id: op.callrail_inbound_call_id
  }
  output log : CallLog
}
