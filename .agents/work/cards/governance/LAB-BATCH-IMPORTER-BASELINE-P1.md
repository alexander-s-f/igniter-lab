# LAB-BATCH-IMPORTER-BASELINE-P1

**Status:** CLOSED — PROVED 161/161 PASS  
**Route:** lab / app baseline / batch_importer  
**Date:** 2026-06-15  
**Date closed:** 2026-06-15  
**Verdict:** ACCEPT — positive dual-toolchain baseline  
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

## Closure Summary

`batch_importer` is accepted as a positive dual-toolchain baseline and pressure
source for pure partial-success import receipts.

| Metric | Value |
|---|---|
| proof | 161/161 PASS |
| Ruby | ok / 0 diagnostics |
| Rust | ok / 0 diagnostics |
| source files | 3 |
| types | 3 |
| variants | 1 (`RowResult`) |
| contracts | 9 |
| call_contract sites | 11 |
| source match expressions | 1 |
| match arms | 2 |
| entrypoint | `RunImport` |
| source_hash | `sha256:a6c198e3078d53a44e0ac8805c72d574f984e622e669666d215bef766bc67524` |

The proof runner records the draft registry's "2 match" metric as two match
arms; executable source shape has one `match` expression.

`LANG-SUMTYPE-CONSTRUCT-MATCH-P3` is closed at proof time. That changes the
pressure shape but not this app baseline: built-in Option/Result construction
and matchability are no longer the blocker, but BI-P01 still correctly describes
typed extraction as missing. The app can count `Valid` rows via `filter` plus a
match predicate, but cannot extract `Collection[ImportRecord]` from
`Collection[RowResult]` without a later collect/partition or app migration card.

Deliverables:

| Artifact | Path |
|---|---|
| Proof runner | `igniter-lab/igniter-view-engine/proofs/verify_lab_batch_importer_baseline_p1.rb` |
| Lab doc | `igniter-lab/lab-docs/governance/lab-batch-importer-baseline-v0.md` |
| Pressure registry | `igniter-lab/igniter-apps/batch_importer/PRESSURE_REGISTRY.md` |
| Portfolio index | `igniter-lab/.agents/portfolio-index.md` |
| Private checkpoint | `igniter-gov/portfolio/governance/2026-06-15-lab-batch-importer-baseline-p1-v0.md` |

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
