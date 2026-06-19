# LAB-IGNITER-VIEW-ENGINE-DISPOSITION-P2 — view-engine disposition map

Status: CLOSED  
Lane: standard / readiness / cleanup-disposition  
Opened: 2026-06-19  
Delegate label: OPUS-VIEW-ENGINE-DISPOSITION-A  
Skill: idd-agent-protocol  

## Why This Card

`LAB-IGNITER-LAB-REPO-BOUNDARY-READINESS-P1` found three `igniter-view-engine`
locations and concluded they are probably **not three live forks**:

- `igniter-lab/igniter-view-engine/` — substantive historical JS proof/fixture tree;
- `igniter-lab/igniter-compiler/igniter-view-engine/` — likely generated/out-only stub;
- workspace sibling `../igniter-view-engine/` — likely stale archive/proof copy.

Before any repo split or cleanup, we need a focused disposition map: what is
source, what is generated, what is still referenced, what can later be archived
or removed, and what name should survive.

This card does **not** delete, move, or archive anything.

## Authority

Readiness / disposition only.

Allowed:
- Inspect all observed `igniter-view-engine` locations.
- Inspect references from tests, docs, cards, fixtures, scripts, and proof
  packets.
- Produce a disposition packet and close this card.
- Recommend follow-up archive/delete/move cards with exact candidate paths.

Not allowed:
- No `rm`, `git rm`, `git mv`, `mv`, or directory copy.
- No generated-output cleanup.
- No rewrite of compiler, frame, UI, console, or web code.
- No rename of the live frame/UI architecture.
- No canonical claim that "view-engine" is deprecated globally unless live
  evidence supports the narrower statement.
- No changing `.gitignore` in this card.

## Verify First

Run live checks from `igniter-lab`:

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
git status --short
du -sh igniter-view-engine igniter-compiler/igniter-view-engine ../igniter-view-engine 2>/dev/null
find igniter-view-engine -maxdepth 3 -type f | sort | sed -n '1,200p'
find igniter-compiler/igniter-view-engine -maxdepth 4 -type f | sort | sed -n '1,200p'
find ../igniter-view-engine -maxdepth 4 -type f | sort | sed -n '1,200p'
rg -n "igniter-view-engine|view-engine|view_engine|web_router|rack_core|igniter_view_runtime" .
rg -n "igniter-view-engine|view-engine|view_engine|web_router|rack_core|igniter_view_runtime" ..
```

Also inspect:

- `igniter-lab/lab-docs/lang/lab-igniter-lab-repo-boundary-readiness-p1-v0.md`
- `igniter-view-engine/README.md` if present
- `igniter-view-engine/lib/` if present
- `igniter-view-engine/fixtures/`
- `igniter-view-engine/proofs/`
- `igniter-view-engine/out/`
- `igniter-compiler/igniter-view-engine/out/`
- `../igniter-view-engine/fixtures/`
- `../igniter-view-engine/proofs/`
- any compiler/machine tests that refer to `web_router`, `rack_core`, or `../ln`.

Live tree wins. If a path does not exist anymore, record that as current truth.

## Questions To Answer

### 1. What exactly is in each location?

For each location, report:

- size;
- file counts by extension;
- top-level layout;
- source files vs generated output;
- docs/proofs/fixtures;
- last apparent role from README or proof docs;
- whether it has a manifest/package file;
- whether it is tracked by git.

### 2. Which files are source-of-truth vs generated?

Separate:

```text
AUTHOR_SOURCE     code, fixtures, README, hand-authored proof inputs
PROOF_EVIDENCE    proof docs, screenshots, expected outputs worth archiving
GENERATED_OUTPUT  out/, build/, compiled artifacts, transient render output
STALE_COPY        duplicate of a source/proof elsewhere
UNKNOWN           cannot classify without human decision
```

Do not let generated `out/` size make the source tree look more important than
it is.

### 3. What still references view-engine?

Produce a reference table:

- code references;
- test references;
- fixture references;
- docs/cards references;
- scripts/tooling references;
- workspace sibling references.

For each reference, classify whether it is:

```text
ACTIVE_DEPENDENCY     live tests/build rely on it
HISTORICAL_EVIDENCE   docs/proofs only
STALE_REFERENCE       points at old path/name with no live consumer
UNKNOWN               needs another check
```

Special focus: `web_router`, `rack_core`, and `../ln` fixture paths.

### 4. Is "view-engine" superseded by frame-ui?

Answer carefully.

Compare `igniter-view-engine` with the live frame/UI stack:

- `igniter-frame`
- `igniter-ui-kit`
- `igniter-console`
- `igniter-3d`
- `igniter-gui`
- `.igv` / ViewArtifact docs

Do not overclaim. The expected answer may be:

```text
"view-engine" is superseded as the name for the live Rust UI/frame direction,
but the old view-engine tree still contains historical fixtures/proofs.
```

Confirm or correct this from live evidence.

### 5. Are the three locations duplicates or distinct?

For the three observed locations, decide:

- same content duplicate;
- generated copy of another;
- stale archive copy;
- distinct proof track;
- empty/noise.

Use file hashes or deterministic listing comparison if useful, but do not spend
hours perfecting a forensic diff. The deliverable needs actionable disposition.

### 6. What should happen next?

Recommend a disposition for each location:

```text
KEEP_AS_ARCHIVE       keep but mark as historical/proof fixture
KEEP_LIVE             active surface, should stay discoverable
MOVE_CANDIDATE        later physical move/rename card needed
ARCHIVE_CANDIDATE     later archive card needed
DELETE_CANDIDATE      later deletion card needed
NEEDS_HUMAN_DECISION  cannot safely decide from evidence
```

No actual move/archive/delete in this card.

### 7. What is the smallest no-code cleanup follow-up?

Propose one smallest next card. Examples:

- add a README/status marker to historical `igniter-view-engine`;
- delete only the 0-byte generated stub later;
- move generated `out/` to ignored output later;
- consolidate sibling archive later.

Keep it smaller than a repo split.

### 8. What are the risks?

Name the risks of each possible action:

- deleting generated output;
- deleting fixtures;
- moving the lab copy;
- leaving stale duplicate names in place;
- renaming "view-engine" prematurely;
- confusing frame-ui with old view-engine.

### 9. What should Gemini/Sonnet/Codex do if parallelized?

Suggested split:

- **Gemini:** broad reference census (`rg` over docs/cards/fixtures) and file
  listing comparison. Output one lab note only.
- **Sonnet:** critique disposition wording and overclaims, especially whether
  "superseded" is too strong.
- **Codex:** verify git/tracked status and execute later mechanical cleanup only
  under a separate card.
- **Opus:** synthesize final disposition and next-card recommendation.

### 10. How does this feed repo-boundary work?

Explain how the result updates `LAB-IGNITER-LAB-REPO-BOUNDARY-READINESS-P1`:

- reduces noise before split;
- protects historical fixtures;
- separates generated output from architecture;
- clarifies whether view/UI lives under frame-ui now;
- avoids premature physical repo extraction.

## Deliverable

Write one packet:

```text
lab-docs/lang/lab-igniter-view-engine-disposition-p2-v0.md
```

Recommended structure:

1. Executive summary.
2. Three-location inventory.
3. Source/proof/generated classification.
4. Reference/coupling table.
5. Frame-ui comparison.
6. Disposition recommendation per location.
7. Risks and non-actions.
8. Smallest next cleanup card.
9. Parallel agent notes.
10. Closing acceptance map.

Then update this card with a closing report.

## Acceptance

- Git state checked before analysis.
- All three observed `view-engine` locations checked, or absence recorded.
- File counts/sizes/layouts captured for each location.
- References from code/tests/docs/cards/scripts searched.
- `web_router`, `rack_core`, and `../ln` fixture coupling investigated.
- Generated output is separated from source/proof evidence.
- Frame-ui comparison is evidence-based and avoids overclaiming.
- Each location gets one recommended disposition.
- No files are moved, deleted, copied, or renamed.
- Follow-up card recommendation is smaller than a repo split.

## Closing Report Template

Report:

- command evidence;
- inventory summary;
- active references found;
- generated vs source split;
- frame-ui/supersession conclusion;
- disposition table;
- smallest next cleanup;
- risks/non-actions;
- next cards.

---

## Closing report — 2026-06-19

**Deliverable:** `lab-docs/lang/lab-igniter-view-engine-disposition-p2-v0.md` (10 sections). No file
moved/deleted/copied/renamed; no `.gitignore` change; no canon. Git clean except this card.

**Command evidence:**
- `git status --short` → 1 (this card only).
- `du -sh` + `find -type f`: lab `igniter-view-engine/` = **11M / 1751 files** (1340 json, 198 ig, 172
  rb, **14 igv**, 10 md, 10 html, 4 js, **1 ebnf**, .gitignore); `igniter-compiler/igniter-view-engine/`
  = **0 B / 0 files**; `../igniter-view-engine/` = **432K / 44 files** (23 ig, 11 rb, 7 json, 3 html).
- lab `.gitignore` ignores `out/ tmp/ log/ node_modules/ dist/ build/` → the bulk (1283 of 1340 json in
  `out/`) is **gitignored generated output**, not tracked weight.
- `ls -ld ln` from lab root → **`ln` absent** (so machine-test `../ln/...` paths don't resolve now).
- `rg` reference census + `resolve_workspace_path` definition (commands.rs:1292) → pops to **igniter-lab**.

**Headline finding (corrects P1):** the lab `igniter-view-engine/` is an **ACTIVE dependency of
`igniter-ide`** — 20+ refs in `igniter-ide/src-tauri/{lib.rs,commands.rs}` resolve
`igniter-view-engine/out/*`, `/fixtures/*`, `/igniter_view_runtime.js`, and run
`run_mock_session_runner_hmac_proof.rb` via `resolve_workspace_path` (→ lab-root copy), plus
`ViewInspector.svelte`. So it is **KEEP_LIVE**, not "historical PROOF_FIXTURE" as P1 stated.

**Generated vs source:** source = `lib`/`fixtures`/14 `.igv`/`.ebnf` grammar/runtime.js/`run_*`/README/
docs/proofs (tracked); generated = lab `out/` (1283 json, gitignored, yet IDE-load-bearing) + the empty
compiler `out/` stub.

**Supersession (no overclaim):** "view-engine" is superseded **as the name for new Rust UI authoring**
(frame-ui + ViewArtifact/`.igv`, which descend from the IVF `.igv`/`.ebnf` here) but is **still a live
`igniter-ide` preview/runtime backend** — not deprecated/removable.

**Disposition table:** lab `igniter-view-engine/` → **KEEP_LIVE**; `igniter-compiler/igniter-view-engine/`
→ **DELETE_CANDIDATE** (0 files, no referrers); `../igniter-view-engine/` → **ARCHIVE_CANDIDATE** (stale
44-file subset, IDE reads the lab copy not this).

**Smallest next cleanup:** `LAB-IGNITER-VIEW-ENGINE-STATUS-MARKER-P3` — a 1-file `STATUS.md` in the lab
view-engine declaring its dual role (IVF predecessor of frame-ui + live IDE backend; `out/` gitignored;
compiler stub/sibling are delete/archive candidates). No deletion.

**Risks/non-actions:** don't clean lab `out/` (IDE-load-bearing); don't delete `fixtures/` (IDE +
possible `../ln`); don't move/rename the lab copy (breaks IDE's hardcoded paths + doc links) — needs a
path-sweep + IDE refactor first.

**Next cards:** (1) `LAB-IGNITER-VIEW-ENGINE-STATUS-MARKER-P3` (no-code, 1 file); (2)
`LAB-IGNITER-LAB-GENERATED-OUTPUT-HYGIENE-P2` owns the 0-byte compiler-stub deletion + the absent-`ln`
machine-test coupling; (3) sibling archive + IDE path-refactor are gated, post-`CARGO-WORKSPACE-ROOT-P3`.

All acceptance met.

