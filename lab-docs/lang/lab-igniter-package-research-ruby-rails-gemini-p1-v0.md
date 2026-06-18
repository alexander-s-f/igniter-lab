# lab-igniter-package-research-ruby-rails-gemini-p1-v0 — RubyGems, Bundler, and Rails engines lessons for Igniter packages

**Delegation-Code:** `GEMINI-20260618-PACKAGES-C`  
**Card Reference:** `LAB-IGNITER-PACKAGE-RESEARCH-RUBY-RAILS-GEMINI-P1.md`  
**Status:** RESEARCH REPORT (v0 / Recommended)  
**Scope:** Comparative packaging research for RubyGems, Bundler, and Rails engines/plugins. **No code changes, no CLI package manager implementation, and no canon specifications.**

---

## 1. Executive Summary

This report surveys the package management and plugin architectures of **RubyGems**, **Bundler**, and **Rails engines**, extracting design lessons for the Igniter ecosystem. 

Bundler excels at local-first development by supporting path-based dependency overrides and strict lockfile pinning. However, the Ruby package model suffers from lack of sandboxing, permitting post-install build scripts to run arbitrary shell commands. Furthermore, Rails engines extend host apps by sharing a global runtime, which leads to database migration conflicts, global routing namespace collisions, and hidden boot-phase side-effects.

For Igniter's package model, we recommend adopting Bundler's local path ergonomics and strict lockfile discipline, while rejecting Rails' engine model. In Igniter, app extensions must lower to static, declarative targets (like contracts and projection dialects), ensuring that database schemas, routes, and side-effects remain strictly encapsulated and under host control.

---

## 2. Comparative Table (Ecosystem Review)

| Ecosystem | Package identity | Locking | Build hooks | Namespace/imports | Trust/provenance | Strengths | Failure modes | Igniter lesson |
|---|---|---|---|---|---|---|---|---|
| **RubyGems** | Gem name + SemVer version | None (delegated to Bundler) | C extension compile (`extconf.rb`) runs arbitrary code on install | Global load path; gems share a single global Ruby namespace | RubyGems.org API key verification; checksums | Simple metadata; native C compilation | Malicious code execution on install; runtime namespace collision | Package managers must never compile arbitrary binaries. Native dependencies belong at the host layer. |
| **Bundler** | Gem name + version, resolved from `Gemfile` | `Gemfile.lock` pins transitive dependency closure | None at Bundler layer | Same as RubyGems | Validates gem checksums against registry index | Excellent local `path:` overrides; dev-to-prod lockfile parity | Dependency resolution conflicts; registry source hijacking | Local relative-path overrides are crucial for development; lockfiles must pin exact sources. |
| **Rails Engines** | Ruby gems loaded into a host Rails app | Same as Bundler | Initializers run arbitrary code during app boot | Dynamic route mounting; shared global namespace | Same as RubyGems/Bundler | Rapid modularization of routes, views, and controllers | Database migration conflicts; global route collisions; untraceable decorators | Never allow packages to dynamically inject migrations or inject global routes. Extensions must remain static. |

---

## 3. What Bundler Gets Right for Local-First Reproducibility

* **Local Path Ergonomics:** Bundler’s `gem "foo", path: "../foo"` allows developers to split applications into separate packages locally without publishing to a remote registry, accelerating modular architecture.
* **Lockfile Discipline:** The `Gemfile.lock` serves as a single source of truth for the entire transitive dependency graph, guaranteeing that code compiles identically across developer machines and production targets.
* **Dependency Groups:** Bundler groups (e.g., `group :test`, `group :production`) provide a clean way to isolate dependencies based on execution environment. Igniter should adopt a similar metadata tagging scheme.

---

## 4. Rails Engines as a Warning: Extension Without Ownership

Rails engines are loaded into the host process and obtain full access to the global ActiveRecord database connection, route tables, and memory space. This violates encapsulation:
* **The Igniter Rule:** An Igniter library package must never dynamically inject code, initializers, or decorators into the host runtime environment.
* **Static Injections:** If a package provides a reusable workflow, the host app must explicitly import the module and invoke it via static dispatch: `call_contract("Package.Contract", req)`. The host remains in absolute control of its routes and execution cadence.

---

## 5. Migration/Assets Pitfalls and Igniter Analogues

### Database Migration Conflicts
In Rails, engines copy database migrations into the host app’s `db/migrate` folder. When engines are updated, migrations can drift, causing split-brain schemas.
* *Igniter Analogue:* Storage capabilities are declared in deployment recipes, and local database collections are isolated per capsule. Packages do NOT own global database tables. If a package needs storage, it must be granted capability scope by the host, maintaining clean database tenant partitioning.

### Asset Pipeline Collisions
Rails engines drop CSS/JS files into a shared assets path, leading to CSS namespace clashing.
* *Igniter Analogue:* UI projections (`.igv`) compile to ViewArtifact JSON templates, which are strictly isolated component trees. Styling is local to the components and does not pollute a global CSS scope.

### Hidden Initializers
Engines execute `initializer` blocks during boot, altering settings or decorating core classes under the hood.
* *Igniter Analogue:* Igniter contracts are pure and stateless; there is no boot-phase configuration execution inside libraries.

---

## 6. App/Domain vs. Stdlib/Canon Packages

Igniter must divide its packaging layers to prevent feature creep:
* **App/Domain Packages (Lab-only, Private):** These live in local workspaces, containing business logic, database capsules, and projection dialects (`.igweb`/`.igv`). They carry no public registry authority and are resolved locally.
* **Stdlib/Canon Packages (Core, Public):** Shipped directly with the compiler, containing core primitive contracts (such as regular expressions or networking utilities). They are read-only and reference-validated.
* **Boundary Split:** Projection dialects (e.g., `.igweb` routes mapping) must be lowered to canonical `.ig` code before compilation, keeping the public canon compiler free of domain-specific features.

---

## 7. Concrete Future Card Ideas (Recommended Backlog)

### Idea 1: `LAB-IGNITER-PACKAGE-METADATA-SPEC-P2` (Package Spec)
* **Goal**: Define the JSON/YAML metadata schema of `igniter.toml` package sections, including dependency names, version constraints, and target capability requirements.

### Idea 2: `LAB-IGNITER-LOCAL-PATH-RESOLVER-P3` (Relative Paths)
* **Goal**: Implement local relative path dependency resolution (`path = "../foo"`) inside the compiler's multi-file scanner to support multi-package workspaces.

### Idea 3: `LAB-IGNITER-DEPENDENCY-ISOLATION-P4` (Encapsulation Guard)
* **Goal**: Build compile-time encapsulation checks ensuring imported package modules cannot access internal, unexported modules or invoke undeclared capabilities.
