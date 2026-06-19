# LAB-IGNITER-VIEW-ENGINE-STATUS-MARKER-P3 — live status marker for view-engine

Status: CLOSED  
Lane: fast_lane / no-code documentation marker  
Opened: 2026-06-19  
Delegate label: OPUS-VIEW-ENGINE-STATUS-MARKER-A  
Skill: idd-agent-protocol  

## Why This Card

`LAB-IGNITER-VIEW-ENGINE-DISPOSITION-P2` corrected the P1 repo-boundary map:

`igniter-lab/igniter-view-engine/` is **not disposable historical junk**. It is
both:

1. the historical IVF/view-engine predecessor of the current frame-ui /
   ViewArtifact / `.igv` line; and
2. a **live backend dependency of `igniter-ide`**, which reads:
   - `igniter-view-engine/out/*`
   - `igniter-view-engine/fixtures/*`
   - `igniter-view-engine/igniter_view_runtime.js`
   - `run_mock_session_runner_hmac_proof.rb`

Future cleanup agents need a local marker inside the directory itself so they
do not mistake it for generated trash.

This card creates that marker only.

## Authority

No-code documentation marker.

Allowed:
- Add `igniter-view-engine/STATUS.md`.
- Optionally add one short pointer to `igniter-view-engine/README.md` if it
  exists and the pointer is clearly helpful.
- Add a tiny proof doc and close this card.

Not allowed:
- No file deletion, archive, move, copy, or rename.
- No editing `igniter-ide` paths.
- No cleanup of `out/`.
- No `.gitignore` change.
- No code changes in compiler, frame, UI, console, web, or IDE.
- No repo split or Cargo/workspace changes.
- No claim that `view-engine` is canon or deprecated globally.

## Verify First

From `igniter-lab`:

```bash
git status --short
test -d igniter-view-engine
test -f igniter-view-engine/README.md || true
test -f igniter-view-engine/STATUS.md && echo "already exists" || true
rg -n "igniter-view-engine/out|igniter_view_runtime|run_mock_session_runner_hmac_proof|resolve_workspace_path" \
  igniter-ide/src-tauri igniter-ide/src 2>/dev/null
sed -n '1,220p' lab-docs/lang/lab-igniter-view-engine-disposition-p2-v0.md
```

Live tree wins. If `STATUS.md` already exists, update it rather than create a
second marker.

## Implementation

Create:

```text
igniter-view-engine/STATUS.md
```

The marker should be short and hard to misread. Required sections:

1. **Current Status**
   - `KEEP_LIVE`
   - not a Rust crate;
   - historical IVF/view-engine proof tree;
   - live `igniter-ide` preview/runtime backend.

2. **Do Not Delete / Move Blindly**
   - `out/` is gitignored generated output, but `igniter-ide` reads it at
     runtime;
   - `fixtures/`, `igniter_view_runtime.js`, and proof runner scripts are
     referenced by IDE code;
   - moving/renaming this directory requires an IDE path-refactor card first.

3. **Relationship To Frame/UI**
   - new Rust UI authoring lives in `igniter-frame`, `igniter-ui-kit`,
     `igniter-console`, `.igv`/ViewArtifact;
   - this tree is historical lineage plus IDE backend, not the name for new
     Rust UI work.

4. **Known Disposition**
   - lab copy: `KEEP_LIVE`;
   - `igniter-compiler/igniter-view-engine/`: `DELETE_CANDIDATE` under a later
     hygiene card;
   - workspace sibling `../igniter-view-engine/`: `ARCHIVE_CANDIDATE` after a
     later human/archive decision.

5. **References**
   - link to `lab-docs/lang/lab-igniter-view-engine-disposition-p2-v0.md`;
   - link to `LAB-IGNITER-VIEW-ENGINE-DISPOSITION-P2.md`.

Keep wording precise: "superseded as the name for new Rust UI authoring" is OK;
"deprecated" or "safe to delete" is not.

## Optional README Pointer

If `igniter-view-engine/README.md` exists, add one short line near the top:

```markdown
> Status: see `STATUS.md` before cleanup or relocation; this tree is still an
> `igniter-ide` runtime dependency.
```

Do not rewrite the README.

## Proof / Verification

Required:

- `git status --short` before and after.
- `rg -n "KEEP_LIVE|igniter-ide|out/|STATUS" igniter-view-engine/STATUS.md`
- `rg -n "igniter-view-engine/out|igniter_view_runtime|run_mock_session_runner_hmac_proof" igniter-ide/src-tauri igniter-ide/src`
- Confirm only allowed files changed:
  - `igniter-view-engine/STATUS.md`
  - optionally `igniter-view-engine/README.md`
  - this card
  - proof doc

No tests required; this is a documentation marker. If an agent runs tests, keep
them read-only with respect to app behavior and report them as extra evidence.

## Deliverables

- `igniter-view-engine/STATUS.md`
- `lab-docs/lang/lab-igniter-view-engine-status-marker-p3-v0.md`
- Closing report in this card
- Optional one-line README pointer

## Acceptance

- `STATUS.md` exists inside `igniter-view-engine/`.
- It clearly says `KEEP_LIVE`.
- It clearly says `out/` is generated but IDE-load-bearing.
- It names `fixtures/`, `igniter_view_runtime.js`, and proof runner scripts as
  referenced by IDE code.
- It distinguishes old view-engine from the current frame-ui / ViewArtifact /
  `.igv` line without overclaiming.
- It records the disposition of all three observed `view-engine` locations.
- It links to P2 disposition evidence.
- No code, `.gitignore`, generated output, or IDE path was changed.
- No files were deleted, moved, copied, or renamed.

## Closing Report Template

Report:

- files changed;
- marker summary;
- live IDE references reconfirmed;
- any README pointer added or skipped;
- verification commands;
- non-actions held;
- next card recommendation.

---

## Closing report — 2026-06-19

**Files changed (git after = only allowed):**
- `igniter-view-engine/STATUS.md` — **created** (the marker).
- `igniter-view-engine/README.md` — **+3 lines** (one `> Status: see STATUS.md …` pointer after the
  title; README not rewritten).
- `lab-docs/lang/lab-igniter-view-engine-status-marker-p3-v0.md` — proof doc.
- this card — closing report.

`git status --short` after = ` M README.md` + `?? STATUS.md` + `?? proof doc` + `?? this card` — nothing
else (no `out/`, fixtures, runtime.js, proof runners, IDE code, `.gitignore`, Cargo).

**Marker summary:** 5 required sections — (1) `KEEP_LIVE`, not a Rust crate, historical IVF + live IDE
backend; (2) do-not-delete/move (`out/` gitignored yet IDE-load-bearing; fixtures/runtime.js/ruby proof
IDE-referenced; move needs IDE path-refactor first); (3) frame/UI relationship ("superseded as the
*name*", not deprecated); (4) 3-location disposition table; (5) links to P2 + cards + P1.

**Live IDE references reconfirmed:** `rg … igniter-ide/src-tauri igniter-ide/src | wc -l` → **21**
(lib.rs + commands.rs + ViewInspector.svelte). Wording matches P2 evidence; no overclaim.

**README pointer:** added (README existed: `# Igniter View Engine Lab Prototype`). One blockquote line.

**Verification commands:** `git status --short` before (1) / after (allowed files only);
`test -d/-f`; `rg -n "KEEP_LIVE|igniter-ide|out/|STATUS" igniter-view-engine/STATUS.md` → present.

**Non-actions held:** no deletion/archive/move/copy/rename; no `out/` cleanup; no `.gitignore`; no IDE
path edit; no compiler/frame/UI/console/web/IDE code; no repo split / Cargo / workspace; no canon or
global-deprecation claim.

**Next card:** `LAB-IGNITER-LAB-GENERATED-OUTPUT-HYGIENE-P2` — the only clean deletion (0-file
`igniter-compiler/igniter-view-engine/` stub) + the absent-`ln` machine-test coupling. Sibling archive +
IDE path-refactor stay gated, post-`CARGO-WORKSPACE-ROOT-P3`.

All acceptance met.

