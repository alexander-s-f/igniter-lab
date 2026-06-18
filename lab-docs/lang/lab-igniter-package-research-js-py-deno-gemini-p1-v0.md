# lab-igniter-package-research-js-py-deno-gemini-p1-v0 — JS, Python, Deno, and JSR lessons for Igniter packages

**Delegation-Code:** `GEMINI-20260618-PACKAGES-B`  
**Status:** RESEARCH REPORT (v0 / Gemini shard)  
**Target Card:** `LAB-IGNITER-PACKAGE-RESEARCH-JS-PY-DENO-GEMINI-P1`  
**Authority:** Research only. No package spec authority. No code edits.

---

## 1. Executive Summary

This report analyzes package management and registry architectures in the JavaScript (npm/pnpm/yarn, Deno/JSR) and Python (pip/poetry/uv) ecosystems. We focus on critical security and reliability boundaries: install script vulnerabilities, transitive dependency risks, lockfile reproducibility, namespace imports, and execution permission sandboxing. The goal is to define targeted lessons for Igniter's package manager readiness.

---

## 2. Comparative Table Rows

| Ecosystem | Package identity | Locking | Build hooks | Namespace/imports | Trust/provenance | Strengths | Failure modes | Igniter lesson |
|---|---|---|---|---|---|---|---|---|
| **npm / pnpm / yarn** | Name + SemVer in `package.json` | Content hashes and dependency pins in `package-lock.json` or `pnpm-lock.yaml` | Arbitrary lifecycle scripts (`preinstall`, `postinstall`, `prepare`) | Nested `node_modules` directory lookup; ESM `exports` limits internal file leaks | SHA hashes, registry-level signatures, Sigstore/GitHub OIDC provenance | Large registry; `pnpm` symlink deduplication; workspaces | Malicious postinstall scripts, phantom dependencies, dependency confusion, typosquatting | Ban arbitrary install hooks; enforce strict lockfiles; isolate imports from directory layout. |
| **Python Packaging** | Name + SemVer in `pyproject.toml` or setup metadata | Version pins in lockfiles (`poetry.lock`, `uv.lock`) or requirements files | Build-system hooks (`setup.py` execution, PEP 517 build backends) | Shared `site-packages` folder imports (requires virtualenv isolation) | PyPI hash verification, Trusted Publishers (OIDC keyless publishing) | Binary wheels simplify native dependencies; unified configuration metadata | Setup-time arbitrary execution, global namespace collisions, tooling fragmentation | Enforce hermetic project isolation without virtualenvs; lock transitive source files. |
| **Deno / JSR** | URL-based modules (`https://...`) or JSR namespaced packages (`jsr:@scope/pkg`) | Deterministic remote module hash lockfiles (`deno.lock`) | None. Zero install-time script execution | Explicit module paths and ESM imports; JSR transpiles ts-to-js | HTTPS TLS validation, JSR OIDC publishing, Sigstore verification | Sandboxed runtime permissions, zero-install caching, typescript first | Remote URL domain hijacking, offline cache invalidation, host downtime | Adopt scoped naming; support URL/relative imports; forbid build-time execution. |

---

## 3. Install/Build Hook Risk Analysis

### The Vulnerability:
*   In **npm/Yarn** and **Python (setup.py)**, installing a package executes arbitrary code in the user's shell (e.g., `postinstall` scripts or Python execution during setup).
*   Attackers exploit this by publishing packages that steal environment variables, leak credentials (AWS/npm tokens), download malicious binaries, or run cryptominers during local development or CI/CD pipelines.

### Mitigation in Deno/JSR:
*   Deno and JSR explicitly forbid install scripts. When a package is downloaded, it is cached as static source files. No code runs during the resolution/download phase.

### Igniter Stance (v0/recommended):
*   **Banning Shell Hooks:** Igniter must forbid arbitrary shell scripts or install hooks during package resolution.
*   **Lowering Target Generation:** For Projection Dialects (like `.igv` lowering to JSON, or `.igweb` to `.ig`), the compilation/lowering must be performed as a pure, deterministic compilation pass by the local compiler tool, not by an arbitrary script embedded inside a downloaded package.

---

## 4. Lockfile and Transitive Dependency Lessons

### Transitive Resolution Risks:
*   **Phantom Dependencies:** Standard npm/yarn historically allowed code to import packages not listed in their direct dependencies if they happened to be installed transitively in `node_modules`. This is mitigated by `pnpm`'s strict symlink layout and Go's module design.
*   **Drift/Hijacking:** If transitive dependencies are not locked with strict content digests, a patch update can introduce malicious code without the top-level developer's knowledge.

### Igniter Recommendations:
*   **Digest-Locked Trees:** Every dependency (direct and transitive) should be pinned in a lockfile
    with its content digest. The exact digest algorithm is a later Igniter design choice.
*   **Strict Scope Resolution:** The compiler must only resolve imports to packages explicitly declared in the project's dependency manifest, preventing phantom imports.

---

## 5. Namespace/Import Lessons

### The Problem:
*   Python's flat `site-packages` directory causes collision if two libraries define the same folder structure.
*   Node's relative/nested `node_modules` path search leads to slow disk scanning, duplicate versions of the same library, and "module not found" errors in complex monorepos.

### Igniter Recommendations:
*   **Explicit Namespaced Paths:** Adopt a JSR-style scoped naming convention (e.g., `import @scope/pkg/Module`).
*   **No Path Scanning:** The compiler must resolve imports by looking up the namespace in a local, lockfile-generated map that points directly to a content-addressed directory, rather than scanning the filesystem recursively.

---

## 6. Permissions/Provenance Lessons

### Permissions (Deno):
*   Deno defaults to a secure sandbox. Access to the network, environment, or filesystem must be explicitly granted via flags (`--allow-net`, `--allow-env`).
*   Igniter packages (which evaluate pure contracts) are inherently stateless and execute on a secure, capability-isolated host. No package can perform side-effects unless it returns a `ServerDecision` that the host executes under its own authority.

### Provenance (JSR/npm):
*   Sigstore and OIDC integrations allow verifying that a published package was built in a specific GitHub Action repository, signing the artifact without requiring static registry keys.
*   Igniter should support OIDC-based signature verification in its future registry, assuring the authenticity of packages.

---

## 7. Igniter Recommendations and Anti-Patterns

### Anti-patterns to Reject:
1.  **npm-style script hooks:** Never allow packages to declare shell commands that execute automatically on install.
2.  **Global Namespace Imports:** Avoid flat imports (e.g., `import Logger`) that lead to naming collisions. All imports must be namespaced/scoped.
3.  **Dynamic Version Resolution at Runtime:** The runtime must never resolve versions or fetch packages. Version locking must happen statically at compile/transpile time.

### Recommended Igniter Package Model (v0/targeted):
*   **Workspace-First (Local):** The package manager starts as a local-first workspace coordinator (a `project.toml` file mapping dependency names to local paths or content-addressed cache folders).
*   **Static Manifest:** A package consists of static `.ig` contracts, Projection Dialects (`.igv`/`.igweb`), and a manifest declaring required host capabilities (e.g., "requires postgres capability"). It contains no executable binaries or scripts.
