# APP-RECHECK-WAVE-P13

**Status:** OPEN — GOVERNANCE RECHECK  
**Route:** lab / app pressure / fleet recheck  
**Date:** 2026-06-15  
**Authority:** evidence-only fleet recheck; no compiler or app source changes

## Goal

Run the next fleet pressure recheck after the Sumtype/Option/Result wave and the Rust loop-body safety fix.

Primary expected deltas:

- `batch_importer` should remain dual-clean; if `LAB-BATCH-IMPORTER-FILTER-MAP-MIGRATION-P1` has landed, BI-P01 should be RESOLVED via `filter_map`.
- `rule_engine` should remain the single known fail-closed app unless a separate dynamic-dispatch card explicitly changed it.
- Rust loop-body assignment tightening should not regress `job_runner` or any current app.

## Gate

Start after at least one of:

- `LANG-MATCH-ARM-PARAM-UNIFICATION-P2` CLOSED.
- `LANG-SUMTYPE-COLLECT-P3` CLOSED.
- `LAB-BATCH-IMPORTER-FILTER-MAP-MIGRATION-P1` CLOSED.
- `LAB-RUST-LOOP-BODY-ASSIGNMENT-P1` CLOSED.

If only the Rust loop safety card landed, classify the wave as a safety-regression recheck with no app-pressure resolution expected.

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/docs/app-pressure-recheck-wave-p12-2026-06-15-v0.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/governance/APP-RECHECK-WAVE-P12.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/lang/lab-rust-loop-body-assignment-p1-proof-v0.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/.agents/work/cards/lang/LANG-MATCH-ARM-PARAM-UNIFICATION-P2.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/.agents/work/cards/lang/LANG-SUMTYPE-COLLECT-P3.md`
- All app `PRESSURE_REGISTRY.md` files under `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/*/`.

## Work

1. Enumerate the active app fleet from `igniter-lab/igniter-apps`.
2. Compile every app with Ruby canon and Rust lab using stable Open3/mktmpdir style invocations; avoid shell redirection races.
3. Capture exact status, diagnostic count, diagnostic codes/messages, entrypoint, and source hash where available.
4. Compare with Wave P12.
5. Update every `PRESSURE_REGISTRY.md` with a compact Wave P13 section.
6. Write rollup doc and close this card.

## Deliverables

- Rollup doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/docs/app-pressure-recheck-wave-p13-2026-06-15-v0.md`.
- Update all relevant app `PRESSURE_REGISTRY.md` files.
- Update this card with closure summary.
- Update `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/portfolio-index.md`.

## Acceptance

- Fleet size is explicit and reconciled with Wave P12.
- Ruby/Rust status table included for every app.
- Any app delta has a named pressure ID and route.
- `rule_engine` golden diagnostics are preserved unless an authorized card changed them.
- New app pressures are not silently folded into old IDs.
- No app or compiler source edits.

## Closed Surfaces

- No source fixes.
- No compiler changes.
- No app migrations.
- No stale-doc routing without live compile evidence.
- No interpretation of proof docs as authority over live code.

## Agent Recommendation

Give this to **Codex GPT 5.5**. It benefits from reliable local scripting and exact registry updates.
