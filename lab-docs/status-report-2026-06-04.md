# Igniter Lab Status Report - 2026-06-04

Status: historical snapshot
Scope: `igniter-lab/`

---

## Executive Summary

Igniter Lab is now documented as a single nested playground repo with multiple
project directories. The main navigation document is
`lab-docs/igniter-lab-project-map.md`.

Current high-signal status:

```text
active lane:
  Rust compiler + VM candidate pressure

major pressure topic:
  loops / recursion / service-loop spec boundary

architecture thread:
  igniter-machine as unified compiler + VM + fact-memory machine

backend thread:
  igniter-tbackend as backend/substrate candidate, not runtime authority

tooling/app pressure:
  IDE/plugin/app sketches are useful but non-authoritative
```

## Documentation Changes In This Pass

Changed or added:

```text
README.md
lab-docs/README.md
lab-docs/igniter-lab-project-map.md
lab-docs/status-report-2026-06-04.md
```

No code files were edited.

## Current Project Status

| Project | Status | Note |
| --- | --- | --- |
| `igniter-compiler` | active lab compiler / pressure input | Rich source surface; no README yet. |
| `igniter-vm` | active delegated runtime candidate | README minimal; pre-existing `AD igniter-vm/scratch_inputs.json` left untouched. |
| `igniter-runtime` | proof archive / delegated runtime research | README is useful and current enough for navigation. |
| `igniter-stdlib` | proof candidate / expansion needed | No README yet; stdlib proof and source directories present. |
| `igniter-tbackend` | backend/substrate candidate | README exists but uses strong capability wording; lab map fences it as non-authoritative. |
| `acts-as-tbackend` | shadow adapter sketch | README is useful and boundary-aware. |
| `igniter-machine` | experimental architecture prototype | README minimal; source crate now exists beyond older proposal-only notes. |
| `igniter-ide` | UI prototype | README still template-level; should be replaced in a later docs pass. |
| `igniter-jetbrains-plugin` | early IDE plugin prototype | README minimal; source tree exists. |
| `igniter-apps` | local app sketches | README is useful and boundary-aware. |
| `lab-docs` | active documentation surface | Now has docs index, project map, and current status report. |

## Open Documentation Debt

1. Add real subproject READMEs for `igniter-compiler`, `igniter-stdlib`,
   `igniter-machine`, `igniter-ide`, and `igniter-jetbrains-plugin`.
2. Tighten `igniter-tbackend/README.md` wording so production-style claims are
   clearly marked as playground ambition/evidence, not current authority.
3. Add a short "local checks" table per subproject once the desired smoke
   commands are confirmed.
4. Decide whether generated `out/`, WAL, logs, build products, and local app
   state should be listed as evidence or ignored in future reports.

## Boundary

This report does not authorize:

```text
canonical semantics
runtime/API/CLI widening
public runtime support
Reference Runtime support
stable API
production readiness
release evidence
Spark integration
public demo or performance claims
portability guarantees
```

## Next Recommended Pass

Run a focused docs pass for subproject READMEs:

```text
igniter-compiler README
igniter-vm README refresh
igniter-stdlib README
igniter-machine README refresh
igniter-ide README replacement
igniter-jetbrains-plugin README refresh
```

Keep the next pass docs-only unless explicitly routed into code or proof work.
