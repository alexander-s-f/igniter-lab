# LAB-PACKAGE-MODEL-P1: Package Identity and Distribution Boundary Research v0

**Track:** package-identity-distribution-and-authority-boundary-v0
**Route:** RESEARCH / DESIGN BOUNDARY / NO IMPLEMENTATION
**Status:** DRAFT v0
**Date:** 2026-06-11

---

## 1. Problem Statement: What are we preventing?

Igniter's Covenant enforces honesty: programs must be transparent accounts of what they do to the world. Conventional packaging models (like npm, cargo, or pip) operate on an opposing principle: opaque executable authority. In those ecosystems, importing a dependency brings both code and the implicit authority for that code to execute anything its runtime allows (e.g., file system access, network calls). This creates ambient authority, hidden transitive runtime behavior, and mutable dependency trees.

Igniter must avoid this trap. An Igniter package cannot be a dependency dump. Instead, **an Igniter package must be a sealed claim artifact.** It makes code and reusable declarations available for verification by the consumer's compiler, but it **must not silently grant authority**. Import must remain strictly a compile-time name resolution mechanism.

## 2. Substrate Inventory: What pieces exist today?

Igniter already possesses a robust verification substrate, meaning packaging can build on existing identity and evidence structures rather than reinventing them. The following pieces are established in canon or lab proofs:

*   **Module Identity & Multi-file Compilation:** `LANG-MODULE-IDENTITY-P2` unified `program_id` around a SHA256 discipline. `PROP-IMPORT-RESOLUTION-P5` established multi-file compilation universes where `import` resolves names but grants zero capability/profile authority.
*   **Source Units Evidence:** `source_units` are already emitted in compilation reports and `.igapp` manifests as evidence of composition.
*   **Entrypoint Metadata:** `PROP-ENTRYPOINT-P4` proved that a package or module can declare a top-level `entrypoint` which acts as manifest metadata without creating runtime execution authority.
*   **Typed Contract Refs:** `LANG-TYPED-CONTRACT-REF-PROP-P3` enables `uses ContractName` declarations, lowering to `dependency_edges` in the `.igapp` manifest (execution dependency: false).
*   **Form Vocabularies:** `LAB-FORM-VOCABULARY-P1` proved cross-module form coherence under explicit `speaks` import models, allowing reusable domain surfaces without hidden syntax injection.
*   **Compiler Profiles:** `PROP-036` and `PROP-040` establish `compiler_profile_id` and profile declarations as the bedrock of compiler and capability authority.

## 3. Package Identity Structure

In Igniter, identity must be semantic and content-addressed, not nominal. 

*   **Content Hash as Identity:** A package's true identity is a cryptographic hash (SHA256) of its manifest and its semantic contents (e.g., `source_units` or SemanticIR), continuing the existing artifact hash discipline.
*   **Distribution Unit:** A package is distributed as an `igpack`—a sealed bundle containing the modules, the manifest, and pre-computed evidence receipts.
*   **Semantic Versioning:** SemVer (`1.2.0`) is retained as a human-facing label, but the resolver's ground truth relies on the computed facts of the artifact hash and compatibility fingerprints.

## 4. Capability & Profile Boundary

This is the core security boundary of the Igniter ecosystem. **Authority does not flow via import.**

1.  **Consumer-side Binding:** If a dependency contains effectful or privileged contracts, importing the module is inert. The *consuming* module must explicitly bind those contracts to a consumer-declared profile (e.g., via PROP-033's `via <profile>` syntax) and supply the necessary capability parameters.
2.  **Transitive Effect Summary:** A package must declare a complete effect summary. Every capability required by its internal code or transitive dependencies must be surfaced. A dependency cannot widen a consumer's capability surface silently—it violates Covenant Postulate 20 (no evidence lost at composition).
3.  **Check, Not Trust:** The consumer's compiler verifies the package's claim. If a package claims `pure` but its SemanticIR contains an `effect` node, the compiler refuses it.

## 5. Resolution & Registry Hypothesis

A conventional registry is a package server. An Igniter registry is **"a content-addressed store of sealed claims."**

*   **Lockfiles as Proof Receipts:** A lockfile in Igniter is not merely a list of resolved versions. It is a verified graph of dependencies, acting as a proof receipt that the resolved closure is compatible and coherent.
*   **Compatibility-Computed Resolution:** Version resolution builds on PROP-017 (contract versioning and CompatibilityReport). Instead of blindly trusting `^1.2.0`, the resolver computes `CompatibilityReport(dep@new, dep@pinned) = safe` using schema fingerprints.

## 6. Concrete `igpack` Manifest Schema Hypothesis

To support this model, the package manifest (e.g., `igpack.json`) must look substantially different from a `package.json`. It resembles the existing `.igapp` manifest but elevated for distribution:

```json
{
  "package_name": "example_domain_lib",
  "version": "1.0.0",
  "package_hash": "sha256:...",
  "compiler_profile_id": "compiler_profile_unified/sha256:...",
  "exports": [
    "Example.Domain.PublicModA",
    "Example.Domain.PublicModB"
  ],
  "effect_summary": {
    "capabilities_required": ["IO.FileCapability", "IO.NetworkCapability"],
    "max_fragment_class": "ESCAPE"
  },
  "dependencies": {
    "some_other_lib": {
      "version_constraint": "^2.1.0",
      "resolved_hash": "sha256:..."
    }
  },
  "compatibility_fingerprints": {
    "Example.Domain.PublicModA.MainContract": "fingerprint_hash_..."
  },
  "proof_receipts": [
    "verify_contract_forms_p1_pass"
  ]
}
```

*   `exports`: Establishes the public/private module visibility boundary.
*   `effect_summary`: Allows consumers to audit required authority before fetching or resolving.
*   `compatibility_fingerprints`: Powers the semantic resolver.
