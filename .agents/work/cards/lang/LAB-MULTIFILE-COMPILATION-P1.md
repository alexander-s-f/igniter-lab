# LAB-MULTIFILE-COMPILATION-P1
## Multi-File Compilation Unit and Import Resolution Proof

**Card:** LAB-MULTIFILE-COMPILATION-P1
**Track:** multifile-compilation-unit-import-resolution-v0
**Status:** CLOSED - ACCEPT (60/60)
**Route:** LAB PROOF / MULTI-FILE COMPILATION / IMPORT REALITY
**Authority:** lab-only evidence
**Date:** 2026-06-11

## Goal

Prove a minimal multi-file compilation universe:

```text
N .ig source files -> one logical compilation universe -> one .igapp-style result
```

with real import resolution, fail-closed diagnostics, deterministic identity,
cross-file record reuse, and cross-file literal `call_contract`.

## Decision

**ACCEPT.**

C2/C3 from LANG-MODULE-IDENTITY-P1 are closed enough for the next design route:
- import is no longer decorative inside the proof-local driver;
- duplicate modules fail closed;
- multi-file identity is deterministic and file-order independent.

## Delivered

| Artifact | Path | Status |
|---|---|---|
| Fixtures | `igniter-view-engine/fixtures/multifile_compilation/` | DONE |
| Proof runner | `igniter-view-engine/proofs/verify_lab_multifile_compilation_p1.rb` | DONE - 60/60 PASS |
| Lab doc | `lab-docs/lang/lab-multifile-compilation-import-resolution-proof-v0.md` | DONE |
| Portfolio update | `.agents/portfolio-index.md` | DONE |

## Proof Results

| Section | Checks |
|---|---:|
| MF-COMPILE | 8/8 |
| MF-IMPORT | 8/8 |
| MF-IDENTITY | 9/9 |
| MF-DIAGNOSTICS | 11/11 |
| MF-AUTHORITY | 8/8 |
| MF-COPYPASTE | 6/6 |
| MF-CLOSED | 10/10 |

Total: **60/60 PASS**.

## Fixtures

Valid:
- `valid_basic`
- `valid_order_independent`
- `valid_cross_file_contract_call`

Invalid fail-closed:
- `invalid_unknown_import`
- `invalid_circular_import`
- `invalid_duplicate_module`
- `invalid_duplicate_contract`
- `invalid_authority_import_attempt`

## Identity Rule

Proof-local multi-file `source_hash`:

```text
sha256(canonical_json([{ module, source_hash, source }, ...] sorted by module))
```

This makes input file order irrelevant while keeping raw-source identity honest.
Changing one file or a comment changes the multi-file `source_hash`.

`contract_ref` remains per-contract. Multi-file `source_hash` does not collapse
into `artifact_hash`.

## Diagnostics

- unknown import -> `OOF-M2`
- circular import -> `OOF-M1`
- duplicate module -> `OOF-M3` candidate
- duplicate contract -> `LAB-MF-DUP-CONTRACT`
- imported effect contract called by pure consumer -> existing `OOF-TY0`

## Authority Boundary

Import does not grant capability authority. Imported effect contracts do not
become executable without consumer-side capability/profile binding. Import does
not change fragment classification by itself.

## Closed Surfaces

- no production compiler CLI
- no package registry
- no semver/distribution/trust store
- no public/internal visibility
- no stdlib-as-import
- no cross-module capability import/binding
- no real IO
- no VM bytecode identity redesign
- no public/stable API
- no canon PROP authority

## Next Route

Recommended:

**PROP-IMPORT-RESOLUTION-P1**

Parallel after this:

**PROP-ENTRYPOINT-P1**

Module visibility remains deferred until import/multifile semantics are stable.
