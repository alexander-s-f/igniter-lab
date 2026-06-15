# Lab: Batch Importer Baseline

**Card:** `LAB-BATCH-IMPORTER-BASELINE-P1`  
**Date:** 2026-06-15  
**Proof runner:** `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_batch_importer_baseline_p1.rb`  
**Status:** CLOSED — PROVED  
**Authority:** lab evidence baseline only; no canon authority

## Purpose

Freeze `batch_importer` as a positive dual-toolchain baseline for a pure
parse -> validate -> partial-success receipt core.

The app intentionally models validation outcomes with a user
`variant RowResult` instead of migrating to built-in
`Result[ImportRecord, Error]`. After `LANG-SUMTYPE-CONSTRUCT-MATCH-P3`,
built-in Option/Result construction and matchability are no longer the blocker;
the remaining BI-P01 pressure is typed extraction via collect/partition or a
separately authorized app migration.

## Baseline Numbers

| Metric | Value |
|---|---|
| Ruby status | ok / 0 diagnostics |
| Rust status | ok / 0 diagnostics |
| source files | 3 |
| types | 3 |
| variants | 1 (`RowResult`) |
| contracts | 9 |
| call_contract sites | 11 |
| source match expressions | 1 |
| match arms | 2 |
| entrypoint | `RunImport` |
| source_hash | `sha256:a6c198e3078d53a44e0ac8805c72d574f984e622e669666d215bef766bc67524` |

The proof records the source match expression and its two arms separately. The
draft registry phrase "2 match" is therefore interpreted as the two match arms,
while the executable expression count is one.

## App Structure

| File | Module | Role |
|---|---|---|
| `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/batch_importer/types.ig` | `BatchImporterTypes` | `RawRow`, `ImportRecord`, `RowResult`, `ImportReceipt` |
| `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/batch_importer/validate.ig` | `BatchImporterValidate` | row validation, `map`, match predicate, `filter`, `count`, receipt build |
| `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/batch_importer/example.ig` | `BatchImporterExample` | four-row demo batch and `RunImport` entrypoint |

## Proof Matrix

| Section | Topic |
|---|---|
| A | Preconditions |
| B | Source shape |
| C | Required reads and routing |
| D | Ruby compile |
| E | Rust compile |
| F | SemanticIR and manifest |
| G | Positive partial-success pattern |
| H | Pressure registry |
| I | Closed surfaces |
| J | Liveness and determinism |
| K | Source integrity |
| L | Baseline verdict |

## Key Findings

### Dual-Toolchain Clean

Both toolchains compile the full app with zero diagnostics. Ruby and Rust agree
on the program id, SemanticIR ref, compilation report ref, and source hash under
the project-standard Open3/mktmpdir route.

### Positive Partial-Success Core

`ValidateAll` maps raw rows into `Collection[RowResult]`. `CountAccepted` then
filters with a match-backed predicate and counts accepted rows. This proves the
current language can model partial-success counting as pure application logic.

### Typed Extraction Still Missing

BI-P01 remains active. The app can count `Valid` rows, but it cannot produce a
homogeneous `Collection[ImportRecord]` from the `Valid` payloads without a
partial map / Option collect / partition surface. `LANG-SUMTYPE-CONSTRUCT-MATCH-P3`
is closed at proof time, so the pressure is now narrowed to extraction and
migration governance. The app is not migrated to built-in `Result`.

### Result Pressure Preserved

`RowResult` is a user variant standing in for aspirational
`Result[ImportRecord, Error]`. That is app-fleet pressure, not a canon claim.
`LANG-SUMTYPE-CONSTRUCT-MATCH-P3` has landed, but migration is deliberately not
part of this baseline card.

## Pressure Summary

| ID | Status | Route |
|---|---|---|
| BI-P01 | ACTIVE primary, narrowed after Sumtype P3 | collect/partition plus app migration gate |
| BI-P02 | DOCUMENTED escape boundary | parse/effect surface |
| BI-P03 | ACTIVE ergonomics | indexed map / enumerate |
| BI-P04 | ACTIVE | built-in `Result` construction/match |
| BI-P05 | ACTIVE | record literal inference |
| BI-P06 | DOCUMENTED behind | storage/effect surface |
| BI-P07 | DOCUMENTED | first/last Option plus matchability |

## Closed Surfaces

- No CSV/Bytes parsing.
- No String-to-Integer parse.
- No DB write or batch persistence.
- No typed payload extraction implementation.
- No app migration to built-in `Result`.
- No IO, network, Rack, SQL, ORM, capability, or effect authority.
- No `.ig` app source edits.

## Evidence

```text
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab && ruby igniter-view-engine/proofs/verify_lab_batch_importer_baseline_p1.rb
Summary: 161/161 checks passed
```

This document is evidence only. Canon authority remains in `igniter-lang`;
frontier pressure remains in `igniter-lab`.
