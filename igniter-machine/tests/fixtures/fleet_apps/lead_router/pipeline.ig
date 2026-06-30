module LeadRouterPipeline
import LeadRouterTypes
import stdlib.collection.{ count }

-- ============================================================
-- The eligibility railway (ExecutorService .bind chain, pure)
-- ============================================================
-- Each step is `input prev : Pipe -> output Pipe`. A Reject is carried
-- through unchanged (short-circuit); a Proceed does the step's work.
--
-- PRESSURE LR-P01: with no `bind` / `and_then` combinator, every step
-- must `match prev { Reject => carry ; Proceed => ... }` BY HAND. The
-- whole file is the railway plumbing dry-monads gives for free.
--
-- PRESSURE LR-P06/P07: DB reads, the clock, and the RNG are INJECTED as
-- inputs (trade_found, vendor, slot_counts, current_min, upi). The pure
-- core never performs IO — that is the effect-surface boundary.

-- ── Ctx factories (avoid branch-record-Unknown; = record_step state) ──
-- PRESSURE LR-P04: updating one field means rebuilding the whole Ctx
-- record by hand — the entity/state-threading pain.

pure contract CtxWithTrade {
  input c : Ctx
  input trade_name : String
  compute n = {
    params: c.params, trade_name: trade_name, vendor: c.vendor, zip_ok: c.zip_ok,
    current_min: c.current_min, availability_mode: c.availability_mode,
    available_slots: c.available_slots, bid: c.bid, did: c.did, upi: c.upi, duration: c.duration
  }
  output n : Ctx
}

pure contract CtxWithVendor {
  input c : Ctx
  input vendor : Vendor
  compute n = {
    params: c.params, trade_name: c.trade_name, vendor: vendor, zip_ok: c.zip_ok,
    current_min: c.current_min, availability_mode: c.availability_mode,
    available_slots: c.available_slots, bid: c.bid, did: c.did, upi: c.upi, duration: c.duration
  }
  output n : Ctx
}

pure contract CtxWithZip {
  input c : Ctx
  compute n = {
    params: c.params, trade_name: c.trade_name, vendor: c.vendor, zip_ok: 1,
    current_min: c.current_min, availability_mode: c.availability_mode,
    available_slots: c.available_slots, bid: c.bid, did: c.did, upi: c.upi, duration: c.duration
  }
  output n : Ctx
}

pure contract CtxWithMode {
  input c : Ctx
  input mode : String
  compute n = {
    params: c.params, trade_name: c.trade_name, vendor: c.vendor, zip_ok: c.zip_ok,
    current_min: c.current_min, availability_mode: mode,
    available_slots: c.available_slots, bid: c.bid, did: c.did, upi: c.upi, duration: c.duration
  }
  output n : Ctx
}

pure contract CtxWithSlots {
  input c : Ctx
  input slots : Integer
  compute n = {
    params: c.params, trade_name: c.trade_name, vendor: c.vendor, zip_ok: c.zip_ok,
    current_min: c.current_min, availability_mode: c.availability_mode,
    available_slots: slots, bid: c.bid, did: c.did, upi: c.upi, duration: c.duration
  }
  output n : Ctx
}

pure contract CtxWithBid {
  input c : Ctx
  input bid : Integer
  input did : String
  input upi : String
  input duration : Integer
  compute n = {
    params: c.params, trade_name: c.trade_name, vendor: c.vendor, zip_ok: c.zip_ok,
    current_min: c.current_min, availability_mode: c.availability_mode,
    available_slots: c.available_slots, bid: bid, did: did, upi: upi, duration: duration
  }
  output n : Ctx
}

-- ── Step 1: validate (no prev — entry of the railway) ───────
pure contract Validate {
  input params : Params
  input current_min : Integer

  compute c0 = {
    params: params, trade_name: "", vendor: call_contract("NullVendor"),
    zip_ok: 0, current_min: current_min, availability_mode: "",
    available_slots: 0, bid: 0, did: "", upi: "", duration: 0
  }

  compute ok = if params.trade_query == "" { 0 } else {
    if params.vendor_key == "" { 0 } else {
      if params.zip == "" { 0 } else { 1 }
    }
  }

  compute r = if ok == 1 {
    Proceed { ctx: c0 }
  } else {
    Reject { stage: "validate", message: "missing required param" }
  }
  output r : Pipe
}

pure contract NullVendor {
  compute v = {
    key: "", name: "", availability_mode: "", availability_threshold: 0,
    start_min: 0, stop_min: 0, did: "", duration: 0, bid: 0
  }
  output v : Vendor
}

-- ── Step 2: find trade ──────────────────────────────────────
pure contract FindTrade {
  input prev : Pipe
  input trade_found : Integer
  input trade_name : String
  compute r = match prev {
    Reject  { stage, message } => Reject { stage: stage, message: message }
    Proceed { ctx } => if trade_found == 1 {
      Proceed { ctx: call_contract("CtxWithTrade", ctx, trade_name) }
    } else {
      Reject { stage: "find_trade", message: "Trade not found" }
    }
  }
  output r : Pipe
}

-- ── Step 3: find vendor ─────────────────────────────────────
pure contract FindVendor {
  input prev : Pipe
  input vendor_found : Integer
  input vendor : Vendor
  compute r = match prev {
    Reject  { stage, message } => Reject { stage: stage, message: message }
    Proceed { ctx } => if vendor_found == 1 {
      Proceed { ctx: call_contract("CtxWithVendor", ctx, vendor) }
    } else {
      Reject { stage: "find_vendor", message: "Vendor not found" }
    }
  }
  output r : Pipe
}

-- ── Step 4: find zip code ───────────────────────────────────
pure contract FindZip {
  input prev : Pipe
  input zip_found : Integer
  compute r = match prev {
    Reject  { stage, message } => Reject { stage: stage, message: message }
    Proceed { ctx } => if zip_found == 1 {
      Proceed { ctx: call_contract("CtxWithZip", ctx) }
    } else {
      Reject { stage: "find_zip_code", message: "Zip Code not found" }
    }
  }
  output r : Pipe
}

-- ── Step 5: business hours (pure tod compare, injected current_min) ──
pure contract InBusinessHours {
  input time : Integer
  input start_min : Integer
  input stop_min : Integer
  compute open = if start_min <= stop_min {
    if time >= start_min { if time <= stop_min { 1 } else { 0 } } else { 0 }
  } else {
    if time >= start_min { 1 } else { if time <= stop_min { 1 } else { 0 } }
  }
  output open : Integer
}

pure contract BusinessHours {
  input prev : Pipe
  compute r = match prev {
    Reject  { stage, message } => Reject { stage: stage, message: message }
    Proceed { ctx } => if call_contract("InBusinessHours", ctx.current_min, ctx.vendor.start_min, ctx.vendor.stop_min) == 1 {
      Proceed { ctx: ctx }
    } else {
      Reject { stage: "business_hours", message: "Closed" }
    }
  }
  output r : Pipe
}

-- ── Step 6: resolve availability mode ───────────────────────
pure contract ResolveMode {
  input prev : Pipe
  compute r = match prev {
    Reject  { stage, message } => Reject { stage: stage, message: message }
    Proceed { ctx } => Proceed { ctx: call_contract("CtxWithMode", ctx, ctx.vendor.availability_mode) }
  }
  output r : Pipe
}

-- ── Step 7: check availability (fold slots vs threshold) ────
-- PRESSURE LR-P03: slots is a SCALAR fold here; the production code
-- accumulates over locations × technicians × dates (nested fold /
-- flat_map) — out of scope, but the slot total is a fold.
pure contract SumSlots {
  input slot_counts : Collection[Integer]
  compute total = fold(slot_counts, 0, (acc, s) -> acc + s)
  output total : Integer
}

pure contract CheckAvailability {
  input prev : Pipe
  input slot_counts : Collection[Integer]
  compute slots = call_contract("SumSlots", slot_counts)
  compute r = match prev {
    Reject  { stage, message } => Reject { stage: stage, message: message }
    Proceed { ctx } => if ctx.availability_mode == "always_bid" {
      Proceed { ctx: call_contract("CtxWithSlots", ctx, slots) }
    } else {
      if slots >= ctx.vendor.availability_threshold {
        Proceed { ctx: call_contract("CtxWithSlots", ctx, slots) }
      } else {
        Reject { stage: "check_availability", message: "Not available: below threshold" }
      }
    }
  }
  output r : Pipe
}

-- ── Step 8: generate results (bid/did/duration present) ─────
pure contract GenerateResults {
  input prev : Pipe
  input upi : String
  compute r = match prev {
    Reject  { stage, message } => Reject { stage: stage, message: message }
    Proceed { ctx } => if ctx.vendor.bid > 0 {
      Proceed { ctx: call_contract("CtxWithBid", ctx, ctx.vendor.bid, ctx.vendor.did, upi, ctx.vendor.duration) }
    } else {
      Reject { stage: "generate_results", message: "Configuration: no positive bid" }
    }
  }
  output r : Pipe
}
