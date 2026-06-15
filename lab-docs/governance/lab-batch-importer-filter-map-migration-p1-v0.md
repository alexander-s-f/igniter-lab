# Lab: Batch Importer filter_map Migration

**Card:** `LAB-BATCH-IMPORTER-FILTER-MAP-MIGRATION-P1`  
**Date:** 2026-06-15  
**Proof runner:** `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_batch_importer_filter_map_migration_p1.rb`  
**Status:** CLOSED — APP MIGRATION PROVED  
**Authority:** app-source migration evidence only; no canon or compiler authority

## Purpose

Resolve `batch_importer` BI-P01 by replacing the valid-row counting workaround
with canonical `stdlib.collection.filter_map`.

`batch_importer` still models validation outcomes with the user
`variant RowResult`; this card does not migrate the app to built-in `Result`.

## Migration

`CountAccepted` now extracts `Collection[ImportRecord]` before counting:

```igniter
compute valid_records : Collection[ImportRecord] = filter_map(results, r -> match r {
  Valid { record } => some(record)
  Invalid { } => none()
})
compute n = count(valid_records)
```

The domain surface is unchanged: 3 source files, 3 types, 1 user variant, 9
contracts, and entrypoint `RunImport`. Only `validate.ig` changed.

## Baseline Delta

| Metric | Baseline | Migration |
|---|---:|---:|
| source files | 3 | 3 |
| types | 3 | 3 |
| variants | 1 | 1 |
| contracts | 9 | 9 |
| call_contract sites | 11 | 10 |
| source match expressions | 1 | 2 |
| match arms | 2 | 4 |
| executable filter sites | 1 | 0 |
| executable filter_map sites | 0 | 1 |

| Hash | Value |
|---|---|
| baseline source_hash | `sha256:a6c198e3078d53a44e0ac8805c72d574f984e622e669666d215bef766bc67524` |
| Ruby migration source_hash | `sha256:1cf7a0f1e5d874c418954b699e5145a3e8c7dfada40bd1c3f94f78093d91d0fa` |
| Rust migration source_hash | `sha256:1cf7a0f1e5d874c418954b699e5145a3e8c7dfada40bd1c3f94f78093d91d0fa` |
| `types.ig` | `sha256:a13f9f71326bb10fb978ef1526d2392fe2f2e2422e68b5622ec56fe8b165a61d` |
| `validate.ig` | `sha256:3d6137bb1a777a1b666ff79ed5c136110d0469c7257f4a81d33932d094958cb9` |
| `example.ig` | `sha256:2e3e619f6a6e5de98cc52ad49b778535befdb7ed4db2921a573c5a8a17e280f7` |

Under the absolute Open3/mktmpdir route used by the proof, Ruby and Rust report
the same multifile source hash. The proof still asserts stability within each
toolchain rather than relying on source hash alone as the behavioral metric.

## Proof Matrix

| Section | Topic |
|---|---|
| A | Gate and required reads |
| B | Source migration shape |
| C | Domain surface and baseline delta |
| D | Ruby compile |
| E | Rust compile |
| F | SIR and manifest evidence |
| G | Governance artifacts |
| H | Closed surfaces |

## Verdict

`BI-P01` is **RESOLVED** for `batch_importer`.

Both toolchains compile the migrated app cleanly:

```text
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
ruby igniter-view-engine/proofs/verify_lab_batch_importer_filter_map_migration_p1.rb
Summary: 107/107 checks passed
```

## Closed Surfaces

- No compiler changes.
- No storage or parse effects.
- No app-wide style sweep.
- No dynamic dispatch expansion.
- No new variants or domain model changes.
- No migration of other apps.
- No migration to built-in `Result`.

This document is evidence only. Canon authority remains in `igniter-lang`;
frontier/app evidence remains in `igniter-lab`.
