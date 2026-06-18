# Card: LAB-IGNITER-PACKAGE-RESEARCH-CARGO-GO-GEMINI-P1 — Cargo and Go modules lessons for Igniter packages

**Lane:** background / research  
**Status:** CLOSED (Research report delivered)  
**Date opened:** 2026-06-18  
**Date closed:** 2026-06-18  
**Delegation-Code:** `GEMINI-20260618-PACKAGES-A`  
**Research label:** `BACKGROUND-RESEARCH`  
**Authority:** Research only. No code. No package spec authority. No canon.

## Parent card

`LAB-IGNITER-PACKAGE-MANAGER-READINESS-P1`

## Goal

Research Cargo/crates.io and Go modules specifically, then extract lessons for Igniter's package
identity, lockfile/provenance, imports, workspaces, and feature/options model.

## Scope

Compare:

- Cargo / crates.io / Cargo.lock / features / workspaces / source replacement.
- Go modules / module paths / minimal version selection / go.sum / replace directives.

## Output contract

Write exactly one report:

`lab-docs/lang/lab-igniter-package-research-cargo-go-gemini-p1-v0.md`

Then update only this card with a closing report.

## Required sections

1. Executive summary.
2. Comparative table rows using the parent table schema:
   `Ecosystem | Package identity | Locking | Build hooks | Namespace/imports | Trust/provenance | Strengths | Failure modes | Igniter lesson`
3. Cargo lessons for Igniter.
4. Go modules lessons for Igniter.
5. Feature/options warning: what to borrow and what to reject.
6. Concrete Igniter implications for local workspace packages and lockfiles.
7. 3-5 future card ideas, marked as ideas only.

## Closed surfaces

- Do not edit parent card or sibling reports.
- Do not implement package manager code.
- Do not add dependencies or config files.
- Do not claim Cargo/Go choices are authority for Igniter.

## Acceptance

- [x] Report covers both Cargo and Go.
- [x] Report has concise table rows in the parent schema.
- [x] Report names at least 3 failure modes to avoid.
- [x] Report gives Igniter-specific lessons, not generic ecosystem notes.
- [x] No code changed.

---

## Closing Report — 2026-06-18

**Outcome:** Completed the comparative research survey for Cargo/crates.io and Go modules, analyzing their package identity, locking mechanisms, imports, workspaces, and options models.

**Deliverable:** `lab-docs/lang/lab-igniter-package-research-cargo-go-gemini-p1-v0.md`

**Sources/Ecosystems Reviewed:** Cargo (crates.io official specs, SemVer resolver rules, workspaces) and Go modules (MVS specification, `go.sum` and check databases, `replace` directives).

**Recommended v0 Package Model:** A local-first workspace manager resolving logical package imports
via AST module declarations in files (as implemented in `project.rs`), with a flat (featureless)
dependency model and explicit local paths/content digests. MVS is a later option only if
remote/versioned packages appear.

**Top 5 Anti-patterns to Avoid:**
1. **Arbitrary Build Hooks:** Rust's `build.rs` compile-time scripts are a major security vulnerability; Igniter must forbid run-on-install hooks.
2. **Direct VCS Identifiers:** Go's use of raw Git URLs as module paths makes builds vulnerable to repository deletions or changes; Igniter must decouple logical names from VCS paths.
3. **Optional Feature Combinatorics:** Cargo's complex `features` unification creates versioning complexity; Igniter v0 must remain featureless, dividing libraries into smaller packages instead.
4. **Solver Non-determinism:** Complex SAT solvers are fragile and slow; v0 should avoid version
   solving entirely.
5. **No Cryptographic Anchors:** Releasing without strict content hashing leads to dependency spoofing; Igniter must enforce `igniter.lock` hashes.

**Verification:** No code, dependencies, or configuration files were changed. The research report has been written exactly to the specified path.
