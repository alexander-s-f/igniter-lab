module CallRouterTypes

-- ============================================================
-- call_router — a SparkCRM companion microservice (pure core)
-- ============================================================
-- Models the production webhook-correlation engine: CallRail (many
-- companies / tracking numbers) forwards a call into a single RingCentral
-- main number. BOTH send webhooks; we MATCH them and let the
-- (call, channel) pair drive the operator's behaviour.
--
--   CallRail webhook   ──► upsert CallrailInboundCall (by call_id)
--   RingCentral webhook──► find Operator by extensionId ──► on CallConnected
--                          match the CallRail call by customer phone ──►
--                          derive company / trade / vendor ──► set operator context
--
-- Production sources: Webhooks::{CallrailController, RingcentralController},
-- Calls::CallrailWebhook, Ringcentral::{WebhookService, Lib::Parser},
-- models CallrailCompany / Operator / RingcentralLog.
--
-- PURE CORE only. Phones are pre-normalized Strings; times are
-- minute-of-day Integers; every DB read/write is injected. See
-- PRESSURE_REGISTRY.md.

-- ── The CallRail inbound call (upserted across webhooks) ────
type CallrailCall {
  id                    : Integer
  call_id               : String
  callrail_company_id   : Integer   -- the CallRail "company" = the channel
  customer_phone        : String    -- normalized (no +1)
  tracking_phone        : String    -- normalized; maps to a TradeVendor DID
  answered              : Integer
  started_at_min        : Integer   -- ordering key (most-recent wins)
  webhooks              : Collection[String]   -- lifecycle: pre_call, ... , post_call
  operator_id           : Integer
}

-- ── The channel (CallRail company): kind drives flow ────────
type CallrailCompany {
  id          : Integer
  callrail_id : Integer
  kind        : String   -- "marketing" | "call_center"
  name        : String
  status      : String   -- "active" | "canceled"
}

-- ── Channel behaviour (what the flow grants the operator) ───
type ChannelBehavior {
  flow_label          : String
  available_for_orders : Integer
  disputable          : Integer
}

-- ── Trade vendor resolved from the tracking number ──────────
type TradeVendor {
  did_phone  : String    -- normalized
  trade_name : String
  trade_id   : Integer
  vendor_id  : Integer
}

-- ── The operator (the entity whose context we mutate) ───────
type Operator {
  id                          : Integer
  extension_id                : String
  status                      : String   -- "no_call" | "ringing" | "call_connected"
  current_callrail_company_id : Integer
  current_trade_name          : String
  current_trade_id            : Integer
  callrail_inbound_call_id    : Integer
}

-- ── The RingCentral presence event (parsed activeCall) ──────
type RcEvent {
  extension_id     : String
  telephony_status : String   -- "CallConnected" | "NoCall" | "Ringing"
  direction        : String   -- "Inbound" | "Outbound"
  from_phone       : String   -- normalized
  to_phone         : String   -- normalized
  started_at_min   : Integer
}

-- ── The audit log row ───────────────────────────────────────
type CallLog {
  operator_id              : Integer
  extension_id             : String
  telephony_status         : String
  direction                : String
  customer_phone           : String
  callrail_inbound_call_id : Integer
}

-- ── Telephony state (Parser#call_connected?/no_call?/ringing?) ──
variant Telephony {
  NoCall        { }
  Ringing       { }
  CallConnected { customer_phone : String, direction : String, started_at_min : Integer }
}

-- ── Call/channel correlation outcome ────────────────────────
variant MatchResult {
  Matched   { call : CallrailCall }
  Unmatched { }
}

-- ── Channel flow (kind → operator behaviour) ────────────────
variant ChannelFlow {
  Marketing  { }
  CallCenter { }
  Inactive   { }
}
