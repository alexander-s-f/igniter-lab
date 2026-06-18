# Card: LAB-IGNITER-PACKAGE-RESEARCH-OCI-WASM-TERRAFORM-GEMINI-P1 — OCI, WASM components, and Terraform module lessons

**Lane:** background / research  
**Status:** CLOSED 2026-06-18  
**Date opened:** 2026-06-18  
**Delegation-Code:** `GEMINI-20260618-PACKAGES-D`  
**Research label:** `BACKGROUND-RESEARCH`  
**Authority:** Research only. No code. No package spec authority. No canon.

## Parent card

`LAB-IGNITER-PACKAGE-MANAGER-READINESS-P1`

## Goal

Research artifact/provenance-heavy ecosystems: OCI artifacts, WASM component model/WIT, and Terraform
providers/modules. Extract lessons for content-addressed packages, interface-first packages,
capability boundaries, lockfiles, and provider authority.

## Scope

Compare:

- OCI artifacts/containers: blobs, tags vs digests, provenance/signing.
- WASM component model / WIT: interface-first portable components.
- Terraform providers/modules: declarative package use, provider authority, locks, registry model.

## Output contract

Write exactly one report:

`lab-docs/lang/lab-igniter-package-research-oci-wasm-terraform-gemini-p1-v0.md`

Then update only this card with a closing report.

## Required sections

1. Executive summary.
2. Comparative table rows using the parent table schema.
3. Content-addressing and tag/digest lessons.
4. Interface/capability declaration lessons.
5. Provider authority and hidden execution risks.
6. Provenance/signing implications for Igniter lockfiles.
7. Suggested Igniter v0 constraints.

## Closed surfaces

- Do not edit parent card or sibling reports.
- Do not propose container runtime adoption as a default.
- Do not implement signing/provenance.
- No code changes.

## Acceptance

- [x] Report covers OCI, WASM components/WIT, and Terraform.
- [x] Report has table rows in the parent schema.
- [x] Report focuses on content-addressing, provenance, and authority.
- [x] Report names concrete failure modes to avoid.
- [x] No code changed.

## Closing Report

*   **Sources/Ecosystems Reviewed**: OCI Artifacts/Containers, WASM Component Model & WIT, Terraform Providers & Modules.
*   **Comparative Table Location**: Section 2 of [lab-igniter-package-research-oci-wasm-terraform-gemini-p1-v0.md](../../lab-docs/lang/lab-igniter-package-research-oci-wasm-terraform-gemini-p1-v0.md).
*   **Recommended v0 Package Model**: Flat, local-first path-based workspaces using content digests as dependency identifiers, utilizing explicit capability declarations linked top-down by the host (no ambient authority).
*   **Top 5 Anti-Patterns to Avoid**:
    1.  *Mutable Tag Resolution*: Pinned versions mutating post-publication. Avoid by mapping human tags to immutable cryptographic digests.
    2.  *Ambient Capability Smuggling*: Dependencies accessing network or filesystems directly. Avoid by enforcing explicit abstract capability ports linked by the host.
    3.  *Arbitrary Build/Install Scripts*: Running shell scripts (npm-style) on download. Avoid by enforcing zero-script installation.
    4.  *Binary Provider Execution*: Downloading and executing unvetted native provider code. Avoid by enforcing bytecode-only VM packaging.
    5.  *Nested Dialect Dependency loops*: Packages depending on intermediate dialects. Avoid by using flat DAG builds (Dialect -> `.ig` -> compilation).
*   **Alignment with Igniter Philosophy**: Grounded in "deterministic artifacts" (via immutable digests) and "explicit authority" (via host-bound capability ports).
*   **Next Card Recommendation**: `LAB-IGNITER-PACKAGE-WORK-WORKSPACE-P1` (implement path-based workspace resolution in `ProjectConfig`, mapping package dependencies to isolated logical namespaces).
