# Call Router — Pressure Report

## What This Is

`call_router` is a **pure Igniter companion** for a real, in-production SparkCRM
subsystem: the **CallRail ↔ RingCentral webhook correlation** engine and the
**operator state machine** it drives — a 5-year-old piece of the business.

The setup:

```
CallRail (many companies + tracking numbers)            RingCentral (single main number)
        │  pre_call / routing / post_call webhooks              │  presence webhook
        ▼                                                        ▼
   upsert CallrailInboundCall (by call_id)            find Operator by extensionId
        └──────────────── MATCH by customer phone ───────────────┘
                                   │
                    (call, channel) decides operator behaviour:
              company context · trade/vendor · what's available for orders
```

A customer dials a CallRail tracking number; CallRail forwards the call to the one
RingCentral main number. RingCentral fires a *presence* webhook (telephonyStatus:
`NoCall` / `Ringing` / `CallConnected`) for the operator's extension. On
`CallConnected` we match the CallRail call by the customer phone, derive the
channel (CallRail company) + trade/vendor, and set the operator's context. The
**channel kind** (`marketing` vs `call_center`) then governs the operator's flow.

We re-expressed the **pure decision core**. Every DB read/write, the clock, and
the HTTP ingress are injected or recorded as pressure.

## The Standout: a Telephony State Machine in `variant` + `match`

The RingCentral parser classifies presence into a few states; the service mutates
the operator accordingly. That is a textbook state machine, and Igniter's
`variant` + `match` express it cleanly and **dual-clean**:

```igniter
variant Telephony { NoCall { }  Ringing { }  CallConnected { customer_phone : String, direction : String, started_at_min : Integer } }

pure contract OperatorStep {
  input op : Operator
  input t : Telephony
  input matched : Integer
  ...
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
```

**CR-P01 (positive):** with lead_router's `Pipe` railway, this is the second strong
proof that `variant`/`match` is production-ready for **result types and state
machines**. The "channel determines behaviour" rule is the same shape —
`ChannelFlow { Marketing | CallCenter | Inactive }` → behaviour.

## Where Correlation Hits Walls

The matching layer is where the language is thinnest:

- **CR-P02 — no fuzzy phone match.** Production matches
  `customer_phone_number LIKE %suffix%`. `stdlib.string` has `concat`/`char_at`/
  `substring` but **no `contains`/`ends_with`**, so `MatchCall` falls back to exact
  normalized equality.
- **CR-P03 — picking the most recent hit is awkward.** `find_record...first` wants
  `first(candidates)`, but `first` returns `Option[T]`, is **Rust-only** (the Ruby
  TC lacks it), and **`Option` is not a matchable variant** (`OOF-KIND4`). So the
  resolved `matched_call` (the DB `.first`) is injected and the pure scan only
  *counts* matches. A dual-toolchain `first`/`last` + a matchable `Option` would
  let the whole correlation be pure.

## Familiar pressure, real domain

- **CR-P04 (entity):** `SetContext`/`ClearContext` rebuild the whole `Operator`
  record each transition — the entity/state-threading pain, here as call context.
- **CR-P05 (record literals):** inline records in `if/else` AND `match` arms infer
  to `Unknown` in the Rust TC (`OOF-TY1 expected ChannelBehavior, got Unknown`),
  forcing `MakeBehavior` / `Demo*` factories.
- **CR-P06 (webhook fold):** a CallRail call accrues webhooks across its lifecycle
  (`pre_call → routing → post_call`); `AppendWebhook` grows the list with `concat`,
  but the natural form is a `fold` over the event stream into the call record.

## What We Need From IO (to run the correlation for real)

This subsystem is the most **IO-shaped** of the three companions: it is literally
two webhook streams that must be correlated and persisted.

| Production effect | What it needs from IO | Closest track |
|---|---|---|
| `Operator.where(extension_id)`, `CallrailInboundCall.where(LIKE).first`, company/vendor/tracking lookups | **StorageCapability reads** (typed, receipted) — injected here | `PROP-046` storage + `LAB-IGNITER-LANG-IO-RUNTIME` |
| `operator.save`, `callrail.save`, `RingcentralLog` insert | **StorageCapability writes** with receipts | `PROP-035` effect surface (write family) |
| `created_at: 15.minutes.ago..now` freshness window | **clock capability** — injected as `started_at_min` | clock capability (`LANG-TEMPORAL-STATE-P1` boundary) |
| two webhook endpoints (CallRail + RingCentral) | **ServiceRequest envelopes**, one per webhook | `LAB-IGNITER-LANG-MICROSERVICE` (single-shot dispatch — proven) |
| correlating across the two streams | **stream input + a correlation window** | `PROP-023` stream input + ServiceLoop/`PROP-037` for any standing matcher |
| `Analytics::AnalyticsCallWorker.perform_async`, matcher workers | **background/standing worker** | ServiceLoop/`PROP-037` (proposal-only) + Sidekiq-style dispatch (`LAB-SIDEKIQ`) |

### The serve-loop angle

Two shapes meet here, matching the service-loop map:

- **request→reply per webhook** — the natural fit for both controllers; the
  microservice envelope already proves single-shot dispatch.
- **a standing correlator / worker** — e.g. a phone-matcher that retries linking a
  CallRail call to an order, or an outbox/analytics drainer. That is the
  **ServiceLoop / Progression** (`PROP-037`) territory — proposal-only today.

Either way the **decision core stays pure**: `HandleRingcentral` is a pure function
of (event, operator, candidates, resolved lookups). IO is the membrane that
delivers the two webhook streams, the DB reads, and the clock, and carries the
operator mutation + log back out.

```
  [ IO: CallRail webhook ] → upsert  ┐
                                     ├─ correlation window (stream) ─┐
  [ IO: RingCentral webhook ] ───────┘                              │
                                                                    ▼
                          PURE CORE: HandleRingcentral(ev, op, …) : Operator
                                     │
                                     ├─► [ IO: operator/call writes + log ]
                                     └─► ChannelBehavior → operator flow
```

## Status

Dual-toolchain CLEAN (Ruby 0 / Rust ok 0). 6 files, 7 types, 3 variants, 25
contracts. A positive baseline and a pressure source modeled from real, long-lived
production code — the third SparkCRM companion alongside lead_router (request/reply
railway) and air_combat (tick loop). See `PRESSURE_REGISTRY.md` for the routed
pressure table.
