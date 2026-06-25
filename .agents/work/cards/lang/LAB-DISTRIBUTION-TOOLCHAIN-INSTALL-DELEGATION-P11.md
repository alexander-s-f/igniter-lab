# LAB-DISTRIBUTION-TOOLCHAIN-INSTALL-DELEGATION-P11 - wire `igniter toolchain install/update`

Status: CLOSED (2026-06-25)
Lane: distribution / toolchain DX
Type: implementation + proof
Date: 2026-06-25
Skill: idd-agent-protocol

## Context

Depends on:

- `LAB-DISTRIBUTION-CONTROL-CENTER-CLI-SKELETON-P7`
- `LAB-DISTRIBUTION-BOOTSTRAP-INSTALL-P8`

P8 added `bin/igniter-install`, but `igniter toolchain install|update` still fail closed and point at P8.
The control-center promise is stronger if users can stay inside `igniter` after the first bootstrap.

## Goal

Wire:

```text
igniter toolchain install [--prefix PATH]
igniter toolchain update  [--prefix PATH]
```

to the existing bootstrap installer, without inventing remote downloads, registries, version solvers, or a
second package manager.

## Verify First

- Read current `bin/igniter`.
- Read `bin/igniter-install`.
- Confirm P8 fresh-prefix install still works before editing.
- Confirm `igniter-install` remains bootstrap-only and can be safely called by `igniter toolchain`.
- Decide whether `install` and `update` are aliases in v0 or whether `update` requires existing manifest.

## Required Behavior

- `igniter toolchain install --prefix PATH` delegates to `bin/igniter-install --prefix PATH`.
- `igniter toolchain update --prefix PATH` is either the same idempotent rebuild/restage or checks for an
  existing manifest first; whichever is chosen, document it in the proof.
- Default prefix matches `bin/igniter-install`.
- `igniter toolchain list` remains non-mutating.
- `igniter toolchain install/update --help` describes local-source semantics and explicitly says no remote
  download/registry.
- Delegation works both from source checkout and from a staged installed prefix if feasible; if staged-prefix
  update cannot work without source checkout, fail clearly with a source-required message.

## Acceptance

- [x] `igniter toolchain install --prefix <tmp>` creates the same staged prefix as `bin/igniter-install`.
- [x] `igniter toolchain update --prefix <same>` succeeds idempotently or fails clearly if no source checkout is available.
- [x] `igniter toolchain list` still reports the 5-binary fleet and blocked repl.
- [x] Help text states local-source only; no remote download, registry, or signing.
- [x] Fresh staged `igniter check <todo_app>` still works after install/update.
- [x] Existing wrapper tests remain green; add focused toolchain tests.
- [x] `git diff --check` clean.

## Result (2026-06-25)

Wired `igniter toolchain install|update` in `bin/igniter` to delegate to the P8 bootstrap installer
(`bin/igniter-install`). No remote/registry/solver/signing introduced — pure local-source delegation.

**Design decisions (as the card asked to document):**
- **Delegation target:** `INSTALLER="$SCRIPT_DIR/igniter-install"`. In a SOURCE checkout the installer is a
  sibling of `igniter` in `bin/`; a STAGED prefix stages only the front door, so `$INSTALLER` is absent
  there → install/update fail clearly with a **source-required** message (you must run from a checkout).
- **install vs update:** both are the SAME idempotent rebuild+restage (the installer is idempotent).
  `update` adds ONE precondition — an existing `<prefix>/igniter-manifest.json` (proof of a prior install);
  without it, `update` fails closed and points at `install`. This gives `update` a meaningful, distinct
  contract while reusing one installer.
- **Default prefix:** single-sourced in the installer. `igniter` forwards `--prefix` only when given; with
  no `--prefix` it execs the installer with no args so the installer applies its own default
  (`$HOME/.igniter`). The mirrored `DEFAULT_PREFIX` in `igniter` is used only for the update-manifest
  precondition check.
- `toolchain list` unchanged (non-mutating).

**Proof — automated (hermetic; no nested cargo, mirrors the repo's no-nested-build test rule):** 6 focused
tests added to `server/igniter-web/tests/igniter_serve_wrapper_smoke_tests.rs`, using a copied real
`bin/igniter` + a FAKE `igniter-install` that records argv:
- install forwards `--prefix P`; install with no `--prefix` forwards no args;
- update fails closed with no manifest (installer NOT invoked); update delegates when a manifest exists;
- staged-prefix (front door only) install is source-required;
- install/update `--help` state "LOCAL SOURCE ONLY / NO remote download / NO registry / NO signed artifacts"
  and update names the manifest precondition.
Existing `igniter_placeholders_fail_closed` updated (dropped `toolchain install`, now wired; `app bundle`
stays the placeholder). Full suite: **16/16 green** (incl. the pre-existing doctor/serve/list tests).

**Proof — manual end-to-end (the real build path, kept out of the test suite to avoid a nested-cargo
target-dir lock):**
- `igniter toolchain install --prefix <tmp>` stages **byte-identical** to `bin/igniter-install --prefix
  <tmp>` — all 6 artifacts (igc, igniter, igniter-mcp, igniter-vm, igweb-serve, tbackend) sha256-match.
- staged `<tmp>/bin/igniter check <todo_app>` → `check ok … (no socket opened)`.
- `igniter toolchain update --prefix <tmp>` (manifest present) → idempotent success; staged check still ok.
- guards verified live: update-no-manifest → exit 3 "no prior install"; staged-prefix install → exit 3
  "STAGED … source checkout"; unknown arg → usage + exit 2.

Acceptance: all checked. `git diff --check` clean.

Note: `bin/igniter` was concurrently receiving the P10 doctor rewrite (`doc_emit`/`doc_render_text`,
severities + `--json`) during this work; that landed and is green. P11 edits are isolated to the
toolchain verb + its usage/help and do not touch doctor/package.

Next route: a future packager card can consume a staged prefix; staged-prefix `toolchain install/update`
remains intentionally source-required (no remote channel in v0).

## Closed Surfaces

No remote update channel. No registry. No signed downloads. No Homebrew/Docker/tarball. No root workspace.
No `igniter-repl` inclusion unless separately fixed.
