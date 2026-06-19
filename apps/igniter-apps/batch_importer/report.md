# Batch Importer — Pressure Report

## What This Is

`batch_importer` is pulled from the **mundane** pressure specimens
(`igniter-csv-importer-v1.ig`, `igniter-webhook-ingestor-v1.ig`) — the "boring
mechanics" that make up most real applications: parse → validate → batch import
with partial success and a receipt.

The specimen writes the happy path in a modern-language idiom:

```
rows.map(MapAndValidateRow)   -- → List[Result[ImportRecord, Error]]
    .filter(Ok)               -- keep the successes
    .map(Ok.value)            -- extract the records
→ BatchImport(records)
```

That idiom assumes built-in `Result` + `Ok`/`Err` matchability — **not dual-clean
today**. So this app models validation outcomes with a user `variant RowResult {
Valid | Invalid }` and produces a partial-success receipt. It compiles dual-clean,
and the gap it can't paper over is the point.

## The Headline Gap (BI-P01): "filter Ok, map value"

You can validate a batch and **count** the outcomes today:

```igniter
compute results = map(rows, r -> ValidateRow(r))    -- Collection[RowResult]
compute valids  = filter(results, r -> IsValid(r))  -- still Collection[RowResult]
compute accepted = count(valids)                    -- ✓ works
```

But you **cannot** extract `Collection[ImportRecord]` of just the valid rows.
`filter` keeps the element type `RowResult`; turning it into `ImportRecord` needs a
*partial map* — exactly the `.filter(Ok).map(Ok.value)` the specimen wants, which
requires matchable `Option`/`Result` + a `collect`/`partition`. This is the cleanest
real-app demonstration of why `LANG-SUMTYPE-CONSTRUCT-MATCH` matters: the fleet can
*count* partial success but cannot *carry forward* only the good records.

It also reproduces the design tension as a positive: `RowResult` (a user variant)
is dual-clean and models `Result` faithfully — strong regression evidence that the
sum-type machinery is production-ready for *user* variants, and that built-in
`Result` should reuse it (the P1 recommendation).

## Other Pressure

- **BI-P02 (no CORE parse):** amounts arrive as Integer; String→Int parse is the
  escape boundary. Validation is pure business rules (`amount > 0`, `email != ""`).
- **BI-P03 (`map` has no index):** errors key on `row_id`, not a positional index,
  because the `map` lambda exposes only the element. A real importer wants enumerate.
- **BI-P07 (first error):** surfacing the first rejection needs `first` → `Option`
  (Rust-only, non-matchable today).
- **BI-P06 (the one true effect):** only `BatchImport` (the DB write) is escape;
  everything upstream is CORE. The specimen's own "what this proves" makes the same
  point — the CORE/ESCAPE boundary is crisp.

## What We'd Need To Make It Real

| Step | Capability | Track |
|---|---|---|
| CSV/Bytes → rows | a parse effect (escape) | effect-surface / stdlib parse |
| keep only valid records | matchable `Result` + `collect`/`partition` | `LANG-SUMTYPE-CONSTRUCT-MATCH` |
| batch persist | StorageCapability write + receipt | `PROP-046` + effect surface |

The validation core stays pure and deterministic; parse and persist are the
membrane. Same shape as the other companions.

## Status

Dual-toolchain CLEAN (Ruby 0 / Rust ok 0, 9 contracts). 3 files, 3 types, 1 variant.
Entrypoint `RunImport` (total 4 / accepted 2 / rejected 2). The fleet's clearest
"filter-Ok/map-value" pressure source for the sum-type track. See
`PRESSURE_REGISTRY.md`.
