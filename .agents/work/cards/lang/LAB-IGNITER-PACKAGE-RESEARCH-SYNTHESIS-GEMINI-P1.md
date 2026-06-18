# Card: LAB-IGNITER-PACKAGE-RESEARCH-SYNTHESIS-GEMINI-P1 — Synthesis packet for package-manager research shards

**Lane:** background / synthesis research  
**Status:** CLOSED (Synthesis report delivered)  
**Date opened:** 2026-06-18  
**Date closed:** 2026-06-18  
**Delegation-Code:** `GEMINI-20260618-PACKAGES-F`  
**Research label:** `BACKGROUND-RESEARCH`  
**Authority:** Research synthesis only. No code. No package spec authority. No canon.

## Parent card

`LAB-IGNITER-PACKAGE-MANAGER-READINESS-P1`

## How to run this card

Preferred: run after A-E reports exist. If launched in parallel overnight, produce an independent
synthesis from the parent card and clearly list which shard reports were unavailable.

## Goal

Produce a compact synthesis packet that turns the package research into a morning decision aid:
recommended v0 direction, anti-patterns, lockfile/provenance model, and next implementation card
candidates.

## Inputs

Read any reports that exist:

- `lab-igniter-package-research-cargo-go-gemini-p1-v0.md`
- `lab-igniter-package-research-js-py-deno-gemini-p1-v0.md`
- `lab-igniter-package-research-ruby-rails-gemini-p1-v0.md`
- `lab-igniter-package-research-oci-wasm-terraform-gemini-p1-v0.md`
- `lab-igniter-package-research-igniter-artifacts-gemini-p1-v0.md`

Also read the parent card and P0 Projection Dialects packet.

## Output contract

Write exactly one report:

`lab-docs/lang/lab-igniter-package-research-synthesis-gemini-p1-v0.md`

Then update only this card with a closing report.

## Required sections

1. One-page executive recommendation.
2. Required comparative table, merged from available shard reports.
3. Recommended Igniter v0 package model.
4. Lockfile/provenance sketch.
5. Top 7 anti-patterns to avoid.
6. Deferred surfaces.
7. Next 2-3 implementation/readiness cards with acceptance sketches.
8. Missing inputs / confidence notes.

## Closed surfaces

- Do not edit shard reports.
- Do not edit parent card.
- Do not implement package-manager code.
- Do not claim final spec authority.
- No canon promotion.

## Acceptance

- [x] Report clearly states which shard reports were available.
- [x] Report gives one recommended v0 direction and alternatives.
- [x] Report preserves research-only boundary.
- [x] Report includes next-card candidates.
- [x] No code changed.

---

## Closing Report — 2026-06-18

**Outcome:** Completed the synthesis of all five packaging sharded research reports (Cargo/Go, JS/Python/Deno, Ruby/Rails, OCI/WASM/Terraform, and Igniter internal taxonomy).

**Deliverable:** `lab-docs/lang/lab-igniter-package-research-synthesis-gemini-p1-v0.md`

**Sources/Shard Reports Available:** All 5 sharded reports were successfully read and integrated:
1. `lab-igniter-package-research-cargo-go-gemini-p1-v0.md`
2. `lab-igniter-package-research-js-py-deno-gemini-p1-v0.md`
3. `lab-igniter-package-research-ruby-rails-gemini-p1-v0.md`
4. `lab-igniter-package-research-oci-wasm-terraform-gemini-p1-v0.md`
5. `lab-igniter-package-research-igniter-artifacts-gemini-p1-v0.md`

**Recommended v0 Package Model:** A local-first workspace manager resolving dependencies via relative filesystem path mapping, using Minimal Version Selection (MVS) for transitive imports and scanning files for AST `module` declarations. Packages consist of authored source code + generated dialect outputs + compiled `.igapp` bytecode, keeping secrets and native execution strictly at the host layer.

**Top 7 Anti-patterns to Avoid:**
1. **Lifecycle Compile Hooks (npm/setup.py):** Run-on-install script vulnerabilities.
2. **Dynamic initializers (Rails engines):** Boot-phase monkey patching and memory modification.
3. **Database Migration Splitting (Rails engines):** Dynamic database migration file copying.
4. **Mutable tags (OCI/VCS):** Version drift due to mutable tags like `v1.0.0`.
5. **Flat namespaces (Python/Ruby):** Folder-level load-path dependency conflicts.
6. **Phantom transitive imports (npm/Node):** Importing unlisted transitive dependencies.
7. **Secrets smuggling (Terraform providers):** Storing connection details and secrets in packages.

**Next Cards proposed:**
* `LAB-IGNITER-PACKAGE-WORKSPACE-RESOLVER-P2` (Local workspace path mappings)
* `LAB-IGNITER-LOCKFILE-GENERATOR-P3` (Cryptographic lockfile serialization)

**Verification:** No code or specifications were changed. The synthesis report has been written exactly to the specified path.
