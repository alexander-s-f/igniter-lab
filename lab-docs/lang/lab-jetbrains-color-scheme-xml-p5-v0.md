# lab-jetbrains-color-scheme-xml-p5-v0

Proof doc for card `LAB-JETBRAINS-COLOR-SCHEME-XML-P5` — fix the GUI-only defect found by
`LAB-JETBRAINS-RUNIDE-SMOKE-P4`: the bundled Igniter color-scheme XML embedded `--`
inside `<!-- … -->` comments, so IntelliJ logged `EditorColorsManagerImpl` `SEVERE` and
did not load the plugin's default syntax colors at startup.

**Status:** CLOSED. **Skill:** idd-agent-protocol (observation-first; evidence is not authority).
**Lane:** lang / JetBrains plugin / GUI-smoke follow-up.

> Tiny resource-hygiene fix. No language / compiler / annotator / quickfix / inlay /
> navigation / settings changes. No `.ig` changes. No source-editing quickfixes.

## Root cause

XML forbids the literal `--` anywhere inside a comment body (only the closing `-->`
may contain it). The two bundled `additionalTextAttributes` schemes labelled design
tokens as `--ignite`, `--amber`, etc. inside comments, so `JDOMUtil.load` →
`com.fasterxml.aalto` threw `String '--' not allowed in comment` while
`EditorColorsManagerImpl` was loading the bundled scheme. The IDE booted (fell back to
default attributes) but the Igniter Ember/Paper palette never applied.

## Files / lines fixed

Each `--<token>` inside a comment was rewritten to `token: <token>` (legal, preserves
the design-token hint). Hex values and `<option>` attribute keys were untouched.

`src/main/resources/colorSchemes/IgniterDark.xml`:

| Line | Before | After |
|---|---|---|
| 9   | `<!-- #FF6A3D  --ignite  · bold -->` | `<!-- #FF6A3D  token: ignite  · bold -->` |
| 17  | `<!-- #F0A868  --amber   · type names -->` | `<!-- #F0A868  token: amber   · type names -->` |
| 24  | `<!-- #FFB07A  --ember   · numeric & bool literals -->` | `<!-- #FFB07A  token: ember   · … -->` |
| 55  | `<!-- #E7DDD2  --grey-3  · identifiers -->` | `<!-- #E7DDD2  token: grey-3  · identifiers -->` |
| 62  | `<!-- #9A8A7C  --grey  · operators & all punctuation -->` | `<!-- #9A8A7C  token: grey  · … -->` |
| 117 | `<!-- #D9694A  --oof  · bad character -->` | `<!-- #D9694A  token: oof  · bad character -->` |

`src/main/resources/colorSchemes/IgniterLight.xml`:

| Line | Before | After |
|---|---|---|
| 118 | `<!-- #D9694A  --oof  · bad character -->` | `<!-- #D9694A  token: oof  · bad character -->` |

No other files changed (acceptance 6).

## Verification (exact commands + results)

```bash
cd igniter-jetbrains-plugin

# Acceptance 1 — no '--' left inside any comment body (card's own check)
rg -n '<!--[^\n]*--[^>]' src/main/resources/colorSchemes
#  -> no matches  (clean)

# well-formedness, both files
xmllint --noout src/main/resources/colorSchemes/IgniterDark.xml   # -> OK
xmllint --noout src/main/resources/colorSchemes/IgniterLight.xml  # -> OK

# Acceptance 2 — tests still green
./gradlew test --rerun-tasks
#  -> BUILD SUCCESSFUL; tests=23 skipped=0 failures=0 errors=0

# Acceptance 3/4 — runIde resource-load proof (old log archived to idea.log.p4 first)
IGNITER_COMPILER=../igniter-compiler/target/release/igniter_compiler ./gradlew runIde
```

`runIde` evidence — `build/idea-sandbox/system/log/idea.log` (run 2026-06-17 13:23,
IntelliJ IDEA 2023.3 `IC-233.11799.241`, JBR 17, macOS):

```
[42]  INFO - #c.i.i.p.PluginManager - Loaded custom plugins: Igniter Language (0.1.0)
[812] INFO - #c.i.u.i.IndexDataInitializer - Index data initialization done … igniter.symbols …
```

- ✅ **Plugin loads** in the sandbox (acceptance 4) — and the `igniter.symbols` index
  still builds, so the plugin is healthy.
- ✅ **The defect is gone** (acceptance 3): a full grep for `EditorColorsManagerImpl`
  and `String '--' not allowed in comment` returns **nothing** this run.
- ✅ **Severity drop**: this run logged **0 SEVERE** (P4 had 15, all from the color
  scheme). The remaining 5 `WARN` are standard platform/offline-sandbox noise
  (`preload` service hint, missing `CFBundleURLTypes`, LaF `rowHeight`, empty trusted
  root certs offline, a `FilenameIndex`/`PluginUtil` init hint) — none from the plugin,
  none color-scheme related.

## Acceptance ledger

| # | Requirement | Outcome |
|---|---|---|
| 1 | no `--` inside XML comments in either scheme file | ✅ `rg` clean; `xmllint` OK |
| 2 | `./gradlew test --rerun-tasks` still passes | ✅ 23 tests, 0 fail, 0 skip |
| 3 | runIde / resource-load proof shows the error gone | ✅ no `EditorColorsManagerImpl` error; 0 SEVERE |
| 4 | plugin still loads, or launch failure classified | ✅ plugin loaded; `igniter.symbols` built |
| 5 | proof doc names exact files/lines + commands | ✅ above |
| 6 | no unrelated plugin files changed | ✅ only the two scheme XMLs |

## Out of scope / next route

Editor gestures (diagnostic annotation, `PLUGIN-001` quickfix, inlay render, Ctrl+Click)
were **not** exercised here — that is the keyboard/modifier-click GUI smoke deferred by
P4. Next route unchanged: a human-run or robot-driven (`runIdeForUiTests`) GUI smoke for
those four gestures. No language/compiler follow-up is implied by this card.

## Boundaries honoured

Comment text only; no hex/keys/palette redesign; no settings, annotator, quickfix, inlay,
navigation, compiler, or `.ig` changes; no external network (Marketplace `INFO`/`WARN`
lines are the expected offline-sandbox behaviour).
