# LAB-LEAD-ROUTER-BASELINE-P1

**Status:** CLOSED — PROVED (175/175 PASS)  
**Route:** lab / app baseline / lead_router  
**Date:** 2026-06-14  
**Authority:** evidence baseline only; no implementation

## Goal

Freeze `lead_router` as a positive dual-toolchain baseline and pressure source.

`lead_router` is a pure Igniter companion for a real SparkCRM lead-routing / bid-eligibility microservice. It models the production `dry-monads` Result `.bind` railway as an Igniter `variant Pipe` plus `match` short-circuit chain while keeping DB, clock, RNG, HTTP ingress, and outbox writes outside the pure core.

## Current Claimed Baseline

From `lead_router/PRESSURE_REGISTRY.md` and `report.md`:

| Metric | Value |
|---|---|
| Ruby | ok / 0 diagnostics |
| Rust | ok / 0 diagnostics |
| source files | 4 |
| types | 6 |
| variants | 1 (`Pipe { Proceed | Reject }`) |
| contracts | 31 |
| call_contract sites | 38 textual; 37 executable, all Tier-1 literals |
| match sites | 10 textual; 9 executable |
| fold sites | 1 scalar |
| source_hash | `sha256:3cca9ed52a593e60ed86fb59e359809d255425af5690ded364cd8329fab71e1b` (`entrypoint RunAccept` present) |

## Closure Summary (2026-06-14)

Verdict: **positive dual-toolchain baseline frozen; pressure source preserved.**

Proof:

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_lead_router_baseline_p1.rb`
- Result: `175/175 PASS`

Lab doc:

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/governance/lab-lead-router-compilation-baseline-v0.md`

Findings:

- Ruby canon compile: `ok` / 0 diagnostics.
- Rust lab compile: `ok` / 0 diagnostics.
- Ruby and Rust agree on full-app absolute-path multifile `source_hash`:
  `sha256:3cca9ed52a593e60ed86fb59e359809d255425af5690ded364cd8329fab71e1b`.
- The runner uses fresh `--out` paths and a spaced second Rust invocation to
  avoid the known assembler timing/path race.
- `entrypoint RunAccept` is present and reflected in manifest/SIR metadata.
- Textual counts preserve registry pressure (`38` `call_contract`, `10` `match`);
  executable source after stripping comments has `37` literal `call_contract`
  forms and `9` `match` expressions.
- All executable `call_contract` sites are Tier-1 string literals resolving to
  known contracts; desired dynamic vendor dispatch appears only as LR-P05
  comment/pressure.
- `variant Pipe { Proceed | Reject }` + `match` compiles dual-clean and models
  the production Result/.bind railway.
- LR-P01..LR-P11 remain routed; no Outcome/bind, entity, fold-to-struct, dynamic
  dispatch, IO, HTTP, DB, clock, RNG, or outbox implementation was opened.
- No app `.ig` source changes were made.

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/dev-tutorial.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/lead_router/PRESSURE_REGISTRY.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/lead_router/report.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/lead_router/types.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/lead_router/pipeline.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/lead_router/service.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/lead_router/example.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lab/LAB-DYNAMIC-CONTRACT-DISPATCH-P2.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/.agents/work/cards/lang/LANG-FOLD-STRUCT-ACCUMULATOR-P3.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/.agents/work/cards/lang/LANG-COMPOSE-ENTITY-PROP-P2.md`
- Microservice / IO runtime P5 docs for request-reply boundary context.

## Proof Questions

1. Does the full 4-file app compile cleanly in Ruby and Rust using fresh `--out` paths and spaced Rust invocations where needed?
2. Are the claimed counts stable: 4 files, 6 types, 1 variant, 31 contracts, 38 `call_contract`, 10 `match`, 1 scalar fold?
3. Are all `call_contract` sites Tier-1 string literals rather than dynamic callees?
4. Does `variant Pipe { Proceed | Reject }` + `match` compile dual-clean and model Result/railway short-circuiting?
5. Does LR-P01 route to a future stdlib `Outcome`/`Result` + `bind`/`and_then` combinator without implementing it here?
6. Does the app keep DB/clock/RNG/HTTP/outbox as injected inputs or effect-surface pressure, not core logic?
7. Does the report clearly position `lead_router` as request/reply complement to `air_combat` tick-loop pressure?
8. Is `entrypoint RunAccept` present, dual-clean, and reflected in manifest/metadata?
9. Is LR-P11 captured as rich PROP-029 run-profile pressure (`RunAccept` / `RunAcceptSignal` / `RunReject`)?
10. Is the Rust assembler timing flake documented so future runners avoid false internal-error conclusions?

## Pressure IDs To Preserve

| ID | Pressure | Route |
|---|---|---|
| LR-P01 | Outcome/bind railway by hand | stdlib `Outcome`/`Result` + `bind`/`and_then` |
| LR-P02 | fold-to-struct step receipts | `LANG-FOLD-STRUCT-ACCUMULATOR-P3/P4` |
| LR-P03 | nested availability fold | fold-struct + future nested iteration |
| LR-P04 | entity/state threading (`Ctx`, `Vendor`) | `LANG-COMPOSE-ENTITY` |
| LR-P05 | dynamic vendor-protocol dispatch avoided | `LAB-DYNAMIC-CONTRACT-DISPATCH-P2` |
| LR-P06 | record-literal inference factories | record literal / nested record tracks |
| LR-P07 | DB reads / StorageCapability | `PROP-035` / `PROP-046` / IO-runtime |
| LR-P08 | clock capability | clock/event-time boundary |
| LR-P09 | RNG capability | future effect-surface RNG |
| LR-P10 | service envelope + outbox write | MICROSERVICE envelope + effect write + ServiceLoop host |
| LR-P11 | named run-profiles wanted | `PROP-029` rich entrypoint profiles |

## Deliverables

- Proof runner: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_lead_router_baseline_p1.rb`, target at least 95 checks.
- Lab doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/governance/lab-lead-router-compilation-baseline-v0.md`.
- Update `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/lead_router/PRESSURE_REGISTRY.md` with closure summary if needed.
- Update this card with closure summary.
- Portfolio index update after closure.

## Acceptance

- Ruby compile is `ok` / 0 diagnostics.
- Rust compile is `ok` / 0 diagnostics.
- Source hash is stable across two fresh runs or path sensitivity is documented.
- Proof runner avoids rapid back-to-back Rust invocations or accounts for the known assembler timing flake.
- LR-P01..LR-P11 are preserved and routed.
- `entrypoint RunAccept` is present and verified dual-clean.
- `variant` + `match` positive capability discovery is explicitly documented.
- The app is classified as positive baseline + pressure source, not blocker.
- No app source edits unless correcting documentation-only metadata.

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

## Runner Notes

Use fresh `--out` paths and avoid rapid repeated Rust compiler invocations against the same app. The Rust CLI assembler can intermittently report a spurious `Internal compiler error: No such file or directory` on rapid back-to-back runs; a spaced single invocation to a fresh path returns the real result.
