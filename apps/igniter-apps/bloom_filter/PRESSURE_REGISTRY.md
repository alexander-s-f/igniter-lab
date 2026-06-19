# Bloom Filter Pressure Registry

Updated: 2026-06-14 — APP-RECHECK-WAVE-P11
Last checked: 2026-06-14
Scope: app-pressure evidence only; not a canon stdlib or compiler proposal.

## Current Live Check

Rust compile:

```bash
cd igniter-compiler
cargo run -- compile ../igniter-apps/bloom_filter/types.ig ../igniter-apps/bloom_filter/hash.ig ../igniter-apps/bloom_filter/ops.ig ../igniter-apps/bloom_filter/example.ig --out /tmp/bloom_filter_p6_probe.igapp
```

Result:

- `status`: `oof`
- `parse`: `ok`
- `classify`: `ok`
- `typecheck`: `oof`
- diagnostics: 15
- diagnostic class: `OOF-TY0 call_contract: unknown callee 'append' — not found in this module`
- liveness: `typechecker.infer_expr.max_depth=6`, `form_resolver.walk_expr.max_depth=6`, no breaches
- Rust `source_hash`: `sha256:3502c095892a35f6f31b872d52d9ae1012b6e6789f901275d5fba292b2dfa880`

Ruby/canon compile:

- `status`: `oof`
- `pass_result`: `oof`
- diagnostics: 16
- first 15 diagnostics: `OOF-TY0 call_contract: unknown callee 'append' — not found in this module` in `InitFilter16`
- cascade diagnostic: `OOF-P1 Unresolved symbol: b14`
- Ruby `source_hash`: `sha256:1b1833de88b9d5805b030f6f768d8bc3ca93bb3314966e95d268d6607b5847fd`

The older app report says full compilation was achieved. Current compiler state is stricter: the app now blocks on stringly stdlib `append` calls during initialization.

## Source Inventory

Files:

- `types.ig` — `BloomFilterTypes`; types `BitSlot`, `BloomFilter`, `HashSeed`, `QueryResult`
- `hash.ig` — `BloomFilterHash`; contracts `Mod`, `Hash1`, `Hash2`, `Hash3`
- `ops.ig` — `BloomFilterOps`; contracts `SetBitAtIndex`, `MakeSlotTrue`, `CheckBitAtIndex`, `Insert`, `Query`; imports `stdlib.collection.{ map, filter }`
- `example.ig` — `BloomFilterExample`; contracts `InitFilter16`, `RunBloomExample`; imports `stdlib.collection.{ map, range }` (was `{ append }` — updated LAB-BLOOM-FILTER-RANGE-MIGRATION-P1)

## Pressures

| ID | Status | Pressure | Evidence | Route |
|---|---|---|---|---|
| BF-P01 | RESOLVED | Stringly `call_contract("append")` initialization chain | `InitFilter16` had 15 chained stringly sites; all migrated in `LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P2`: BF-S01 → `compute b0 : Collection[BitSlot] = [s0, s1]`; BF-S02–S15 → `append(b{n-1}, s{n+1})` | `LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P2` CLOSED |
| BF-P02 | RESOLVED | Collection bootstrap shape | First append was `call_contract("append", s0, s1)` (BOOTSTRAP); migrated to `compute b0 : Collection[BitSlot] = [s0, s1]` typed seed in P2; Rust ok because output is record literal `output bf : BloomFilter` (gap does not apply) | `LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P2` CLOSED |
| BF-P03 | RESOLVED | Missing `range()` / collection generation | `example.ig` manually defines 16 slots and chains append; report says `range(0, 16)` would reduce this to a compact map | `LAB-BLOOM-FILTER-RANGE-MIGRATION-P1` CLOSED |
| BF-P04 | ACTIVE-DESIGN-PRESSURE | No indexed collection access | Bit array modeled as `Collection[BitSlot]`; `SetBitAtIndex` maps over all slots by `pos` | `LAB-STDLIB-COLLECTION-INDEX-ACCESS-P1` |
| BF-P05 | PARTIALLY-RESOLVED | Filter-to-boolean collapse | Prior report says `is_empty`/`length` needed; `stdlib.collection.is_empty/non_empty` now exists, app source has not been migrated | Include in stringly/source migration after P01 |
| BF-P06 | ACTIVE-DESIGN-PRESSURE | Missing modulo operator | `hash.ig` implements modulo manually as `a - (a / b) * b` | `LANG-STDLIB-NUMERIC-MOD-P1` |
| BF-P07 | ACTIVE-DESIGN-PRESSURE | No string hashing | `example.ig` uses integer URL hashes because string hashing is absent | `LANG-STDLIB-STRING-HASH-P1` after string surface |
| BF-P08 | OBSERVED | Map/filter collection ops are usable | `ops.ig` imports and uses `map`/`filter`; current first failure is append initialization, not map/filter import | Keep as regression evidence for collection stdlib |
| BF-P09 | OBSERVED | Liveness budget is safe | Rust liveness `tc=6`, `fr=6`, no breaches despite chained initialization | Keep as baseline evidence for app-pressure wave |

## LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P2 Recheck (2026-06-13)

Ruby: **ok/0** — all 15 stringly append sites migrated; BF-P01 RESOLVED; BF-P02 RESOLVED; OOF-P1 b14 cascade cleared.  
Rust: **ok/0** — all 15 sites migrated; output is `BloomFilter` record (typed-[] propagation gap does not apply).  
**bloom_filter is DUAL-TOOLCHAIN CLEAN.**  
Remaining design pressures: BF-P03 (range), BF-P04 (indexed access), BF-P06 (modulo), BF-P07 (string hashing) — unchanged.

## Wave P6 Recheck Summary (2026-06-13)

Rust: oof / 15 diagnostics — 15× `OOF-TY0 call_contract: unknown callee 'append' — not found in this module` (all from `InitFilter16`). Ruby: oof / 16 diagnostics — 15× same + `OOF-P1 Unresolved symbol: b14` (cascade). Rust source_hash confirmed `sha256:3502c095892a35f6f31b872d52d9ae1012b6e6789f901275d5fba292b2dfa880`. Ruby source_hash confirmed `sha256:1b1833de88b9d5805b030f6f768d8bc3ca93bb3314966e95d268d6607b5847fd`. LANG-RUBY-RECORD-LITERAL-INFERENCE-P3 had no effect: BF-P01 is stringly call_contract("append",...) — NOT_RECORD_LITERAL classification confirmed. BF-P01 ACTIVE — `LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1` dominant route. BF-P03 (range/generation) and BF-P04 (indexed access) remain pending-behind-P01. No new pressures. No regressions. First full fleet inclusion in Wave P6.

## P6 Inclusion

Include `bloom_filter` in `APP-RECHECK-WAVE-P6`.

Expected P6 classification:

- Rust: `oof`, first blocker `OOF-TY0 call_contract append`
- Ruby: `oof`, first blocker `OOF-TY0 call_contract append`, with `OOF-P1 b14` cascade
- Dominant route: `LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1`

## Interpretation

Bloom filter is no longer a clean app baseline under the current compiler. That is useful evidence: the stricter `call_contract` boundary is doing its job and forcing stdlib calls to migrate to canonical source forms.

The app also exposes deeper collection/numeric needs, but those should not be promoted until the append bootstrap is migrated and the app reaches the next blocker.

## Non-Goals

- Do not special-case `call_contract("append")`.
- Do not add mutable bit arrays or runtime indexing authority.
- Do not treat manual modulo as canon numeric semantics.
- Do not introduce string hashing before the basic `stdlib.string` surface exists.

## Wave P7 Recheck Summary (2026-06-13)

Rust: ok / 0 diagnostics — unchanged. Ruby: ok / 0 diagnostics — unchanged. DUAL-TOOLCHAIN CLEAN. No pressure ID changes this wave. No new pressures. (Waves P3–P7 all no-change for this app since LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P2 achieved dual-clean.)

## LAB-BLOOM-FILTER-RANGE-MIGRATION-P1 Migration Summary (2026-06-13)

Gate: LANG-STDLIB-COLLECTION-RANGE-P3 CLOSED (range dual-toolchain).

Changes:
- `ops.ig`: added `MakeSlot` contract (`input pos : Integer` → `output slot : BitSlot` with `set: false`); placed before `MakeSlotTrue`
- `example.ig`: import changed `stdlib.collection.{ append }` → `stdlib.collection.{ map, range }`; `InitFilter16` rewritten — 31 manual nodes (16 slot computes + 14 append chain + 1 bootstrap) replaced with 2 computes:
  - `compute slots : Collection[BitSlot] = map(range(0, 16), i -> call_contract("MakeSlot", i))`
  - `compute bf = { size: 16, num_hashes: 3, bits: slots }`

Note: inline record literal in lambda body (`i -> { pos: i, set: false }`) fails to parse (parser treats `{` as block body in expression position). Workaround: named `MakeSlot` helper contract + type annotation on `slots` compute declaration.

Rust: ok / 0 — CLEAN. Ruby: ok / 0 — CLEAN. DUAL-TOOLCHAIN CLEAN maintained.

BF-P03: ACTIVE-DESIGN-PRESSURE → RESOLVED.
Proof: `igniter-lab/igniter-view-engine/proofs/verify_lab_bloom_filter_range_migration_p1.rb` 50/50 PASS.
Lab doc: `lab-docs/governance/lab-bloom-filter-range-migration-p1-v0.md`.

## Wave P8 Recheck Summary (2026-06-13)

Rust: ok / 0 diagnostics — unchanged. Ruby: ok / 0 diagnostics — unchanged. DUAL-TOOLCHAIN CLEAN. LANG-STRING-TEXT-ALIAS-P2, LANG-RUBY-RECORD-LITERAL-INFERENCE-P5, LANG-STDLIB-STRING-SUBSTRING-P2, and LAB-BLOOM-FILTER-RANGE-MIGRATION-P1 had no effect on this app. No new pressures. No regressions.

## Wave P9 Recheck Summary (2026-06-13)

Rust: ok / 0 diagnostics — unchanged. Ruby: ok / 0 diagnostics — unchanged. DUAL-TOOLCHAIN CLEAN. LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P4, LAB-VE-NEW-OBJ-INFERENCE-P1, LAB-VECTOR-MATH-FIELD-ALIGNMENT-P1, LAB-HOF-LAMBDA-ERROR-PROPAGATION-P2, and LAB-PARSER-RECORD-IN-HOF-P1 had no effect on this app. No new pressures. No regressions.

## Wave P10 Recheck Summary (2026-06-14)

Rust: ok / 0 diagnostics — unchanged. Ruby: ok / 0 diagnostics — unchanged. DUAL-TOOLCHAIN CLEAN. No pressure ID changes this wave. No new pressures. No regressions.

## Wave P11 Recheck Summary (2026-06-14)

Rust: ok / 0 diagnostics — unchanged. Ruby: ok / 0 diagnostics — unchanged. DUAL-TOOLCHAIN CLEAN.

Companion baseline integration (`air_combat`, `lead_router`, `call_router`) and Fold P3/P4 landing had no diagnostic impact on this app. No pressure ID changes this wave. No new pressures. No regressions.

## Wave P12 Recheck Summary (2026-06-15)

Rust: ok / 0 diagnostics. Ruby: ok / 0 diagnostics. DUAL-TOOLCHAIN CLEAN.

The 20-app fleet expansion and new companion intake (`audit_ledger`, `batch_importer`, `job_runner`, `web_router`) had no diagnostic impact on this app. No pressure ID changes. No new pressures. No regressions.

## Wave P13 Recheck Summary (2026-06-15)

Ruby: ok/0. Rust: ok/0. DUAL-CLEAN. Source files: 4. Source hash: `sha256:1a7f62f1976a027d57f69b3ca4b12b5d5d3a3d81e3baefee67bc4c8cb80370f3`. Entrypoint: `none`. unchanged clean app.
No source changes in this wave. No new pressures. No regressions.
