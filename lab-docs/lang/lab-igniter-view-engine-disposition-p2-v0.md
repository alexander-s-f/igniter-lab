# lab-igniter-view-engine-disposition-p2-v0 — view-engine disposition map

**Card:** `LAB-IGNITER-VIEW-ENGINE-DISPOSITION-P2` · **Delegation:** `OPUS-VIEW-ENGINE-DISPOSITION-A`
**Status:** READINESS / DISPOSITION (no moves). Forensic disposition of the three `igniter-view-engine`
locations. **No `rm`/`git rm`/`mv`/copy/rename, no generated-output cleanup, no `.gitignore` change, no
canon.**
**Authority:** Lab disposition. Verified against the live tree + git 2026-06-19.

## 1. Executive summary

**Key correction to repo-boundary P1:** the lab `igniter-view-engine/` is **NOT merely historical** — it
is a **LIVE dependency of `igniter-ide`**. The Tauri IDE resolves `igniter-view-engine/out/…`,
`fixtures/…`, `igniter_view_runtime.js`, and even runs `run_mock_session_runner_hmac_proof.rb` via
`resolve_workspace_path(...)`, which (per its own comment) "go[es] up from igniter-ide to igniter-lab"
→ it reads the **lab-root copy**. So:
- **`igniter-lab/igniter-view-engine/` → KEEP_LIVE** (active `igniter-ide` preview/runtime backend; its
  generated `out/` is gitignored, so the IDE expects it to be *run* locally). Mark its dual role; do not
  move/rename until the IDE's hardcoded paths are refactored.
- **`igniter-lab/igniter-compiler/igniter-view-engine/` → DELETE_CANDIDATE** (0 files, empty stub, no
  referrers — the IDE points at the lab-root copy).
- **`../igniter-view-engine/` (workspace sibling) → ARCHIVE_CANDIDATE** (44-file stale copy; the IDE does
  NOT read it; verify no other consumer, then archive).

"view-engine" is **not globally superseded**: it is the historical IVF predecessor whose `.igv` + grammar
seeded the live frame-ui/ViewArtifact line, AND it remains the IDE's live view backend. Git is clean
(only this card untracked).

## 2. Three-location inventory

| Location | Size | Files | Layout | Manifest | Git |
|---|---|---|---|---|---|
| `igniter-lab/igniter-view-engine/` | **11M** | **1751** (1340 json, 198 ig, 172 rb, 14 igv, 10 md, 10 html, 4 js, 1 ebnf, .gitignore) | README, `lib`, `fixtures`, `proofs`, `docs`, `out`, `igniter_view_runtime.js`, `ivf_p2_browser_proof.html`, ~16 `run_*.rb`/`run_*.js` | none (JS/Ruby tree, **not a Cargo crate**); has own `.gitignore` (ignores `out/ tmp/ log/ node_modules/ dist/ build/`) | tracked (source); `out/` **gitignored** |
| `igniter-lab/igniter-compiler/igniter-view-engine/` | **0 B** | **0** | only an (empty) `out/` | none | effectively empty/gitignored stub |
| `../igniter-view-engine/` (sibling) | 432K | **44** (23 ig, 11 rb, 7 json, 3 html) | `fixtures`, `out`, `proofs` (no `lib`/README/`.igv`/`.ebnf`) | none | outside lab |

The lab copy's bulk (1283 of 1340 json) is in `out/`, which **is already in `.gitignore`** — so the 11M
is mostly local generated output, **not tracked architectural weight**. The tracked content is the
source: `lib`, `fixtures`, the **14 `.igv`** files, the **`.ebnf` grammar**, README/docs/proofs, and the
`run_*` proof runners.

## 3. Source / proof / generated classification

| Bucket | What | Where |
|---|---|---|
| **AUTHOR_SOURCE** | `lib/`, `fixtures/`, 14 `.igv`, `.ebnf` grammar, `igniter_view_runtime.js`, `run_*.rb`/`run_*.js`, README | lab copy (tracked) |
| **PROOF_EVIDENCE** | `proofs/`, `docs/`, `ivf_p2_browser_proof.html`, 10 md | lab copy (tracked) |
| **GENERATED_OUTPUT** | `out/` (1283 json) — **gitignored** | lab copy `out/` |
| **GENERATED_OUTPUT (empty)** | empty `out/` stub | `igniter-compiler/igniter-view-engine/` |
| **STALE_COPY** | 44-file subset (no lib/grammar/runtime) | `../igniter-view-engine/` |

The generated `out/` must not make the tree look heavier than its real (source) footprint — but note the
IDE *consumes* `out/` at runtime, so it is generated-yet-load-bearing-for-the-IDE.

## 4. Reference / coupling table

| Referrer | What it references | Class |
|---|---|---|
| **`igniter-ide/src-tauri/{lib.rs,commands.rs}`** | `igniter-view-engine/out/*`, `/fixtures/*`, `/igniter_view_runtime.js`, runs `/run_mock_session_runner_hmac_proof.rb` (20+ refs via `resolve_workspace_path` → **lab-root copy**) | **ACTIVE_DEPENDENCY** |
| `igniter-ide/src/lib/components/ViewInspector.svelte` | view-engine output rendering | ACTIVE_DEPENDENCY (UI) |
| `igniter-apps/*/PRESSURE_REGISTRY.md`, `web_router/{report,types}.ig`, `web_router/PRESSURE_REGISTRY.md` | provenance notes ("pulled from `rack_core`"), `web_router` | HISTORICAL_EVIDENCE (web_router itself now lives in `igniter-apps`) |
| `lab-docs/governance/lab-web-router-baseline-v0.md`, repo-boundary P1 | baselines/maps | HISTORICAL_EVIDENCE |
| `igniter-machine/tests/{machine_tests,capability_io_*}.rs` | `../ln/web_router`, `../ln/fixtures/...` | **UNKNOWN / likely STALE** — `ln` is **absent** in `igniter-lab/` now; those paths don't resolve (a separate coupling concern owned by the generated-output-hygiene card) |

**`web_router`/`rack_core`/`../ln` focus:** `web_router` is now an authored app in
`igniter-apps/web_router` (P-cards); the view-engine `fixtures/rack_core` is its **historical origin**.
The machine-test `../ln/...` paths reference a sibling `ln` that **does not currently exist** in the lab
root → flag as stale/needs-verify (not a view-engine question; hand to the hygiene card).

## 5. Frame-ui comparison (no overclaim)

- The **live Rust UI architecture** is the **frame-ui** stack (`igniter-frame`/`ui-kit`/`console`/`3d`/
  `gui`) + `ViewArtifact`/`.igv`. The `.igv` dialect and the `.ebnf` grammar in the view-engine tree are
  its **lineage** — frame-ui/ViewArtifact descend from IVF.
- BUT `igniter-view-engine` is **still the live preview/runtime backend for `igniter-ide`** (it reads the
  view-engine `out/` + fixtures + runtime.js). So the accurate statement is:

> "view-engine" is superseded **as the name for new Rust UI authoring** (that is now frame-ui +
> ViewArtifact/`.igv`), but the IVF view-engine tree is **still a live dependency of `igniter-ide`** and
> is **not deprecated or removable**.

This corrects P1's "historical PROOF_FIXTURE, superseded by frame-ui" → it is KEEP_LIVE for the IDE.

## 6. Disposition per location

| Location | Disposition | Reason |
|---|---|---|
| `igniter-lab/igniter-view-engine/` | **KEEP_LIVE** | active `igniter-ide` dependency (out/ + fixtures + runtime.js + ruby proof); also IVF lineage of frame-ui/.igv. Add a STATUS marker; **MOVE only after the IDE's hardcoded `resolve_workspace_path("igniter-view-engine/…")` is refactored**. |
| `igniter-lab/igniter-compiler/igniter-view-engine/` | **DELETE_CANDIDATE** | 0 files, empty stub, no referrers (IDE uses lab-root copy). Safe to delete under the hygiene card. |
| `../igniter-view-engine/` (sibling) | **ARCHIVE_CANDIDATE** | 44-file stale subset; the IDE reads the lab copy, not this; verify no other consumer, then archive. (Lean NEEDS_HUMAN_DECISION since it's a workspace sibling outside lab.) |

**No move/archive/delete performed in this card.**

## 7. Risks and non-actions

- **Deleting generated `out/`** (lab) → would break `igniter-ide` at runtime until re-run; `out/` is
  gitignored but **load-bearing for the IDE**. Do NOT clean it blindly.
- **Deleting fixtures** (rack_core etc.) → RISK: IDE reads `fixtures/`; and the machine `../ln` paths may
  (if `ln` is restored) point here. Verify before any deletion.
- **Moving the lab copy** → breaks the IDE's hardcoded `resolve_workspace_path("igniter-view-engine/…")`
  + doc/card links → needs a path-sweep + IDE refactor first.
- **Leaving 3 "view-engine" names** → ongoing confusion; mitigated by a STATUS marker, not a rename.
- **Renaming "view-engine"** → overclaim; the IDE depends on the literal name/path. Do NOT rename.
- **Confusing frame-ui with old view-engine** → they coexist (live Rust UI = frame-ui; IDE preview
  backend = IVF view-engine); the marker + this packet clarify.

## 8. Smallest next cleanup card

**`LAB-IGNITER-VIEW-ENGINE-STATUS-MARKER-P3`** *(no-code, 1 file)* — add a `STATUS.md` (or a header note
to the existing README) in `igniter-lab/igniter-view-engine/` stating: (a) it is the historical IVF
predecessor of the frame-ui/ViewArtifact/`.igv` line; (b) it is **still a live `igniter-ide` preview
backend** (out/ + fixtures + runtime.js); (c) `out/` is gitignored generated output; (d) the
compiler-nested `igniter-view-engine/out` stub and the `../igniter-view-engine` sibling are
delete/archive candidates pending a hygiene card. No deletion. (The 0-byte compiler stub deletion is
even smaller but is a *deletion* → it belongs to `LAB-IGNITER-LAB-GENERATED-OUTPUT-HYGIENE-P2`.)

## 9. Parallel agent notes

- **Gemini:** broad reference census — `rg` over all docs/cards/fixtures for `igniter-view-engine`/`ivf`/
  `rack_core`/`web_router` and a deterministic listing diff of the lab vs sibling copies. One lab note.
- **Sonnet:** critique the supersession wording (ensure "superseded as a name, live for the IDE" is not
  over- or under-stated) and the KEEP_LIVE call.
- **Codex:** verify git-tracked status of each tree, confirm `resolve_workspace_path` resolves to the lab
  copy at runtime, check whether `ln` exists/needed, and execute any later mechanical cleanup ONLY under
  the hygiene/marker cards.
- **Opus:** this synthesis + the disposition table + next-card.

## 10. How this feeds repo-boundary P1

- **Corrects P1:** the lab `igniter-view-engine/` is reclassified from "historical PROOF_FIXTURE" to
  **KEEP_LIVE (igniter-ide dependency)** — it must NOT be archived/moved before the IDE is refactored.
- **Reduces noise safely:** only the 0-byte compiler stub is a clean delete-candidate; the sibling is an
  archive-candidate; neither touches the IDE.
- **Separates generated from architecture:** lab `out/` is gitignored generated (yet IDE-load-bearing);
  it should not inflate architectural weight in the split analysis.
- **Clarifies UI ownership:** live Rust UI = frame-ui; the view-engine is the IDE's preview backend +
  IVF lineage — both real, distinct.
- **Avoids premature extraction:** the IDE's hardcoded `igniter-view-engine` paths + the absent `../ln`
  are concrete blockers to moving either the view-engine or the machine fixtures before a path-sweep.

---

*Disposition only. Compiled 2026-06-19 against the live tree + git (clean but this card). No files moved/
deleted/copied/renamed. Headline: lab view-engine = KEEP_LIVE (igniter-ide dep), compiler stub =
DELETE_CANDIDATE, sibling = ARCHIVE_CANDIDATE; next = a 1-file STATUS marker.*
