# Card: LAB-IGNITER-TRANSPILING-RESEARCH-DX-GEMINI-P1 — Project DX for dialect lowering, build, watch, and editor overlays

**Lane:** background / research  
**Status:** CLOSED (research report delivered)  
**Date opened:** 2026-06-18  
**Date closed:** 2026-06-18  
**Delegation-Code:** `GEMINI-20260618-TRANSPILING-C`  
**Research label:** `BACKGROUND-RESEARCH`  
**Authority:** Lab research only. No code. No canon.

## Why this card exists

Projection dialects need project-level DX: how files are discovered, lowered, watched, cached, and
compiled with unsaved editor overlays. We need research before deciding whether this belongs in a
small tool, compiler flag, build wrapper, or project manifest.

## Read first

- `.agents/work/cards/lang/LAB-IGNITER-PROJECTION-DIALECTS-P0.md`
- `lab-docs/lang/lab-igniter-projection-dialects-p0-v0.md`
- `igniter-compiler/src/project.rs`
- `igniter-compiler/src/main.rs`
- any current project-mode/overlay proof docs found by `rg "PROJECT|OVERLAY|project-root|overlay" lab-docs/lang igniter-compiler`
- JetBrains project-mode cards if present: `rg "PROJECT-MODE|OVERLAY|JetBrains" .agents/work/cards/lang lab-docs/lang`

## Goal

Produce one research packet that answers: **what is the best developer workflow for projection
dialect lowering in projects with directories, imports, generated files, and editor overlays?**

## Questions to research

1. Should dialect lowering be driven by a compiler flag, a small standalone tool, or project config?
2. What is the minimal `igniter.toml` or dialect config shape, if any?
3. How should generated files be placed: checked-in `generated/`, temp build dir, or IDE-only virtual
   files?
4. How does this interact with project-root compilation and `--overlay` for unsaved editor buffers?
5. How should watch/hot-reload work without turning the compiler into a daemon?
6. What should a Makefile/task wrapper do, and what should remain a compiler responsibility?
7. How should multiple dialects compose in one project without hidden order dependencies?
8. What is the smallest useful CLI sketch that does not over-commit architecture?

## Output contract

Write exactly one report:

`lab-docs/lang/lab-igniter-transpiling-research-dx-gemini-p1-v0.md`

Then update only this card with a closing report.

## Closed surfaces

- No implementation.
- No Makefile/CLI changes.
- No JetBrains plugin edits.
- No compiler edits.
- No canon promotion.
- Do not touch unrelated dirty files.

## Acceptance

- [x] Report maps at least three DX shapes: compiler flag, standalone tool, project config/build wrapper.
- [x] Report recommends a smallest-next-step v0 with clear tradeoffs.
- [x] Report covers editor overlay and unsaved-buffer implications.
- [x] Report covers generated-file policy.
- [x] Report includes future card ideas and explicit non-goals.
- [x] No code changed.

---

## Closing report — 2026-06-18

**Outcome**: Research packet delivered. It analyzes the developer experience (DX) and build pipeline for projection dialects, generated files, watch/hot-reload, and editor overlays without introducing code modifications.

**Deliverable**: `lab-docs/lang/lab-igniter-transpiling-research-dx-gemini-p1-v0.md`

**Decisions Captured**:
1.  **Build Wrapper**: Recommend driving dialect lowering via a configuration-driven build wrapper (`igniter` CLI) rather than compiler flags, keeping `igc` focused purely on canonical `.ig` graph resolution.
2.  **Generated File Placement**: Place lowered targets in checked-in `generated/` directories for maximum inspectability and simpler compiler resolution.
3.  **Two-Stage Overlay**: Map unsaved dialect editor buffers by having the IDE first lower them to a temp `.ig` buffer and then pass the temporary file path as a standard `--overlay` target to `igc`.
4.  **Stateless Watcher**: Implement watching via a stateless CLI wrapper (`igniter watch`) that manages rebuilds sequentially, avoiding background daemon complexity.
5.  **Acyclic Composition**: Enforce a strict no-nested-dialect rule to ensure all lowering steps can run in parallel without ordering dependencies.
