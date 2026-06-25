# LAB-DISTRIBUTION-REPL-SURFACE-REFRESH-P22 - refresh distribution docs after REPL opt-in

Status: CLOSED (2026-06-25) — front-door doc refreshed to P20/P21 truth; stale "pending smoke/opt-in" wording removed from the live surface
Lane: distribution / hygiene
Type: implemented-surface refresh
Date: 2026-06-25

## Context

P20 proved `igniter-repl --script <file>` headless smoke. P21 is expected to add installer opt-in
`--with-repl` without changing the default 5-binary fleet.

This card is a hygiene follow-up. Run it **after P21 lands**. If P21 has not landed, stop and report that this
card is blocked.

## Goal

Refresh the distribution front-door docs and stale labels so agents no longer read old "pending headless
smoke" / "no installer opt-in" claims as current truth.

## Verify First

Read live sources first:

- `bin/igniter-install`
- `bin/igniter`
- `runtime/igniter-machine/src/bin/repl.rs`
- `runtime/igniter-machine/tests/repl_headless_smoke_tests.rs`
- `lab-docs/lang/lab-distribution-implemented-surface-v0.md`
- P20 card
- P21 card

Confirm P21 is actually closed and live:

- `bin/igniter-install --help` mentions `--with-repl`;
- `bin/igniter toolchain install --help` mentions `--with-repl`;
- `bin/igniter-install --with-repl --prefix <tmp>` stages `igniter-repl`;
- P20 staged smoke works.

If not, do not update docs.

## Required Updates

Update `lab-docs/lang/lab-distribution-implemented-surface-v0.md`:

- `igniter-repl` precise status:
  - release build recovered;
  - headless script smoke implemented and passing;
  - installer opt-in available via `--with-repl`;
  - still **not** in default v0 fleet;
  - default dependency boundary unchanged (`ratatui`/`crossterm` opt-in only).
- `Live commands` / toolchain row:
  - `igniter toolchain install|update [--with-repl] [--prefix PATH]`.
- `Closed surfaces`:
  - remove "REPL fleet inclusion excluded pending P17 follow-ups" phrasing;
  - replace with "default fleet inclusion still excluded; opt-in install implemented".
- `Superseded phrasings`:
  - add a note that old P17/P19/P20 language about "pending installer opt-in" is superseded by P21.

Optional, only if live code still has stale wording:

- update `bin/igniter-install` / `bin/igniter` comments/help strings that still say "pending headless smoke";
- keep behavior unchanged.

## Acceptance

- [x] rg over the **current surface** (`bin` + `lab-docs`) is CLEAN. Remaining matches live only in the
      closed `…REPL-LABEL-HYGIENE-P19.md` (history) and this `…P22.md` (its own spec) — allowed as history.
- [x] `lab-docs/lang/lab-distribution-implemented-surface-v0.md` names **P20** (headless smoke) and **P21**
      (installer opt-in) as current truth (repl-status section, toolchain row, closed surfaces, superseded note).
- [x] `bin/igniter-install --help` and `bin/igniter toolchain install --help` show the same `--with-repl` opt-in story.
- [x] P20 smoke still passes: `cargo test --features repl --test repl_headless_smoke_tests` → 3/3.
- [x] `git diff --check` clean.

## Reporting

1. **Stale phrases removed / re-scoped:**
   - `bin/igniter-install` comment: "not in the default v0 fleet **pending headless smoke** — P17" →
     "release build recovered (P1; headless smoke P20) — NOT in the default fleet, staged on demand via
     `--with-repl` (P21)".
   - front-door doc: toolchain row gained `[--with-repl]`; the `igniter-repl` status section was rewritten
     to state P20 smoke + P21 opt-in + unchanged dep boundary; Closed-surfaces line "REPL fleet inclusion
     excluded **pending P17 follow-ups**" → "default-fleet inclusion still excluded; opt-in install
     implemented (P21)"; added a "Superseded by P20/P21" note.
2. **One-sentence REPL distribution status:** *`igniter-repl`'s release build is recovered (P1), it has a
   passing non-interactive `--script` headless smoke (P20), and it installs on demand via `--with-repl`
   (P21) — but it is deliberately NOT in the default 5-binary fleet and adds no default dependency.*
3. **Historical packets left unchanged:** the closed P17/P19 cards (their "pending" wording is historical,
   framed by their CLOSED status) and this P22 card's own spec text. Per the card's "do not over-edit
   historical proof", only the *current surface* (live `bin` + the front-door doc) was refreshed.

No behavior change — wording/comment only. No default-fleet inclusion, no installer-logic change.

## Closed Surfaces

No behavior change unless only help/comment wording is stale. No default fleet inclusion. No installer logic
changes beyond already-landed P21. No release packaging, signing, registry, tarball, Docker, or Homebrew.
