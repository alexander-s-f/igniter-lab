# STATUS — `igniter-view-engine` (read before any cleanup or relocation)

## 1. Current Status

**`KEEP_LIVE`.**

- This is **not a Rust crate** (no `Cargo.toml`) — it is a JS/Ruby IVF (Igniter View Format) /
  view-engine proof tree.
- It is the **historical IVF/view-engine predecessor** of the current frame-ui / ViewArtifact / `.igv`
  line.
- It is **also a live preview/runtime backend for `igniter-ide`** — the Tauri IDE reads from this exact
  directory at runtime (21 references in `igniter-ide/src-tauri/{lib.rs,commands.rs}` +
  `igniter-ide/src/lib/components/ViewInspector.svelte`, resolved via
  `resolve_workspace_path("igniter-view-engine/…")` which points at this lab-root copy).

## 2. Do Not Delete / Move Blindly

- `out/` is **gitignored generated output**, **but `igniter-ide` reads it at runtime**
  (`igniter-view-engine/out/*`, e.g. `tabs_ssr_output.html`, `tauri_playback_receipt.json`). Do **not**
  clean `out/` blindly — the IDE expects it to have been produced locally.
- `fixtures/`, `igniter_view_runtime.js`, and the proof-runner scripts (notably
  `run_mock_session_runner_hmac_proof.rb`) are **referenced by IDE code**. Do not delete or rename them.
- **Moving or renaming this directory requires an IDE path-refactor card first** — the IDE paths are
  hardcoded relative to the lab root. No move/rename until that refactor lands.

## 3. Relationship To Frame / UI

- **New Rust UI authoring lives elsewhere:** `igniter-frame`, `igniter-ui-kit`, `igniter-console`,
  `igniter-3d`, `igniter-gui`, plus `.igv` / ViewArtifact.
- This tree is **historical lineage** (the `.igv` dialect and the `.ebnf` grammar here seeded that line)
  **plus the IDE backend** — it is **superseded as the *name* for new Rust UI work**, but it is **not
  deprecated and not safe to delete**.

## 4. Known Disposition (from P2)

| Location | Disposition |
|---|---|
| `igniter-lab/igniter-view-engine/` (this dir) | **`KEEP_LIVE`** |
| `igniter-lab/igniter-compiler/igniter-view-engine/` | `DELETE_CANDIDATE` — under a later hygiene card (0 files, no referrers) |
| workspace sibling `../igniter-view-engine/` | `ARCHIVE_CANDIDATE` — after a later human/archive decision (IDE reads this copy, not the sibling) |

## 5. References

- Disposition evidence: [`lab-docs/lang/lab-igniter-view-engine-disposition-p2-v0.md`](../lab-docs/lang/lab-igniter-view-engine-disposition-p2-v0.md)
- Cards: `LAB-IGNITER-VIEW-ENGINE-DISPOSITION-P2`, `LAB-IGNITER-VIEW-ENGINE-STATUS-MARKER-P3`
- Upstream map: `lab-docs/lang/lab-igniter-lab-repo-boundary-readiness-p1-v0.md`
