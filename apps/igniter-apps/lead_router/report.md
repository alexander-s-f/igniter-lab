# Lead Router — Pressure Report

## What This Is

`lead_router` is a **pure Igniter companion** for a real, in-production SparkCRM
service: the **eLocal lead webhook** and the marketing eligibility engine behind
it (`Api::Marketing::ExecutorService`, `RequestService`, `Webhooks::ElocalController`).

The production code is "legacy that works but is scary to touch" — a 13-step
`dry-monads` `Result` `.bind` railway threading vendor/zip/availability state,
gated by business hours and an availability threshold, then mapped to a vendor
wire protocol and written to an outbox. We re-expressed its **decision core** as
pure Igniter contracts to see how the language handles a realistic service, and
to name precisely what it still needs from IO.

```
webhook ──► normalize ──► ExecutorService (.bind railway) ──► RequestService#elocal ──► OutboxEvent
 (HTTP)      (HVAC etc.)    (validate→…→generate bid)          (accept/reject wire)      (lead_signal)
```

Everything that touches the outside world — DB lookups, the clock, the RNG token,
the HTTP ingress, the outbox append — is **injected** or recorded as pressure. The
pure core stays pure.

## The Headline: a Railway Without `bind`

The production engine is a monadic railway:

```ruby
validate(params).bind do |_|
  find_trade(params).bind do |trade|
    find_vendor(trade, params).bind do |vendor|
      ... # 10 more steps, each short-circuiting on Failure
```

`.bind` gives **short-circuit-on-failure for free**: any step's `Failure` skips
the rest. Igniter has no such combinator yet — but it DOES have `variant` + `match`,
which compile dual-clean. So we model the Result faithfully:

```igniter
variant Pipe { Proceed { ctx : Ctx }  Reject { stage : String, message : String } }

pure contract FindVendor {
  input prev : Pipe
  input vendor_found : Integer
  input vendor : Vendor
  compute r = match prev {
    Reject  { stage, message } => Reject { stage: stage, message: message }   -- carry
    Proceed { ctx } => if vendor_found == 1 {
      Proceed { ctx: call_contract("CtxWithVendor", ctx, vendor) }
    } else {
      Reject { stage: "find_vendor", message: "Vendor not found" }
    }
  }
  output r : Pipe
}
```

**Pressure LR-P01:** every one of the 8 steps must hand-write the `Reject => carry`
arm. That is exactly the plumbing `.bind` abstracts away. The clean unlock is a
stdlib `Outcome`/`Result` with a `bind`/`and_then` combinator over `variant`, so a
step becomes just its happy path. This is the strongest motivation in the fleet for
an Outcome-combinator surface (complements `PROP-044` variants and the existing
`LANG-STDLIB-OUTCOME` predicates).

**Positive discovery:** `variant` + `match` is the cleanest railway the fleet has
expressed, and — unlike plain record literals — variant constructors work inside
`if/else` branches without inferring to `Unknown`.

## Entity & fold pressure (familiar shapes, real domain)

- **LR-P04 (entity):** the pipeline threads an accumulating `Ctx` (`@trade`,
  `@vendor`, `@zip`, `@availability_mode`, slots, bid…) by rebuilding the whole
  record at each step via `CtxWithX` factories. `Vendor` is a config+behaviour
  entity. Same `LANG-COMPOSE-ENTITY` pain as air_combat/trade_robot — here in a
  CRUD-service idiom.
- **LR-P02 (fold-to-struct):** the production `record_step` accumulates an audit
  trail (`@steps`). Folding receipts into one structure is the fold-to-struct case.
- **LR-P03 (nested fold):** `check_availability` sums slots over
  locations × technicians × dates. We reduce it to a scalar `SumSlots` fold; the
  nested/`flat_map` shape is the deeper (out-of-scope) pressure.
- **LR-P06 (record literals):** `MakeParams`/`MakeAccept`/`MakeReject`/`MakeSignalX`
  exist only to pin record types — an inline `params` literal stays `Unknown` in the
  Rust TC, so `params.vendor_key` raised `OOF-P1` until wrapped in a factory.

## What We Need From IO (to run this for real)

This is the same membrane we mapped for air_combat — but here it is a **request/reply
service**, not a tick loop, so it leans on the ServiceRequest/ServiceResponse
envelope and effect capabilities rather than a ServiceLoop tick source.

| Production effect | What it needs from IO | Closest track |
|---|---|---|
| `find_trade/vendor/zip`, `companies`, `technician.availability` | **StorageCapability reads** (typed, receipted) — currently injected as `trade_found`/`vendor`/`slot_counts` | `PROP-046` storage capability + `LAB-IGNITER-LANG-IO-RUNTIME` |
| `Time.current.in_time_zone` + business hours | **clock capability** (TZ-aware) — injected as `current_min` | clock capability (the `LANG-TEMPORAL-STATE-P1` boundary; event-time, no source `now()`) |
| `Random.alphanumeric(8)` | **RNG capability** — injected as `upi` | effect-surface RNG (none yet) |
| webhook ingress + JSON reply | **ServiceRequest → ServiceResponse envelope** | `LAB-IGNITER-LANG-MICROSERVICE-P1/P3` (single-shot dispatch proven; no accept loop) |
| `OutboxEvent.create!(lead_signal)` | **effect write with receipt** (the outbox/transactional-outbox pattern) | `PROP-035` effect surface + storage write family |

### How the serve loop fits (ties to the ServiceLoop mapping)

A lead webhook is **request→reply**, which is exactly what the microservice
envelope already proves at lab level: `ServiceRequest → RuntimeMachine.evaluate_effect
→ CapabilityExecutor → EffectReceipt → ServiceResponse`. The *core* of `lead_router`
(`RunPipeline`) is a pure function that belongs **inside one such dispatch** — it
needs no loop of its own.

Where a loop *would* appear is the **host**: accepting connections / pulling from a
queue. Per the current state of the service loop, that is:

- **single-shot dispatch** — proven (`LAB-IGNITER-LANG-MICROSERVICE`), and the right
  fit for a per-webhook decision like this one;
- **accept loop / sockets** — closed (no `IO.NetworkCapability`);
- **ServiceLoop / Progression** (`PROP-037`) — the canonical home for any *standing*
  worker (e.g. an outbox-draining loop or a Sidekiq-style consumer), proposal-only.

So `lead_router` is the **request/reply** complement to air_combat's **tick-loop**:
together they exercise both shapes the future runtime must serve, while keeping the
decision logic a pure core under a thin effect membrane.

```
   [ IO: HTTP ingress ] → ServiceRequest
                              │  inject: trade/vendor/zip reads, clock, rng
                              ▼
                    PURE CORE: RunPipeline(params, …) : Pipe   ← stays pure
                              │
                              ├─► VendorProtocol → ServiceResponse (accept/reject)
                              └─► BuildLeadSignal → [ IO: outbox write + receipt ]
```

## Status

Dual-toolchain CLEAN (Ruby 0 / Rust ok 0). 4 files, 6 types, 1 variant, 31
contracts. A positive baseline and a pressure source modeled from real production
code — not a blocker. See `PRESSURE_REGISTRY.md` for the routed pressure table.
