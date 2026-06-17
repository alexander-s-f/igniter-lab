# LAB-JETBRAINS-COLOR-SCHEME-XML-P5

Status: CLOSED
Lane: lang / JetBrains plugin / GUI-smoke follow-up
Skill: idd-agent-protocol
Owner: next agent

## Goal

Fix the GUI-only defect found by `LAB-JETBRAINS-RUNIDE-SMOKE-P4`: the bundled Igniter color-scheme
XML files contain `--` inside XML comments, so IntelliJ reports `EditorColorsManagerImpl` `SEVERE`
and does not load the plugin's default syntax colors.

This is a tiny resource hygiene fix. It does not change the language, compiler, annotator,
quickfixes, inlays, navigation, or settings model.

## Verify-first anchors

Read before editing:

- `lab-docs/lang/lab-jetbrains-runide-smoke-p4-v0.md`
- `.agents/work/cards/lang/LAB-JETBRAINS-RUNIDE-SMOKE-P4.md`
- `igniter-jetbrains-plugin/src/main/resources/colorSchemes/IgniterLight.xml`
- `igniter-jetbrains-plugin/src/main/resources/colorSchemes/IgniterDark.xml`

Observed P4 finding:

- `IgniterLight.xml:118` contains `<!-- #D9694A  --oof  ·  bad character -->`
- `IgniterDark.xml` contains comments such as `--ignite`, `--amber`, `--ember`, `--grey-3`,
  `--grey`, `--oof`
- XML forbids `--` inside comments; IntelliJ logs `String '--' not allowed in comment`

Live files beat this card if line numbers drift.

## Scope

Allowed:

1. Edit only the two color-scheme XML resource files if possible.
2. Replace illegal `--token` comment text with legal wording that preserves the design-token hint,
   for example:
   - `token: ignite`
   - `design token ignite`
   - `ignite token`
   Do not use `--` anywhere inside XML comments.
3. Add a focused test if the plugin already has a convenient resource/XML validation test harness.
   If no harness exists, do not invent a large one; rely on Gradle + `runIde` smoke evidence.
4. Record exact verification in a proof doc.

Closed:

- no `.ig` compiler/language changes;
- no annotator/quickfix/inlay/navigation changes;
- no palette redesign;
- no settings redesign;
- no external network;
- no source-editing quickfixes.

## Acceptance

1. No `--` remains inside XML comments in `IgniterLight.xml` or `IgniterDark.xml`.
2. `./gradlew test --rerun-tasks` still passes.
3. A `runIde` smoke or equivalent resource-load proof shows the previous
   `EditorColorsManagerImpl` / `String '--' not allowed in comment` error is gone.
4. Plugin still loads in the sandbox, or any launch failure is classified and not caused by the
   color-scheme XML.
5. Proof doc names the exact files/lines fixed and exact commands run.
6. No unrelated plugin files are changed.

## Suggested verification

```bash
cd igniter-jetbrains-plugin
./gradlew test --rerun-tasks

rg -n "<!--[^\\n]*--[^>]" src/main/resources/colorSchemes

IGNITER_COMPILER=../igniter-compiler/target/release/igniter_compiler ./gradlew runIde
```

For the `runIde` proof, it is enough to launch, wait for `idea.log`, confirm:

- `Loaded custom plugins: Igniter Language (0.1.0)`
- no `EditorColorsManagerImpl` `String '--' not allowed in comment`

Then close the IDE. Do not try to exercise editor gestures in this card.

## Deliverables

- code/resource fix in the color-scheme XML files;
- proof doc: `lab-docs/lang/lab-jetbrains-color-scheme-xml-p5-v0.md`;
- close this card with:
  - changed files;
  - exact Gradle result;
  - runIde/log result;
  - remaining GUI surfaces, if any, explicitly out of scope.

## Next route

After P5:

- human-run or robot-driven GUI smoke for diagnostic / quickfix / inlay / Ctrl+Click gestures;
- no language/compiler follow-up implied by this card.

---

## Closing Report (2026-06-17)

Proof doc: `lab-docs/lang/lab-jetbrains-color-scheme-xml-p5-v0.md`.

**Changed files** (2, comment text only — no hex/keys/palette change):
- `igniter-jetbrains-plugin/src/main/resources/colorSchemes/IgniterDark.xml` — lines
  9, 17, 24, 55, 62, 117: `--<token>` → `token: <token>`.
- `igniter-jetbrains-plugin/src/main/resources/colorSchemes/IgniterLight.xml` — line
  118: `--oof` → `token: oof`.

**Gradle result.** `./gradlew test --rerun-tasks` → BUILD SUCCESSFUL,
**23 tests, 0 skipped, 0 failures**. `rg '<!--[^\n]*--[^>]' src/main/resources/colorSchemes`
→ no matches; `xmllint --noout` → OK for both files.

**runIde / log result.** `IGNITER_COMPILER=../igniter-compiler/target/release/igniter_compiler ./gradlew runIde`
(prev log archived to `idea.log.p4`). Fresh `idea.log` shows
`Loaded custom plugins: Igniter Language (0.1.0)` and `igniter.symbols` index built; a
grep for `EditorColorsManagerImpl` / `String '--' not allowed in comment` returns
nothing. **0 SEVERE** this run (P4 had 15); the 5 remaining WARN are standard
platform/offline-sandbox noise, none from the plugin.

**Remaining GUI surfaces (explicitly out of scope).** Editor gestures — diagnostic
annotation, `PLUGIN-001` quickfix, inlay render, Ctrl+Click navigation — were not
exercised; they stay deferred to a future human-run / `runIdeForUiTests` GUI smoke.

Acceptance 1–6: all met.
