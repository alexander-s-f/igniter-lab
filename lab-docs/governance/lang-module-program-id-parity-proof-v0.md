# LANG-MODULE-IDENTITY-P2
## Program ID Algorithm Parity and Identity Contract - v0

**Track:** program-id-algorithm-parity-and-identity-contract-v0
**Status:** CLOSED - ACCEPT; C1 closed
**Route:** GOVERNANCE + PROOF / IDENTITY PARITY / BOUNDED IMPLEMENTATION
**Date:** 2026-06-11
**Authority:** governance/proof evidence only

## 1. Authority Boundary

P2 resolves only C1 from LANG-MODULE-IDENTITY-P1: Ruby/Rust `program_id`
algorithm divergence.

This packet does not authorize:
- multi-file compilation
- import resolution
- OOF-M1/M2/M3 import/module implementation
- package registry or distribution
- public/internal visibility
- stdlib-as-import
- VM bytecode identity redesign
- artifact passport expansion
- canon PROP

Lab evidence does not become canon by itself. The implementation change is
bounded to Rust lab pass-id parity in `classifier.rs` and `typechecker.rs`.

## 2. Current `program_id` Inventory

| Surface | Location | Algorithm | Input material | Output shape | Version material | Consumers | Stable across identical source |
|---|---|---|---|---|---|---|---|
| Ruby classifier pass id | `igniter-lang/lib/igniter_lang/classifier.rb` | SHA256 prefix16 | `source_path`, `grammar_version`, `source_hash`, classifier version | `classifier_pass/<16hex>` | `classifier-pass-executable-proof-v0` | Ruby classified program; Ruby typechecker seed | Yes, if path/source/version same |
| Ruby typechecker pass id | `igniter-lang/lib/igniter_lang/typechecker.rb` | SHA256 prefix16 | classifier `program_id`, `source_hash`, typechecker version | `typed_pass/<16hex>` | `typed-pass-executable-proof-v0` | Ruby typed program; Ruby SemanticIR emitter input | Yes, if classifier/source/version same |
| Ruby SemanticIR program id | `igniter-lang/lib/igniter_lang/semanticir_emitter.rb` | source SHA256 prefix16 | `source_hash` | `semanticir/<16hex>` | none beyond source hash | `semantic_ir_ref`, `.igapp` manifest | Yes, if raw source same |
| Ruby compilation report id | `igniter-lang/lib/igniter_lang/semanticir_emitter.rb` | source SHA256 prefix16 | `source_hash` | `compilation_report/<16hex>` | none beyond source hash | `compilation_report_ref`, `.igapp` manifest | Yes, if raw source same |
| Rust classifier pass id before P2 | `igniter-lab/igniter-compiler/src/classifier.rs` | blake3-derived | `grammar_version`, classifier version | `classifier_pass/<legacy>` | classifier version | Rust classified program; Rust typechecker seed | Deterministic but not Ruby-parity |
| Rust classifier pass id after P2 | `igniter-lab/igniter-compiler/src/classifier.rs` | SHA256 prefix16 | `source_path`, `grammar_version`, `source_hash`, classifier version | `classifier_pass/<16hex>` | `classifier-pass-executable-proof-v0` | Rust classified program; Rust typechecker seed | Yes, parity with Ruby seed contract |
| Rust typechecker pass id before P2 | `igniter-lab/igniter-compiler/src/typechecker.rs` | blake3-derived | classified `program_id`, typechecker version | `typed_pass/<legacy>` | typechecker version | Rust typed program | Deterministic but not Ruby-parity |
| Rust typechecker pass id after P2 | `igniter-lab/igniter-compiler/src/typechecker.rs` | SHA256 prefix16 | classified `program_id`, `source_hash`, typechecker version | `typed_pass/<16hex>` | `typed-pass-executable-proof-v0` | Rust typed program | Yes, parity with Ruby seed contract |
| Rust SemanticIR program id | `igniter-lab/igniter-compiler/src/emitter.rs` | source SHA256 prefix16 | `source_hash` | `semanticir/<16hex>` | none beyond source hash | `semantic_ir_ref`, `.igapp` manifest | Yes, parity with Ruby |
| Rust compilation report id | `igniter-lab/igniter-compiler/src/emitter.rs` | source SHA256 prefix16 | `source_hash` | `compilation_report/<16hex>` | none beyond source hash | `compilation_report_ref`, `.igapp` manifest | Yes, parity with Ruby |

Note: the Rust `classified_ast.json` emitted in `.igapp` output is an assembled
projection with `semanticir/<16hex>`, not the raw classifier pass artifact. P2
does not expand `.igapp` artifacts to expose raw pass-local ids.

## 3. Semantic Classification

`program_id` is namespace-dependent:
- `classifier_pass/<16hex>` and `typed_pass/<16hex>` are deterministic pass identities.
- `semanticir/<16hex>` is a deterministic compilation-unit reference derived from raw `source_hash`.
- `compilation_report/<16hex>` is a deterministic diagnostic/report reference derived from raw `source_hash`.

`program_id` is not source/content identity stronger than `source_hash`, contract
identity, artifact identity, compiler profile identity, capability authority,
package/module authority, or a trust signal.

The stronger identities remain `source_hash`, `contract_ref`, `artifact_hash`,
and `compiler_profile_id`.

## 4. Algorithm Decision

Decision: **UNIFY TO SHA256** for pass-local `program_id`.

P2 aligns Rust lab classifier/typechecker pass-id algorithms to the existing
Ruby seed contract:

```text
classifier_pass = sha256(
  source_path | grammar_version | source_hash | classifier_version
)[0,16]

typed_pass = sha256(
  classified_program_id | source_hash | typechecker_version
)[0,16]
```

`semanticir/<16hex>` and `compilation_report/<16hex>` already used
`source_hash` prefix16 in both toolchains. P2 keeps that behavior.

P2 does not rename or split fields in artifacts. A future canon/schema route may
choose clearer field names, but that is not needed to close C1.

## 5. Input Material Decision

| Identity | Input material | Rationale |
|---|---|---|
| `classifier_pass/*` | `source_path + grammar_version + source_hash + classifier_version` | Identifies this deterministic classifier pass result for this source unit and compiler pass version |
| `typed_pass/*` | `classified_program_id + source_hash + typechecker_version` | Chains typed identity to the classified pass and raw source identity |
| `semanticir/*` | `source_hash` prefix16 | Keeps emitted SemanticIR reference stable across toolchains for the same raw source |
| `compilation_report/*` | `source_hash` prefix16 | Keeps emitted report reference stable across toolchains for the same raw source |

Comment-only changes are raw-source changes. They change `source_hash` and
therefore change `program_id` under this contract. P2 does not introduce a
semantic hash that ignores comments.

## 6. Cross-Toolchain Parity Evidence

Proof runner:

```text
igniter-view-engine/proofs/verify_lang_module_identity_p2.rb
```

Result:

```text
LANG-MODULE-IDENTITY-P2 PASS (42/42)
```

Evidence summary:
- P1 divergence record found: C1 + `blake3`.
- Rust classifier/typechecker pass-id code now imports SHA256.
- Rust classifier/typechecker pass-id code no longer calls `blake3::hash`.
- Ruby classifier id equals the chosen SHA256 seed.
- Rust classifier source uses the same seed order and prefix length.
- Ruby typed id equals the chosen chained SHA256 seed.
- Rust typechecker source uses the same chained seed shape.
- Ruby/Rust `semanticir/<16hex>` refs match for the same fixture.
- Ruby/Rust `compilation_report/<16hex>` refs match for the same fixture.
- Rust manifest refs remain shape-valid.
- two different sources produce different `source_hash`, classifier ids, and SemanticIR refs.
- comment-only source changes are explicitly classified as raw-source identity changes.

Because Rust `.igapp` does not emit raw classifier/typechecker pass artifacts,
the proof checks Rust pass-id parity at source level and emitted SemanticIR /
report / manifest parity at artifact level. P2 deliberately avoids expanding
artifact output solely to expose raw pass-local ids.

Additional regression:

```text
cargo build --release
cargo test --release
```

Result:
- build PASS
- test PASS: 14/14 integration tests, 0 unit/doc tests
- pre-existing warnings only

## 7. Ref Impact

| Surface | Impact |
|---|---|
| `semantic_ir_ref` | No behavior change; remains `semanticir/<source_hash prefix16>` |
| `compilation_report_ref` | No behavior change; remains `compilation_report/<source_hash prefix16>` |
| `.igapp` manifest | No new fields; manifest refs remain shape-valid |
| source maps | No identity redesign; source map behavior unchanged |
| bytecode maps / VM trace | No VM bytecode identity work opened |
| future multi-file `source_hash` | Still requires a separate multi-file source hashing rule |
| compiler profile ID | Unchanged; `program_id` does not replace `compiler_profile_id` |

## 8. Regression / Non-Authority Checks

Confirmed by proof:
- `source_hash` remains SHA256 raw source identity.
- `contract_ref` remains contract identity.
- `artifact_hash` remains full artifact identity.
- `program_id` does not become capability authority.
- `program_id` does not replace `compiler_profile_id`.
- no multi-file compiler driver was added.
- no import resolution was implemented.
- no package registry surface was added.
- no VM bytecode identity was changed.

## 9. Decision Matrix

Decision: **ACCEPT**

C1 is closed for the scoped identity contract:
- pass-local `program_id` algorithms are SHA256-aligned in Ruby/Rust source;
- emitted SemanticIR/report/manifest refs already match under source-hash prefix identity;
- no import/multi-file/package authority was opened.

Remaining P1 blockers:
- C2 import remains semantically inert; belongs to LAB-MULTIFILE-COMPILATION-P1.
- C3 duplicate module names can ship with the multi-file driver.

## 10. Exact Next Route

Next route:

**LAB-MULTIFILE-COMPILATION-P1**

Scope for that later route:
- N `.ig` files to one `.igapp`
- import resolution
- OOF-M1/M2 enforcement for import graph failures
- OOF-M3 duplicate module declaration handling
- canonical multi-file `source_hash` rule

Still closed:
- package registry
- public/internal visibility
- stdlib-as-import
- runtime capability authority
- public/stable package API

## 11. Changed Files

Implementation:
- `igniter-lab/igniter-compiler/src/classifier.rs`
- `igniter-lab/igniter-compiler/src/typechecker.rs`

Proof/governance:
- `igniter-lab/igniter-view-engine/proofs/verify_lang_module_identity_p2.rb`
- `igniter-lab/lab-docs/governance/lang-module-program-id-parity-proof-v0.md`
- `igniter-lab/.agents/work/cards/governance/LANG-MODULE-IDENTITY-P2.md`
- `igniter-lab/.agents/portfolio-index.md`
