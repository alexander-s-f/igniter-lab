# lab-igniter-package-research-oci-wasm-terraform-gemini-p1-v0 — OCI, WASM components, and Terraform module lessons

**Delegation-Code:** `GEMINI-20260618-PACKAGES-D`  
**Card Reference:** `LAB-IGNITER-PACKAGE-RESEARCH-OCI-WASM-TERRAFORM-GEMINI-P1.md`  
**Parent Card:** `LAB-IGNITER-PACKAGE-MANAGER-READINESS-P1`  
**Status:** RESEARCH REPORT (v0 / Recommended)  
**Scope:** Design analysis of OCI artifacts, WASM components/WIT, and Terraform provider/module patterns to extract package architecture lessons for Igniter. **No code implementation, no package spec creation, no compiler edits.**  
**Authority:** Lab research only. Grounded in `project.rs`, `protocol.rs`, and the `Projection Dialects (P0)` contract.

---

## 1. Executive Summary

We analyze three artifact- and provenance-heavy ecosystems—OCI registry artifacts, the WASM Component Model (WIT), and Terraform providers/modules—to extract core structural lessons for the Igniter package manager design. 

Our key design takeaways are:
1.  **Immutability over Convenience (OCI)**: Human-readable tags are mutable aliases. Igniter must enforce content digests as the primary key of package identity to guarantee build reproducibility.
2.  **Strict Interface Boundaries (WASM/WIT)**: Packages must interact solely through typed interface contracts. Capability bindings (e.g. DB or HTTP ports) are linked top-down by the host, ensuring dependencies never smuggle ambient authority.
3.  **No Ambient Binary Execution (Terraform)**: While declarative modules are easy to review, Terraform's model of downloading and executing native provider binaries on `init` creates high supply-chain risks. Igniter packages must compile to pure VM bytecode; all side effects must route through host-provided executors.
4.  **Sidecar Provenance**: Cryptographic signatures and build metadata (compiler versions, lowerer logs) must live as sidecars in the package structure, keeping execution code clean and inspectable.

---

## 2. Comparative Table

| Ecosystem | Package identity | Locking | Build hooks | Namespace/imports | Trust/provenance | Strengths | Failure modes | Igniter lesson |
|---|---|---|---|---|---|---|---|---|
| **OCI Artifacts** | Repository + Tag (mutable) or Digest (immutable SHA-256) | Digest pinned in deployment manifests | None at installation time (image layers are static) | Flat namespace (host/repo/image). Layers extract to local paths. | Cryptographic signatures (Cosign, Notary) and attestations stored as sidecars. | Bit-for-bit immutable artifacts; standardized storage layout. | Tag mutation (stealthily replacing a tag); bloated layers with hidden software. | Pinned dependencies must use content hashes. Provenance metadata lives in sidecars. |
| **WASM Components (WIT)** | Namespace + Name + SemVer (e.g. `wasi:http@0.2.0`) or Digest | link-time/runtime resolution via registries (e.g. warg) pinning digests | None. Pre-compiled bytecode modules. | WebAssembly Interface Type (WIT) declarations mapping imports/exports. | Cryptographic verification of binary format; registry transparency logs. | Language-agnostic, zero-cost virtualization, strict sandbox isolation. | Interface drift/mismatch causing link-time crashes. | Enforce static interface-first contracts. Statically check imports/exports before VM load. |
| **Terraform (Providers/Modules)** | Namespace + Name (e.g. `hashicorp/aws`) or Module registry URL | Checksums (`.terraform.lock.hcl`) pinning provider binaries | None during download, but providers run custom logic on initialization. | Module blocks pass variables. Providers map resource types globally. | Provider binaries GPG-signed by developers and verified by CLI. | Highly declarative schemas; multi-platform lockfile hashes. | Unvetted provider execution (malicious binaries executing during `terraform init`). | Declarative layout is highly reviewable. Forbid execution of external binaries in packages. |

---

## 3. Content-Addressing and Tag/Digest Lessons

### The Mutable Tag Trap
In OCI and Terraform module registries, a version tag (e.g. `v1.2.0`) is a mutable pointer. A publisher can delete and push a different commit to the same tag. This introduces silent build drifts and vulnerability injections.

### Igniter Content-Addressed Identity
*   **Digest as Primary Key**: Igniter packages should be identified by a cryptographic content
    digest of their source files. The exact digest algorithm is a later design choice; the manifest
    and lockfile must bind dependencies to whatever digest scheme Igniter selects.
*   **Tags as Aliases**: Human-readable tags and names (e.g., `spark_auth: v1.0.0`) are evaluated only once during dependency resolution to resolve the target digest.
*   **Sidecar Metadata**: Provenance details (lowerer logs, developer signatures, compiler version) must reside as sidecar files in the package directory/tarball. They are not compiled into the `.igapp` bytecode, keeping the executable code lightweight and easily auditable.

---

## 4. Interface and Capability Declaration Lessons

### WIT-Style Decoupling
In the WASM Component Model, components are modular units of code that communicate strictly via WebAssembly Interface Types (WIT). A component imports abstract functions (e.g. `wasi:http/outgoing-handler`) and exports others, never interacting with ambient system APIs directly.

### Igniter Capability Isolation
*   **Statically Declared Ports**: An Igniter package cannot dynamically open sockets or read files. It must explicitly declare its capability requirements in its manifest (e.g., `requires = ["Postgres.Read"]`).
*   **Top-Down Linkage**: The host runtime acts as the linker. At startup, it binds the package's abstract port requests to actual resource pools (e.g. a specific read-only database socket). The package remains completely sandboxed, unable to escalate authority.

---

## 5. Provider Authority and Hidden Execution Risks

### The Terraform Provider Vulnerability
Terraform modules are pure declarative text, but Terraform providers (the plugins that execute resource creation) are native executable binaries. Running `terraform init` downloads these binaries to the local machine and runs them. If a provider is compromised, it has full access to the runner's machine and environment variables.

### Igniter Safety Constraints
*   **No Dependency Binaries**: Igniter packages must not contain or compile to native machine binaries, nor are they allowed to execute sub-processes.
*   **Pure VM Compilation**: Every Igniter dependency must compile down to pure VM bytecode.
*   **Host-Only Execution**: The execution of native capability code is restricted exclusively to the host environment (e.g., through vetted `dyn CapabilityExecutor` instances compiled directly into the server). Dependencies only pass data payloads to these executors.

---

## 6. Provenance & Signing Implications for Igniter Lockfiles

To guarantee that a workspace build is completely reproducible, the `igniter.lock` file must pin the entire execution footprint:

1.  **Source Hashes**: Cryptographic hash of the raw authoring source files.
2.  **Transpiled Hashes**: If a package includes projection dialects (e.g., `.igweb`), the lockfile must pin the hash of the generated `.ig` target files. This prevents malicious alterations to generated code during local builds.
3.  **Engine Pins**: The lockfile must explicitly pin the exact `igc` compiler version and dialect lowerer versions used. 
4.  **Attestation Sidecars**: The package registry model should support sidecar signatures containing cryptographic developer attestations (`in-toto` style) verifying build pipelines.

---

## 7. Suggested Igniter v0 Constraints

To ensure a simple, secure, and robust package manager, we recommend enforcing the following invariants for the v0 local-workspace implementation:

*   **Zero Script Hooks**: Statically ban all pre-install, post-install, and build script execution. Package installation is purely an I/O copy/link operation.
*   **Flat DAG Phases**: Projections must lower to canonical `.ig` files in parallel (Phase 1), followed by a single compilation pass of all targets by `igc` (Phase 2). No nested dialect dependencies are allowed.
*   **Local Path Mapping**: Version resolution in v0 is bypassed; dependencies are declared via explicit local filesystem paths (`{ path = "../spark_auth" }`) and pinned by directory hash.
*   **Sandboxed VM Execution**: Package execution is strictly confined to the `igniter-vm` stack. Packages cannot obtain ambient file system, network, or process access.
