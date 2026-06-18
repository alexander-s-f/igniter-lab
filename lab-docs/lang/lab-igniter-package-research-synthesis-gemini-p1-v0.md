# lab-igniter-package-research-synthesis-gemini-p1-v0 — Synthesis report for package-manager research

**Delegation-Code:** `GEMINI-20260618-PACKAGES-F`  
**Card Reference:** `LAB-IGNITER-PACKAGE-RESEARCH-SYNTHESIS-GEMINI-P1.md`  
**Status:** SYNTHESIS REPORT (v0 / Recommended)  
**Scope:** Synthesis of sharded studies on Cargo, Go, JS, Python, Deno, Ruby, Rails, OCI, WASM Component Model, and Terraform modules to outline the Igniter package manager architecture. **No code implementation, no package spec creation, no compiler edits.**  
**Authority:** Lab research only. Grounded in `project.rs`, `protocol.rs`, and the `Projection Dialects (P0)` contract.

---

## 1. Executive Recommendation

This synthesis report integrates research from all **five sharded reports** (covering Cargo/Go, JS/Python/Deno, Ruby/Rails, OCI/WASM/Terraform, and Igniter Artifacts) to define the package management architecture for Igniter. 

For the Igniter v0 package manager, we recommend a **local-first, workspace-driven, and content-addressed package model**. This model adopts Bundler's local path override ergonomics and Cargo's lockfile determinism while rejecting dynamic install-time build hooks, mutable version tags, and Rails-style engine database coupling. 

### Shard Reports Availability & Status
* **Available inputs:** 
  * `lab-igniter-package-research-cargo-go-gemini-p1-v0.md` (P1, closed)
  * `lab-igniter-package-research-js-py-deno-gemini-p1-v0.md` (P1, closed)
  * `lab-igniter-package-research-ruby-rails-gemini-p1-v0.md` (P1, closed)
  * `lab-igniter-package-research-oci-wasm-terraform-gemini-p1-v0.md` (P1, closed)
  * `lab-igniter-package-research-igniter-artifacts-gemini-p1-v0.md` (P1, closed)
* **Confidence level:** **Medium-high**. All five sharded reports are present as research docs and
  align on sandbox, determinism, and capability-isolation principles. External ecosystem facts still
  need a focused Opus/primary-source validation pass before becoming design authority.

---

## 2. Integrated Comparative Table

We merge the findings across the five sharded studies into a single comparative taxonomy:

| Ecosystem | Package identity | Locking | Build hooks | Namespace/imports | Trust/provenance | Strengths | Failure modes | Igniter lesson |
|---|---|---|---|---|---|---|---|---|
| **Cargo (Rust)** | Name + SemVer version | `Cargo.lock` pins transitive closure | `build.rs` runs arbitrary code on compile | Crates are global namespaces; modules use files/folders | Crates.io acts as registry; SHA hashes in lockfile | Bit-for-bit reproducibility; excellent workspace ergonomics | Native build scripts hijack hosts; feature combinatorics | Lockfiles are essential, but install-time compile scripts must be banned. |
| **Go modules** | VCS repo URL + SemVer tag | `go.sum` pins hashes; no lockfile solver | None allowed | Import paths map to URLs/subfolders | Direct VCS download; `sumdb` checksum database | Decentralized; Minimal Version Selection (MVS) is stable | Repo deletion breaks builds; major version prefixing | Decouple logical name from repository path; MVS is simpler than SAT solvers. |
| **npm / pnpm** | Name + SemVer in `package.json` | `package-lock.json` pins transitive hashes | Lifecycle scripts (`postinstall`, etc.) | Nested `node_modules` folder resolution | SHA hashes, Sigstore OIDC build provenance | Massive registry; pnpm symlink layout | Malicious postinstall scripts; phantom imports | Ban install scripts; imports must be decoupled from folder layouts. |
| **Python** | Name + SemVer in config | Lockfiles (`poetry.lock`, `uv.lock`) | PEP 517 build backends; `setup.py` | Shared `site-packages` directory | PyPI hashes; Trusted Publishers OIDC | Binary wheels; metadata normalization | Compile-time host hijack; import collisions | Enforce hermetic project isolation; lock all source hashes. |
| **Deno / JSR** | URL-based or JSR scoped name | `deno.lock` pins remote module hashes | None allowed | Explicit module paths and ESM imports | HTTPS TLS; JSR OIDC signatures | Sandboxed permissions; zero-install caching | Domain hijacking; offline cache invalidation | Adopt scoped names; support URL/local imports; zero build hooks. |
| **RubyGems** | Gem name + SemVer version | None (delegated to Bundler) | C extension compile (`extconf.rb`) | Global load path; single global Ruby namespace | RubyGems.org API key verification | Simple metadata; native C compilation | Shell execution on install; runtime namespace collisions | Keep native dependencies at the host layer; packages contain only code. |
| **Bundler** | Gem name + version, from `Gemfile` | `Gemfile.lock` pins exact dependency graphs | None (delegated to RubyGems) | Same as RubyGems | Validates gem checksums against registry | Excellent local `path:` overrides | Constraint solver version conflicts | Local relative-path overrides are crucial for developer ergonomics. |
| **Rails Engines** | Ruby gems loaded into host Rails app | Same as Bundler | Initializers run arbitrary code during boot | Dynamic route mounting; shared global namespace | Same as RubyGems/Bundler | Rapid modularization of routes and views | Migration duplication desyncs; route collisions; monkey-patching | Never allow packages to dynamically inject migrations or global routes. |
| **OCI Artifacts** | Repository + Tag or Digest | Digest pinned in deployment configs | None (image layers are static) | Flat namespace; layers extract to paths | Cryptographic signatures and attestations | Bit-for-bit immutability; standard layout | Tag mutation (stealthily replacing a tag) | Pinned dependencies must use content hashes. Provenance metadata lives in sidecars. |
| **WASM (WIT)** | Namespace + Name + SemVer | Registry transparency logs | None; pre-compiled bytecode | WIT declarations mapping imports/exports | Registry signature validation | Language-agnostic; strict capability sandbox | Interface mismatch causing link-time crash | Enforce static interface-first contracts. Verify imports/exports before VM load. |
| **Terraform** | Namespace + Name | Checksums (`.terraform.lock.hcl`) | None during download; providers run binaries | Module blocks pass variables | GPG-signed binaries verified by CLI | Highly declarative schemas; multi-platform hashes | Unvetted provider execution (malicious init binaries) | Forbid execution of external binaries inside packages. |

---

## 3. Recommended Igniter v0 Package Model

We recommend the **Dual Package Model (Source + Generated + Compiled)** combined with a **Local-First Workspace Resolver**:

1.  **Logical Identity**: A package is identified by a unique, scoped name (e.g. `@acme/spark_auth`) and its cryptographic digest (BLAKE3/SHA-256 of the source files). Version tags are mutable aliases used only during resolution to determine the target digest.
2.  **Contents**:
    *   **Source**: Canonical `.ig` code and Projection Dialect sources (`.igweb`/`.igv`).
    *   **Generated**: Deterministic outputs of dialect compilation (e.g. generated `.ig` routes and JSON views), committed directly into `generated/` folders. This allows human inspection and diff tracking.
    *   **Compiled**: Ephemeral compilation units (`.igapp` bytecode), generated by the compiler and verified against the source hash.
3.  **Local-First Workspaces**: No public registry or version solver is required in v0. The package
    manager resolves dependencies locally in `igniter.toml` via relative filesystem paths:
    ```toml
    [dependencies]
    spark_auth = { path = "../shared/spark_auth" }
    ```
4.  **No Code Execution**: Resolving or compiling a package does not execute arbitrary lifecycle scripts. Lowering dialects is a pure compilation pass, not an install-time shell hook.

---

## 4. Lockfile & Provenance Schema

To ensure that workspace builds are completely reproducible, the `igniter.lock` file must pin the entire compile-time footprint:

```toml
# Candidate igniter.lock structure (research sketch, not a spec)

[[package]]
name = "spark_auth"
version = "0.1.0"
source_hash = "<digest>:d8a57e3f89a..."     # Hash of original source files
generated_hash = "<digest>:4a3e218b9c..."  # Hash of generated projection targets
dependencies = [
    "spark_types"
]

[engines]
compiler_version = "0.2.1"                # Exact igc version
stdlib_version = "0.1.0"                  # Hash of the standard library registry
igweb_lowerer_version = "0.1.5"           # Version of the routes dialect compiler
```

By locking the **compiler**, **stdlib**, and **dialect lowerer** versions alongside source hashes, we prevent compilation drift (where identical source code yields different bytecode on different machines).

---

## 5. Top 7 Anti-Patterns to Avoid

1.  **Arbitrary Build/Install Scripts (npm/Python/Ruby):** Executing post-install shell commands or compile hooks. Igniter must ban all install-time scripts; dialect compilation must run as a pure compiler pass.
2.  **Dynamic Initializers & Monkey-Patching (Rails Engines):** Allowing dependencies to run arbitrary code at app boot to decorate classes or mutate host state. In Igniter, packages are stateless, pure, and statically mapped.
3.  **Shared Global Database Migrations (Rails Engines):** Having packages copy migration files into the host repository. Igniter database collections are strictly capsule-isolated; packages only declare capability requirements, not database tables.
4.  **Mutable Version Tags (OCI/VCS/Go):** Pinning dependencies to human-readable version tags (like `v1.2.0`) that can be deleted or force-pushed. Igniter must enforce content-addressed hashes (`igniter.lock` digests) as the final authority.
5.  **Global Load Paths / Flat Namespaces (Python/Ruby Gems):** Flattening packages into a single directory, leading to naming collisions. All Igniter packages must resolve to isolated, namespaced module paths (e.g. `import SparkAuth.Validator`).
6.  **Phantom/Transitive Import Leakage (npm/Node):** Allowing code to import packages not listed in their direct dependencies because they were resolved transitively. Igniter must statically verify imports against the package's direct dependencies list.
7.  **Smuggling Secrets & Credentials (OCI/Terraform):** Bundling connection strings, passwords, or tokens inside packages. Igniter manifests declare abstract capability requests (e.g., `requires = ["Postgres.Read"]`); the host runtime links them to credentialed resource pools at startup.

---

## 6. Deferred Surfaces

*   **Remote Package Registries:** We defer the implementation of a centralized registry server, credential management, and remote download transports. Workspaces will rely entirely on local filesystems.
*   **Transitive Version Solvers:** We defer both complex SemVer SAT solvers and Go-style MVS.
    Workspaces will use pinned paths, explicit overrides, and content digests in v0.
*   **Dynamic Code Loading:** We defer compilation and execution of dynamic modules. The compiler continues compiling all targets statically.

---

## 7. Next Implementation Cards

### Card 1: `LAB-IGNITER-PACKAGE-WORKSPACE-RESOLVER-P2`
* **Goal**: Support path-based local dependencies and multi-package scanning in `igniter.toml` without remote registries.
* **Acceptance criteria**:
  * Workspace config parses `[workspace]` and `[dependencies]` blocks.
  * Scans and indexes modules by parsing `module` declarations inside all relative-path source roots (per `project.rs`).
  * Compiles the unified workspace project clean.
  * Fails assembly if duplicate module names are declared across different packages (OOF-IMP4).

### Card 2: `LAB-IGNITER-LOCKFILE-SKETCH-P3`
* **Goal**: Define the serialization format of `igniter.lock` and write validators that check source content hashes and compiler/lowerer versions.
* **Acceptance criteria**:
  * Generates `igniter.lock` containing package names, versions, source digests, and generated file hashes.
  * Pins `compiler_version` and `stdlib_version`.
  * Fails the build if local source file hashes do not match the lockfile digests.
