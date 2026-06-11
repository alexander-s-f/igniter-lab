# LANG-MODULE-IDENTITY-P2
## Program ID Algorithm Parity and Identity Contract

**Card:** LANG-MODULE-IDENTITY-P2
**Track:** program-id-algorithm-parity-and-identity-contract-v0
**Status:** CLOSED - ACCEPT; C1 closed
**Route:** GOVERNANCE + PROOF / IDENTITY PARITY / BOUNDED IMPLEMENTATION
**Authority:** governance/proof evidence only
**Date:** 2026-06-11

## Goal

Resolve LANG-MODULE-IDENTITY-P1 blocker C1:

Ruby and Rust toolchains used divergent pass-local `program_id` algorithms.
P2 decides the identity contract and proves parity without opening multi-file,
import, package, visibility, or VM identity work.

## Decision

Decision: **UNIFY TO SHA256**.

Pass-local ids are deterministic pass identities:

```text
classifier_pass = sha256(source_path | grammar_version | source_hash | classifier_version)[0,16]
typed_pass      = sha256(classified_program_id | source_hash | typechecker_version)[0,16]
```

Emitted refs remain source-derived:

```text
semanticir/<source_hash prefix16>
compilation_report/<source_hash prefix16>
```

`program_id` is not authority, not `source_hash`, not `contract_ref`, not
`artifact_hash`, and not `compiler_profile_id`.

## Delivered

| Artifact | Path | Status |
|---|---|---|
| Rust classifier parity fix | `igniter-compiler/src/classifier.rs` | DONE |
| Rust typechecker parity fix | `igniter-compiler/src/typechecker.rs` | DONE |
| Proof runner | `igniter-view-engine/proofs/verify_lang_module_identity_p2.rb` | DONE - 42/42 PASS |
| Readiness/proof doc | `lab-docs/governance/lang-module-program-id-parity-proof-v0.md` | DONE |
| Portfolio update | `.agents/portfolio-index.md` | DONE |

## Proof Results

| Section | Checks |
|---|---:|
| MIDP2-INVENTORY | 6/6 |
| MIDP2-CONTRACT | 8/8 |
| MIDP2-PARITY | 6/6 |
| MIDP2-REFS | 6/6 |
| MIDP2-SENSITIVITY | 6/6 |
| MIDP2-NONAUTH | 10/10 |

Total: **42/42 PASS**.

Additional regression:

```text
cargo build --release
cargo test --release
```

Result: PASS. Rust compiler tests: 14/14 integration tests passed.

## Explicit Answers

1. C1 closed? YES.
2. Algorithm decision clear? YES - SHA256.
3. Input material explicit? YES.
4. Ruby/Rust parity proved? YES, source-level pass-id parity plus emitted ref parity.
5. `semantic_ir_ref` changed? NO.
6. `compilation_report_ref` changed? NO.
7. `source_hash` remains raw source SHA256? YES.
8. `contract_ref` remains contract identity? YES.
9. `artifact_hash` remains artifact identity? YES.
10. `program_id` becomes authority/trust signal? NO.

## Boundary Notes

Rust `.igapp` output does not expose raw classifier/typechecker pass artifacts;
`classified_ast.json` is an assembled projection carrying `semanticir/*`.
P2 does not expand artifacts just to expose pass-local ids.

Comment-only changes are classified as raw-source changes because `source_hash`
is raw source SHA256. P2 does not create a semantic hash that ignores comments.

## Closed Surfaces

- no multi-file compiler driver
- no import resolution
- no OOF-M1/M2/M3 import/module implementation
- no package registry
- no public/internal visibility
- no stdlib-as-import
- no VM bytecode identity redesign
- no artifact passport expansion
- no canon PROP
- no authority claim from `program_id`

## Next Route

**LAB-MULTIFILE-COMPILATION-P1**

Scope for next route: N `.ig` files to one `.igapp`, import resolution,
OOF-M1/M2 import graph failures, OOF-M3 duplicate module handling, and a
canonical multi-file `source_hash` rule.
