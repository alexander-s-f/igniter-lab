# LAB-JETBRAINS-IMPORT-AWARE-COMPILE-P6

Status: CLOSED
Lane: lang / JetBrains plugin / compiler context
Skill: idd-agent-protocol
Owner: next agent

## Goal

Fix the real RubyMine/JetBrains plugin compile-context gap:

```text
current .ig file imports sibling modules
  -> plugin currently invokes igniter_compiler with ONLY the current temp file
  -> imported type declarations are missing
  -> false OOF-P1 unresolved-field diagnostics
```

The Rust compiler already supports multi-file input:

```bash
igniter_compiler compile SOURCE [SOURCE ...] --out OUT.igapp
```

This card is plugin-side only: make editor analysis and explicit compile invoke the compiler with
the current file plus its imported project `.ig` modules.

## User-observed symptom

In RubyMine, `webhook.ig`:

```ig
module CallRouterWebhook
import CallRouterTypes
import stdlib.collection.{ count }
```

compiles fine only when no imports are required. With imports, the plugin emits false diagnostics such
as:

```text
OOF-P1 Unresolved field: CallrailCall.customer_phone
OOF-P1 Unresolved field: CallrailCall.tracking_phone
OOF-P1 Unresolved field: CallrailCall.webhooks
```

This is not a typechecker bug if the same program compiles when the imported module file is passed to
`igniter_compiler`.

## Verify-first anchors

Read before editing:

- `igniter-jetbrains-plugin/src/main/kotlin/com/igniter/plugin/model/IgniterModelService.kt`
  - currently writes current editor text to a temp file and calls `compile(src.toFile(), dir)`.
- `igniter-jetbrains-plugin/src/main/kotlin/com/igniter/plugin/compiler/IgniterCompilerService.kt`
  - currently builds `listOf(binary, "compile", sourceFile.absolutePath, "--out", ...)`.
- `igniter-jetbrains-plugin/src/main/kotlin/com/igniter/plugin/actions/CompileIgniterFileAction.kt`
  - explicit "Compile Now" action should use the same import-aware path where possible.
- `igniter-compiler/src/main.rs`
  - CLI accepts `compile SOURCE [SOURCE ...] --out OUT.igapp`.
- `igniter-compiler/src/multifile.rs`
  - import validation / `compile_units` are already compiler-side authority.
- P1/P2/P3/P4/P5 JetBrains docs/cards for existing tested surfaces.

Live code wins over this card if details drift.

## Scope

Implement a small import-aware compile path for JetBrains plugin analysis.

Preferred shape:

1. Add a pure-ish planner/resolver for module sources, e.g. `IgniterImportCompilePlanner`.
2. Given the current `.ig` file path + current editor text:
   - parse `module ...` and top-level `import ...` lines lightly;
   - ignore `stdlib.*` imports (compiler owns them);
   - scan project `.ig` files to build `module_path -> file`;
   - include direct imported module files.
3. If cheap and not risky, resolve transitive imports too, with a visited set.
   Direct imports are the minimum acceptable P6; transitive can be P6b if it widens too much.
4. Preserve unsaved current editor text:
   - current file must be compiled from the temp copy containing editor text;
   - imported files may be read from disk in v0.
5. Extend `IgniterCompilerService` to invoke:

   ```text
   igniter_compiler compile <current-temp.ig> <imported-a.ig> ... --out <out>.igapp
   ```

6. Use the same import-aware path from:
   - `IgniterModelService.analyze(...)` (annotator, inlays, navigation/model);
   - explicit `CompileIgniterFileAction` if a project context is available.

Keep the fallback simple: if import resolution cannot find a module, still call the compiler with the
sources you have and let compiler-side `OOF-IMP*` diagnostics be the authority.

## Hard boundaries

- Do NOT change Rust compiler import semantics.
- Do NOT change language canon.
- Do NOT suppress `OOF-P1` globally.
- Do NOT compile the entire project by default unless the narrow import graph cannot be built.
- Do NOT require saved current editor text for analysis; unsaved current text must still be honored.
- Do NOT introduce source-editing quickfixes.
- Do NOT touch color-scheme XML (P5 already closed that).

## Acceptance

1. A two-file fixture where `webhook.ig` imports `CallRouterTypes` compiles through the plugin path
   without false `OOF-P1` unresolved-field diagnostics.
2. The same fixture compiled as current-file-only still demonstrates the old failure in a unit/proof
   test or documented baseline.
3. `stdlib.*` imports do not require a project file.
4. Missing non-stdlib import produces compiler-authoritative import diagnostics (`OOF-IMP*`), not a
   plugin fallback guess.
5. Unsaved current editor text is used for the current file (temp source wins over on-disk current).
6. Existing single-file cases still pass.
7. `./gradlew test --rerun-tasks` passes; report exact test count.
8. Build a fresh plugin zip after the fix (`./gradlew clean buildPlugin`) and record path.

## Test guidance

Prefer JVM tests over IDE fixture tests if possible:

- pure planner tests:
  - parse imports from text;
  - ignore `stdlib.*`;
  - map `CallRouterTypes` to `types.ig`;
  - stable ordering of source args;
  - missing import behavior.
- live compiler proof:
  - create temp project with `types.ig` + `webhook.ig`;
  - invoke the same service/planner path or the exact constructed compiler command;
  - assert false `OOF-P1` diagnostics disappear when imported module is passed.

If IntelliJ project APIs make service-level tests heavy, keep a pure planner plus an integration proof
around `igniter_compiler compile current imported --out ...`.

## Suggested fixture shape

Minimal enough to isolate the issue:

```ig
-- types.ig
module CallRouterTypes

type CallrailCall = {
  id: String,
  call_id: String,
  customer_phone: String,
  tracking_phone: String,
  webhooks: [String],
  operator_id: String
}
```

```ig
-- webhook.ig
module CallRouterWebhook
import CallRouterTypes
import stdlib.collection.{ count }

pure contract AppendWebhook {
  input call : CallrailCall
  input webhook_type : String
  compute next = {
    id: call.id,
    call_id: call.call_id,
    customer_phone: call.customer_phone,
    tracking_phone: call.tracking_phone,
    webhooks: concat(call.webhooks, [webhook_type]),
    operator_id: call.operator_id
  }
  output next : CallrailCall
}

pure contract WebhookCount {
  input call : CallrailCall
  compute n = count(call.webhooks)
  output n : Integer
}
```

Adjust syntax only if the live compiler requires it; do not change the intent.

## Verification commands

```bash
cd igniter-jetbrains-plugin
./gradlew test --rerun-tasks
./gradlew clean buildPlugin
```

Optional if time allows:

```bash
IGNITER_COMPILER=../igniter-compiler/target/release/igniter_compiler ./gradlew runIde
```

Then check in RubyMine manually against the user's import-heavy file.

## Deliverables

- Code fix in the JetBrains plugin.
- Tests/proof fixture.
- Proof doc:
  `lab-docs/lang/lab-jetbrains-import-aware-compile-p6-v0.md`
- Close this card with:
  - changed files;
  - exact command line shape before/after;
  - tests and counts;
  - fresh plugin zip path;
  - any remaining limits (for example direct-only imports if transitive is deferred).

## Next route

After P6:

- install fresh plugin zip in RubyMine and re-check the real `webhook.ig`;
- human-run / robot-driven GUI smoke for diagnostic, quickfix, inlay, Ctrl+Click gestures;
- transitive/project-wide import graph only if P6 intentionally ships direct-import-only.

---

## Closing Report (2026-06-17)

Proof doc: `lab-docs/lang/lab-jetbrains-import-aware-compile-p6-v0.md`.

**Changed / new files (plugin only):**
- NEW `src/main/kotlin/com/igniter/plugin/compiler/IgniterImportCompilePlanner.kt` — pure
  parse (`moduleNameOf`/`importedModules`/`isStdlib`) + transitive `resolve` (visited set,
  current-module excluded, deterministic) + thin `scanProject` filesystem index.
- `src/main/kotlin/com/igniter/plugin/compiler/IgniterCompilerService.kt` — `compile(...)`
  gains `extraSources: List<File> = emptyList()`; command now
  `compile <current> <extras…> --out OUT.igapp`.
- `src/main/kotlin/com/igniter/plugin/model/IgniterModelService.kt` — model from current-file
  compile (editor coordinates); diagnostics from import-aware multi-file compile when imports
  resolve, else standalone. Imports out-dir created.
- `src/main/kotlin/com/igniter/plugin/actions/CompileIgniterFileAction.kt` — explicit compile
  is import-aware when a project is available.
- NEW fixtures `src/test/resources/fixtures/import_aware/{types.ig,webhook.ig}`.
- NEW tests `compiler/IgniterImportCompilePlannerTest.kt` (9), `IgniterImportAwareCompileProofTest.kt` (4).

**Command-line shape before/after:**
- before: `igniter_compiler compile <current-temp.ig> --out OUT.igapp`
- after:  `igniter_compiler compile <current-temp.ig> <imported…> --out OUT.igapp`
  (only when non-stdlib imports resolve to project files; otherwise unchanged)

**Tests/counts:** `./gradlew test --rerun-tasks` → **36 tests, 0 skipped, 0 failures**
(23 prior + 9 planner + 4 live proof; the 4 import-aware live proofs ran against the real
release binary). Live behaviour verified: single-file → 7 false `OOF-P1`; current+import →
0 diagnostics (order-independent); missing import (multi-file) → `OOF-IMP2`.

**Fresh plugin zip:**
`igniter-jetbrains-plugin/build/distributions/igniter-jetbrains-plugin-0.1.0.zip`
(via `./gradlew clean buildPlugin`).

**Remaining limits:** transitive imports shipped (not direct-only). Semantic
model/inlays/navigation stay current-file-only for importing files — import-aware model
coordinates need per-file source spans from the compiler (multi-file currently emits merged
`Lab.Multifile.Universe` coordinates with `line:null` diagnostics); deferred as a
compiler-side follow-up. Importing files run two compiles (model + diagnostics), cached per
content hash. GUI gesture smoke remains the deferred human/robot route; next route = install
the zip in RubyMine and re-check the real `webhook.ig`.

Acceptance 1–8: all met.
