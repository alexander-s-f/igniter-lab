# lab-igniter-package-research-igniter-artifacts-gemini-p1-v0 — Igniter-specific package unit and artifact taxonomy

**Card:** `LAB-IGNITER-PACKAGE-RESEARCH-IGNITER-ARTIFACTS-GEMINI-P1`  
**Parent Card:** `LAB-IGNITER-PACKAGE-MANAGER-READINESS-P1`  
**Delegation-Code:** `GEMINI-20260618-PACKAGES-E`  
**Status:** RESEARCH PACKET (v0 / Recommended)  
**Scope:** Design analysis of Igniter's internal artifact taxonomy, namespace routing, capabilities boundary, lockfile reproducibility, and package manager v0 design. **No code implementation, no compiler edits, no package spec creation.**  
**Authority:** Lab research only. Grounded in `project.rs`, `protocol.rs`, and the `Projection Dialects (P0)` contract.

---

## 1. Executive Summary

We define a targeted package model for the Igniter ecosystem based on its native artifact taxonomy rather than importing assumptions from other language ecosystems. 

Our key design recommendations are:
1.  **Dual Package Model (Source + Generated + Compiled)**: A package should package the authored source (for auditing), generated projection outputs (for caching and version safety), and compiled `.igapp` binaries (for execution efficiency).
2.  **Explicit Lockfile Pins**: An `igniter.lock` must cryptographically pin not just dependency hashes, but compiler, stdlib, and dialect lowerer versions to prevent compilation drift.
3.  **Namespace Isolation**: Package modules must map to isolated logical namespaces derived from package names (e.g. `import PackageName.Module`) to prevent import graph collisions.
4.  **No Smuggled Secrets**: Host capabilities (e.g., Postgres or HTTP upstreams) must be declared in manifests as privilege requests; secrets and connection details must remain strictly host-owned.

---

## 2. Artifact Taxonomy

Igniter's workflow involves several distinct artifacts. A robust packaging model must classify and treat each artifact category appropriately:

```
[Authoring Syntax] ──────► [Generated Artifact] ─────► [Compiled Artifact] ─────► [Durable Deployment]
  .ig (canonical)            gen/routes.ig (inspectable)   build/app.igapp (binary)    ServiceRecipe (signed)
  .igweb (dialect)           gen/views.json                (Monomorphized IR)          (Host topology)
  .igv (dialect)
```

1.  **Source (`.ig`)**: Canonical, executable contract logic. This is the only runtime authority. Consumed directly by `igc` for module graph assembly.
2.  **Projection Source (`.igweb`, `.igv`)**: Ergonomic authoring syntax. As defined in `P0`, dialects hold zero runtime authority and must compile down to canonical targets.
3.  **Generated (`.ig` from `.igweb`, `.json` from `.igv`)**: The deterministic outputs of projection lowerers. Placed in checked-in `generated/` directories. These must remain fully inspectable and reviewable by developers.
4.  **Compiled (`.igapp` / Semantic IR)**: The output of the compiler assembler (`Assembler::assemble`). It represents a packaged compilation unit containing monomorphized functions, type tables, form tables, and a source hash. Consumed by `igniter-vm` or host runtimes.
5.  **Deployed (`ServiceRecipe` JSON)**: Signed host metadata pinning the capsule image (`capsule_digest`), entry contract, duplicate policy, and runtime configuration. Consumed by `igniter-machine` at execution time.
6.  **Capability Declarations**: Package metadata declaring required host capabilities (e.g., `Postgres.Read`, `HTTP`). Represents the privilege scope of the package.

---

## 3. Candidate Package Units Evaluation

We score the candidate package models from the parent card `LAB-IGNITER-PACKAGE-MANAGER-READINESS-P1` against Igniter-specific design criteria:

### A. Source Package Only (authored `.ig`/`.igweb`/`.igv` + metadata)
*   *Score*: 6/10
*   *Tradeoffs*: Simple to package and publish. However, it forces every down-stream consumer to have all dialect lowerers installed and run them locally. If lowerer versions mismatch, generated artifacts will drift, compromising build determinism.

### B. Compiled Artifact Package (`.igapp` + metadata + source hash)
*   *Score*: 5/10
*   *Tradeoffs*: High execution efficiency. However, `.igapp` is a compiled binary. Distributing binary-only packages breaks the core Igniter principle of auditable, contract-first source code (reviewers cannot audit logic).

### C. Dual Package (Source + Generated + Compiled + Lock)
*   *Score*: 9/10 (Recommended)
*   *Tradeoffs*: Captures the complete provenance trail. Developers compile and publish source + generated `.ig` + `.igapp`. The compiler verifies that the compiled `.igapp` matches the hash of the source, and down-stream consumers can either use the pre-compiled binary for fast execution or recompile the source for audits.

### D. App-Local Workspace Package (Local workspace resolver, no remote registry)
*   *Score*: 9/10 (Recommended v0 implementation)
*   *Tradeoffs*: Solves local modularization and dependency mapping without introducing network, security, or registry server complexities. Serves as the necessary foundation.

### E. Registry-Backed Package Manager (Public/private registry from day one)
*   *Score*: 3/10 (Deferred)
*   *Tradeoffs*: Unnecessary overhead for the current lab phase. Introduces security, registry server maintenance, and network transport issues prematurely.

### F. OCI / Content-Addressed Artifact Store (addressed by digest, names as tags)
*   *Score*: 8/10
*   *Tradeoffs*: Aligns with Igniter's content-addressing philosophy. However, requiring users to
    manually reference raw digests is poor DX; it must be wrapped in a human-readable local workspace
    format.

---

## 4. Lockfile Pins

To guarantee deterministic builds, the `igniter.lock` file must pin the following variables:

```toml
# Candidate igniter.lock structure (research sketch, not a spec)

[[package]]
name = "spark_auth"
version = "0.1.0"
source_hash = "<digest>:d8a5..." # Cryptographic digest of source code
generated_hash = "<digest>:4a3e..." # Hash of all lowered generated files

[engines]
compiler_version = "0.2.1" # igc compiler version
stdlib_version = "0.1.0"   # stdlib-inventory.json hash
igweb_lowerer_version = "0.1.5" # dialect lowerer version
```

By locking the **compiler**, **stdlib**, and **dialect lowerer** versions alongside source hashes, we prevent compilation drift (where the same source compiled on different machines yields different bytecode).

---

## 5. Imports and Namespace Implications

To prevent package modules from causing namespace collisions or path ambiguity:

1.  **Logical Module Namespace**: Every package defines a root module name (e.g. `package = "spark_auth"` maps to logical namespace `SparkAuth`).
2.  **Namespace Enforcement**: The compiler's project scanner resolves imports under that namespace. Package files must reside under their logical module names:
    `import SparkAuth.TokenValidator`
3.  **Anti-Collision Rule**: Multiple packages cannot share the same root module name.
4.  **Stdlib Exclusion**: No package is permitted to declare or modify `stdlib.*`.

---

## 6. Capabilities and Secrets Boundary

A packages manifest declares what host capabilities it requires, but never packages the actual secrets:

```toml
# igniter.toml (inside dependency package)
[capabilities]
requires = [
    "Postgres.Write",
    "HTTP.StagingCallRail"
]
```

*   **Boundary Rule**: The package declares the *request* for a capability. The host environment provides the *grant* and injects connection strings, bearer tokens, or database credentials.
*   **Security Guarantee**: Packages can be securely distributed and audited because they contain no hardcoded passwords, tokens, or environment-specific connection strings.

---

## 7. Smallest v0 Recommendation: Local Workspace Packages

We recommend **`LAB-IGNITER-PACKAGE-WORK-WORKSPACE-P1`** as the smallest next step:

1.  **Local Workspaces**: Support path-based local dependencies in `igniter.toml`:
    ```toml
    [dependencies]
    spark_auth = { path = "../shared/spark_auth" }
    ```
2.  **Static Resolution**: The build wrapper scans the local dependency paths, appends them to the compiler's source roots scan, and compiles them in a single project invocation.
3.  **Local Lockfile**: Generates a local `igniter.lock` file recording local path hashes and compiler details.
4.  **No Network**: Zero registry, zero curl, zero download scripts. Fully offline and deterministic.

---

## 8. Deferred Surfaces

*   **Remote Registries**: No publishing to a central package repository.
*   **Transitive Version Resolution**: No complex semver resolution algorithms (e.g., Sat solving). Workspaces use pinned path configurations in v0.
*   **Post-install Scripts**: Installing a package must never run arbitrary CLI commands or build scripts (npm-style risk eliminated).
