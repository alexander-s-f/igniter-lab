# LAB-MULTIFILE-COMPILATION-P1
## Multi-File Compilation Unit and Import Resolution Proof - v0

**Track:** multifile-compilation-unit-import-resolution-v0
**Status:** CLOSED - ACCEPT (60/60)
**Route:** LAB PROOF / MULTI-FILE COMPILATION / IMPORT REALITY
**Date:** 2026-06-11
**Authority:** lab-only evidence

## Decision

**ACCEPT.** Multi-file compilation works proof-locally, and C2/C3 from
LANG-MODULE-IDENTITY-P1 are closed enough to open the next design/proposal
route.

P1 proves:

```text
N .ig files -> one proof-local compilation universe -> one .igapp-style result
```

with real import resolution, fail-closed import/module diagnostics, deterministic
multi-file identity, cross-file named record reuse, and cross-file literal
`call_contract`.

## Authority Boundary

This proof uses a proof-local Ruby driver named `ProofLocalMultifileDriver`.
The driver parses N files, validates module/import relationships, merges
declarations into one temporary universe source, and uses the existing Rust lab
compiler as the single-file backend.

This card does not authorize:
- production compiler CLI support
- canon import resolution
- package registry
- semver / distribution / trust store
- public/internal visibility
- stdlib-as-import
- cross-module capability import or binding
- VM bytecode identity redesign
- public/stable API
- canon PROP authority

## Delivered

| Artifact | Path | Purpose |
|---|---|---|
| Fixtures | `igniter-view-engine/fixtures/multifile_compilation/` | 3 valid and 5 invalid fixture sets |
| Proof runner | `igniter-view-engine/proofs/verify_lab_multifile_compilation_p1.rb` | 60 checks |
| Lab doc | `lab-docs/lang/lab-multifile-compilation-import-resolution-proof-v0.md` | This packet |
| Agent card | `.agents/work/cards/lang/LAB-MULTIFILE-COMPILATION-P1.md` | Work card |
| Portfolio | `.agents/portfolio-index.md` | Index entry |

## Fixture Matrix

Valid fixtures:
- `valid_basic/` - provider module declares `QueryResult` and `FilterPredicate`; consumer imports and uses them.
- `valid_order_independent/` - three files, whole-module and selective imports, file-order determinism.
- `valid_cross_file_contract_call/` - consumer imports a pure contract and calls it via literal `call_contract`.

Invalid fixtures:
- `invalid_unknown_import/` - unknown module path.
- `invalid_circular_import/` - two-module import cycle.
- `invalid_duplicate_module/` - duplicate module declaration.
- `invalid_duplicate_contract/` - duplicate contract name across the universe.
- `invalid_authority_import_attempt/` - pure consumer attempts to call imported effect contract.

## Proof Results

| Section | Checks | Purpose |
|---|---:|---|
| MF-COMPILE | 8 | valid universes compile; all files visible; single-file backend unchanged |
| MF-IMPORT | 8 | module/selective imports; cross-file records; literal `call_contract`; order behavior |
| MF-IDENTITY | 9 | deterministic multi-file `source_hash`; manifest-like refs; per-contract refs |
| MF-DIAGNOSTICS | 11 | unknown/circular/duplicate failures |
| MF-AUTHORITY | 8 | import carries no capability authority |
| MF-COPYPASTE | 6 | `QueryResult` / `FilterPredicate` reused without consumer redefinition |
| MF-CLOSED | 10 | closed surfaces remain closed |

Total: **60/60 PASS**.

## Import Semantics Proved

P1 proves:
- importing a module resolves against the module table;
- selective imports resolve named types/contracts;
- imported named record types typecheck in consumer outputs;
- imported pure contracts are visible to literal `call_contract`;
- file order passed to the driver does not affect the result;
- import-line order does not affect resolved contract set.

The proof keeps raw-source identity honest: changing source text, including a
comment-only change, changes multi-file `source_hash`.

## Multi-File Identity Rule

Proof-local multi-file `source_hash` is:

```text
sha256(canonical_json([
  { module, source_hash, source },
  ...
] sorted by module))
```

Consequences:
- input file order does not affect identity;
- module name alone is not content identity;
- changing one file changes identity;
- comment-only changes are raw-source identity changes;
- multi-file `source_hash` does not collapse into `artifact_hash`.

Manifest-like refs use the multi-file source hash prefix:

```text
semanticir/<source_hash prefix16>
compilation_report/<source_hash prefix16>
```

`contract_ref` remains per-contract, not per-module.

## Diagnostics

P1 proves fail-closed diagnostics:

| Case | Rule |
|---|---|
| Unknown import path | `OOF-M2` |
| Circular import | `OOF-M1` |
| Duplicate module declaration | `OOF-M3` candidate |
| Duplicate contract name | `LAB-MF-DUP-CONTRACT` |
| Imported effect contract called from pure consumer | `OOF-TY0` from existing call_contract purity gate |

Diagnostics include module/path facts sufficient for debugging.

## Authority Semantics

Import does not confer capability authority. P1 proves:
- pure fixtures remain `core`;
- imported effect contract does not become callable through import;
- import does not inject capability grants;
- no consumer-side capability/profile binding appears in pure fixtures;
- package/registry/distribution metadata remains absent.

## Copy-Paste Reduction Evidence

`valid_basic/types.ig` declares `QueryResult` and `FilterPredicate` once.
`valid_basic/consumer.ig` imports both and does not redefine either type.

The consumer output typechecks using imported `QueryResult`, and another
consumer output typechecks using imported `FilterPredicate`.

This is proof-local reuse, not stdlib authority.

## Closed Surfaces

Still closed:
- package registry
- semver
- public/internal visibility
- stdlib-as-import claim
- real file/network/storage IO
- VM bytecode identity redesign
- public/stable API
- canon PROP authority

## Next Route

Recommended next route:

**PROP-IMPORT-RESOLUTION-P1**

Purpose: proposal-authoring for import resolution semantics, diagnostics, and
multi-file compilation-unit identity.

Parallel route that may run after this:

**PROP-ENTRYPOINT-P1**

Module visibility remains deferred until import/multifile semantics are stable.
