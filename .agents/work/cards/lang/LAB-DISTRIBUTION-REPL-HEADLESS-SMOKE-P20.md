# LAB-DISTRIBUTION-REPL-HEADLESS-SMOKE-P20 - make `igniter-repl` functionally smokeable

Status: CLOSED (2026-06-25) — `igniter-repl --script <file>` headless mode added; 3 tests green; checkpoint/resume round-trip proven; gate satisfied for installer opt-in
Lane: distribution / repl
Type: implementation + proof
Date: 2026-06-25

## Context

P1 recovered the release build for `igniter-repl --features repl`.

P17 decided the distribution policy:

```text
igniter-repl is optional / opt-in, not in the default v0 fleet.
Promotion requires a non-interactive functional smoke.
```

P19 relabeled the live distribution surfaces from `build-broken` / `[blocked]` to `[optional]`.

The remaining gap is testability: `igniter-repl` is an interactive ratatui TUI. Current smoke only proves
linkage and one pre-TUI error path (`--resume /nonexistent.igm`), not REPL function.

## Goal

Add a narrow **headless / scripted smoke mode** for `igniter-repl` that exercises real REPL functionality
without entering the TUI.

This is a gate for future fleet inclusion, not fleet inclusion itself.

## Verify First

- Read:
  - `runtime/igniter-machine/src/bin/repl.rs`
  - `runtime/igniter-machine/Cargo.toml`
  - existing REPL command dispatch / command parser, if any
  - `tests/machine_tests.rs` or nearby fixtures that can load/dispatch/checkpoint/resume a tiny app
  - P17 packet: `lab-docs/lang/lab-distribution-repl-fleet-inclusion-readiness-p17-v0.md`
- Confirm:
  - `[[bin]] igniter-repl` remains `required-features = ["repl"]`;
  - default feature tree remains free of `ratatui` / `crossterm`;
  - no existing headless mode already exists.

## Required Behavior

Add one small non-interactive path, choosing the least invasive shape that fits live code:

Preferred shape:

```text
igniter-repl --script <file>
```

Acceptable simpler shape if script parsing is too broad:

```text
igniter-repl --headless-smoke
```

The smoke must exercise more than startup:

1. load or construct a tiny machine/program;
2. dispatch at least one contract or machine command;
3. checkpoint;
4. resume from that checkpoint;
5. dispatch again or inspect a deterministic fact/state after resume;
6. exit `0` on success, non-zero on failure;
7. print a concise machine-readable or grep-friendly success line.

If `--script` is implemented, keep the command vocabulary minimal and documented by the test. If
`--headless-smoke` is implemented, it may use an embedded/minimal fixture.

## Acceptance

- [x] `cargo build --release --bin igniter-repl --features repl` succeeds (Finished).
- [x] New `--script <file>` exits `0` and prints the marker `igniter-repl: SCRIPT OK`.
- [x] Test proves it exercises real ops, not startup: machine `write` → `facts` → `checkpoint` → `resume` →
      `facts` (the written fact `{"v":42}` reappears AFTER the resume line — state survived the round-trip).
- [x] Failure paths exit non-zero with `SCRIPT FAILED`: bad command (`Unknown command`) and bad resume path
      (`IO error`) — two tests.
- [x] No TUI: the headless branch runs BEFORE any terminal setup; test asserts no alternate-screen escape in stdout.
- [x] `cargo test --no-default-features --lib --tests` in `runtime/igniter-machine` green; the smoke file is
      `#![cfg(feature = "repl")]` so it compiles to nothing without the feature. Full
      `cargo test --no-default-features` still hits an unrelated pre-existing doctest/rustdoc crate-resolution
      issue in `src/bridge.rs` (`can't find crate for igniter_vm`), outside this card.
- [x] `cargo tree -e normal --no-default-features` → 0 `ratatui`/`crossterm`; `--features repl` → both present.
- [x] No `bin/igniter-install` fleet change (still 5 rows), no `--with-repl` anywhere.
- [x] `git diff --check` clean.

## Reporting

- **Shape chosen: `igniter-repl --script <file>`** (the preferred shape), over `--headless-smoke`. Reason: it
  reuses the existing `App::execute_command` dispatch verbatim, so the smoke runs the *real* command
  vocabulary (load/dispatch/facts/write/checkpoint/resume/contracts) rather than a separate hardcoded fixture
  path — least invasive (no new command logic) and reusable for any future REPL scripting. Comment lines
  (`#`) and blanks are skipped; any command that produces an error flips the exit code to 1.
- **Exact smoke command:** `igniter-repl --script <file>` where the file is:
  `write demo k1 {"v":42}` → `facts demo k1` → `checkpoint <tmp>.igm` → `resume <tmp>.igm` → `facts demo k1`.
- **Semantic operations exercised:** a machine **write** (fact persisted), a **read** (`facts`), a
  **checkpoint** (state serialized to a real `.igm`, file produced), a **resume** (machine rebuilt from that
  file via the P1-fixed `block_on(resume)`), and a **post-resume read proving the fact survived** the
  round-trip. Exit `0` + `SCRIPT OK` on success; `1` + `SCRIPT FAILED` on any error.
- **Enough to open installer opt-in?** **Yes.** This is the non-interactive functional smoke P17 gated fleet
  inclusion on — it proves the REPL *functions* (not just links) and that checkpoint/resume actually persist
  and restore state. `LAB-DISTRIBUTION-REPL-INSTALLER-OPTIN-P*` can now proceed (add `igniter-install
  --with-repl` + `[optional]→[present-when-built]`). Scope note: this smoke exercises machine **commands**;
  a full `.ig` **contract** `load`+`dispatch` is supported by the same `--script` path but not covered here
  (it would need a tiny compiled fixture) — not required for the gate, optional to add later.

Implementation: `runtime/igniter-machine/src/bin/repl.rs` (`--script` arg + a pre-TUI headless branch +
`run_script`), behind `--features repl`; test `runtime/igniter-machine/tests/repl_headless_smoke_tests.rs`
(feature-gated). No `Cargo.toml`/installer/default-dependency change.

Verification note: normal no-default lib/tests are green; full no-default doctests still fail in the
unrelated `src/bridge.rs` rustdoc path (`can't find crate for igniter_vm`). P20 did not touch that surface.

## Closed Surfaces

No REPL fleet inclusion. No `igniter-install --with-repl`. No default dependency change. No broad TUI
redesign. No new package manager semantics. No registry/download/signing/distribution upload.
