# LANG-CONTRACT-NAMESPACE-P1 — Module-Qualified Contract Namespace Boundary

**Track:** module-qualified-contract-identity-and-duplicate-declaration-boundary-v0
**Route:** RESEARCH / DESIGN BOUNDARY / BLOCKER ANALYSIS / NO IMPLEMENTATION
**Status:** CLOSED — READY FOR P2
**Date:** 2026-06-11
**Routed from:** LAB-PACKAGE-MODEL-P1 (a2, §15 blocker)

---

## Deliverables

| Artefact | Path | Status |
|----------|------|--------|
| Research doc | `igniter-lab/lab-docs/governance/lang-contract-namespace-boundary-v0.md` | Written |
| This card | `igniter-lab/.agents/work/cards/governance/LANG-CONTRACT-NAMESPACE-P1.md` | Written |
| Portfolio update | `igniter-lab/.agents/portfolio-index.md` | Updated |

---

## Problem

Ruby/Rust compilation universes currently treat contract names as globally unique across all
source units (OOF-DECL-DUP-CONTRACT, OOF-DECL-DUP-TYPE). Two packages that both define
`ValidateInput` or `Mapper` cannot coexist — even if their module identities differ
(`Users.ValidateInput` vs `Orders.ValidateInput`).

This is the single most package-hostile property of the current substrate, confirmed
empirically in LANG-TYPED-CONTRACT-REF-PROP-P5 fixture work (could not co-compile two
modules both declaring `Validator` in the same compilation unit).

---

## Findings

### Where the global uniqueness lives

| Surface | File | Lines | Module-aware? |
|---------|------|-------|---------------|
| `duplicate_declaration` (contract) | `multifile_resolver.rb` | 261–267 | NO — flat short-name scan |
| `duplicate_declaration` (type) | `multifile_resolver.rb` | 261–267 | NO — same method |
| `contract_index_for` keys | `assembler.rb` | 416–425 | NO — short `contract_id` |
| `contract_refs` manifest | `assembler.rb` | 246–248 | NO — short `contract_name` |
| `contract_ref` path label | `semanticir_emitter.rb` | 862–864 | NO — `contract/short/sha256:` |
| Entrypoint resolution | `typechecker.rb` | 188–217 | NO — first-match by short name |

### What is already correct

- OOF-IMP4 (duplicate module names) — unchanged, correct
- PATH 1 typed refs (`uses Mod.Contract`) — already module-qualified via `cross_module_registry`
- `per_contract_module` mapping — already maps short name → originating module
- `dependency_edges` `to_module` field — module attribution already present from P5
- OOF-REF2 ambiguity — already fires for ≥2 imported modules with same short contract name

### Recommended identity model

Canonical identity = `(module_name, contract_name)` pair. Source syntax stays short.
Manifest-facing surfaces (contract_index, contract_refs, contract_ref path) use
module-qualified form `module_name.contract_name`.

---

## Design Decisions

### Duplicate rule change

| Case | Current | Required |
|------|---------|----------|
| Same contract name, same module | OOF-DECL-DUP-CONTRACT | UNCHANGED |
| Same contract name, different modules | OOF-DECL-DUP-CONTRACT (WRONG) | ALLOWED |
| Same type name, same module | OOF-DECL-DUP-TYPE | UNCHANGED |
| Same type name, different modules | OOF-DECL-DUP-TYPE (WRONG) | ALLOWED |
| Duplicate module name | OOF-IMP4 | UNCHANGED |

**Fix:** `duplicate_declaration` scans by `(module, name)` pair, not flat short name.

### Contract index keys

`contract_index` and `contract_refs` keys change from `"ValidateInput"` to
`"Users.ValidateInput"` (fully qualified). `contract_ref` path label gains module prefix:
`"contract/Users.ValidateInput/sha256:..."`. File paths: `contracts/users.validate_input.json`.

### Entrypoint disambiguation

`entrypoint ValidateInput` in multifile where two modules both define `ValidateInput` →
OOF-EP2 with qualified disambiguation hint. `entrypoint Users.ValidateInput` resolves
cleanly. Single-file: transparent (one module, no ambiguity possible).

### Migration

Pre-v1 breaking correction. Single-file transparent. Multifile manifest format change
(contract_index keys). No source-level change required by authors.

---

## Closed Surfaces (Unchanged)

Parser implementation / typechecker implementation / resolver implementation beyond the
duplicate check / SemanticIR behavior / assembler beyond contract_index/contract_ref keys /
package manager / registry / import implementation changes / public API / visibility system /
runtime/VM behavior / capability/profile authority.

---

## Required Reads (Done)

- [x] `multifile_resolver.rb` — duplicate_declaration, duplicate_by, source_unit
- [x] `typechecker.rb` — typecheck_uses_contract, validate_entrypoint, build_same_module_registry
- [x] `semanticir_emitter.rb` — contract_ref, typed_contract_ir, contract_refs emission
- [x] `assembler.rb` — contract_index_for, contract_refs, dependency_edges
- [x] LAB-PACKAGE-MODEL-P1-a1 report (compatibility_fingerprints, manifest schema)
- [x] LAB-PACKAGE-MODEL-P1-a2 report (blocker identification, 4-layer separation)
- [x] LANG-TYPED-CONTRACT-REF-PROP-P5 card (per_contract_module, cross_module_registry)
- [x] PROP-ENTRYPOINT-P4 card (qualified entrypoint in Rust lab)

---

## Verdict

**CLOSED — READY FOR P2.**

The problem is precisely scoped. No architectural unknowns remain. The fix is bounded to
five canonical compiler stages (resolver, typechecker, emitter, assembler, orchestrator)
with no parser or runtime changes. Single-file programs are transparent to the change.

Next route:

1. **LAB-PACKAGE-MODEL-P2** — proof-local: implement module-scoped duplicate check +
   module-qualified contract_index; prove two local packages with same-named contracts
   co-compile, manifests are correct, TYPED-REF-P5 (71/71) and IMPORT-P5 (99/99) regressions
   pass, cross-package dependency_edges carry correct to_module attribution, no-authority
   fields assertions, determinism checks.
