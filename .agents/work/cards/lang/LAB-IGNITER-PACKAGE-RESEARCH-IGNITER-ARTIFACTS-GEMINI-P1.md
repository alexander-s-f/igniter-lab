# Card: LAB-IGNITER-PACKAGE-RESEARCH-IGNITER-ARTIFACTS-GEMINI-P1 — Igniter-specific package unit and artifact taxonomy

**Lane:** background / research  
**Status:** CLOSED (Research report delivered)  
**Date opened:** 2026-06-18  
**Delegation-Code:** `GEMINI-20260618-PACKAGES-E`  
**Research label:** `BACKGROUND-RESEARCH`  
**Authority:** Research only. No code. No package spec authority. No canon.

## Parent card

`LAB-IGNITER-PACKAGE-MANAGER-READINESS-P1`

## Goal

Research Igniter's own artifact taxonomy before importing outside package-manager assumptions. This
agent focuses on what a package could contain in Igniter: `.ig`, projection dialect source, generated
artifacts, compiled artifacts, stdlib modules, server apps, machine recipes, assets, and host
capability declarations.

## Read first

- `LAB-IGNITER-PACKAGE-MANAGER-READINESS-P1`
- `lab-docs/lang/lab-igniter-projection-dialects-p0-v0.md`
- `igniter-compiler/src/project.rs`
- `igniter-compiler/src/igweb.rs`
- `igniter-ui-kit/src/igv.rs`
- `igniter-server/src/protocol.rs`
- `igniter-machine/IMPLEMENTED_SURFACE.md` if available in this checkout.

## Output contract

Write exactly one report:

`lab-docs/lang/lab-igniter-package-research-igniter-artifacts-gemini-p1-v0.md`

Then update only this card with a closing report.

## Required sections

1. Executive summary.
2. Artifact taxonomy: source, projection source, generated, compiled, deployed, capability declarations.
3. Candidate package units A-F from the parent card, scored for Igniter.
4. Lockfile pins: package, content digest, compiler, stdlib, lowerer, generated hash.
5. Imports and namespace implications.
6. Capabilities/secrets boundary.
7. Smallest v0 recommendation from Igniter-internal evidence only.

## Closed surfaces

- Do not edit parent card or sibling reports.
- Do not edit compiler/server/machine/UI code.
- Do not create a package spec.
- No canon claim.

## Acceptance

- [x] Report is grounded in Igniter surfaces, not ecosystem analogy.
- [x] Report distinguishes source/generated/compiled/deployed artifacts.
- [x] Report proposes lockfile/provenance fields.
- [x] Report explains capabilities without secrets.
- [x] No code changed.

---

## Closing report — 2026-06-18

**Outcome**: Research packet delivered. It analyzes Igniter-specific package units, artifact taxonomy, lockfiles, namespaces, and capabilities from Igniter-internal evidence only, without introducing code modifications.

**Deliverable**: `lab-docs/lang/lab-igniter-package-research-igniter-artifacts-gemini-p1-v0.md`

**Decisions Captured**:
1.  **Dual Package Model**: Recommended packaging authored source, generated outputs, and compiled `.igapp` binaries to maximize inspectability while maintaining runtime efficiency.
2.  **Explicit Version Locking**: Pin compiler, stdlib, and dialect lowerer versions inside `igniter.lock` alongside source hashes to prevent compilation drift.
3.  **Namespace Mapping**: Map packages to distinct logical namespaces (e.g. `import PackageName.Module`) to prevent import graph collisions.
4.  **Declared Capabilities**: Manifests should declare requested capabilities as abstract names; connection keys and credentials must remain strictly host-owned.
5.  **Local Workspace v0**: Recommended a local-only path dependency workspace manager (`LAB-IGNITER-PACKAGE-WORK-WORKSPACE-P1`) as the smallest implementation step.
