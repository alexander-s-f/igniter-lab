# Call Router Pressure Registry

Created: 2026-06-14 (off-track app — a SparkCRM companion microservice, pure core)

`call_router` is a pure re-modeling of a **real production** SparkCRM subsystem:
the **CallRail ↔ RingCentral webhook correlation** engine and the **operator
state machine** it drives. CallRail (many companies / tracking numbers) forwards a
call into a single RingCentral main number; both send webhooks; we match them, and
the **(call, channel) pair decides the operator's behaviour** (which company /
trade context, and what is available for orders).

Pure core only: phones are pre-normalized Strings, times are minute-of-day
Integers, and every DB read/write is injected.

## Baseline

Dual-toolchain CLEAN.

```bash
cd igniter-compiler
cargo run -- compile \
  ../igniter-apps/call_router/types.ig ../igniter-apps/call_router/correlate.ig \
  ../igniter-apps/call_router/operator.ig ../igniter-apps/call_router/webhook.ig \
  ../igniter-apps/call_router/service.ig ../igniter-apps/call_router/example.ig \
  --out /tmp/call_router.igapp
```

| Metric | Value |
|---|---|
| Ruby | ok / 0 diagnostics |
| Rust | ok / 0 diagnostics |
| source files | 6 |
| types | 7 |
| variants | 3 (`Telephony`, `MatchResult`, `ChannelFlow`) |
| contracts | 25 |
| call_contract sites | 30 (Tier-1 literals — static dispatch) |
| match sites | 11 (state machine + channel flow + extraction) |
| filter / concat | 1 / 1 |
| source_hash | `sha256:1b8da43dd1fb66ae6b587056bfe459734e9eb854ccb2a1b308e996ac0334eed5` (absolute proof-runner path; `entrypoint RunConnectedMatched` added) |

> NOTE: the Rust CLI's package writer intermittently surfaces a spurious
> `Internal compiler error: No such file or directory` when its stdout is shell-
> redirected/piped in rapid succession (an fd/timing artifact, same class as the
> air_combat SIGPIPE note). It is NOT a source fault — the Ruby TC is clean and
> compiling via a clean subprocess (Open3 + mktmpdir, as the proof runners do)
> returns the real `ok` (25 contracts). Reach for the Open3 path to verify.

## Provenance (production → pure model)

| Production (sparkcrm) | call_router model |
|---|---|
| `Webhooks::RingcentralController#create` | `service.ig` HandleRingcentral |
| `Ringcentral::Lib::Parser` (`call_connected?`/`no_call?`/`ringing?`) | `correlate.ig` ClassifyTelephony + `variant Telephony` |
| `Ringcentral::WebhookService#call` (operator state mutation) | `operator.ig` OperatorStep + SetContext/ClearContext |
| `callrail_find_record(phone)` (`LIKE ... .order(desc).first`) | `correlate.ig` MatchCall (pure scan + injected `.first`) |
| `find_company_by_callrail` / `find_trade_vendor_by_did` | injected `company` / `vendor` inputs |
| `CallrailCompany.kind` (marketing/call_center) | `operator.ig` ChannelFlowOf + ChannelBehaviorOf + `variant ChannelFlow` |
| `Calls::CallrailWebhook#update` (webhooks << type) | `webhook.ig` AppendWebhook |
| `RingcentralLog.new(...)` | `service.ig` BuildLog → `CallLog` |

## Pressures

| ID | Name | Evidence | Status | Route |
|---|---|---|---|---|
| CR-P01 | **operator state machine (variant + match)** | `operator.ig` OperatorStep matches `Telephony { CallConnected \| Ringing \| NoCall }` → set/clear context. The cleanest state-machine the fleet has expressed; variant+match compile dual-clean. | POSITIVE — capability | — (keep as regression evidence) |
| CR-P02 | **fuzzy phone matching missing** | production matches `customer_phone_number LIKE %suffix%`; `stdlib.string` has no `contains`/`ends_with`, so `correlate.ig` MatchCall uses EXACT normalized equality. | ACTIVE — stdlib gap | new `LANG-STDLIB-STRING` contains/ends_with |
| CR-P03 | **`first`/`Option` not dual-clean; Option not matchable** | picking the most-recent hit needs `first` → `Option[T]`, but `first` is **Rust-only** (Ruby lacks it) and `Option` is **not a matchable variant** (`OOF-KIND4`). So the resolved `matched_call` is injected; the pure scan only counts. | ACTIVE | dual-toolchain `first`/`last` + an `Option` variant + `or_else`/match |
| CR-P04 | **entity / state threading (Operator)** | SetContext/ClearContext rebuild the whole `Operator` record by hand; `Operator` is the call-context entity. | ACTIVE — design | `LANG-COMPOSE-ENTITY-P1 → PROP` |
| CR-P05 | **record-literal inference (factories)** | inline records in `if/else` AND `match` arms infer to Unknown in Rust (`OOF-TY1 expected ChannelBehavior, got Unknown`), forcing `MakeBehavior`/`Demo*` factories. | ACTIVE | `LANG-RUBY-RECORD-LITERAL-INFERENCE` / `LAB-NESTED-RECORD-LITERAL-TYPING` |
| CR-P06 | **webhook lifecycle fold** | `webhook.ig` AppendWebhook grows `webhooks` via `concat`; the natural form is `fold(events, call0, (call, ev) -> AppendWebhook(...))` — fold-over-record. | ACTIVE | `LANG-FOLD-STRUCT-ACCUMULATOR-P2/P3` |
| CR-P07 | **dynamic vendor/channel dispatch avoided** | behaviour forks on `kind` string statically; a data-named dispatch (`call_contract(kind, ...)`) would be Unknown. | INTENTIONAL fail-closed | `LAB-DYNAMIC-CONTRACT-DISPATCH-P2` |
| CR-P08 | **effect surface — DB reads/writes** | `find_operator_by_extension_id`, `callrail_find_record`, company/vendor/tracking lookups, and operator/call `.save` are StorageCapability effects; all injected here. | DOCUMENTED — behind | `PROP-046` storage + `PROP-035` effect surface + IO-runtime |
| CR-P09 | **clock / freshness window** | `callrail_find_record` is scoped to `created_at: 15.minutes.ago..now` (commented in prod); time is injected as `started_at_min`. Same event-time discipline (no source `now()`). | DOCUMENTED — behind | clock capability (`LANG-TEMPORAL-STATE-P1` boundary) |
| CR-P10 | **two-stream webhook ingress + correlation window** | two independent webhook streams (CallRail lifecycle + RingCentral presence) must be correlated; a real service buffers/windows them. | DOCUMENTED — behind | `PROP-023` stream input + `MICROSERVICE` envelope + ServiceLoop/`PROP-037` |

## Entrypoint / DX Refactor (2026-06-14)

`entrypoint RunConnectedMatched` added — names the start contract in source.

| ID | Name | Evidence | Status | Route |
|---|---|---|---|---|
| CR-P11 | **named run-profiles wanted** | `RunConnectedMatched` / `RunNoCall` / `RunUpsert` / `RunChannel` are four natural scenarios; only one bare `entrypoint` is expressible. Each wants a PROP-029 named profile. | ACTIVE — DX | `PROP-029` rich entrypoint |

## Capability Discovery (positive)

`variant` + `match` model a **telephony presence state machine** cleanly and
dual-clean — `Telephony { NoCall | Ringing | CallConnected{…} }` driving operator
transitions. Together with lead_router's `Pipe` railway, this is strong evidence
that variant/match is production-ready for state machines and result types. Gaps
sit at the edges: `Option` is not matchable and `first` is Rust-only (CR-P03).

## Safety Interpretation

Proves the language can model real telephony webhook correlation + an operator
state machine as a **pure** core. It does NOT claim: any DB/IO, real phone
matching (exact-equality only), a real clock, an HTTP server, a running serve
loop, or stream buffering across the two webhook sources.

## Non-Goals

- No DB / SQL / ORM / ActiveRecord.
- No HTTP server / Rack / accept loop / sockets.
- No real fuzzy phone matching (no `stdlib.string.contains`).
- No clock / `now()`.
- No dynamic channel/vendor dispatch (static only).
- No fold-to-struct / entity / Option-match implementation (pressure, not a fix).

## Recommended Route

1. `stdlib.string.contains`/`ends_with` (CR-P02) + dual-toolchain `first`/`last`
   and a matchable `Option` variant (CR-P03) — the matching layer's real gaps.
2. `LANG-COMPOSE-ENTITY` PROP — for CR-P04 (`Operator` entity).
3. `LANG-FOLD-STRUCT-ACCUMULATOR-P3/P4` — for CR-P06 (webhook fold).
4. Effect-surface + stream input + ServiceLoop (CR-P08..P10) — the real
   correlation service shell. See `report.md`.

## Baseline Closure (2026-06-14)

`LAB-CALL-ROUTER-BASELINE-P1` closed this registry as a positive dual-toolchain
baseline and pressure source. Proof runner:
`igniter-view-engine/proofs/verify_lab_call_router_baseline_p1.rb`
(`178/178 PASS`).

Closure facts:

- Ruby: `ok` / 0 diagnostics.
- Rust: `ok` / 0 diagnostics.
- Absolute proof-runner source hash:
  `sha256:1b8da43dd1fb66ae6b587056bfe459734e9eb854ccb2a1b308e996ac0334eed5`.
- Counts preserved: 6 files, 7 types, 3 variants, 25 contracts, 30
  `call_contract` sites, 11 `match` sites, 1 `filter`, 1 `concat`.
- CR-P01..CR-P11 preserved and routed.
- `entrypoint RunConnectedMatched` verified in manifest and SemanticIR.
- Shell-pipe Rust stdout/package-writer false failures remain documented as an
  fd/timing artifact; use Open3/mktmpdir proof-runner path.
- No app source edits, no DB/clock/HTTP/queue/dynamic-dispatch implementation,
  no host-loop authority.

## Wave P11 Recheck Summary (2026-06-14)

Rust: ok / 0 diagnostics. Ruby: ok / 0 diagnostics. DUAL-TOOLCHAIN CLEAN.

Integrated into the fleet via `LAB-CALL-ROUTER-BASELINE-P1` (`178/178 PASS`). `entrypoint RunConnectedMatched` remains present and clean. Stable baseline hash: `sha256:1b8da43dd1fb66ae6b587056bfe459734e9eb854ccb2a1b308e996ac0334eed5`.

Fold P3/P4 are landed, but this wave made no app source changes; existing pressure IDs remain routed as migration/design opportunities. No new pressures. No regressions.
