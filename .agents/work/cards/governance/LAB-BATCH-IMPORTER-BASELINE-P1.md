# LAB-BATCH-IMPORTER-BASELINE-P1

**Status:** OPEN  
**Route:** lab / app baseline / batch_importer  
**Date:** 2026-06-15  
**Authority:** evidence baseline only; no implementation

## Goal

Freeze `batch_importer` as a positive dual-toolchain baseline and pressure source.

`batch_importer` models parse -> validate -> partial-success receipt as a pure
core. It deliberately uses a user `variant RowResult` where the aspirational
surface wants built-in `Result[ImportRecord, Error]` plus typed extraction.

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/batch_importer/PRESSURE_REGISTRY.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/batch_importer/types.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/batch_importer/validate.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/batch_importer/example.ig`
- `LANG-SUMTYPE-CONSTRUCT-MATCH-P1/P2/P3` if P3 has landed.
- `LANG-STDLIB-COLLECTION-FIRST-LAST-P2`
- `LANG-STDLIB-RESULT-BIND-P2`

## Proof Questions

1. Does the full app compile cleanly in Ruby and Rust?
2. Are the registry metrics stable: 3 files, 3 types, 1 variant, 9 contracts, 11 `call_contract`, 2 `match`, `entrypoint RunImport`?
3. Is source hash stable under the project-standard Open3/mktmpdir compile route?
4. Does `map` over rows into `RowResult`, then `filter` with a `match` predicate and `count`, remain dual-clean?
5. Does BI-P01 correctly describe typed extraction as still missing unless a later collect/partition card has landed?
6. Are BI-P01..BI-P07 preserved and routed accurately?
7. Does the app avoid claiming CSV parse, String-to-Integer parse, DB write, or typed valid-record extraction?

## Deliverables

- Proof runner: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_batch_importer_baseline_p1.rb`, target at least 90 checks.
- Lab doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/governance/lab-batch-importer-baseline-v0.md`.
- Update `batch_importer/PRESSURE_REGISTRY.md` with closure summary.
- Update this card with closure summary.
- Portfolio index update after closure.

## Acceptance

- Ruby compile is `ok` / 0 diagnostics.
- Rust compile is `ok` / 0 diagnostics.
- Source hash and app metrics are frozen.
- BI-P01..BI-P07 remain documented and routed.
- No app source edits.

## Closed Surfaces

- No CSV/Bytes parsing.
- No String-to-Integer parse.
- No DB write / batch persistence.
- No typed payload extraction implementation.
- No app migration to built-in Result.

## Agent Recommendation

Give this to **Gemini** or **Sonnet 4.6**. If `LANG-SUMTYPE-CONSTRUCT-MATCH-P3`
lands first, ask the agent to note whether baseline pressure changed, but not to
migrate the app.
