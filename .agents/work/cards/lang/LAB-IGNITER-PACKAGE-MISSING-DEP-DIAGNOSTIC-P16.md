# LAB-IGNITER-PACKAGE-MISSING-DEP-DIAGNOSTIC-P16 — OOF-IMP9 for missing local dependency paths

Status: CLOSED
Lane: standard / package DX
Type: implementation proof
Delegation code: OPUS-IGNITER-PACKAGE-MISSING-DEP-DIAGNOSTIC-P16
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

P14 implemented the local transitive package graph. It deliberately deferred `OOF-IMP9`: when a declared local
`[dependencies]` path is missing, graph assembly currently does not report the missing path directly; the user
may only see a later missing-import diagnostic (`OOF-IMP2`) if some module imports from that missing package.

Now that the local package model is feature-complete for v0, this is the smallest package-DX polish slice.

## Goal

Add deterministic `OOF-IMP9` for a declared local dependency path that does not exist or is not a readable
package root. The diagnostic should point at the declaring package and the dependency edge, before module
scanning/import resolution falls through to unrelated errors.

## Verify first

Read live code before editing:

- `lang/igniter-compiler/src/project.rs`
  - `ProjectConfig::load`
  - `collect_package_graph`
  - `build_module_index`
  - `workspace_lock`
  - `check_workspace_integrity`
- P14/P15 docs/cards:
  - `lab-docs/lang/lab-igniter-package-transitive-graph-p14-v0.md`
  - `lab-docs/lang/lab-igniter-package-transitive-graph-ci-p15-v0.md`
- Existing package tests:
  - `package_workspace_tests.rs`
  - `package_lockfile_cli_tests.rs`

## Design constraints

- Keep this local-only: no registry, no remote source, no semver solver.
- Do not infer packages by module names.
- Do not make missing dependency paths warnings. A declared local dependency path that does not exist is an
  assembly fault.
- Keep the diagnostic deterministic across machines.
- Do not break P14 diamond/cycle behavior.
- If a path exists but has no `igniter.toml`, decide live from existing `ProjectConfig::load` semantics whether
  that is allowed as a package with defaults, or should be rejected. Document the decision.

## Questions to answer

1. What exactly counts as a missing dependency path: nonexistent path only, file-not-dir, unreadable dir, or no
   `igniter.toml`?
2. Should `OOF-IMP9` be emitted by `collect_package_graph`, `build_module_index`, or `index_integrity`?
3. Should `workspace_lock` fail on `OOF-IMP9` even when no module imports the missing package?
4. Should `verify --strict` surface `OOF-IMP9` under `integrity.diagnostic`?
5. Should plain `verify` fail when graph assembly itself cannot compute the current lock? If yes, how is this
   represented in existing CLI JSON?
6. What should `node` and `source_paths` contain for a missing path edge?

## Expected diagnostic shape

Preferred:

- `rule`: `OOF-IMP9`
- `message`: mentions declaring package, dependency name, and missing path
- `node`: `dependency:<declaring-package-label>-><dep-name>` or similarly stable
- `module_path`: `null` (graph fault, not a module fault)
- `source_paths`: include the declaring package root and the resolved missing path string if useful

Adjust only if live diagnostic conventions make another shape cleaner.

## Required implementation

- Add `OOF-IMP9` generation for missing local dependency path.
- Add focused fixtures, likely:
  - root declares missing local dependency;
  - transitive package declares missing local dependency.
- Add API tests in `package_workspace_tests.rs`.
- Add CLI tests if behavior crosses `lock`, `verify`, or `verify --strict`.

## Acceptance

- [x] Missing root dependency path produces `OOF-IMP9`, not delayed `OOF-IMP2`.
- [x] Missing transitive dependency path produces `OOF-IMP9` naming the declaring package/edge.
- [x] `check_workspace_integrity` / `verify --strict` surface `OOF-IMP9` structurally if graph assembly reaches
      integrity there, or the proof doc explains why graph assembly fails earlier.
- [x] `workspace_lock` / `lock --frozen` behavior is tested or explicitly documented.
- [x] Existing P14/P15 tests remain green.
- [x] Full `igniter-compiler` suite green.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-21)

**Implementation (`project.rs` + `main.rs` + tests):** `collect_package_graph` now detects a dependency edge
whose resolved canonical path is **not a directory** (gate `!dep_canon.is_dir()` — a dir without
`igniter.toml` loads with defaults, so it is NOT missing) and returns a deterministic-first **`OOF-IMP9`**
(sorted by declaring/dep/missing; message uses root-relative path for machine stability). Because both
`build_module_index` (compile / `verify --strict` / `check_workspace_integrity`) and `workspace_lock`
(`lock` / `--frozen`) call `collect_package_graph`, all fail identically. `main.rs` `run_lock`/`run_verify`
gained a structured assembly-error arm (`Err(Diagnostic) → {ok:false, error: d.to_value()}`). Proof doc:
`lab-docs/lang/lab-igniter-package-missing-dep-diagnostic-p16-v0.md`.

**Shape:** `rule:OOF-IMP9`, `node:dependency:<declaring>-><dep>`, `module_path:null`, `source_paths:[declaring,
missing]`, message names package + dep + root-relative missing path.

**Live smoke:** compile missing root → `OOF-IMP9: …'<root>' declares dependency 'ghost' at '../ghost', which
does not exist`; `lock` missing transitive → structured `error` (`node:dependency:mid->ghost`), no lockfile
written.

**Proof — all green:** `package_workspace_tests` **46** (41 + 5 P16), `package_lockfile_cli_tests` **23**
(21 + 2 P16), full `igniter-compiler` suite green (0 failed), `git diff --check` clean. 3 new fixtures
(missing-root / missing-transitive / dir-without-manifest). P14/P15 intact.

**Deferred:** file-vs-absent message distinction; report-all-missing (only first, like other faults);
remote/registry/semver. The local package model is **feature-complete + DX-polished** for v0. **Next:**
remote/registry wave OR `igc package` introspection.

## Required deliverable

- Proof doc: `lab-docs/lang/lab-igniter-package-missing-dep-diagnostic-p16-v0.md`
- Closing report in this card.

## Closed scope

- No registry/remote package lookup.
- No semver/version solving.
- No package publishing format.
- No changes to `.ig` syntax, VM, server, web, stdlib, or machine.
