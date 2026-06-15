# Lead Router Pressure Registry

Created: 2026-06-14 (off-track app — a SparkCRM companion microservice, pure core)

`lead_router` is a faithful, pure re-modeling of a **real production legacy
service** from SparkCRM: the eLocal lead webhook and its
`Api::Marketing::ExecutorService` / `RequestService`. The production code is a
`dry-monads` Result `.bind` railway of ~13 eligibility steps (validate → find
trade/vendor/zip → business hours → availability threshold → generate bid),
followed by a vendor-protocol response mapping and an `OutboxEvent(lead_signal)`.

This Igniter version keeps only the **pure decision core**. Every DB read, the
clock, the RNG token, the HTTP ingress, and the outbox write are injected as
inputs or recorded as effect-surface pressure.

## Baseline

Dual-toolchain CLEAN.

```bash
cd igniter-compiler
cargo run -- compile \
  ../igniter-apps/lead_router/types.ig ../igniter-apps/lead_router/pipeline.ig \
  ../igniter-apps/lead_router/service.ig ../igniter-apps/lead_router/example.ig \
  --out /tmp/lead_router.igapp
```

| Metric | Value |
|---|---|
| Ruby | ok / 0 diagnostics |
| Rust | ok / 0 diagnostics |
| source files | 4 |
| types | 6 |
| variants | 1 (`Pipe { Proceed \| Reject }` — the Result analogue) |
| contracts | 31 |
| call_contract sites | 38 textual mentions; 37 executable sites (all Tier-1 literals — static dispatch) |
| match sites | 10 textual mentions; 9 executable expressions (railway short-circuit) |
| fold sites | 1 (scalar slot total) |
| source_hash | `sha256:3cca9ed52a593e60ed86fb59e359809d255425af5690ded364cd8329fab71e1b` (full-app absolute-path multifile hash; `entrypoint RunAccept` present) |

> NOTE (shared with air_combat): the Rust CLI's assembler intermittently surfaces
> a spurious `Internal compiler error: No such file or directory (os error 2)`
> when invoked in rapid back-to-back succession (a timing/path race in the
> directory-package writer). It is NOT a source fault — the Ruby TC is clean and a
> spaced single invocation to a fresh `--out` path returns the real `ok` result.

## Closure Summary (LAB-LEAD-ROUTER-BASELINE-P1, 2026-06-14)

Proof runner:

`igniter-view-engine/proofs/verify_lab_lead_router_baseline_p1.rb`

Result:

`175/175 PASS`

Closure notes:

- Ruby canon and Rust lab both compile the 4-file app as `ok` / 0 diagnostics.
- Ruby and Rust agree on the full-app source hash:
  `sha256:3cca9ed52a593e60ed86fb59e359809d255425af5690ded364cd8329fab71e1b`.
- The proof uses a spaced second Rust invocation and fresh `--out` paths to avoid
  the known assembler timing/path race.
- The previous hash `sha256:16deae290738578a09cc324de18ff2312b14b960e0d581945285b913d534e3ba`
  is superseded as registry metadata by the live full-app hash above.
- Textual counts preserve historical report pressure (`38` `call_contract`, `10`
  `match`); executable source after stripping comments has `37` literal
  `call_contract` forms and `9` `match` expressions.
- No app `.ig` source was changed for this closure.

## Provenance (production → pure model)

| Production (sparkcrm) | lead_router model |
|---|---|
| `Webhooks::ElocalController#create` | `example.ig` RunAccept/RunReject + `BuildLeadSignal` |
| `ExecutorService#call` (dry-monads `.bind` chain) | `pipeline.ig` railway over `variant Pipe` + `match` |
| `record_step(...)` audit trail | `StepReceipt` type (receipt shape; see LR-P02) |
| `RequestService#elocal` / `#inquirly` | `service.ig` ElocalResponse / InquirlyResponse |
| `OutboxEvent.create!(lead_signal)` | `service.ig` BuildLeadSignal → `LeadSignal` |
| `find_trade/vendor/zip`, `technician.availability`, `Time.current`, `Random` | injected inputs (effect-surface boundary) |

## Pressures

| ID | Name | Evidence | Status | Route |
|---|---|---|---|---|
| LR-P01 | **Outcome/bind railway, by hand** | `pipeline.ig`: 8 steps each `match prev { Reject => carry ; Proceed => work }`. dry-monads gives `.bind` short-circuit for free; here every step re-implements it. The headline. | ACTIVE — primary | stdlib `Outcome`/`Result` + a `bind`/`and_then` combinator over `variant` |
| LR-P02 | **fold-to-struct (step receipts)** | production `record_step` accumulates `@steps` (an audit trail). Modeled as `StepReceipt`; accumulating a `Collection[StepReceipt]` or folding receipts into one record is the fold-to-struct case. | ACTIVE | `LANG-FOLD-STRUCT-ACCUMULATOR-P2/P3` |
| LR-P03 | **nested availability fold** | `check_availability` sums slots over locations × technicians × dates. Modeled as a SCALAR `SumSlots` fold; the nested/`flat_map` shape is out of scope. | ACTIVE (scalar only) | fold-struct + (future) nested-iteration |
| LR-P04 | **entity / state threading (Ctx)** | `pipeline.ig` rebuilds the whole `Ctx` per step via `CtxWithX` factories — the `@trade/@vendor/@zip` accumulated state. `Vendor` is a config+behaviour entity. | ACTIVE — design | `LANG-COMPOSE-ENTITY-P1 → PROP` |
| LR-P05 | **dynamic vendor-protocol dispatch** | `VendorProtocol` branches statically (`elocal`/`inquirly`); we want `call_contract(vendor_key + "Response", p)`. Variable callee → Unknown. | INTENTIONAL fail-closed | `LAB-DYNAMIC-CONTRACT-DISPATCH-P2` |
| LR-P06 | **record-literal inference (factories)** | `MakeParams` / `MakeAccept` / `MakeReject` / `MakeSignalX` exist only to pin record types (inline/branch literals infer to Unknown in Rust → `OOF-P1 Unresolved field` on `params.vendor_key`). | ACTIVE | `LANG-RUBY-RECORD-LITERAL-INFERENCE` / `LAB-NESTED-RECORD-LITERAL-TYPING` |
| LR-P07 | **effect surface — DB reads** | `find_trade/vendor/zip`, `vendor.companies`, `technician.availability` are StorageCapability reads; injected as `trade_found`/`vendor`/`slot_counts`. | DOCUMENTED — behind | `PROP-035` effect surface + `PROP-046` storage capability + IO-runtime |
| LR-P08 | **clock capability** | `set_current_time` / business hours / availability dates need a TZ-aware clock; injected as `current_min` (minute-of-day). Same event-time discipline as air_combat (no source `now()`). | DOCUMENTED — behind | clock capability (see `LANG-TEMPORAL-STATE-P1` boundary) |
| LR-P09 | **RNG capability** | `upi = Random.alphanumeric(8)` — injected as a string token; a real service needs an RNG effect. | DOCUMENTED — behind | effect-surface RNG capability (none yet) |
| LR-P10 | **service envelope + outbox write** | webhook ingress → ServiceRequest; JSON reply → ServiceResponse; `OutboxEvent.create!` is an effect-with-receipt. `BuildLeadSignal` builds the payload purely; the append is out of scope. | DOCUMENTED — behind | `LAB-IGNITER-LANG-MICROSERVICE` envelope + effect write + ServiceLoop/PROP-037 for the serve loop |

## Entrypoint / DX Refactor (2026-06-14)

`entrypoint RunAccept` added — names the start contract in source.

| ID | Name | Evidence | Status | Route |
|---|---|---|---|---|
| LR-P11 | **named run-profiles wanted** | `RunAccept` / `RunAcceptSignal` / `RunReject` are three natural run targets; only one bare `entrypoint` is expressible. Each wants a PROP-029 named profile with its own `args` (accept vs reject fixtures). | ACTIVE — DX | `PROP-029` rich entrypoint |

Cross-cutting (validated across the 3 SparkCRM companions): `variant`+`match` is
dual-clean for result/railway types; the **effect surface is NOT yet dual-clean**
(`effect`+`capability`+`effect using` → Rust `E-IO-EFFECT-UNKNOWN`; `via profile`
→ Rust parser `OOF-G1`) — Ruby-only, confirming the IO gap LR-P07..P10 name.

## Capability Discovery (positive)

`variant` + `match` **compile dual-clean** and faithfully model the dry-monads
`Result`/`.bind` railway: `variant Pipe { Proceed{ctx} | Reject{stage,message} }`
with each step `match`-ing on the carried result. Variant constructors are also
usable inside `if/else` branches without the record-literal-Unknown problem that
plain records hit. This is the cleanest "railway" the fleet has expressed.

## Safety Interpretation

Proves the current language can model a non-trivial, real-world, multi-step
eligibility/routing service as a **pure** railway with typed outcomes, vendor
protocol mapping, and an outbox payload. It does NOT claim: any DB/IO, a real
clock or RNG, an HTTP server, a running serve loop, or production fidelity (the
nested availability scan is reduced to a scalar slot total).

## Non-Goals

- No DB / SQL / ORM / ActiveRecord.
- No HTTP server / Rack / accept loop / sockets.
- No clock / `now()` / time-zone resolution.
- No RNG.
- No durable outbox / queue write.
- No dynamic vendor dispatch (static only).
- No fold-to-struct / entity / bind-combinator implementation (pressure, not a fix).

## Recommended Route

1. stdlib `Outcome`/`Result` + a `bind`/`and_then` combinator over `variant` —
   the single highest-leverage unlock for LR-P01 (collapses the per-step `match`).
2. `LANG-FOLD-STRUCT-ACCUMULATOR-P3/P4` — for LR-P02 (receipt accumulation).
3. `LANG-COMPOSE-ENTITY` PROP — for LR-P04 (`Ctx`/`Vendor` entity).
4. Effect-surface / IO-runtime (LR-P07..P10) — the real microservice shell, via
   the MICROSERVICE envelope + ServiceLoop/PROP-037, once the pure pressure is
   harvested. See `report.md`.

## Wave P11 Recheck Summary (2026-06-14)

Rust: ok / 0 diagnostics. Ruby: ok / 0 diagnostics. DUAL-TOOLCHAIN CLEAN.

Integrated into the fleet via `LAB-LEAD-ROUTER-BASELINE-P1` (`175/175 PASS`). `entrypoint RunAccept` remains present and clean. Stable baseline hash: `sha256:3cca9ed52a593e60ed86fb59e359809d255425af5690ded364cd8329fab71e1b`.

Fold P3/P4 are landed, but this wave made no app source changes; existing pressure IDs remain routed as migration/design opportunities. No new pressures. No regressions.

## Wave P12 Recheck Summary (2026-06-15)

Rust: ok / 0 diagnostics. Ruby: ok / 0 diagnostics. DUAL-TOOLCHAIN CLEAN.

The 20-app fleet expansion and new companion intake had no diagnostic impact on this app. Existing pressure IDs remain routed as migration/design opportunities. No source edits. No new pressures. No regressions.
