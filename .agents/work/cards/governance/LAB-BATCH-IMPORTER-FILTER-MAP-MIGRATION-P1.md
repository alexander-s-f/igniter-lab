# LAB-BATCH-IMPORTER-FILTER-MAP-MIGRATION-P1

**Status:** OPEN — APP MIGRATION  
**Route:** lab / app pressure / batch_importer / BI-P01  
**Date:** 2026-06-15  
**Authority:** app-source migration after canon/lab stdlib support; no compiler changes

## Goal

Migrate `batch_importer` from manual sumtype extraction patterns to canonical `filter_map`, proving BI-P01 is resolved by the new stdlib surface.

Target shape:

```igniter
compute valid_records : Collection[ImportRecord] =
  filter_map(row_results, r -> match r {
    Valid { record } => some(record)
    Invalid { }      => none()
  })
```

The app should remain dual-toolchain clean.

## Gate

Start after:

- `LANG-SUMTYPE-COLLECT-P3` CLOSED.
- Prefer `LANG-MATCH-ARM-PARAM-UNIFICATION-P2` CLOSED, but if P3 used output-context fallback successfully, this migration can still proceed.
- `LAB-BATCH-IMPORTER-BASELINE-P1` CLOSED — current baseline frozen.

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/governance/lab-batch-importer-baseline-v0.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/governance/LAB-BATCH-IMPORTER-BASELINE-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/batch_importer/PRESSURE_REGISTRY.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/batch_importer/validate.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/.agents/work/cards/lang/LANG-SUMTYPE-COLLECT-P3.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/dev-tutorial.md`

## Work

1. Locate current BI-P01 workaround/manual valid-row extraction in app source.
2. Replace only the extraction site with `filter_map` + `match` + `some/none`.
3. Keep app domain types, variants, contracts, and entrypoint unchanged.
4. Compile app with both Ruby and Rust toolchains.
5. Update `PRESSURE_REGISTRY.md`: BI-P01 RESOLVED, source hash refreshed, short Wave note added.
6. Write proof runner and lab doc.

## Deliverables

- Minimal `.ig` source edit(s) in `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/batch_importer/`.
- Proof runner: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_batch_importer_filter_map_migration_p1.rb`, target at least 70 checks.
- Lab doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/governance/lab-batch-importer-filter-map-migration-p1-v0.md`.
- Update this card, app pressure registry, and lab portfolio index.

## Acceptance

- `batch_importer` Ruby compile is ok/0.
- `batch_importer` Rust compile is ok/0.
- BI-P01 is marked RESOLVED with evidence.
- The migration actually uses `filter_map`; no hidden manual append/empty workaround remains for the same extraction.
- Baseline counts/hash changes are documented.
- No unrelated app refactor.

## Closed Surfaces

- No compiler changes.
- No storage/parse effects.
- No app-wide style sweep.
- No dynamic dispatch expansion.
- No new variants or domain model changes unless strictly required by the migration.
- No migration of other apps in this card.

## Agent Recommendation

Give this to **Sonnet 4.6** or **Codex GPT 5.5** after `COLLECT-P3` closes. This is mostly app hygiene plus proof discipline.
