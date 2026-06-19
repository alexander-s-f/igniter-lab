# lab-igniter-view-engine-status-marker-p3-v0 — live status marker for view-engine

**Card:** `LAB-IGNITER-VIEW-ENGINE-STATUS-MARKER-P3` · **Delegation:** `OPUS-VIEW-ENGINE-STATUS-MARKER-A`
**Status:** CLOSED (no-code documentation marker). Adds an in-directory `STATUS.md` so future cleanup
agents do not mistake the live IVF/view-engine tree for generated trash. **No deletion/move/copy/rename,
no `out/` cleanup, no `.gitignore` change, no IDE path edit, no code change.**
**Authority:** Lab documentation only. No canon; no global deprecation claim.

## Files changed

| File | Change |
|---|---|
| `igniter-view-engine/STATUS.md` | **created** — the marker (5 required sections) |
| `igniter-view-engine/README.md` | **+3 lines** — one `> Status: see STATUS.md …` pointer near the top (README not rewritten) |
| `lab-docs/lang/lab-igniter-view-engine-status-marker-p3-v0.md` | this proof doc |
| `.agents/work/cards/lang/LAB-IGNITER-VIEW-ENGINE-STATUS-MARKER-P3.md` | closing report |

No other files touched. No `out/`, fixtures, runtime.js, proof runners, IDE code, `.gitignore`, or Cargo
files changed.

## Marker summary

`STATUS.md` states, precisely and hard-to-misread:
1. **Current status = `KEEP_LIVE`** — not a Rust crate; historical IVF/view-engine proof tree; live
   `igniter-ide` preview/runtime backend.
2. **Do not delete/move blindly** — `out/` is gitignored generated output **but IDE-load-bearing**;
   `fixtures/`, `igniter_view_runtime.js`, and `run_mock_session_runner_hmac_proof.rb` are referenced by
   IDE code; move/rename needs an IDE path-refactor card first.
3. **Relationship to frame/UI** — new Rust UI authoring lives in `igniter-frame`/`ui-kit`/`console`/`3d`/
   `gui` + `.igv`/ViewArtifact; this tree is lineage + IDE backend, "superseded as the *name* for new
   Rust UI work" — **not** "deprecated"/"safe to delete".
4. **Known disposition** — this dir `KEEP_LIVE`; `igniter-compiler/igniter-view-engine/`
   `DELETE_CANDIDATE`; sibling `../igniter-view-engine/` `ARCHIVE_CANDIDATE`.
5. **References** — links to the P2 disposition packet, both cards, and the P1 boundary map.

## Live IDE references reconfirmed

```text
$ rg -n "igniter-view-engine/out|igniter_view_runtime|run_mock_session_runner_hmac_proof" \
    igniter-ide/src-tauri igniter-ide/src | wc -l   → 21
```
21 live references (lib.rs + commands.rs + ViewInspector.svelte) confirm `KEEP_LIVE`. The wording in the
marker matches the P2 evidence exactly (no overclaim).

## README pointer

Added (README exists: `# Igniter View Engine Lab Prototype`). One blockquote line inserted after the
title; the rest of the README is unchanged.

## Verification commands

```text
$ git status --short | wc -l                         → 1 (before: this card only)
$ test -d igniter-view-engine                         → dir present
$ test -f igniter-view-engine/STATUS.md               → absent before; created now
$ head -1 igniter-view-engine/README.md               → "# Igniter View Engine Lab Prototype" (exists)
$ rg -n "KEEP_LIVE|igniter-ide|out/|STATUS" igniter-view-engine/STATUS.md  → present
$ git status --short  (after)                         → STATUS.md (new) + README.md (modified) +
                                                          this card + proof doc only
```

## Non-actions held

No file deleted/archived/moved/copied/renamed; no `out/` cleanup; no `.gitignore` change; no
`igniter-ide` path edit; no compiler/frame/UI/console/web/IDE code change; no repo split / Cargo /
workspace change; no canon or global-deprecation claim.

## Acceptance — met

1. ✓ `STATUS.md` exists inside `igniter-view-engine/`.
2. ✓ Clearly says `KEEP_LIVE`.
3. ✓ Clearly says `out/` is generated but IDE-load-bearing.
4. ✓ Names `fixtures/`, `igniter_view_runtime.js`, and proof-runner scripts as IDE-referenced.
5. ✓ Distinguishes old view-engine from frame-ui/ViewArtifact/`.igv` without overclaiming.
6. ✓ Records the disposition of all three observed `view-engine` locations.
7. ✓ Links to the P2 disposition evidence.
8. ✓ No code/`.gitignore`/generated-output/IDE-path change.
9. ✓ No file deleted/moved/copied/renamed.

## Next card

`LAB-IGNITER-LAB-GENERATED-OUTPUT-HYGIENE-P2` — owns the only clean deletion (the 0-file
`igniter-compiler/igniter-view-engine/` stub) and the absent-`ln` machine-test coupling. The sibling
archive + IDE path-refactor remain gated, after `CARGO-WORKSPACE-ROOT-P3`.

---

*No-code marker. 2026-06-19. `STATUS.md` created + 1-line README pointer; 21 live IDE references
reconfirm `KEEP_LIVE`. No deletion/move/cleanup.*
