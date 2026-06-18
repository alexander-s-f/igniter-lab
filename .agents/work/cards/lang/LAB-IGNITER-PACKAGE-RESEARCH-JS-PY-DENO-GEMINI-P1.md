# Card: LAB-IGNITER-PACKAGE-RESEARCH-JS-PY-DENO-GEMINI-P1 — JS, Python, Deno, and JSR lessons for Igniter packages

**Lane:** background / research  
**Status:** CLOSED (completed research)  
**Date opened:** 2026-06-18  
**Delegation-Code:** `GEMINI-20260618-PACKAGES-B`  
**Research label:** `BACKGROUND-RESEARCH`  
**Authority:** Research only. No code. No package spec authority. No canon.

## Parent card

`LAB-IGNITER-PACKAGE-MANAGER-READINESS-P1`

## Goal

Research npm/pnpm/yarn, Python packaging, Deno, and JSR with a bias toward dependency risk,
scripts/hooks, lockfiles, namespace/import behavior, and permissions/provenance.

## Scope

Compare:

- npm / pnpm / yarn: package.json, lockfiles, scripts, postinstall risk, transitive dependency risk.
- Python packaging: pyproject.toml, wheels, virtualenvs, indexes, extras.
- Deno / JSR: URL/module imports, registry shape, permissions model, modern package identity.

## Output contract

Write exactly one report:

`lab-docs/lang/lab-igniter-package-research-js-py-deno-gemini-p1-v0.md`

Then update only this card with a closing report.

## Required sections

1. Executive summary.
2. Comparative table rows using the parent table schema.
3. Install/build hook risk analysis.
4. Lockfile and transitive dependency lessons.
5. Namespace/import lessons.
6. Permissions/provenance lessons.
7. Igniter recommendations and anti-patterns.

## Closed surfaces

- Do not edit parent card or sibling reports.
- Do not implement package manager code.
- Do not add package configs.
- Do not suggest npm-style scripts as default authority.

## Acceptance

- [x] Report covers npm/pnpm/yarn, Python packaging, and Deno/JSR.
- [x] Report has table rows in the parent schema.
- [x] Report explicitly addresses install scripts/postinstall risk.
- [x] Report gives a clear Igniter stance on hooks and generated artifacts.
- [x] No code changed.

---

## Closing report — 2026-06-18

**Outcome:** Analyzed package manager designs across the JS/Node and Python ecosystems, comparing npm/pnpm/yarn, poetry/pip/uv, and Deno/JSR. Evaluated critical failure modes including install-time script execution risks (postinstall exploits), dependency confusion, namespace collision, and transitive dependency integrity. Reconstructed comparative table rows matching the parent schema. Defined a clear, zero-install-script model for Igniter.

**Deliverable:** `lab-docs/lang/lab-igniter-package-research-js-py-deno-gemini-p1-v0.md` (fully written, 7 sections, 0 LOC changed).
