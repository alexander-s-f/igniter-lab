# Batch Importer Pressure Registry

Created: 2026-06-14 (archaeology pull — mundane pressure specimen → pure app)

`batch_importer` is a pure re-modeling of the **mundane** pressure specimens
(`pressure-specimens/mundane-application-pressure-v0/igniter-csv-importer-v1.ig`,
`igniter-webhook-ingestor-v1.ig`). The specimen wants
`Result[ImportRecord, List[Error]]` + `.filter(Ok).map(Ok.value)` — neither
dual-clean today. This app models validation outcomes with a USER `variant
RowResult` and produces a **partial-success** import receipt — making it direct
regression pressure for `LANG-SUMTYPE-CONSTRUCT-MATCH`.

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
| source_hash | `sha256:20003d518fd2a2d0be81c7e737468b6a2eb5eb5b3699892f0afac882cc3f8500` |

> NOTE (fleet-wide): verify Rust via the Open3/mktmpdir subprocess route; Ruby uses
> `MultifileResolver.resolve` (not naive join).

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
| BI-P01 | **filter-Ok / map-value extraction gap** | `CountAccepted` can COUNT `Valid` via a match predicate, but you cannot extract `Collection[ImportRecord]` of just the valids — `filter` keeps the element type `RowResult`; changing it to `ImportRecord` needs a partial map / Option-collect. The headline. | ACTIVE — primary | `LANG-SUMTYPE-CONSTRUCT-MATCH` (matchable Option/Result + collect) |
| BI-P02 | **no String→Integer parse in CORE** | amounts arrive as Integer (parsing is escape); the specimen parses CSV strings. | DOCUMENTED — escape boundary | effect-surface parse / stdlib parse |
| BI-P03 | **`map` has no element index** | per-row errors key on `row_id`, not positional index, because `map(rows, r -> …)` exposes no index. | ACTIVE — ergonomics | indexed map / enumerate |
| BI-P04 | **Result modeled as a user variant** | `RowResult { Valid \| Invalid }` stands in for `Result[ImportRecord, Error]` because built-in Result is not dual-clean. | ACTIVE | `LANG-SUMTYPE-CONSTRUCT-MATCH` (Result construct/match) |
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

1. `LANG-SUMTYPE-CONSTRUCT-MATCH` (matchable Option/Result + a collect/partition) —
   collapses BI-P01 + BI-P04 + BI-P07 (the whole partial-success extraction story).
2. Indexed `map` / enumerate for BI-P03.
3. Effect-surface parse + storage write for BI-P02 + BI-P06.
