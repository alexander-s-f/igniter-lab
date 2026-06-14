# LAB-CALL-ROUTER-COMPILATION-BASELINE-v0

**Status:** CLOSED - PROVED 178/178 PASS  
**Route:** lab / app baseline / call_router  
**Date:** 2026-06-14  
**Authority:** evidence baseline only; no implementation

---

## Executive Summary

`call_router` is a pure Igniter companion for SparkCRM's real CallRail to
RingCentral webhook-correlation subsystem. It models two independent webhook
streams, a telephony presence state machine, CallRail channel behavior, and the
operator context mutation decision while keeping DB reads/writes, clock freshness
windows, HTTP ingress, outbox writes, and background workers outside the pure
core.

This baseline classifies `call_router` as a positive baseline, a positive
dual-toolchain baseline, and pressure source, not a blocker.

---

## Baseline Verification

The full 6-file app compiles cleanly in both toolchains using the proof-runner
subprocess path (`Open3.capture3` plus `Dir.mktmpdir`) and fresh `--out` paths.
The runner does not pipe compiler stdout through truncating consumers.

| Metric | Value |
|---|---|
| Ruby | `ok` / 0 diagnostics |
| Rust | `ok` / 0 diagnostics |
| source files | 6 |
| types | 7 |
| variants | 3 (`Telephony`, `MatchResult`, `ChannelFlow`) |
| contracts | 25 |
| `call_contract` sites | 30, all Tier-1 PascalCase string literals |
| `match` sites | 11 |
| `filter` / `concat` | 1 / 1 |
| source_hash | `sha256:1b8da43dd1fb66ae6b587056bfe459734e9eb854ccb2a1b308e996ac0334eed5` |

### Path Sensitivity

The live source hash above is the stable value under the standard absolute
workspace paths used by the proof runner:

`/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/call_router/*.ig`

Relative-path invocations can produce a different deterministic hash while still
compiling `ok` / 0 diagnostics. This baseline therefore treats the absolute
proof-runner path as the evidence path.

### Rust stdout / package-writer note

The app registry reports an intermittent Rust CLI package-writer false failure
when stdout is shell-redirected or piped in rapid succession. That is an
fd/timing artifact, not source failure. Baseline verification uses clean
subprocess capture and fresh output directories to avoid false internal-error
conclusions.

---

## Positive Evidence

### Telephony state machine

`Telephony { NoCall | Ringing | CallConnected }` plus `OperatorStep` proves a
real operator state machine with `variant` + `match`. On `CallConnected`, the
pure core either sets the operator's call/channel context or clears context if
the CallRail call is unresolved. On `Ringing` and `NoCall`, context is cleared.

### Channel behavior policy

`ChannelFlow { Marketing | CallCenter | Inactive }` plus `ChannelBehaviorOf`
expresses the channel-to-behavior policy dual-clean. This models the production
fact that the CallRail channel kind determines the operator's available flow.

### Correlation result

`MatchResult { Matched(call) | Unmatched }` preserves the correlation result
shape while keeping the unresolved production `.first` outside the pure core.
The pure scan counts candidate matches; the selected `matched_call` is injected.

### Entrypoint

`entrypoint RunConnectedMatched` is present in source, reflected in the manifest
as `default_entrypoint`, and reflected in SemanticIR as `entrypoint_decl`.

---

## Pressures Preserved

| ID | Pressure | Route |
|---|---|---|
| CR-P01 | operator state machine via `variant` + `match` | positive regression evidence |
| CR-P02 | fuzzy phone matching missing | `LANG-STDLIB-STRING-CONTAINS-ENDS-WITH-P1` |
| CR-P03 | `first` / `last` + matchable `Option` missing | `LANG-STDLIB-COLLECTION-FIRST-LAST-OPTION-P1` |
| CR-P04 | entity/state threading (`Operator`) | `LANG-COMPOSE-ENTITY` |
| CR-P05 | record-literal factories still needed in match/if arms | record literal / nested record tracks |
| CR-P06 | webhook lifecycle fold-over-record | `LANG-FOLD-STRUCT-ACCUMULATOR-P3/P4` |
| CR-P07 | dynamic vendor/channel dispatch avoided | `LAB-DYNAMIC-CONTRACT-DISPATCH-P2` |
| CR-P08 | DB reads/writes | `PROP-046` storage + `PROP-035` effect surface + IO runtime |
| CR-P09 | clock / freshness window | clock capability / temporal boundary |
| CR-P10 | two-stream webhook ingress + correlation window | `PROP-023` stream input + ServiceLoop / `PROP-037` |
| CR-P11 | named run-profiles wanted | `PROP-029` rich entrypoint profiles |

---

## Entrypoint / Run-Profile Pressure

Only one bare entrypoint is implemented today: `entrypoint RunConnectedMatched`.
The app also contains `RunNoCall`, `RunUpsert`, and `RunChannel`; together these
four scenarios are CR-P11 pressure for future PROP-029 named run-profiles.

---

## Cross-Baseline Position

`call_router` is the third distinct companion service shape:

| App | Shape |
|---|---|
| `lead_router` | request/reply railway |
| `air_combat` | tick-loop / ServiceLoop pressure |
| `call_router` | two-stream webhook correlation + operator state machine |

For a real service shell, the request/reply side should use the existing
microservice envelope path, while standing correlation belongs to ServiceLoop /
Progression (`PROP-037`) plus stream input (`PROP-023`). This baseline does not
authorize an ad hoc host loop.

---

## Closed Surfaces

- No DB, SQL, ORM, ActiveRecord, storage read/write, or production persistence.
- No HTTP server, Rack, accept loop, sockets, or webhook listener.
- No real fuzzy phone matching implementation.
- No clock, `now()`, `DateTime`, or time-zone resolution.
- No durable outbox, queue write, or background worker.
- No dynamic vendor/channel dispatch.
- No `contains` / `ends_with` implementation.
- No `first` / `last` / `Option` implementation.
- No fold-to-struct implementation.
- No entity implementation.
- No app source migration.

---

## Proof

```text
runner: igniter-view-engine/proofs/verify_lab_call_router_baseline_p1.rb
target: at least 100 checks
result: 178/178 PASS
```

The proof compiles the full app twice in Rust and twice in Ruby, verifies
manifest/SIR metadata, source hash stability, counts, Tier-1 dispatch, variant
evidence, entrypoint metadata, CR-P01..CR-P11 routes, ServiceLoop routing, closed
surfaces, and closure artifacts.
