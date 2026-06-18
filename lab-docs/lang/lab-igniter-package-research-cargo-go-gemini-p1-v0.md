# lab-igniter-package-research-cargo-go-gemini-p1-v0 — Cargo and Go modules lessons for Igniter packages

**Delegation-Code:** `GEMINI-20260618-PACKAGES-A`  
**Card Reference:** `LAB-IGNITER-PACKAGE-RESEARCH-CARGO-GO-GEMINI-P1.md`  
**Status:** RESEARCH REPORT (v0 / Recommended)  
**Scope:** Comparative packaging research for Cargo/crates.io and Go modules. **No code changes, no CLI package manager implementation, and no canon specifications.**

---

## 1. Executive Summary

This report surveys the package management architectures of **Cargo/crates.io** (Rust) and **Go modules** (Go), extracting design lessons for the Igniter ecosystem. 

Cargo depends on a central index with a constraint-solver and lockfile, but permits execution of arbitrary build hooks (`build.rs`). Go modules utilizes direct VCS paths as identities, relies on Minimal Version Selection (MVS) to avoid solvers, and strictly bans compilation-phase build scripts. 

For Igniter's v0 package manager, we recommend a local-first workspace model that bans install-time
build hooks, enforces cryptographic lockfile pinning, resolves imports based on in-file `module`
declarations, and rejects package-feature complexity in favor of flat dependencies. Go-style MVS is a
useful later model if remote/versioned packages appear; v0 should use explicit local paths and content
digests, not a version solver.

---

## 2. Comparative Table (Ecosystem Review)

| Ecosystem | Package identity | Locking | Build hooks | Namespace/imports | Trust/provenance | Strengths | Failure modes | Igniter lesson |
|---|---|---|---|---|---|---|---|---|
| **Cargo / crates.io** | Name + SemVer version | `Cargo.lock` pins exact dependency graphs with SHA-256 | `build.rs` runs arbitrary code during compile time | Crates are global namespaces; modules use files/folders | Crates.io acts as registry authority; hashes verified | Predictable, reproducible builds; excellent workspace support | Security vulnerabilities via build scripts; feature bloat | Lockfiles are essential for determinism, but build/install hooks must be banned. |
| **Go modules** | VCS repository path URL + version tags | `go.sum` pins expected module hashes; no lockfile solver | None allowed | Import paths map to URLs/subfolders | Direct VCS download; `sumdb` prevents MITM | Decentralized; Minimal Version Selection (MVS) is stable | Repo deletion breaks downstream builds; major version prefixing | Decoupling package identity from direct VCS paths keeps names stable; MVS is simpler than SAT solvers. |

---

## 3. Cargo Lessons for Igniter

* **Determinism through Lockfiles:** Pins transitive dependencies. Igniter must use a lockfile (`igniter.lock`) containing cryptographic source digests to guarantee identical compiles.
* **Workspace Support:** Local multi-package development is highly productive. Igniter should support local workspaces in `igniter.toml` so developers can reference local packages via relative paths without publishing them.
* **Source Replacement / Patching:** Cargo’s `[patch]` directive is valuable for overriding registry dependencies with local versions during testing. Igniter should adopt a local override mapping.
* **Dangerous Build Hooks:** Arbitrary code execution (`build.rs`) is a massive security hazard. Igniter must forbid install-time hooks. Projection dialect compilation (`.igweb`/`.igv`) must be executed explicitly via CLI commands or pre-run tools, never by the package manager.

---

## 4. Go Modules Lessons for Igniter

* **Minimal Version Selection (MVS):** Rather than using complex constraint satisfaction solvers (SAT
  solvers), MVS simply selects the minimum version of a package that satisfies all requirements in the
  tree. This is worth remembering for a future remote/versioned package phase. Igniter v0 should avoid
  version solving entirely and use explicit local path dependencies pinned by digest.
* **No Build Hooks:** A compiler should only compile. This keeps the toolchain fast and secure.
* **Fragility of Direct VCS Identifiers:** Referencing raw Git repository paths (e.g. `github.com/user/project`) makes builds vulnerable to repository deletions, force-pushes, or network outages. Igniter should separate logical package IDs from VCS paths.
* **Local Replace Directives:** The `replace` directive in `go.mod` provides a clean, local-only path replacement to override dependencies. Igniter should support `[replace]` sections in its local configurations.

---

## 5. Feature/Options Warning: What to Borrow and Reject

* **Borrow:** The ability to selectively import sub-components (such as target platform configurations).
* **Reject:** Cargo-style features (`[features]`) introduce massive complexity (feature unification, additive-only contract pitfalls, and compilation flag combinatorial explosion).
* **Igniter Rule (v0):** Igniter packages must remain **completely featureless** (flat dependencies only). If a library requires optional adapters, they must be split into separate, smaller packages (e.g., `igniter-postgres` as a separate package from `igniter-sqlite`), maintaining simplicity.

---

## 6. Concrete Igniter Implications (Workspaces & Lockfiles)

### The `igniter.lock` Design
To guarantee reproducible builds:
* The lockfile should pin package name, dependency list, and a content-addressed digest of the source
  code. The exact digest algorithm is a later design choice.
* Because dialects are compiled locally, the lockfile should verify the source hash of the dialect inputs (`.igweb`/`.igv`) to ensure generated code remains stable.
* The lockfile should record the compiler and stdlib versions.

### Local Workspaces in `igniter.toml`
* The project configuration should support defining local workspaces:
  ```toml
  [workspace]
  members = ["packages/*"]
  ```
* Imports should resolve via in-file `module` declarations (matching the behavior of
  `igniter-compiler/src/project.rs`), ensuring file renames or directory changes do not break
  dependency imports.
* Local overrides (`replace` configurations) should map registry packages to local workspace folders during development.

---

## 7. Concrete Future Card Ideas (Recommended Backlog)

### Idea 1: `LAB-IGNITER-PACKAGE-WORKSPACE-SOLVER-P2` (Local Workspaces)
* **Goal**: Implement workspace directory parsing in `igniter-compiler::project` to resolve module dependencies across multiple relative-path packages in a single workspace.

### Idea 2: `LAB-IGNITER-LOCKFILE-SPEC-P3` (Lockfile Cryptography)
* **Goal**: Define the JSON/YAML serialization schema of `igniter.lock` and write validators that verify source directories against SHA-256 digests.

### Idea 3: `LAB-IGNITER-VERSION-RESOLUTION-READINESS-P4` (Later, not v0)
* **Goal**: Decide whether Igniter ever needs MVS or another version-selection algorithm once remote
  packages exist. Do not implement a resolver in the local-workspace v0.
