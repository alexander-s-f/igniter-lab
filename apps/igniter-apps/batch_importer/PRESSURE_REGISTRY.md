# Batch Importer Pressure Registry

Created: 2026-06-14 (archaeology pull — mundane pressure specimen → pure app)

`batch_importer` is a pure re-modeling of the **mundane** pressure specimens
(`pressure-specimens/mundane-application-pressure-v0/igniter-csv-importer-v1.ig`,
`igniter-webhook-ingestor-v1.ig`). The specimen wants
`Result[ImportRecord, List[Error]]` + `.filter(Ok).map(Ok.value)`. After
`LANG-SUMTYPE-COLLECT-P3` and `LAB-BATCH-IMPORTER-FILTER-MAP-MIGRATION-P1`, the
homogeneous extraction step is now expressed with canonical
`stdlib.collection.filter_map`. This app intentionally keeps validation outcomes
as a USER `variant RowResult` and produces a **partial-success** import receipt.

## Baseline

Dual-toolchain CLEAN.

```bash
cd igniter-compiler
cargo run -- compile \
  ../igniter-apps/batch_importer/types.ig ../igniter-apps/batch_importer/validate.ig \
  ../igniter-apps/batch_importer/example.ig --out /tmp/batch_importer.igapp
```

| Metric | Value |
|---|---|
| Ruby | ok / 0 diagnostics |
| Rust | ok / 0 diagnostics (9 contracts) |
| source files | 3 |
| types | 3 |
| variants | 1 (`RowResult { Valid \| Invalid }` — Result modeled as a variant) |
| contracts | 9 |
| call_contract sites | 11 (Tier-1 literals) |
| match sites | 2 |
| entrypoint | `RunImport` |
| source_hash | `sha256:a6c198e3078d53a44e0ac8805c72d574f984e622e669666d215bef766bc67524` |

> NOTE (fleet-wide): verify Rust via the Open3/mktmpdir subprocess route; Ruby uses
> `MultifileResolver.resolve` (not naive join).

## Closure Summary (LAB-BATCH-IMPORTER-BASELINE-P1)

Closed 2026-06-15 as a positive dual-toolchain baseline.

Proof runner:

```bash
ruby igniter-view-engine/proofs/verify_lab_batch_importer_baseline_p1.rb
```

Verdict:

| Check | Value |
|---|---|
| proof | 161/161 PASS |
| Ruby | ok / 0 diagnostics |
| Rust | ok / 0 diagnostics |
| source_hash | `sha256:a6c198e3078d53a44e0ac8805c72d574f984e622e669666d215bef766bc67524` |

The live Open3/mktmpdir proof refreshed the frozen hash from the earlier draft
registry value. No `.ig` app source files were edited.

At baseline time, `LANG-SUMTYPE-CONSTRUCT-MATCH-P3` was closed, so the pressure
had narrowed: Option/Result construction and matchability were no longer the
blocker. BI-P01 still needed collect/partition or a separately authorized app
migration. The app remained on user `variant RowResult` and was not migrated to
built-in `Result`.

## Closure Summary (LAB-BATCH-IMPORTER-FILTER-MAP-MIGRATION-P1)

Closed 2026-06-15 as an app-source migration after `LANG-SUMTYPE-COLLECT-P3`.

Proof runner:

```bash
ruby igniter-view-engine/proofs/verify_lab_batch_importer_filter_map_migration_p1.rb
```

Verdict:

| Check | Value |
|---|---|
| proof | 107/107 PASS |
| Ruby | ok / 0 diagnostics |
| Rust | ok / 0 diagnostics |
| Ruby source_hash | `sha256:1cf7a0f1e5d874c418954b699e5145a3e8c7dfada40bd1c3f94f78093d91d0fa` |
| Rust source_hash | `sha256:1cf7a0f1e5d874c418954b699e5145a3e8c7dfada40bd1c3f94f78093d91d0fa` |
| validate.ig source_hash | `sha256:3d6137bb1a777a1b666ff79ed5c136110d0469c7257f4a81d33932d094958cb9` |

`CountAccepted` now computes:

```igniter
compute valid_records : Collection[ImportRecord] = filter_map(results, r -> match r {
  Valid { record } => some(record)
  Invalid { } => none()
})
compute n = count(valid_records)
```

Shape delta from `LAB-BATCH-IMPORTER-BASELINE-P1`: source files/types/variant/
contracts/entrypoint unchanged; `call_contract` sites 11 -> 10; source match
expressions 1 -> 2; match arms 2 -> 4; executable `filter` sites 1 -> 0;
executable `filter_map` sites 0 -> 1. `types.ig` and `example.ig` hashes are
unchanged; only `validate.ig` changed.

## Provenance (specimen → pure model)

| Specimen (aspirational) | batch_importer (dual-clean) |
|---|---|
| `ParseCsvFile(Bytes) -> List[CsvRow]` | injected `Collection[RawRow]` (parse = escape) |
| `MapAndValidateRow -> Result[ImportRecord, List[Error]]` | `ValidateRow -> variant RowResult { Valid \| Invalid }` |
| `rows.map(MapAndValidateRow).filter(Ok).map(Ok.value)` | `ValidateAll` (map) + `CountAccepted` (`filter_map` + count) — BI-P01 resolved |
| `BatchImport escape db_write_batch` | injected; receipt built purely |
| `ImportReceipt` | `ImportReceipt { total, accepted, rejected }` |

## Pressures

| ID | Name | Evidence | Status | Route |
|---|---|---|---|---|
| BI-P01 | **filter-Ok / map-value extraction gap** | `CountAccepted` now extracts `Collection[ImportRecord]` with `filter_map(results, r -> match r { Valid { record } => some(record); Invalid { } => none() })` and counts the extracted records. | RESOLVED — `LAB-BATCH-IMPORTER-FILTER-MAP-MIGRATION-P1` | closed by `LANG-SUMTYPE-COLLECT-P3` + app migration |
| BI-P02 | **no String→Integer parse in CORE** | amounts arrive as Integer (parsing is escape); the specimen parses CSV strings. | DOCUMENTED — escape boundary | effect-surface parse / stdlib parse |
| BI-P03 | **`map` has no element index** | per-row errors key on `row_id`, not positional index, because `map(rows, r -> …)` exposes no index. | ACTIVE — ergonomics | indexed map / enumerate |
| BI-P04 | **Result modeled as a user variant** | `RowResult { Valid \| Invalid }` stands in for `Result[ImportRecord, Error]`. Built-in Result is dual-clean, but this app has not been migrated. | WATCH — migration gated | separate app migration card after BI-P01 closure |
| BI-P05 | **record-literal factories** | `MakeRow` / `MakeRecord` pin record types (inline literals → Unknown in Rust). | ACTIVE | `LANG-RUBY-RECORD-LITERAL-INFERENCE` |
| BI-P06 | **batch import is an effect** | `BatchImport escape db_write_batch` is a StorageCapability write; injected here, receipt built purely. | DOCUMENTED — behind | `PROP-046` storage + effect surface |
| BI-P07 | **first-error extraction needs first()→Option** | surfacing the first rejection message needs `first` over the invalids → `Option`, which is Rust-only + non-matchable. | DOCUMENTED | `LANG-STDLIB-COLLECTION-FIRST-LAST-OPTION` |

## Capability Discovery (positive)

`map` over a `Collection[RawRow]` producing a `Collection[RowResult]` (a variant),
then `filter_map` with a `match` callback extracting `Valid.record` via
`some(record)` and dropping `Invalid` via `none()`, is **dual-clean**. Typed
extraction of one arm's payload into a homogeneous collection is now resolved
for this app.

## Safety Interpretation

Proves the language can model a parse→validate→extract-valids→batch receipt flow
as a **pure** core. It does NOT claim: CSV/Bytes parsing, String→Int parse, a DB
write, built-in `Result` migration, or first-error surfacing — all remain
separate pressure.

## Non-Goals

- No CSV/Bytes parsing (escape).
- No String→Integer parse in CORE.
- No DB write / batch persistence.
- No unrelated app mutation beyond the BI-P01 `filter_map` migration.
- No migration to built-in `Result`.

## Recommended Route

1. Indexed `map` / enumerate for BI-P03.
2. Built-in `Result` migration, separately gated, for BI-P04.
3. Effect-surface parse + storage write for BI-P02 + BI-P06.

## Wave P12 Recheck Summary (2026-06-15)

Rust: ok / 0 diagnostics. Ruby: ok / 0 diagnostics. DUAL-TOOLCHAIN CLEAN.

Integrated into the 20-app fleet as a new companion app. Its pressure routes remain evidence-only: `LANG-SUMTYPE-CONSTRUCT-MATCH` for Result/Option-style payload extraction, indexed map/enumerate, and parse/storage effect surfaces. No source edits. No new pressures. No regressions.

## Wave P13 Migration Note (2026-06-15)

BI-P01 is resolved by `filter_map` app migration. Ruby and Rust are both ok/0.
This is app-source evidence only; canon authority remains in `igniter-lang`.

## Wave P13 Recheck Summary (2026-06-15)

Ruby: ok/0. Rust: ok/0. DUAL-CLEAN. Source files: 3. Source hash: `sha256:1cf7a0f1e5d874c418954b699e5145a3e8c7dfada40bd1c3f94f78093d91d0fa`. Entrypoint: `RunImport`. BI-P01 is RESOLVED by `filter_map`; source hash changed vs Wave P12 due to the authorized migration.
No source changes in this wave. No new pressures. No regressions.
