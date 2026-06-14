module LeadRouterTypes

-- ============================================================
-- lead_router — a SparkCRM companion microservice (pure core)
-- ============================================================
-- Models the production lead-eligibility pipeline that lives in
-- sparkcrm `Api::Marketing::ExecutorService` (a dry-monads Result/.bind
-- railway) + `RequestService` (vendor protocol mapping) + the eLocal
-- webhook controller (ingress + OutboxEvent).
--
-- This is the PURE CORE only. Every DB read, the clock, the RNG, the
-- HTTP ingress, and the outbox write are INJECTED as inputs or recorded
-- as effect-surface pressure (see PRESSURE_REGISTRY.md). All fixed-point
-- money is Integer cents; times are minute-of-day Integers (0..1439).

-- ── Inbound request (the webhook payload, normalized) ───────
type Params {
  trade_query : String     -- e.g. "HVAC" (after heating/cooling→HVAC normalize)
  vendor_key  : String     -- e.g. "elocal"
  zip         : String
}

-- ── Reference data (would be DB rows — injected here) ───────
type Vendor {
  key                  : String
  name                 : String
  availability_mode    : String   -- "same_day_and_tomorrow" | "always_bid" | ...
  availability_threshold : Integer
  start_min            : Integer  -- business hours open  (minute-of-day)
  stop_min             : Integer  -- business hours close (minute-of-day)
  did                  : String   -- dialed number
  duration             : Integer  -- call duration (seconds)
  bid                  : Integer  -- bid price (cents)
}

-- ── Accumulating pipeline context (the @trade/@vendor/... state) ──
-- Grows as the railway proceeds. Defaulted fields are filled by later
-- steps; this is exactly the manually-threaded ExecutorService state.
type Ctx {
  params            : Params
  trade_name        : String
  vendor            : Vendor
  zip_ok            : Integer
  current_min       : Integer   -- injected clock reading (minute-of-day)
  availability_mode : String
  available_slots   : Integer
  bid               : Integer
  did               : String
  upi               : String    -- injected RNG token
  duration          : Integer
}

-- ── The railway result (dry-monads Result analogue) ─────────
-- Proceed carries the growing Ctx; Reject short-circuits the chain.
variant Pipe {
  Proceed { ctx : Ctx }
  Reject  { stage : String, message : String }
}

-- ── Audit trail (the ExecutorService record_step receipts) ──
type StepReceipt {
  stage   : String
  ok      : Integer
  message : String
}

-- ── Outbound vendor protocol (RequestService#elocal) ────────
type VendorResponse {
  status   : String   -- "accept" | "reject"
  price    : Integer
  phone    : String
  uid      : String
  service  : String
  duration : Integer
  message  : String
}

-- ── Outbox event payload (lead_signal) ──────────────────────
type LeadSignal {
  channel               : String
  trade_name            : String
  vendor_name           : String
  zip                   : String
  accepted              : Integer
  bid                   : Integer
  did                   : String
  upi                   : String
  eligibility_mode      : String
  eligibility_slots     : Integer
  eligibility_threshold : Integer
  request_id            : String
  trace_id              : String
}
