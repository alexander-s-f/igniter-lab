# lab-compiler-project-mode-compile-p1-v0

Proof doc for card `LAB-COMPILER-PROJECT-MODE-COMPILE-P1` — give `igniter_compiler`
a canonical **project-root compile mode** so Makefiles, JetBrains, CI, and future
host tooling can call one compiler-owned import-graph assembler instead of each
reimplementing module discovery.

**Status:** CLOSED. **Skill:** idd-agent-protocol (verify-first; the live compiler
is the authority, not this card). **Lane:** standard / compiler DX foundation.

> Compiler/CLI foundation only. No language import-semantics change; no filesystem-path
> imports; no `OOF-P1`/`OOF-IMP` suppression; no JetBrains integration in this card;
> no package/dependency management, lockfiles, or remote modules; no qualified-name
> namespace work; user files still may not declare `stdlib.*`.

## Verify-first findings (live surfaces, confirmed before coding)

- `igniter-compiler/src/main.rs` — CLI was `compile SOURCE [SOURCE ...] --out OUT.igapp`;
  dispatches single-file vs multi-file on `source_paths.len()` (`main.rs:64`).
- `igniter-compiler/src/multifile.rs` — `compile_units(&[String])` already does the full
  import-graph validation when all files are passed explicitly: `OOF-IMP5` (missing
  `module`), `OOF-IMP4` (duplicate module), `OOF-IMP6` (user `stdlib.*`), `OOF-IMP2`
  (unknown import path / unknown stdlib module), `OOF-IMP3` (unknown imported name),
  `OOF-IMP1` (circular import), `OOF-DECL-DUP-TYPE` / `OOF-DECL-DUP-CONTRACT` (global
  duplicate declarations after merge). stdlib imports resolve from
  `igniter-lang/docs/spec/stdlib-inventory.json`, not from files.
- `igniter-compiler/src/parser.rs` — `module` is parsed by `parse_module_path` (dotted
  logical path), `import` by `parse_import`. `SourceFile.module: Option<String>`,
  `SourceFile.imports: Vec<Import>`, `Import.module_path: String`.

**The compiler was already multi-file; it just had no project-root entry point.** P1
adds the discovery + closure front end and reuses `compile_units` unchanged for ALL
import validation. That reuse is deliberate: missing-import (`OOF-IMP2`), duplicate
type/contract, and cycle behavior are inherited, not re-implemented.

## Exact CLI shape implemented

```
igniter_compiler compile --project-root <ROOT> --entry <Module.Path> --out <OUT.igapp>
```

- Detected in `main.rs` by the presence of `--project-root`; otherwise the **existing
  positional multi-file CLI runs byte-for-byte as before** (acceptance 1).
- Project mode always routes through the multi-file pipeline (even for a single resolved
  file) so `source_units` evidence is always emitted.
- Resolution failures render as a `compiler_result` with `status:"oof"` and a
  `project_resolve` stage, mirroring the existing multi-file error shape (no panics).

## Source-root / default behavior

- New module `igniter-compiler/src/project.rs`: `ProjectConfig`, `ModuleIndex`,
  `ProjectDiagnostic`, `ProjectError`, `resolve_entry(root, entry) -> Vec<PathBuf>`.
- Config: if `<root>/igniter.toml` exists, a minimal hand-rolled reader extracts
  `source_roots = ["a", "b"]` (no `toml` crate added in P1). Otherwise default to
  `["."]` (scan the whole project root recursively).
- Scan ignores `.git`, `target`, `build`, `.idea`, and any hidden directory.
- The module index is built by **parsing each `.ig` file's `module` declaration**.
  Directory names never define module paths (acceptance 7).
- Closure: start at `--entry`, follow non-stdlib imports transitively; stdlib imports
  are dropped (not file dependencies). Files reachable but absent from the index are
  left dangling so `compile_units` reports `OOF-IMP2` (acceptance 5). Duplicate module
  declarations make the index ambiguous and are surfaced up front as a deterministic
  `OOF-IMP4` with all source paths (acceptance 6).
- Deterministic order: scan list sorted+deduped; closure traversal sorted; final file
  list sorted by path. `compile_units` re-sorts by module path, so the emitted
  `source_hash` and `source_units` order are stable across repeated builds (acceptance 9).

## Acceptance matrix

| # | Requirement | Result |
|---|-------------|--------|
| 1 | Explicit `compile a.ig b.ig --out` unchanged | ✅ `explicit_multifile_cli_still_works` + manual run `status:"ok"` |
| 2 | Project compile of `SparkCRM.CallRouter.Webhook` includes Webhook+Types; stdlib not a file | ✅ `source_units = [SparkCRM.CallRouter.Types, SparkCRM.CallRouter.Webhook]`, `status:"ok"` |
| 3 | Transitive A→B→C compiles | ✅ `source_units = [Chain.A, Chain.B, Chain.C]`, `status:"ok"` |
| 4 | Missing entry → deterministic diagnostic, no panic | ✅ `OOF-PROJ-ENTRY`, `status:"oof"` |
| 5 | Missing non-stdlib import → import diagnostic | ✅ routed to existing `OOF-IMP2` |
| 6 | Duplicate module → diagnostic with both paths | ✅ `OOF-IMP4`, `source_paths=[x.ig, y.ig]` |
| 7 | Directories do not define modules | ✅ resolves `Flat.Single` from nested dir; `deeply.nested.leaf_dir.leaf` → `OOF-PROJ-ENTRY` |
| 8 | Global duplicate type/contract behavior unchanged | ✅ inherited from `compile_units` (NOT modified) — documented, not "fixed" |
| 9 | Deterministic source hash + order across builds | ✅ identical `source_hash` and `source_units` order on repeat |
| 10 | Focused tests + existing tests run | ✅ see below |

## New diagnostic

- `OOF-PROJ-ENTRY` — entry module not found in project source roots. This is a
  **project-assembly** diagnostic, distinct from the language `OOF-IMP*` family, and is
  lab-only (no canon impact). All other failure classes route to existing `OOF-IMP*` /
  `OOF-DECL-*` codes.

## Proof commands & exact results

```
cd igniter-compiler
cargo test --test project_mode_tests --quiet   # 9 passed; 0 failed
cargo test --no-fail-fast --quiet               # see breakdown below
```

Full-suite breakdown (`--no-fail-fast`):

| Test binary | Result |
|-------------|--------|
| lib unit | 0 passed |
| bin (main) unit | 0 passed |
| `effect_name_parity_tests` | 4 passed |
| `loop_conformance_tests` | 10 passed / **4 failed** |
| `project_mode_tests` (new) | **9 passed** |
| doctests | 0 |

**The 4 `loop_conformance_tests` failures are pre-existing and unrelated to this card.**
Proven by stashing the P1 changes (`project.rs`, `lib.rs`, `main.rs`, `tests/`) and
re-running on the clean tree: `10 passed; 4 failed` — identical. The failures are
SemanticIR `loop_node` emission assertions, untouched by project-mode resolution.

Fixtures (committed under `igniter-compiler/tests/fixtures/project_mode/`):
`basic/` (dotted modules + selective + stdlib import), `transitive/` (A→B→C),
`missing_import/`, `dup_module/`, `nested/` (module ≠ directory path).

## Authority boundary

igniter-lab only. No canon language change, no production impact. The compiler remains
the authority; this doc is evidence, not authority. Import semantics are untouched —
imports are still logical module paths; `stdlib.*` is still resolved from the inventory
and still forbidden in user files.

## What remains for JetBrains P6

`LAB-JETBRAINS-IMPORT-AWARE-COMPILE-P6` (already CLOSED) made the plugin build its **own**
import graph plugin-side and pass the file set to the multi-file CLI. With P1 landed, the
plugin can instead call `compile --project-root … --entry …` and let the compiler own
graph assembly — deleting the plugin-side scanner. The remaining plugin work:

- Switch the plugin invocation to project mode (compiler-owned graph, single source of truth).
- Preserve the **unsaved editor buffer** via a later overlay mechanism: project mode reads
  files from disk, so an in-flight edit isn't seen. P1 intentionally does NOT solve this;
  an IDE overlay (inject buffer contents for the active file over the scanned set) is the
  follow-up seam.

## Intentionally deferred

- Richer `igniter.toml` schema (only `source_roots` is read in P1).
- IDE unsaved-buffer overlay.
- Makefile wrapper (P1 does not make Makefile the canonical build model).
- Qualified-name namespaces (two modules declaring `type Customer` still collide globally,
  inherited from `compile_units` — left as-is per acceptance 8).
- Package/dependency management, lockfiles, remote modules.

## Surface inventory note

There is no `IMPLEMENTED_SURFACE.md` in `igniter-compiler` (only `igniter-machine` and
`igniter-vm` carry one). No surface file was created — doing so would invent structure
outside this card's scope. The CLI shape and `project.rs` API are recorded here instead.
