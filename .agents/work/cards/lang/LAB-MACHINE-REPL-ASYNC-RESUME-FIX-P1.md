# LAB-MACHINE-REPL-ASYNC-RESUME-FIX-P1 - recover `igniter-repl` release build

Status: CLOSED (2026-06-25) — igniter-repl builds in release with --features repl; wrapper relabeled but fleet inclusion still pending
Lane: runtime / distribution blocker
Type: implementation + proof
Date: 2026-06-25
Skill: idd-agent-protocol

## Context

`LAB-DISTRIBUTION-RELEASE-BINARY-MATRIX-P3` found that 5 of 6 release binaries build, but
`igniter-repl` is excluded because `cargo build --release --bin igniter-repl --features repl` fails with
E0308 around async `checkpoint`/`resume` calls used synchronously. P8/P11/P13 all keep `igniter-repl`
blocked.

This card fixes only the REPL build blocker. Do not broaden into distribution installer changes unless the
fix proves the binary and requires updating matrix text.

## Goal

Make `igniter-repl` build in release mode with `--features repl` while preserving existing machine behavior.

## Verify First

- Run:
  ```text
  cd runtime/igniter-machine
  cargo build --release --bin igniter-repl --features repl
  ```
- Capture the exact compiler errors and lines.
- Read `runtime/igniter-machine/src/bin/repl.rs` around async `checkpoint`/`resume`.
- Read the owning APIs to determine whether `.await`, blocking wrapper, or call-site restructuring is correct.
- Check whether the REPL already runs inside Tokio / async main.

## Required Behavior

- Fix the E0308 async/sync mismatch narrowly.
- Do not change checkpoint/resume semantics outside the REPL.
- Do not introduce new runtime features into default `igniter-machine`.
- Do not touch `igniter` distribution wrapper unless only docs mention REPL still blocked and must be updated after proof.

## Acceptance

- [x] `cargo build --release --bin igniter-repl --features repl` succeeds (binary `target/release/igniter-repl`, 4.6M; only pre-existing dep warnings).
- [x] Existing `runtime/igniter-machine` tests green in default feature mode: **153 passed, 0 failed**.
- [x] No REPL-specific test harness exists (it's an interactive TUI). Startup smoke instead: `igniter-repl
      --resume /nonexistent.igm` → exits 1 with "Failed to resume machine: IO error…" — this drives the very
      `block_on(IgniterMachine::resume(...))` call I fixed (main, pre-TUI), proving it links and runs;
      `--bogus` → exit 1.
- [x] `cargo tree -e normal --no-default-features` excludes `ratatui`/`crossterm`; with `--features repl`
      they appear (ratatui 0.26.3, crossterm 0.27.0). Feature isolation intact.
- [x] Distribution wrapper text updated during curation: no longer says build-broken; still excludes repl from
      the v0 fleet pending a separate inclusion decision.
- [x] `git diff --check` clean. Core REPL fix = 5 insertions / 3 deletions in repl.rs; curation also relabeled
      wrapper text so user-facing control-center output no longer carries stale failure claims.

## Result (2026-06-25)

**Root cause:** `IgniterMachine::checkpoint` and `IgniterMachine::resume` are `async fn` (machine.rs:422 /
467); `repl.rs` called them synchronously inside `match`, so each yielded `impl Future<…>` where a `Result`
was expected → E0308 at 3 call sites (repl.rs 558 checkpoint, 576 `resume`, 894 `resume` in `main`).

**Fix (narrow):** wrapped each in `futures::executor::block_on(...)` — the EXACT synchronous-driver pattern
repl.rs already uses for every other async machine method (`dispatch`, `all_facts`, `facts_for`,
`write_fact`). No Tokio introduced, no checkpoint/resume semantics changed, no default-feature change, no
async/runtime refactor. Changes confined to `src/bin/repl.rs` (behind `--features repl`), so the default
build/tests are untouchable by construction.

**Curation note — wrapper text relabeled, not promoted:** the initial REPL fix left `bin/igniter` saying
`igniter-repl` was "build-broken (P3)". That was no longer true after this card, so curation updated the
doctor/list/help wording to: **excluded from v0 fleet (release build recovered; inclusion pending)**. This
does NOT add repl to the installer/fleet; it only removes a stale user-facing failure claim.

## Closed Surfaces

No installer change. No `igniter toolchain` inclusion unless explicitly justified after build proof. No REPL
feature expansion. No broad async/runtime refactor. No package/workspace changes.
