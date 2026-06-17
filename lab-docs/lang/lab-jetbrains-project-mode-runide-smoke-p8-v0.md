# lab-jetbrains-project-mode-runide-smoke-p8-v0

Proof doc for card `LAB-JETBRAINS-PROJECT-MODE-RUNIDE-SMOKE-P8` — prove P7
(`LAB-JETBRAINS-PROJECT-MODE-DELEGATION-P7`) in a **real JetBrains IDE sandbox**
(`runIde`), not only headless tests: an importing `.ig` file compiles through
compiler project mode + overlay and shows no false `OOF-P1 Unresolved field`.

**Status:** CLOSED — PASS (GUI smoke completed in a real IDE). **Skill:**
idd-agent-protocol (verify-first; the live compiler + the running IDE are the
authority). **Lane:** standard / JetBrains GUI proof. **Builds on:** P7 (CLOSED).

> Smoke/proof only. No language/compiler changes; no diagnostic suppression; no
> source-editing quickfixes. No code was changed for this card.

## Environment / exact paths

| Item | Value |
|------|-------|
| Plugin zip | `igniter-jetbrains-plugin/build/distributions/igniter-jetbrains-plugin-0.1.0.zip` (184289 B) |
| Sandbox IDE | IntelliJ IDEA Community **build #IC-233.11799.241** (2023.3), via `./gradlew runIde` |
| Compiler binary | `igniter-compiler/target/debug/igniter_compiler` (6709760 B), passed via `IGNITER_COMPILER` env so the plugin resolves it with no GUI settings step |
| Fixture project | `igniter-jetbrains-plugin/build/p8-fixture/` — `types.ig` (`module CallRouterTypes`), `webhook.ig` (`module CallRouterWebhook` + `import CallRouterTypes`), `broken.ig` (`module BrokenConsumer` importing only a missing module), `solo.ig` (`module SoloMod`, no imports) |
| Sandbox IDE log | `igniter-jetbrains-plugin/build/idea-sandbox/system/log/idea.log` |

## Verify-first (before runIde)

```
./gradlew clean buildPlugin    # BUILD SUCCESSFUL → fresh zip (184289 B)
IGNITER_COMPILER=… ./gradlew test --rerun-tasks   # 35 passed / 0 failed / 0 skipped
```

## Smoke procedure (as executed)

1. `IGNITER_COMPILER=<debug binary> ./gradlew runIde --args="<…>/build/p8-fixture"` —
   launches the sandbox IDE with the plugin installed and the fixture project open.
2. The IDE loaded the plugin, opened the project, and indexed the four `.ig` files.
3. Opened `webhook.ig` in the editor (double-click in the Project tool window). The
   plugin's `ExternalAnnotator` (autoCompileOnSave = true) fired automatically.
4. Repeated for `broken.ig` (missing import) and `solo.ig` (no imports).
5. Captured: the IDE log's compiler-invocation lines, the produced `.igapp`
   `compilation_report.json` for each, and an editor screenshot.

The plugin reads the compiler path from `IGNITER_COMPILER`, so no Settings dialog
was needed (tier-restricted typing into the IDE was therefore unnecessary).

## Exact in-IDE compiler invocations (from idea.log)

`#com.igniter.plugin.compiler.IgniterCompilerService - Running:` lines, in order
(`…m` = the per-file editor-buffer temp dir; the overlay buffer holds the live
editor text):

```
1  igniter_compiler compile …m/be384b05/webhook.ig --out …m/be384b05/webhook.igapp
2  igniter_compiler compile --project-root …/build/p8-fixture --entry CallRouterWebhook \
       --overlay …/build/p8-fixture/webhook.ig=…m/be384b05/webhook.ig \
       --out …m/be384b05/project/webhook.igapp
3  igniter_compiler compile …m/df7864c7/broken.ig --out …m/df7864c7/broken.igapp
4  igniter_compiler compile --project-root …/build/p8-fixture --entry BrokenConsumer \
       --overlay …/build/p8-fixture/broken.ig=…m/df7864c7/broken.ig \
       --out …m/df7864c7/project/broken.igapp
5  igniter_compiler compile …m/9fce4f7d/solo.ig --out …m/9fce4f7d/solo.igapp
```

- #1/#3 are the single-file **model** compiles (editor coordinates — unchanged, P7 boundary).
- #2/#4 are the **diagnostics** compiles via project mode + overlay (importing files).
- #5 is `solo.ig`: single-file only. **Project mode was never invoked for `SoloMod`**
  (`grep -c "entry SoloMod" = 0`).

## Per-file compile reports (from each `.igapp/compilation_report.json`)

| File | Mode | pass_result | diagnostics |
|------|------|-------------|-------------|
| `webhook.ig` | single-file (model, baseline) | oof | `[OOF-P1]` — the documented pre-P7 false positive |
| `webhook.ig` | **project mode + overlay (diagnostics)** | **ok** | **`[]`** — source_units `[CallRouterTypes, CallRouterWebhook]` |
| `broken.ig` | project mode + overlay | oof | `[OOF-IMP2]` — compiler-authoritative missing import |
| `solo.ig` | single-file | (no project-mode compile emitted) | — |

## Acceptance matrix — all met in a real IDE

| # | Requirement | Result |
|---|-------------|--------|
| 1 | Plugin loads, no `SEVERE` plugin resource error | ✅ `Loaded custom plugins: Igniter Language (0.1.0)`; `grep -cE "SEVERE\| ERROR " idea.log = 0` |
| 2 | `webhook.ig` (import `CallRouterTypes`) compiles without false `OOF-P1 Unresolved field` | ✅ project-mode report `pass_result: ok`, `diagnostics: []`; editor shows green "no problems" check, no red squiggle on `input call : CallrailCall` |
| 3 | Invocation is project-mode shaped (`--project-root`, `--entry CallRouterWebhook`, `--overlay`, `--out`) | ✅ idea.log line #2 above |
| 4 | A baseline still explains why this was broken before P7 | ✅ same-session single-file compile of `webhook.ig` → `OOF-P1` (report `pass_result: oof`); project-mode compile of the same file → clean |
| 5 | Missing-import fixture surfaces `OOF-IMP*` | ✅ `broken.ig` project-mode report → `OOF-IMP2` |
| 6 | No regression to no-import `.ig` compile | ✅ `solo.ig` → single-file compile only; project mode never invoked for `SoloMod` |
| 7 | Proof records zip/sandbox, binary, log snippets, screenshot/textual summary | ✅ this doc |
| 8 | BLOCKED fallback if GUI smoke cannot complete | n/a — GUI smoke completed |

## Editor screenshot summary (acceptance 2 visual)

`webhook.ig` open in the sandbox editor: source lines `module CallRouterWebhook`,
`import CallRouterTypes`, `import stdlib.collection.{ count }`, `pure contract
WebhookCount { input call : CallrailCall … }`. The editor's top-right inspection
widget shows a **green check (no problems)**; there are **no red error underlines**,
in particular none on `CallrailCall` — the cross-module type that single-file
compilation cannot resolve and falsely flags as `OOF-P1`.

## Notes / honesty

- Two IntelliJ instances were present on the machine: the user's real IDEA 2026.1.3
  and the gradle `runIde` sandbox (IC-233 / 2023.3). All actions above were performed
  exclusively against the **sandbox** window (title `p8-fixture`, project path under
  `…/igniter-workspace/…/build/p8-fixture`). The real IDE was never touched.
- Auto-opening `webhook.ig` via a seeded `.idea/workspace.xml` did not take on a
  first project open; the file was opened by a single click in the sandbox's Project
  tool window. Benign startup warnings appeared in the log (Gradle JVM-compat
  `JavaVersion.parse("25")`, `MemorySizeConfigurator` VM-options) — none are `SEVERE`
  and none involve the plugin.

## Authority boundary

igniter-lab only. No compiler/plugin code changed. The running compiler and the live
IDE are the authority; this doc is evidence.
