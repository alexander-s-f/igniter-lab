# LAB-AUDIT-LEDGER-BASELINE-P1

**Status:** OPEN  
**Route:** lab / app baseline / audit_ledger  
**Date:** 2026-06-15  
**Authority:** evidence baseline only; no implementation

## Goal

Freeze `audit_ledger` as a positive dual-toolchain baseline and pressure source.

`audit_ledger` models a bitemporal append-only audit ledger as a pure data core:
explicit Integer valid/transaction time axes, as-of reconstruction with `filter` +
scalar `fold`, and correction entries as append-only deltas.

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/audit_ledger/PRESSURE_REGISTRY.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/audit_ledger/types.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/audit_ledger/ledger.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/audit_ledger/correct.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/audit_ledger/example.ig`
- `LANG-TEMPORAL-STATE-P1/P2` docs if available.
- `LANG-FOLD-STRUCT-ACCUMULATOR-P1/P2/P3` docs if available.

## Proof Questions

1. Does the full app compile cleanly in Ruby and Rust?
2. Are the registry metrics stable: 4 files, 4 types, 13 contracts, 15 `call_contract`, 1 fold, 2 filters, 2 counts, `entrypoint BalanceAsOfDay5`?
3. Is source hash stable under the project-standard Open3/mktmpdir compile route?
4. Does the app prove a pure-data temporal/audit core without claiming runtime `BiHistory`, `as_of`, `now()`, or storage?
5. Are AL-P01..AL-P09 preserved and routed accurately?
6. Is fixed-point Integer cents documented as a Decimal/Money substitute, not a Decimal implementation?
7. Is correction modeled append-only, with no mutation semantics inferred?

## Deliverables

- Proof runner: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_audit_ledger_baseline_p1.rb`, target at least 90 checks.
- Lab doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/governance/lab-audit-ledger-baseline-v0.md`.
- Update `audit_ledger/PRESSURE_REGISTRY.md` with closure summary.
- Update this card with closure summary.
- Portfolio index update after closure.

## Acceptance

- Ruby compile is `ok` / 0 diagnostics.
- Rust compile is `ok` / 0 diagnostics.
- Source hash and app metrics are frozen.
- AL-P01..AL-P09 remain documented and routed.
- No app source edits.

## Closed Surfaces

- No `BiHistory[T]` runtime.
- No clock / `now()`.
- No Decimal/Money implementation.
- No storage backend.
- No supersession dedup primitive.
- No effect-surface authority/provenance implementation.

## Agent Recommendation

Give this to **Gemini** or **Sonnet 4.6**. It is a baseline/proof task with clear
registry evidence; not a scarce Opus slot.
