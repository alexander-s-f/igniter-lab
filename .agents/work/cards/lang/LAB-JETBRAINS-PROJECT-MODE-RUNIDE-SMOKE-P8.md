# Card: LAB-JETBRAINS-PROJECT-MODE-RUNIDE-SMOKE-P8

**Title:** runIde smoke for project-mode imports in real editor
**Skill:** idd-agent-protocol
**Lane:** standard / JetBrains GUI proof
**Status:** ✅ CLOSED — PASS — 2026-06-17
**Authority:** igniter-lab only; no canon impact; no production impact
**Builds on:** LAB-JETBRAINS-PROJECT-MODE-DELEGATION-P7 (CLOSED)
**Proof:** `lab-docs/lang/lab-jetbrains-project-mode-runide-smoke-p8-v0.md`

---

## Card Statement

Prove P7 in a real JetBrains IDE sandbox (`runIde`): an importing `.ig` file compiles
through project mode + overlay and no longer shows false `OOF-P1 Unresolved field`.

## Authority boundary (named before coding)

- **Decides behavior:** the live `igniter_compiler` + the running sandbox IDE with the
  P7 plugin.
- **Evidence only:** this card, the proof doc, the IDE log + compile reports + screenshot.
- **Authorized to change:** nothing — smoke/proof only. **No code changed.**
- **Closed surfaces:** compiler semantics, diagnostics, source-editing quickfixes, the
  user's real (non-sandbox) IDE.

## What was done

`./gradlew clean buildPlugin` + `./gradlew test --rerun-tasks` (35/0/0), then
`./gradlew runIde --args=<fixture>` with `IGNITER_COMPILER` set. Opened `webhook.ig`,
`broken.ig`, `solo.ig` in the sandbox editor; the plugin's annotator compiled each.
Captured the IDE log's compiler invocations, the produced `compilation_report.json`s,
and an editor screenshot.

## Acceptance — all met in a real IDE

1. Plugin loads, no `SEVERE` — `Loaded custom plugins: Igniter Language (0.1.0)`, 0 SEVERE/ERROR ✅
2. `webhook.ig` (import `CallRouterTypes`) → no false `OOF-P1` — project-mode report `ok`, `diagnostics: []`; editor green check, no red squiggle on `CallrailCall` ✅
3. Project-mode invocation shape — `--project-root … --entry CallRouterWebhook --overlay …=… --out …` (idea.log) ✅
4. Baseline explains the pre-P7 break — same-session single-file compile of `webhook.ig` → `OOF-P1` ✅
5. Missing-import `broken.ig` → `OOF-IMP2` ✅
6. No regression — `solo.ig` single-file only; project mode never invoked for `SoloMod` ✅
7. Proof doc records zip/sandbox, binary, log snippets, screenshot/textual summary ✅
8. BLOCKED fallback — n/a, GUI smoke completed ✅

## Verification (exact)

- Sandbox IDE: IntelliJ IDEA IC-233.11799.241 (2023.3) via `runIde`.
- Compiler: `igniter-compiler/target/debug/igniter_compiler` (6709760 B).
- Plugin zip: `build/distributions/igniter-jetbrains-plugin-0.1.0.zip` (184289 B).
- In-IDE invocation (acc 3):
  `igniter_compiler compile --project-root …/build/p8-fixture --entry CallRouterWebhook --overlay …/p8-fixture/webhook.ig=<buffer>/webhook.ig --out <buffer>/project/webhook.igapp`
- webhook project-mode report: `pass_result: ok`, `diagnostics: []`, source_units `[CallRouterTypes, CallRouterWebhook]`.
- webhook single-file (baseline): `pass_result: oof`, `[OOF-P1]`.
- broken project-mode report: `[OOF-IMP2]`. solo: single-file only.

## Notes

- Two IDEs were on the machine (user's real IDEA 2026.1.3 + the 2023.3 sandbox). All
  actions targeted only the sandbox window (`p8-fixture`, workspace path); the real IDE
  was never touched.
- No code changed; no speculative fixes. Smoke confirms the P7 implementation behaves
  identically in a real editor as in the headless/live-binary proofs.
