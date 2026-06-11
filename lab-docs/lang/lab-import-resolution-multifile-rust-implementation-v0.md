# PROP-IMPORT-RESOLUTION-P3
## Rust-Lab Multi-File Import Resolution Implementation - v0

**Track:** import-resolution-multifile-compiler-driver-implementation-v0
**Status:** CLOSED - ACCEPT (83/83)
**Route:** BOUNDED IMPLEMENTATION / RUST-LAB FIRST
**Date:** 2026-06-11
**Authority:** lab/Rust implementation evidence only

## Decision

**ACCEPT.** The Rust lab compiler now has a bounded multi-file compilation
pre-pass for import/module resolution.

P3 implements:

```text
compile SOURCE [SOURCE ...] --out OUT.igapp
```

When more than one source path is provided, the lab compiler builds a source-unit
inventory, validates the module/import graph, fails closed on duplicate
declarations, then merges the files into one deterministic logical universe for
the existing classifier/typechecker/emitter/assembler path.

Single-source behavior is preserved.

## Authority Boundary

This is Rust-lab implementation only.

Still closed:

- Ruby canon implementation
- package registry / distribution / semver / trust store
- public/internal visibility
- stdlib-as-import promotion
- runtime loading / dynamic imports
- capability/profile import
- VM changes
- public/stable API
- package trust authority

Import remains compile-time name resolution only. It does not grant capability,
profile, package, runtime, or execution authority.

## Implementation Delivered

| Artifact | Path | Purpose |
|---|---|---|
| Multi-file resolver | `igniter-compiler/src/multifile.rs` | SourceUnit inventory, module table, import graph, duplicate declaration checks, composite source hash, merged source |
| CLI integration | `igniter-compiler/src/main.rs` | Preserve single-source path; route N>1 sources through Rust-lab multi-file pre-pass |
| Module export | `igniter-compiler/src/lib.rs` | Expose resolver module |
| Manifest evidence | `igniter-compiler/src/assembler.rs` | Copy `source_units` evidence into manifest when present |
| Fixtures | `igniter-view-engine/fixtures/multifile_compilation_p3/` | Valid and invalid P3 fixture matrix |
| Proof runner | `igniter-view-engine/proofs/verify_prop_import_resolution_p3.rb` | 83 checks |
| Lab doc | `lab-docs/lang/lab-import-resolution-multifile-rust-implementation-v0.md` | This packet |
| Agent card | `.agents/work/cards/lang/PROP-IMPORT-RESOLUTION-P3.md` | Work card |
| Portfolio | `.agents/portfolio-index.md` | Index entry |

## CLI Shape

Lowest-risk shape chosen:

```text
igniter_compiler compile one.ig --out out.igapp
igniter_compiler compile one.ig two.ig three.ig --out out.igapp
```

The first form keeps existing behavior. The second form is lab compiler
multi-file behavior and does not claim a public/stable CLI API.

## SourceUnit Inventory

For each source file, P3 records:

- `source_path`
- raw `source`
- per-file `source_hash`
- parsed `SourceFile`
- `module_path`
- `imports`
- top-level type names
- top-level contract names

The manifest and compilation report include `source_units` evidence for
multi-file compiles:

- `module`
- `source_path`
- `source_hash`
- `types`
- `contracts`

This evidence is not a Ch6 canon schema update.

## Multi-File Identity

Composite `source_hash` is:

```text
sha256(canonical_json([
  { module, source_path, source_hash, source },
  ...
] sorted by module path then source_path))
```

The proof establishes:

- file input order does not affect `source_hash`;
- source edits change `source_hash`;
- comment-only edits change `source_hash`;
- `contract_ref` remains per-contract;
- `artifact_hash` remains distinct from `source_hash`.

## Diagnostics

P3 uses the P2A namespace decision:

| Case | Rule |
|---|---|
| Circular import | `OOF-IMP1` |
| Unknown module import | `OOF-IMP2` |
| Missing selective import name | `OOF-IMP3` |
| Duplicate module declaration | `OOF-IMP4` |
| Missing module declaration in N>1 source unit | `OOF-IMP5` |
| Duplicate contract across universe | `OOF-DECL-DUP-CONTRACT` |
| Duplicate type across universe | `OOF-DECL-DUP-TYPE` |

The proof verifies diagnostic payload facts:

- `source_path`
- `module_path`
- `import_path`
- `missing_name`
- `source_paths`
- `module_paths`
- `cycle_path`

No import failure emits the old candidate `OOF-M1/M2/M3` codes.

## Proof Results

| Section | Checks | Purpose |
|---|---:|---|
| IMP3-COMPILE | 9 | Rust-lab N-source compile and single-source regression |
| IMP3-IMPORT | 10 | whole/selective imports, cross-file record use, literal `call_contract`, order behavior |
| IMP3-IDENTITY | 13 | composite identity, source_units evidence, refs, artifact identity |
| IMP3-DIAGNOSTICS | 20 | `OOF-IMP*` and declaration duplicate failures |
| IMP3-AUTHORITY | 8 | import does not grant authority |
| IMP3-COPYPASTE | 8 | `QueryResult` / `FilterPredicate` reuse without redefinition |
| IMP3-CLOSED | 10 | closed surfaces remain closed |
| IMP3-REGRESSION | 5 | cargo/toolchain and machine-readable result checks |

Total: **83/83 PASS**.

Additional compatibility check:

```text
LAB-MULTIFILE-COMPILATION-P1 PASS (60/60)
```

The older P1 proof remains green and is now historical/proof-local evidence; P3
is the Rust-lab implementation route using final P2A diagnostic names.

## Fixture Matrix

Valid:

- `valid_basic/`
- `valid_order_independent/`
- `valid_cross_file_contract_call/`

Invalid fail-closed:

- `invalid_unknown_import/`
- `invalid_missing_selective_name/`
- `invalid_circular_import/`
- `invalid_duplicate_module/`
- `invalid_missing_module/`
- `invalid_duplicate_contract/`
- `invalid_duplicate_type/`
- `invalid_authority_import_attempt/`

## Authority Semantics

P3 proves:

- import does not change fragment classification;
- imported effect contracts do not become callable from pure consumers;
- no package registry/distribution metadata appears;
- no capability grants or imported authority appear;
- pure fixtures remain core.

## Next Routes

Recommended:

```text
PROP-IMPORT-RESOLUTION-P4 - Ruby/canon implementation planning or parity decision
```

Independent parallel route:

```text
PROP-ENTRYPOINT-P3
```

Still deferred:

- module visibility;
- package/distribution;
- stdlib-as-import;
- real runtime loading.
