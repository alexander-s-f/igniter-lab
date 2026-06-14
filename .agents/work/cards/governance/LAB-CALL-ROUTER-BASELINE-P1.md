# LAB-CALL-ROUTER-BASELINE-P1

**Status:** CLOSED — PROVED (178/178 PASS)  
**Route:** lab / app baseline / call_router  
**Date:** 2026-06-14  
**Authority:** evidence baseline only; no implementation

## Goal

Freeze `call_router` as a positive dual-toolchain baseline and pressure source.

`call_router` is a pure Igniter companion for a real SparkCRM CallRail ↔ RingCentral webhook-correlation subsystem. It models two independent webhook streams, a telephony presence state machine, and the operator context mutation decision while keeping DB reads/writes, clock freshness windows, HTTP ingress, and background workers outside the pure core.

This is the third distinct service shape in the current companion set:

| App | Shape |
|---|---|
| `lead_router` | request/reply railway |
| `air_combat` | tick-loop / ServiceLoop pressure |
| `call_router` | two-stream webhook correlation + operator state machine |

## Current Claimed Baseline

From `call_router/PRESSURE_REGISTRY.md` and `report.md`:

| Metric | Value |
|---|---|
| Ruby | ok / 0 diagnostics |
| Rust | ok / 0 diagnostics |
| source files | 6 |
| types | 7 |
| variants | 3 (`Telephony`, `MatchResult`, `ChannelFlow`) |
| contracts | 25 |
| call_contract sites | 30, all Tier-1 literals |
| match sites | 11 |
| filter / concat | 1 / 1 |
| source_hash | `sha256:1b8da43dd1fb66ae6b587056bfe459734e9eb854ccb2a1b308e996ac0334eed5` (absolute proof-runner path; `entrypoint RunConnectedMatched` added) |

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/dev-tutorial.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/call_router/PRESSURE_REGISTRY.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/call_router/report.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/call_router/types.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/call_router/correlate.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/call_router/operator.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/call_router/webhook.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/call_router/service.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/call_router/example.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/governance/LAB-LEAD-ROUTER-BASELINE-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/governance/LAB-AIR-COMBAT-BASELINE-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lab/LAB-DYNAMIC-CONTRACT-DISPATCH-P2.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/spec/ch13-managed-recursion.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/language-covenant.md`

## Proof Questions

1. Does the full 6-file app compile cleanly in Ruby and Rust using the proof-runner subprocess path rather than shell-piped rapid invocations?
2. Are the claimed counts stable: 6 files, 7 types, 3 variants, 25 contracts, 30 `call_contract`, 11 `match`, 1 `filter`, 1 `concat`?
3. Are all `call_contract` sites Tier-1 string literals rather than dynamic callees?
4. Does `variant Telephony` + `match` express the RingCentral presence state machine dual-clean?
5. Does `variant ChannelFlow` + `match` express channel-to-behavior policy dual-clean?
6. Does `MatchResult` prove the correlation result shape while keeping unresolved DB `.first` outside the pure core?
7. Does CR-P02 correctly route to `stdlib.string.contains` / `ends_with` rather than pretending exact equality is production-faithful?
8. Does CR-P03 correctly route to dual-toolchain `first`/`last` plus matchable `Option`?
9. Does CR-P10 explicitly route standing two-stream correlation to ServiceLoop / PROP-037 rather than an ad hoc host loop?
10. Does the app keep DB/clock/RNG/HTTP/outbox/background-worker authority outside the pure core?
11. Is `entrypoint RunConnectedMatched` present, dual-clean, and reflected in manifest/metadata?
12. Is CR-P11 captured as rich PROP-029 run-profile pressure (`RunConnectedMatched` / `RunNoCall` / `RunUpsert` / `RunChannel`)?
13. Is the Rust assembler/stdout timing flake documented so baseline verification avoids false internal-error conclusions?

## Pressure IDs To Preserve

| ID | Pressure | Route |
|---|---|---|
| CR-P01 | operator state machine via `variant` + `match` | positive regression evidence |
| CR-P02 | fuzzy phone matching missing | `LANG-STDLIB-STRING-CONTAINS-ENDS-WITH-P1` |
| CR-P03 | `first`/`last` + matchable `Option` missing | `LANG-STDLIB-COLLECTION-FIRST-LAST-OPTION-P1` |
| CR-P04 | entity/state threading (`Operator`) | `LANG-COMPOSE-ENTITY` |
| CR-P05 | record-literal factories still needed in match/if arms | record literal / nested record tracks |
| CR-P06 | webhook lifecycle fold-over-record | `LANG-FOLD-STRUCT-ACCUMULATOR-P3/P4` |
| CR-P07 | dynamic vendor/channel dispatch avoided | `LAB-DYNAMIC-CONTRACT-DISPATCH-P2` |
| CR-P08 | DB reads/writes | `PROP-046` storage + `PROP-035` effect surface + IO runtime |
| CR-P09 | clock / freshness window | clock capability / temporal boundary |
| CR-P10 | two-stream webhook ingress + correlation window | `PROP-023` stream input + ServiceLoop / `PROP-037` |
| CR-P11 | named run-profiles wanted | `PROP-029` rich entrypoint profiles |

## Deliverables

- Proof runner: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_call_router_baseline_p1.rb`, target at least 100 checks.
- Lab doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/governance/lab-call-router-compilation-baseline-v0.md`.
- Update `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/call_router/PRESSURE_REGISTRY.md` with closure summary if needed.
- Update this card with closure summary.
- Portfolio index update after closure.

## Acceptance

- Ruby compile is `ok` / 0 diagnostics.
- Rust compile is `ok` / 0 diagnostics.
- Source hash is stable across two fresh proof-runner-style runs or path sensitivity is documented.
- Proof runner uses Open3/mktmpdir or an equivalent clean subprocess route and avoids shell-pipe false failures.
- CR-P01..CR-P11 are preserved and routed.
- `entrypoint RunConnectedMatched` is present and verified dual-clean.
- `Telephony`/`ChannelFlow`/`MatchResult` positive `variant` + `match` evidence is explicitly documented.
- `call_router` is classified as positive baseline + pressure source, not blocker.
- ServiceLoop / PROP-037 is named as the route for standing correlation; no host-loop evasion.
- No app source edits unless correcting documentation-only metadata.

## Closed Surfaces

- No DB / SQL / ORM / ActiveRecord.
- No HTTP server / Rack / accept loop / sockets.
- No real fuzzy phone matching implementation.
- No clock / `now()` / time-zone resolution.
- No durable outbox / queue write.
- No background worker implementation.
- No dynamic vendor/channel dispatch.
- No `contains` / `ends_with` implementation.
- No `first` / `last` / `Option` implementation.
- No fold-to-struct implementation.
- No entity implementation.
- No app source migration.

## Runner Notes

The registry reports a Rust CLI package-writer false failure when stdout is shell-redirected or piped in rapid succession. Use a clean subprocess path such as Ruby `Open3` plus `mktmpdir`, fresh `--out` paths, and avoid piping compiler stdout through truncating consumers. The baseline should distinguish compiler/typecheck diagnostics from package-writer fd/timing artifacts.

---

## Closure Summary (2026-06-14)

**Status:** CLOSED - PROVED 178/178.  
**Result:** `verify_lab_call_router_baseline_p1.rb` passes the full baseline
guard.

### Compiler baseline

| Toolchain | Status | Diagnostics |
|---|---|---|
| Ruby | `ok` | 0 |
| Rust | `ok` | 0 |

The absolute proof-runner source hash is stable in both toolchains:

`sha256:1b8da43dd1fb66ae6b587056bfe459734e9eb854ccb2a1b308e996ac0334eed5`

Relative-path invocations can produce a different deterministic hash, so the
baseline names the absolute Open3/mktmpdir proof-runner path as the evidence
path.

### Counts frozen

6 files, 7 types, 3 variants, 25 contracts, 30 Tier-1 literal
`call_contract` sites, 11 `match` sites, 1 `filter`, 1 `concat`.

### Positive evidence

- `Telephony` + `OperatorStep` proves the RingCentral presence state machine.
- `ChannelFlow` + `ChannelBehaviorOf` proves channel-to-behavior policy.
- `MatchResult` proves correlation result shape while DB `.first` remains
  injected/outside the pure core.
- `entrypoint RunConnectedMatched` is present and reflected in manifest/SIR.

### Pressure routes preserved

CR-P01..CR-P11 are preserved and routed. Standing two-stream correlation routes
to PROP-023 stream input plus ServiceLoop / PROP-037, not an ad hoc host loop.
CR-P11 captures named run-profile pressure for `RunConnectedMatched`,
`RunNoCall`, `RunUpsert`, and `RunChannel`.

### Deliverables

| Artefact | Path | Status |
|---|---|---|
| Proof runner | `igniter-view-engine/proofs/verify_lab_call_router_baseline_p1.rb` | **178/178 PASS** |
| Lab doc | `lab-docs/governance/lab-call-router-compilation-baseline-v0.md` | Written |
| Pressure registry | `igniter-apps/call_router/PRESSURE_REGISTRY.md` | Updated |
| This card | `.agents/work/cards/governance/LAB-CALL-ROUTER-BASELINE-P1.md` | CLOSED |
| Portfolio index | `.agents/portfolio-index.md` | Updated |

### Closed surfaces

No app source edits, DB/SQL/ORM/ActiveRecord, HTTP/Rack/server/socket, real fuzzy
phone matching, clock/`now()`/DateTime, durable outbox/queue, background worker,
dynamic vendor/channel dispatch, `contains`/`ends_with`, `first`/`last`/`Option`,
fold-to-struct, entity implementation, or host-loop authority.
