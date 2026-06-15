# Batch Importer Pressure Registry

Created: 2026-06-14 (archaeology pull — mundane pressure specimen → pure app)

`batch_importer` is a pure re-modeling of the **mundane** pressure specimens
(`pressure-specimens/mundane-application-pressure-v0/igniter-csv-importer-v1.ig`,
`igniter-webhook-ingestor-v1.ig`). The specimen wants
`Result[ImportRecord, List[Error]]` + `.filter(Ok).map(Ok.value)`. After
`LANG-SUMTYPE-CONSTRUCT-MATCH-P3`, built-in Option/Result construction and match
are dual-clean, but the homogeneous extraction step still needs collect/partition
or an app migration card. This app intentionally keeps validation outcomes as a
USER `variant RowResult` and produces a **partial-success** import receipt.

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

`LANG-SUMTYPE-CONSTRUCT-MATCH-P3` is closed at proof time, so the pressure has
narrowed: Option/Result construction and matchability are no longer the blocker.
BI-P01 remains active because typed extraction of `Collection[ImportRecord]` from
`Collection[RowResult]` still needs collect/partition or a separately authorized
app migration. The app remains on user `variant RowResult` and is not migrated to
built-in `Result`.

## Provenance (specimen → pure model)

| Specimen (aspirational) | batch_importer (dual-clean) |
|---|---|
| `ParseCsvFile(Bytes) -> List[CsvRow]` | injected `Collection[RawRow]` (parse = escape) |
| `MapAndValidateRow -> Result[ImportRecord, List[Error]]` | `ValidateRow -> variant RowResult { Valid \| Invalid }` |
| `rows.map(MapAndValidateRow).filter(Ok).map(Ok.value)` | `ValidateAll` (map) + `CountAccepted` (filter+count) — extraction is the gap (BI-P01) |
| `BatchImport escape db_write_batch` | injected; receipt built purely |
| `ImportReceipt` | `ImportReceipt { total, accepted, rejected }` |

## Pressures

| ID | Name | Evidence | Status | Route |
|---|---|---|---|---|
| BI-P01 | **filter-Ok / map-value extraction gap** | `CountAccepted` can COUNT `Valid` via a match predicate, but you cannot extract `Collection[ImportRecord]` of just the valids — `filter` keeps the element type `RowResult`; changing it to `ImportRecord` needs a partial map / Option-collect. The headline. | ACTIVE — primary, narrowed after Sumtype P3 | collect/partition + app migration gate |
| BI-P02 | **no String→Integer parse in CORE** | amounts arrive as Integer (parsing is escape); the specimen parses CSV strings. | DOCUMENTED — escape boundary | effect-surface parse / stdlib parse |
| BI-P03 | **`map` has no element index** | per-row errors key on `row_id`, not positional index, because `map(rows, r -> …)` exposes no index. | ACTIVE — ergonomics | indexed map / enumerate |
| BI-P04 | **Result modeled as a user variant** | `RowResult { Valid \| Invalid }` stands in for `Result[ImportRecord, Error]`. Built-in Result is now dual-clean after Sumtype P3, but this app has not been migrated. | WATCH — migration gated | app migration card after collect/partition decision |
| BI-P05 | **record-literal factories** | `MakeRow` / `MakeRecord` pin record types (inline literals → Unknown in Rust). | ACTIVE | `LANG-RUBY-RECORD-LITERAL-INFERENCE` |
| BI-P06 | **batch import is an effect** | `BatchImport escape db_write_batch` is a StorageCapability write; injected here, receipt built purely. | DOCUMENTED — behind | `PROP-046` storage + effect surface |
| BI-P07 | **first-error extraction needs first()→Option** | surfacing the first rejection message needs `first` over the invalids → `Option`, which is Rust-only + non-matchable. | DOCUMENTED | `LANG-STDLIB-COLLECTION-FIRST-LAST-OPTION` |

## Capability Discovery (positive)

`map` over a `Collection[RawRow]` producing a `Collection[RowResult]` (a variant),
then `filter` with a `match`-as-predicate and `count`, is **dual-clean**. So
partial-success *counting* works today; only typed *extraction* of one arm's
payload into a homogeneous collection is blocked (BI-P01).

## Safety Interpretation

Proves the language can model a parse→validate→batch importer with a
partial-success receipt as a **pure** core. It does NOT claim: CSV/Bytes parsing,
String→Int parse, a DB write, typed extraction of valid records, or first-error
surfacing — all documented pressure.

## Non-Goals

- No CSV/Bytes parsing (escape).
- No String→Integer parse in CORE.
- No DB write / batch persistence.
- No typed extraction of `Valid` payloads (the sum-type gap, BI-P01).
- No app mutation.

## Recommended Route

1. collect/partition or a dedicated app migration card —
   collapses the remaining BI-P01 extraction story after Sumtype P3.
2. Indexed `map` / enumerate for BI-P03.
3. Effect-surface parse + storage write for BI-P02 + BI-P06.

## Wave P12 Recheck Summary (2026-06-15)

Rust: ok / 0 diagnostics. Ruby: ok / 0 diagnostics. DUAL-TOOLCHAIN CLEAN.

Integrated into the 20-app fleet as a new companion app. Its pressure routes remain evidence-only: `LANG-SUMTYPE-CONSTRUCT-MATCH` for Result/Option-style payload extraction, indexed map/enumerate, and parse/storage effect surfaces. No source edits. No new pressures. No regressions.
