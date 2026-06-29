# LANG-STDLIB-COLLECTION-PREDICATE-OPS-P4

Status: CLOSED (2026-06-29) — inventory published; digest recomputed; proof 47/47; next = take/drop readiness
Lane: lang / stdlib / collection / predicate-ops / inventory
Mode: bounded implementation
Skill: idd-agent-protocol

## Goal

Publish the already-implemented predicate collection ops into the canonical stdlib inventory:

```text
stdlib.collection.find(Collection[T], T -> Bool) -> Option[T]
stdlib.collection.any(Collection[T], T -> Bool)  -> Bool
stdlib.collection.all(Collection[T], T -> Bool)  -> Bool
```

This card is **surface publication + digest**, not semantics. Canon Ruby P2 and lab Rust P3 already
implemented/typechecked/lowered the operations. The current live gap is that agents and import
resolution still cannot treat these functions as declared stdlib surface because
`stdlib-inventory.json` does not list them.

## Context

Upstream chain:

1. `LANG-STDLIB-COLLECTION-ALGEBRA-PARITY-PROP-P1` chose predicate ops as the first parity slice.
2. `LANG-STDLIB-COLLECTION-PREDICATE-OPS-P2` implemented canon Ruby registry/typechecking/SIR.
3. `LANG-STDLIB-COLLECTION-PREDICATE-OPS-P3` normalized lab Rust:
   - `find -> Option[T]`;
   - `any/all -> Bool`;
   - `OOF-COL1`, `OOF-COL2`, `OOF-COL3`;
   - bare-name qualification to `stdlib.collection.find/any/all`;
   - VM left untouched because qualified mapping already existed.

Live verify-first at card creation:

```text
stdlib.collection.find missing
stdlib.collection.any  missing
stdlib.collection.all  missing
inventory count        43
stdlib_surface_digest  31934924da8a451687830feb1f9a6d3eabe524b69248b068ae70d663ddc1a86a
```

## Authority

Work from:

```text
/Users/alex/dev/projects/igniter-workspace/igniter-lab
```

Primary authority file:

```text
/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/spec/stdlib-inventory.json
```

Useful existing proof patterns:

```text
/Users/alex/dev/projects/igniter-workspace/igniter-lab/frame-ui/igniter-view-engine/proofs/verify_lab_stdlib_collection_map_filter_count_inventory_p5.rb
/Users/alex/dev/projects/igniter-workspace/igniter-lab/lang/igniter-compiler/verify_import_stdlib_surface_p4.rb
/Users/alex/dev/projects/igniter-workspace/igniter-lab/lang/igniter-compiler/src/multifile.rs
```

Read first:

- `LANG-STDLIB-COLLECTION-PREDICATE-OPS-P2`
- `LANG-STDLIB-COLLECTION-PREDICATE-OPS-P3`
- current `stdlib-inventory.json`
- `lang/igniter-compiler/src/multifile.rs` (`include_str!` inventory table)
- current `collection_predicate_ops_tests.rs`

## Scope

Allowed:

- update `/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/spec/stdlib-inventory.json`;
- add one focused verifier/proof script in lab, if useful;
- add one focused lab doc proof packet, if the local pattern calls for it;
- update this card with the closing report.

Closed:

- no changes to Ruby typechecker/registry semantics;
- no changes to Rust typechecker/emitter semantics;
- no VM/runtime changes;
- no parser/syntax changes;
- no new collection operations (`take/drop`, `zip`, `Pair`, `query`, DB predicates);
- no package/import semantics beyond consuming the updated inventory.

## Implementation Notes

Add three entries in `stdlib-inventory.json` following the shape of existing collection entries.

Recommended fields:

```json
{
  "canonical_name": "stdlib.collection.find",
  "semantic_ir_name": "stdlib.collection.find",
  "legacy_sir": null,
  "aliases": [{ "kind": "source_alias", "name": "find" }],
  "category": "collection",
  "lifecycle_status": "production-implemented",
  "semantic_stability": "design-locked",
  "lowering_status": "dual-toolchain",
  "compatibility_status": "pre-v1-none",
  "fragment_class": "core",
  "purity": "pure",
  "deterministic": true,
  "totality": "total",
  "type_params": ["T"],
  "input_signature": ["Collection[T]", "T -> Bool"],
  "output_signature": "Option[T]",
  "diagnostics": ["OOF-COL1", "OOF-COL2", "OOF-COL3"],
  "failure_behavior": "compile-time diagnostics for arity, first argument, and predicate shape",
  "authority_surface": "none",
  "proof_lineage": [
    "LANG-STDLIB-COLLECTION-PREDICATE-OPS-P2",
    "LANG-STDLIB-COLLECTION-PREDICATE-OPS-P3"
  ],
  "examples": ["find(xs, x -> x > 0) -> Option[T]"],
  "compatibility_note": null,
  "owner_surface": "stdlib.collection",
  "entry_digest": null
}
```

Use analogous entries for:

- `stdlib.collection.any`, output `Bool`, example `any(xs, x -> x > 0) -> Bool`;
- `stdlib.collection.all`, output `Bool`, example `all(xs, x -> x > 0) -> Bool`.

After editing entries, recompute `stdlib_surface_digest` using the existing canonical rule:

```text
SHA256(canonical JSON of entries sorted by canonical_name, with entry_digest stripped)
```

Do **not** hash raw file bytes. Preserve the inventory note style and mention P4.

## Proof Requirements

Minimum proof should establish:

1. inventory parses;
2. all required fields are present for the three new entries;
3. each canonical name maps to the matching `semantic_ir_name`;
4. each has one source alias: `find`, `any`, `all`;
5. signatures are exact:
   - `find`: `Collection[T]`, `T -> Bool` -> `Option[T]`;
   - `any/all`: `Collection[T]`, `T -> Bool` -> `Bool`;
6. diagnostics include exactly the relevant collection family: `OOF-COL1`, `OOF-COL2`, `OOF-COL3`;
7. lifecycle/lowering are consistent with P2/P3 (`production-implemented`, `dual-toolchain`);
8. digest recomputes and matches the stored `stdlib_surface_digest`;
9. digest is stable under entry order shuffling and entry_digest stripping;
10. Rust `MultifileResolver` can import the names from `stdlib.collection` because it reads the updated inventory;
11. focused predicate tests from P3 still pass;
12. closed surfaces remain closed: no `take/drop`, no `zip`/`Pair`, no query/DB predicate surface.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab

# Build compiler if a proof script shells out to the binary.
cargo build --manifest-path lang/igniter-compiler/Cargo.toml

# Required focused regressions.
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test collection_predicate_ops_tests
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test package_workspace_tests

# If you add a Ruby proof script, run it explicitly and report pass/fail counts.
# Example:
# ruby frame-ui/igniter-view-engine/proofs/verify_lab_stdlib_collection_predicate_ops_inventory_p4.rb

git diff --check
```

If `package_workspace_tests` is too broad or noisy, replace it with a narrower import-resolution test
that proves:

```ig
import stdlib.collection.{find, any, all}
```

is accepted, while unknown names still produce `OOF-IMP3`.

## Acceptance

- [x] `stdlib.collection.find` entry exists in `stdlib-inventory.json`.
- [x] `stdlib.collection.any` entry exists in `stdlib-inventory.json`.
- [x] `stdlib.collection.all` entry exists in `stdlib-inventory.json`.
- [x] Signatures match P2/P3 exactly.
- [x] Diagnostics list `OOF-COL1`, `OOF-COL2`, `OOF-COL3`.
- [x] `stdlib_surface_digest` is recomputed by canonical entry serialization and matches proof output.
- [x] Inventory import table exposes aliases `find`, `any`, `all`.
- [x] P3 focused Rust tests remain green.
- [x] No runtime/compiler semantics are changed.
- [x] No unrelated collection operations are published.
- [x] `git diff --check` clean.

## Non-goals

- No implementation of `take/drop`.
- No `zip`/`Pair`.
- No collection query DSL.
- No DB predicates.
- No syntax changes.
- No VM edits.

## Closing Report Requirements

Report:

- exact inventory count before/after;
- old and new `stdlib_surface_digest`;
- exact files changed;
- proof command counts;
- whether compiler/VM/runtime semantics were edited;
- the next card.

Expected next card after P4:

```text
LANG-STDLIB-COLLECTION-TAKE-DROP-READINESS-P1
```

or, if live pressure says otherwise:

```text
LANG-STDLIB-COLLECTION-QUERY-SHAPE-READINESS-P1
```

Do not open those surfaces inside this card.

## Closing Report

Closed on 2026-06-29.

Inventory:

- Before: `43` entries
- After: `46` entries
- Old `stdlib_surface_digest`: `31934924da8a451687830feb1f9a6d3eabe524b69248b068ae70d663ddc1a86a`
- New `stdlib_surface_digest`: `d6ec4b7fddc931243c4b59d925680a63da2814fa6aae041b5dcd05f756daf0bc`

Changed files:

- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/spec/stdlib-inventory.json`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/frame-ui/igniter-view-engine/proofs/verify_lab_stdlib_collection_predicate_ops_inventory_p4.rb`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LANG-STDLIB-COLLECTION-PREDICATE-OPS-P4.md`

Published entries:

- `stdlib.collection.find(Collection[T], T -> Bool) -> Option[T]`
- `stdlib.collection.any(Collection[T], T -> Bool) -> Bool`
- `stdlib.collection.all(Collection[T], T -> Bool) -> Bool`

Verification:

- `cargo build --manifest-path lang/igniter-compiler/Cargo.toml --release`
  - passed; release compiler rebuilt so `MultifileResolver` embeds the updated inventory
- `ruby -c frame-ui/igniter-view-engine/proofs/verify_lab_stdlib_collection_predicate_ops_inventory_p4.rb`
  - `Syntax OK`
- `ruby frame-ui/igniter-view-engine/proofs/verify_lab_stdlib_collection_predicate_ops_inventory_p4.rb`
  - `predicate ops inventory P4: 47 passed, 0 failed`
- `cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test collection_predicate_ops_tests`
  - `6 passed; 0 failed`
- `cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test package_workspace_tests`
  - `53 passed; 0 failed`
- `git diff --check`
  - clean in both `igniter-lang` and `igniter-lab`

Boundary:

- No Ruby typechecker/registry semantics changed.
- No Rust typechecker/emitter semantics changed.
- No VM/runtime edits.
- No parser/syntax edits.
- No `take/drop`, `zip`/`Pair`, query, or DB predicate surface published.

Import note:

- The P4 proof uses the true multifile resolver path to verify `import stdlib.collection.{ find, any, all }`.
- Single-file compile remains permissive for unknown selective stdlib imports; that pre-existing behavior was not changed in this inventory card.

Next card:

- `LANG-STDLIB-COLLECTION-TAKE-DROP-READINESS-P1`
