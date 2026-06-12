# Lab Doc: stdlib.collection.append Rust Parity
## LANG-STDLIB-COLLECTION-APPEND-PROP-P4

**Lane:** lang / stdlib / collection / append  
**Track:** Rust TC parity proof  
**Status:** CLOSED — PROVED 66/66 PASS  
**Date:** 2026-06-12  
**Proof runner:** `igniter-lab/igniter-view-engine/proofs/verify_lab_stdlib_collection_append_rust_parity_p4.rb`  
**Card:** `igniter-lab/.agents/work/cards/lang/LANG-STDLIB-COLLECTION-APPEND-PROP-P4.md`

---

## Summary

P4 implements `stdlib.collection.append` in the Rust lab compiler — matching the Ruby P3
behavior across all three OOF codes, Unknown permissive rule, happy path, and SIR
qualification. Two changes in `typechecker.rs` and `emitter.rs`; inventory `lowering_status`
upgraded from `ruby-only` to `dual-toolchain`. 66-check proof runner reaching 66/66 PASS.

---

## Changes

### `igniter-lab/igniter-compiler/src/typechecker.rs`

**New `"append"` arm** inserted after the `"fold"` arm, before `"avg" | "min" | "max"`:

- `is_resolved = true` guards prevent fall-through
- OOF-COL1: `args.len() != 2` → Unknown result
- OOF-COL2: first typed arg not `"Collection"` and not `"Unknown"` → Unknown result
- Element type extracted via `get_param(&typed_args[0].resolved_type, 0)`; falls back to Unknown for Unknown collections
- OOF-COL6: both concrete and different names → diagnostic recorded, inference continues
- Return type: `{"name": "Collection", "params": [elem_type]}` — preserves input element type
- SIR fn: `"stdlib.collection.append"` (set by `COLLECTION_HOF_OPS` rewrite in emitter)

### `igniter-lab/igniter-compiler/src/emitter.rs`

**Change 1** — `COLLECTION_HOF_OPS` table extended to 4 entries:

```rust
const COLLECTION_HOF_OPS: &[(&str, &str)] = &[
    ("map",    "stdlib.collection.map"),
    ("filter", "stdlib.collection.filter"),
    ("count",  "stdlib.collection.count"),
    ("append", "stdlib.collection.append"),
];
```

**Change 2** — `TEXT_STDLIB_OPS_C` delegation guard in `semantic_expr_for_compute`:

```rust
|| matches!(fn_val, "map" | "filter" | "count" | "append")
```

Both changes are required: `COLLECTION_HOF_OPS` handles the direct-call path (bare → qualified
name rewrite); the delegation guard handles the compute-block path (delegates to `semantic_expr`
for SIR qualification).

### `igniter-lang/docs/spec/stdlib-inventory.json`

`stdlib.collection.append` entry updated:

| Field | P3 value | P4 value |
|-------|----------|----------|
| `lowering_status` | `ruby-only` | `dual-toolchain` |
| `proof_lineage` | P3 entry | P3 + P4 entry added |
| `stdlib_surface_digest` | `f0e592fc…` | `a94ef6fe…` |

Full P4 digest: `a94ef6fea90bd8d14f210df323bc4250086c52f9ffe62909f2323702a2521c44`  
(27 entries, computed with Ruby due to UTF-8 vs `\uXXXX` encoding requirement)

---

## OOF Code Parity

| Code | Ruby P3 rule string | Rust P4 rule string | Match |
|------|---------------------|---------------------|-------|
| OOF-COL1 | `"OOF-COL1"` | `"OOF-COL1"` | ✓ |
| OOF-COL2 | `"OOF-COL2"` | `"OOF-COL2"` | ✓ |
| OOF-COL6 | `"OOF-COL6"` | `"OOF-COL6"` | ✓ |

All three codes, messages, and Unknown permissive behavior are verified identical by G section
(6 checks).

---

## SIR Qualification

Bare `append` in source produces `"fn": "stdlib.collection.append"` in SIR for both toolchains.
The emitter's `COLLECTION_HOF_OPS` table is the single rewrite point — both the direct-call
and compute-block paths delegate through it. A-07 and A-08 verify the table shape and absence
of bare name in SIR.

---

## Build

`cargo build --release` — 15.63s clean build, 0 errors, 0 warnings on modified paths.

---

## Proof Matrix

| Section | Content | Checks |
|---------|---------|--------|
| A (Rust source structure) | arm/table entries/delegation guard/SIR | 8 |
| B (OOF-COL1) | 0 args / 1 arg / 3 args | 6 |
| C (OOF-COL2) | String/Integer/custom type first arg | 6 |
| D (OOF-COL6) | Collection[String]+Integer / Collection[Integer]+String | 6 |
| E (Unknown permissive) | Unknown collection / Unknown item / matching types | 5 |
| F (happy path + SIR) | String/Integer/custom; fn name qualified; bare absent; status ok | 8 |
| G (Ruby P3 parity) | OOF codes / messages / no diagnostics / fn name | 6 |
| H (inventory) | entry / lowering_status / lifecycle / digest / P4 lineage | 7 |
| I (authority closed) | no VM dispatch / purity / HOF table count / is_resolved | 6 |
| J (regression) | map/filter/count/fold/sum all pass | 8 |
| **Total** | | **66 / 66 PASS** |

---

## Closed Surfaces

- No parser / classifier / assembler changes
- No VM / runtime / capability authority
- No new OOF-IMP codes — emitter changes are internal rewrite table only
- No app fixture edits
- No map / filter / count / fold / sum regressions
- No `stdlib.collection.empty` / concat changes

---

## Next Routes

- **LANG-STDLIB-IMPORT-SURFACE-P3** — `import stdlib.collection.{ append }` resolves without
  OOF-IMP3 once import surface is wired to inventory `lab-implemented` entries
- **LANG-STDLIB-COLLECTION-APPEND-PROP-P5** — VM lowering path (if scheduled)
