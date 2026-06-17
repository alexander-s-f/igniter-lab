# Card: LAB-COMPILER-PROJECT-MODE-COMPILE-P1

**Title:** Canonical project-root compile mode for multi-file Igniter projects
**Skill:** idd-agent-protocol
**Lane:** standard / compiler DX foundation
**Status:** ✅ CLOSED — 2026-06-17
**Authority:** igniter-lab only; no canon impact; no production impact
**Proof:** `lab-docs/lang/lab-compiler-project-mode-compile-p1-v0.md`

---

## Card Statement

Make the compiler own canonical project assembly. Add a project-root compile mode

```
igniter_compiler compile --project-root <ROOT> --entry <Module.Path> --out <OUT.igapp>
```

that scans source roots, builds a logical module index by parsing each file's `module`
declaration, resolves the transitive non-stdlib import closure for the entry module, and
hands the resulting file list to the existing multi-file pipeline. Makefiles, JetBrains,
CI, and host tooling call this instead of reimplementing import-graph scanning.

## Authority boundary (named before coding)

- **Decides behavior:** the live `igniter_compiler` (parser + `multifile::compile_units`).
- **Evidence only:** this card, the proof doc, test output.
- **Authorized to change:** `igniter-compiler` CLI + new `project.rs`; add tests/fixtures.
- **Closed surfaces:** language import semantics, `OOF-IMP*`/`OOF-P1` behavior, JetBrains
  plugin, Makefile build model, package/dependency management, qualified namespaces,
  `stdlib.*` ownership.

## What landed

- `igniter-compiler/src/project.rs` — `ProjectConfig` (minimal `igniter.toml` `source_roots`,
  default `["."]`), `ModuleIndex`, `ProjectDiagnostic`, `ProjectError`,
  `resolve_entry(root, entry) -> Vec<PathBuf>`. Recursive `.ig` scan (ignores `.git`,
  `target`, `build`, `.idea`, hidden dirs); module index by parsed `module` decl (no
  directory inference); deterministic transitive non-stdlib closure.
- `igniter-compiler/src/main.rs` — `run_project_mode` + `emit_project_diagnostic`; positional
  multi-file CLI unchanged.
- `igniter-compiler/src/lib.rs` — `pub mod project;`.
- `igniter-compiler/tests/project_mode_tests.rs` — 9 tests; fixtures under
  `tests/fixtures/project_mode/`.
- One new lab-only diagnostic: `OOF-PROJ-ENTRY` (entry module not found). All other failure
  classes route to existing `OOF-IMP2`/`OOF-IMP4`/`OOF-DECL-*` via reuse of `compile_units`.

## Acceptance — all 10 met

1. Explicit positional multi-file CLI unchanged ✅
2. Project compile includes entry + imported module; stdlib not a file ✅
3. Transitive A→B→C ✅
4. Missing entry → `OOF-PROJ-ENTRY`, no panic ✅
5. Missing non-stdlib import → `OOF-IMP2` (routed, not re-implemented) ✅
6. Duplicate module → `OOF-IMP4` with both source paths ✅
7. Directories do not define module names ✅
8. Global duplicate type/contract behavior inherited from `compile_units`, documented not "fixed" ✅
9. Deterministic `source_hash` + `source_units` order across repeated builds ✅
10. Focused tests added; existing tests run ✅

## Verification

```
cd igniter-compiler
cargo test --test project_mode_tests --quiet    # 9 passed; 0 failed
cargo test --no-fail-fast --quiet
#   effect_name_parity_tests: 4 passed
#   loop_conformance_tests:  10 passed; 4 failed  (PRE-EXISTING — proven via git stash; unrelated)
#   project_mode_tests:       9 passed
```

The 4 `loop_conformance_tests` failures predate this card (verified by stashing P1 changes
and re-running the clean tree: identical `10 passed; 4 failed`). They are SemanticIR
`loop_node` emission assertions, untouched by project mode.

## Next / deferred

- **JetBrains P6 follow-up:** switch the plugin to call project mode instead of building its
  own graph; preserve the unsaved editor buffer via a later IDE overlay (project mode reads
  from disk — overlay not solved here, intentional).
- Deferred: richer `igniter.toml` schema, IDE overlay, Makefile wrapper, qualified-name
  namespaces, package/dependency management.
