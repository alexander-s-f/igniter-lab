# LAB Lead Router Compilation Baseline v0

**Card:** LAB-LEAD-ROUTER-BASELINE-P1  
**Status:** CLOSED / PROVED - 175/175 PASS  
**Date:** 2026-06-14  
**Authority:** lab evidence baseline only; no implementation or canon authority

## Decision

`lead_router` is frozen as a positive dual-toolchain baseline and pressure source.

It models a real SparkCRM lead-routing / bid-eligibility microservice as a pure
Igniter core: a `Pipe` railway (`Proceed` / `Reject`) over `variant` + `match`,
with DB reads, clock, RNG, HTTP ingress, and outbox writes outside the core.

## Proof

Runner:

`igniter-view-engine/proofs/verify_lab_lead_router_baseline_p1.rb`

Result:

`175/175 PASS`

The runner uses fresh output directories and a spaced second Rust invocation to
avoid the known assembler timing/path race. The second Rust run confirms hash
stability without rapid back-to-back reuse of the same output path.

## Compilation Baseline

| Toolchain | Result | Diagnostics | Source hash |
|---|---|---:|---|
| Ruby canon `CompilerOrchestrator.compile_sources` | `ok` | 0 | `sha256:3cca9ed52a593e60ed86fb59e359809d255425af5690ded364cd8329fab71e1b` |
| Rust lab `igniter_compiler compile` | `ok` | 0 | `sha256:3cca9ed52a593e60ed86fb59e359809d255425af5690ded364cd8329fab71e1b` |

The previous documentation hash `sha256:16deae290738578a09cc324de18ff2312b14b960e0d581945285b913d534e3ba`
is not the current full-app absolute-path multifile hash. P1 records the current
dual-toolchain full-app hash above.

## Shape

| Metric | Value |
|---|---:|
| source files | 4 |
| types | 6 |
| variants | 1 (`Pipe`) |
| contracts | 31 |
| textual `call_contract` mentions | 38 |
| executable `call_contract` forms | 37, all string-literal Tier 1 |
| textual `match` mentions | 10 |
| executable `match` expressions | 9 |
| fold sites | 1 scalar (`SumSlots`) |
| entrypoint | `RunAccept` |

The `38`/`10` textual counts preserve the registry wording, including comments
and report examples. Executable code has `37` `call_contract` forms and `9`
`match` expressions after stripping comments. All executable `call_contract`
forms use string literal callees and resolve to known contracts.

## Positive Discovery

`variant Pipe { Proceed | Reject }` plus `match` compiles dual-clean and models
the production `dry-monads` Result railway:

- `Proceed { ctx : Ctx }` carries the accumulating context.
- `Reject { stage, message }` short-circuits later steps.
- The seven pipeline step matches carry `Reject` unchanged.
- Vendor response and lead-signal construction also branch over `Pipe`.

This is positive capability evidence, not a request to implement `Outcome` here.

## Entrypoint

`entrypoint RunAccept` is present and verified in both artifacts:

- source: `example.ig`
- manifest entrypoint: `resolved_contract = "RunAccept"`
- SIR/metadata entrypoint: `RunAccept`

`RunAccept`, `RunAcceptSignal`, and `RunReject` remain LR-P11 pressure for
PROP-029 rich named run profiles.

## Pressure Routes

| ID | Route |
|---|---|
| LR-P01 | stdlib `Outcome` / `Result` + `bind` / `and_then` |
| LR-P02 | `LANG-FOLD-STRUCT-ACCUMULATOR-P3/P4` |
| LR-P03 | fold-struct plus future nested iteration |
| LR-P04 | `LANG-COMPOSE-ENTITY` |
| LR-P05 | `LAB-DYNAMIC-CONTRACT-DISPATCH-P2` fail-closed route |
| LR-P06 | record literal / nested record typing tracks |
| LR-P07 | `PROP-035` / `PROP-046` / IO runtime |
| LR-P08 | clock/event-time boundary |
| LR-P09 | future effect-surface RNG |
| LR-P10 | microservice envelope + effect write + ServiceLoop host |
| LR-P11 | `PROP-029` rich entrypoint profiles |

## IO Boundary

The source contains no executable capability/effect declarations, no DB/SQL/ORM,
no HTTP server primitive, no ambient clock, and no RNG call.

Boundary shape:

- DB reads are injected as flags/data (`trade_found`, `vendor`, `slot_counts`).
- Clock is injected as `current_min`.
- RNG token is injected as `upi`.
- HTTP ingress and JSON reply are ServiceRequest/ServiceResponse pressure only.
- Outbox write is pressure only; `BuildLeadSignal` creates the pure payload.

This positions `lead_router` as the request/reply complement to `air_combat`'s
tick-loop pressure.

## Closed Surfaces

- No DB / SQL / ORM / ActiveRecord.
- No HTTP server / Rack / accept loop / sockets.
- No clock / `now()` / time-zone resolution.
- No RNG.
- No durable outbox / queue write.
- No dynamic vendor dispatch.
- No Outcome/bind implementation.
- No fold-to-struct implementation.
- No entity implementation.
- No app source migration.
