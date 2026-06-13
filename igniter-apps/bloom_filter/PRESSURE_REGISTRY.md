# Bloom Filter Pressure Registry

Status: LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P2 CLOSED — DUAL-CLEAN
Last checked: 2026-06-13
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
- `example.ig` — `BloomFilterExample`; contracts `InitFilter16`, `RunBloomExample`; imports `stdlib.collection.{ append }`

## Pressures

| ID | Status | Pressure | Evidence | Route |
|---|---|---|---|---|
| BF-P01 | RESOLVED | Stringly `call_contract("append")` initialization chain | `InitFilter16` had 15 chained stringly sites; all migrated in `LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P2`: BF-S01 → `compute b0 : Collection[BitSlot] = [s0, s1]`; BF-S02–S15 → `append(b{n-1}, s{n+1})` | `LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P2` CLOSED |
| BF-P02 | RESOLVED | Collection bootstrap shape | First append was `call_contract("append", s0, s1)` (BOOTSTRAP); migrated to `compute b0 : Collection[BitSlot] = [s0, s1]` typed seed in P2; Rust ok because output is record literal `output bf : BloomFilter` (gap does not apply) | `LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P2` CLOSED |
| BF-P03 | ACTIVE-DESIGN-PRESSURE | Missing `range()` / collection generation | `example.ig` manually defines 16 slots and chains append; report says `range(0, 16)` would reduce this to a compact map | `LANG-STDLIB-COLLECTION-RANGE-P1` |
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
