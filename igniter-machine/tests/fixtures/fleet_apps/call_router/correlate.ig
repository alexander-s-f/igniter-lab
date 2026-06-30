module CallRouterCorrelate
import CallRouterTypes
import stdlib.collection.{ filter, count }

-- ============================================================
-- Webhook correlation: classify telephony + match the call
-- ============================================================

-- ── Parser#call_connected?/no_call?/ringing? → Telephony ────
-- Also computes the customer phone: `from` if Inbound else `to`
-- (Ringcentral::WebhookService direction branch).
pure contract ClassifyTelephony {
  input ev : RcEvent
  compute cust = if ev.direction == "Inbound" { ev.from_phone } else { ev.to_phone }
  compute t = if ev.telephony_status == "CallConnected" {
    CallConnected { customer_phone: cust, direction: ev.direction, started_at_min: ev.started_at_min }
  } else {
    if ev.telephony_status == "Ringing" { Ringing { } } else { NoCall { } }
  }
  output t : Telephony
}

-- ── Match the CallRail call by customer phone ───────────────
-- Production: `CallrailInboundCall.where("customer_phone_number LIKE ?")
--              .order(created_at: :desc).first`
-- The PURE part — scanning candidates for a phone match — is here.
-- PRESSURE CR-P02: phone matching is EXACT-equality only. CallRail uses
-- a `LIKE %suffix%` match; `stdlib.string` has no contains/ends_with, so
-- fuzzy suffix matching is not expressible.
-- PRESSURE CR-P03: picking the most-recent hit needs `first`, which
-- returns `Option[T]` AND is Rust-only (Ruby lacks it), and `Option` is
-- not a matchable variant. So the resolved `matched_call` (the DB `.first`)
-- is injected; the pure scan only decides IF a match exists.
pure contract MatchCall {
  input customer_phone : String
  input candidates : Collection[CallrailCall]
  input matched_call : CallrailCall

  compute hits = filter(candidates, c -> if c.customer_phone == customer_phone { true } else { false })
  compute n = count(hits)

  compute r = if n > 0 {
    Matched { call: matched_call }
  } else {
    Unmatched { }
  }
  output r : MatchResult
}

-- Extract the customer phone a Telephony carries (for downstream match).
pure contract CustomerPhoneOf {
  input t : Telephony
  compute phone = match t {
    CallConnected { customer_phone, direction, started_at_min } => customer_phone
    Ringing { } => ""
    NoCall  { } => ""
  }
  output phone : String
}
