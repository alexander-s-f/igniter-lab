# lab-jetbrains-import-aware-compile-p6-v0

Proof doc for card `LAB-JETBRAINS-IMPORT-AWARE-COMPILE-P6` — make the JetBrains
plugin compile an importing `.ig` file *together with its imported project modules*,
so the native `igniter_compiler` resolves cross-module declarations and stops emitting
false `OOF-P1 Unresolved field: …` diagnostics.

**Status:** CLOSED. **Skill:** idd-agent-protocol (verify-first; the live compiler is the
authority, not this card). **Lane:** lang / JetBrains plugin / compiler context.

> Plugin-side only. No Rust compiler / language-canon changes; no global `OOF-P1`
> suppression; no whole-project compile; unsaved editor text still honoured; no
> source-editing quickfixes; color-scheme XML untouched (P5).

## Root cause (verified live, not assumed)

The native CLI is multi-file — `igniter_compiler compile A.ig B.ig … --out OUT.igapp` —
and its import resolution / `OOF-IMP*` validation only runs when **more than one**
source is passed (`igniter-compiler/src/main.rs:64`: `if source_paths.len() == 1 { single } else { multifile }`).
The plugin compiled only the current temp file, so an importing file lost its imported
type declarations and the typechecker reported them as unresolved.

Reproduced with the release binary on the card's fixture (corrected to the syntax the
live compiler accepts — `type T { … }`, list type `Collection[String]`):

| Invocation | Result |
|---|---|
| `compile webhook.ig` (single) | **7 × `OOF-P1 Unresolved field: CallrailCall.*`**, exit 1 |
| `compile types.ig webhook.ig` (multi) | **0 diagnostics**, exit 0 |
| `compile webhook.ig types.ig` (reversed) | 0 diagnostics — resolution is order-independent |
| multi-file with a genuinely missing import | **`OOF-IMP2 unknown import path 'TotallyMissingModule'`** (compiler authority) |
| single-file with a missing import | no `OOF-IMP*` — single-file path skips import validation |

## What was built

### Pure planner — `compiler/IgniterImportCompilePlanner` (IntelliJ-free)

- `moduleNameOf(text)` — first `module X` path.
- `importedModules(text)` — non-stdlib imported module paths, in order, de-duplicated;
  handles `import Foo.Bar` and selective `import Foo.Bar.{ Name }` (module path is the
  part before `.{`).
- `isStdlib(path)` — `stdlib` / `stdlib.*` (compiler-owned; never resolved to a file).
- `resolve(currentModule, imports, index)` — transitive closure over a
  `module path -> ModuleEntry` graph, with a visited set; **excludes the current module**
  (so its on-disk copy is never passed beside the in-editor temp copy → no duplicate
  module); unknown modules are skipped (the compiler reports them); output is sorted for
  deterministic source-arg ordering.
- `scanProject(root, excludePath)` — thin filesystem walk building the module index,
  skipping `.git/.idea/.gradle/build/target/out/dist/node_modules`, capped at 5000 files,
  first-file-wins per module.

### Compiler service — `compiler/IgniterCompilerService`

`compile(sourceFile, outRoot, extraSources = emptyList())` now builds
`compile <sourceFile> <extraSources…> --out OUT.igapp`. The current file stays first;
the default empty list preserves the original single-file behaviour byte-for-byte.

### Wiring — `model/IgniterModelService.build` (the key design call)

Verify-first turned up a constraint the card could not have known: in multi-file mode the
compiler emits a **merged** `sourcemap.json` / `semantic_ir_program.json` under a synthetic
`Lab.Multifile.Universe` (`source_file: multifile:<hash>`), whose line/col are
merged-universe coordinates — **not** the current editor's — and typecheck diagnostics
come back with `line: null`. Also, a *failing* single-file compile of an importing file
already produced **no** model artifacts, so the model is EMPTY for those files today.

So the wiring splits the two concerns:

- **Model** (navigation / inlays / structure) — always from the **current file compiled
  alone**, keeping line/col in editor coordinates (or EMPTY on failure, exactly as before).
- **Diagnostics** — when the file has resolvable non-stdlib imports, from the
  **import-aware multi-file compile** (false `OOF-P1` gone; `OOF-IMP*` authoritative);
  otherwise from the standalone compile (unchanged).

Net effect for an importing file: **strictly better** — diagnostics become correct while
the model is no worse than today. Files with no imports take exactly one compile (the old
path). Files with imports take two compiles (one current-only for the model, one
import-aware for diagnostics); the redundancy is the honest cost of keeping model
coordinates correct without per-file sourcemap support.

The explicit **`CompileIgniterFileAction`** uses the same import-aware resolution when a
project is available.

## Verification

```bash
cd igniter-jetbrains-plugin
./gradlew test --rerun-tasks   # BUILD SUCCESSFUL — 36 tests, 0 failures, 0 skipped
./gradlew clean buildPlugin    # -> build/distributions/igniter-jetbrains-plugin-0.1.0.zip
```

### Tests (36 total = 23 prior + 13 new; live proofs ran, not skipped)

| Class | Tests | Covers |
|---|---|---|
| `compiler.IgniterImportCompilePlannerTest` | 9 | parse module/imports, stdlib filter, selective-import module path, direct + transitive resolve (cycle-safe), current-module exclusion + unknown-skip, deterministic order, `scanProject` (module→file, exclude current, skip build dirs) |
| `IgniterImportAwareCompileProofTest` | 4 | live binary: **baseline single-file shows false `OOF-P1`** (acc. 2); **current + planner-resolved import → no false `OOF-P1`** (acc. 1); **stdlib import needs no file** (acc. 3); **missing non-stdlib import → `OOF-IMP*`** (acc. 4) |
| (prior P1–P3 suites) | 23 | unchanged, all green (acc. 6) |

Fixture: `src/test/resources/fixtures/import_aware/{types.ig,webhook.ig}` — the card's
`CallRouterTypes` / `CallRouterWebhook` example, adjusted only to the syntax the live
compiler accepts (intent preserved).

### Command-line shape — before / after

```
before:  igniter_compiler compile <current-temp.ig> --out OUT.igapp
after :  igniter_compiler compile <current-temp.ig> <imported-a.ig> <imported-b.ig> … --out OUT.igapp
         (only when non-stdlib imports resolve to project files; else unchanged)
```

## Acceptance ledger

| # | Requirement | Outcome |
|---|---|---|
| 1 | two-file fixture compiles via plugin path without false `OOF-P1` | ✅ proof test 2 |
| 2 | current-file-only still shows the old failure (baseline) | ✅ proof test 1 |
| 3 | `stdlib.*` imports need no project file | ✅ proof test 3 + planner filter |
| 4 | missing non-stdlib import → compiler `OOF-IMP*`, not a plugin guess | ✅ proof test 4 |
| 5 | unsaved current editor text used for the current file | ✅ unchanged: `IgniterModelService` writes the temp source from editor text; imported files read from disk (v0) |
| 6 | existing single-file cases still pass | ✅ 23 prior tests green; no-import path unchanged |
| 7 | `./gradlew test --rerun-tasks` passes; report count | ✅ **36** tests, 0 fail, 0 skip |
| 8 | fresh plugin zip built; record path | ✅ `igniter-jetbrains-plugin/build/distributions/igniter-jetbrains-plugin-0.1.0.zip` |

## Remaining limits (explicit)

- **Transitive imports are implemented** (BFS with a visited set), beyond the card's
  direct-only minimum.
- **The semantic model stays current-file-only for importing files.** Import-aware
  *navigation/inlays* would need the compiler to emit per-file source spans in multi-file
  mode (today it emits merged-universe coordinates). That is a separate, compiler-side
  follow-up — not attempted here.
- **Importing files trigger two compiler invocations** (model + diagnostics). Cached per
  content hash; native compiler. A per-file sourcemap would let both collapse to one.
- **Project scan** walks `project.basePath` per cache-miss (skipping build/VCS dirs,
  capped). Fine for v0; a watched module index could replace it later.
- GUI gestures (annotation placement, quickfix, inlays, Ctrl+Click) remain the
  human/robot smoke deferred since P4; this card is proven headlessly + via the live
  compiler. Next route: install the zip in RubyMine and re-check the real `webhook.ig`.

## Boundaries honoured

No Rust compiler / canon change; no global `OOF-P1` suppression (the compiler decides);
no whole-project compile (only the resolved import graph); unsaved current text honoured;
no source-editing quickfix; color-scheme XML untouched.
