# lab-distribution-toolchain-install-delegation-p11-v0 — `igniter toolchain install|update` → bootstrap installer

Card: `LAB-DISTRIBUTION-TOOLCHAIN-INSTALL-DELEGATION-P11`
Status: CLOSED (2026-06-25)
Authority: lab DX implementation. Wrapper delegation only — no new install authority. Closed surfaces
honored: no remote channel, registry, solver, or signing.

## Verify-first basis

- Live `bin/igniter` (`cmd_toolchain` → `cmd_toolchain_iu`, `toolchain_iu_usage`).
- `bin/igniter-install` (the P8 bootstrap installer; the single source of the default prefix and the staged
  fleet).
- Depends on P7 (control-center skeleton) and P8 (bootstrap install). P8 had `bin/igniter-install` but
  `toolchain install|update` still fail-closed pointed at P8.
- Confirmed against the current binary by cheap non-mutating smoke (help + the update-no-manifest guard).

## What changed

`igniter toolchain install|update` went from fail-closed placeholders to **delegation to the repo-local
bootstrap installer** `bin/igniter-install`. Pure local-source orchestration — no remote download,
registry, version solver, or signed artifacts introduced. `toolchain list` stays non-mutating.

Edits are isolated to the toolchain verb (`cmd_toolchain_iu` + its usage/help); doctor and package verbs
are untouched.

## Exact command behavior

`igniter toolchain install [--prefix PATH]` / `igniter toolchain update [--prefix PATH]`:

- **Delegation target:** `INSTALLER="$SCRIPT_DIR/igniter-install"`. In a SOURCE checkout the installer is a
  sibling of `igniter` in `bin/`. A STAGED prefix stages only the front door, so `$INSTALLER` is absent →
  install/update **fail clearly (exit 3) with a source-required message** ("re-run from an igniter-lab
  source checkout"). There is no remote channel in v0.
- **install vs update:** both are the SAME idempotent rebuild+restage (the installer is idempotent).
  `update` adds ONE precondition — an existing `<prefix>/igniter-manifest.json` (proof of a prior install);
  without it `update` fails closed (exit 3) and points at `install`. This gives `update` a distinct,
  meaningful contract while reusing one installer.
- **Default prefix:** single-sourced in the installer. `igniter` forwards `--prefix` only when given; with
  no `--prefix` it `exec`s the installer with no args so the installer applies its own default
  (`$HOME/.igniter`). The `DEFAULT_PREFIX` mirrored in `igniter` is used ONLY for the update-manifest
  precondition check.
- **Args:** `--prefix PATH` and `--prefix=PATH` accepted; unknown args → usage + exit 2. `--help` prints the
  local-source-only contract.
- `exec`-based delegation preserves the installer's exit code.

## Tests / proofs

**Automated** (hermetic; no nested cargo — mirrors the repo's no-nested-build rule), in
`server/igniter-web/tests/igniter_serve_wrapper_smoke_tests.rs`, using a copied real `bin/igniter` + a FAKE
`igniter-install` that records argv:

- `igniter_toolchain_install_delegates_prefix_to_installer` — `install --prefix P` forwards `--prefix P`.
- `igniter_toolchain_install_no_prefix_passes_no_args` — `install` with no `--prefix` forwards no args.
- `igniter_toolchain_update_requires_prior_manifest` — `update` with no manifest fails closed; installer NOT
  invoked.
- `igniter_toolchain_update_delegates_when_manifest_present` — `update` delegates once a manifest exists.
- `igniter_toolchain_install_staged_prefix_is_source_required` — staged front-door-only install is
  source-required (exit 3).
- `igniter_toolchain_install_help_states_local_source_only` — help states "LOCAL SOURCE ONLY / NO remote
  download / NO registry / NO signed artifacts"; update names the manifest precondition.

The full `igniter_serve_wrapper_smoke_tests` suite is green (16 tests, incl. serve/check/doctor/list).

**Manual end-to-end** (the real build path, kept out of the suite to avoid a nested-cargo target-dir lock):

- `igniter toolchain install --prefix <tmp>` stages **byte-identical** to `bin/igniter-install --prefix
  <tmp>` — all 6 artifacts (igc, igniter, igniter-mcp, igniter-vm, igweb-serve, tbackend) sha256-match.
- staged `<tmp>/bin/igniter check <todo_app>` → `check ok … (no socket opened)`.
- `igniter toolchain update --prefix <tmp>` (manifest present) → idempotent success; staged check still ok.
- guards verified live: update-no-manifest → exit 3 "no prior install"; staged-prefix install → exit 3
  "source checkout"; unknown arg → usage + exit 2.

**Re-confirmed for this packet (cheap smoke):** `toolchain install --help` prints the LOCAL-SOURCE-ONLY /
no-remote contract; `toolchain update --prefix <fresh tmp>` fails closed naming the missing
`igniter-manifest.json`.

## Closed surfaces

No remote update channel. No registry. No signed downloads. No Homebrew/Docker/tarball. No root workspace.
No `igniter-repl` inclusion. `igniter-install` stays bootstrap-only and source-required.

## Follow-ons

- A future packager card can consume a staged prefix; staged-prefix `toolchain install/update` stays
  intentionally source-required (no remote channel in v0).
- The `igc` built-artifact name (`igniter_compiler`) vs documented `igc` caveat (P1/P3) is tracked
  separately; the installer already stages it under the name `igc`.
