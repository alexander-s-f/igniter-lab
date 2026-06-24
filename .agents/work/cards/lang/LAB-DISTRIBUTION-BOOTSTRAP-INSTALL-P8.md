# LAB-DISTRIBUTION-BOOTSTRAP-INSTALL-P8 - repo-local bootstrap installer for the `igniter` control center

Status: CLOSED (2026-06-24) — bin/igniter-install stages 5 binaries + front door; 10 wrapper tests green; packet at lab-docs/lang/lab-distribution-bootstrap-install-p8-v0.md
Lane: distribution / bootstrap install
Type: implementation + proof
Date: 2026-06-24
Skill: idd-agent-protocol

## Context

Depends on:

- `LAB-DISTRIBUTION-CONTROL-CENTER-READINESS-P6`
- Preferably `LAB-DISTRIBUTION-CONTROL-CENTER-CLI-SKELETON-P7`, unless P6 explicitly says to bootstrap the P2 wrapper first.

P4 recommended a repo-local bootstrap script as the v0 install channel. This card implements the first
boring local install path while preserving the control-center principle:

```text
bin/igniter-install  ->  installs/stages the first `igniter`
daily workflow       ->  `igniter ...`
```

`igniter-install` must not become a second package manager.

## Goal

Add a repo-local bootstrap installer that stages the v0 command center plus the 5 green release binaries into
a chosen prefix:

```text
bin/igniter-install --prefix ~/.igniter
~/.igniter/bin/igniter
~/.igniter/bin/igc
~/.igniter/bin/igniter-vm
~/.igniter/bin/igweb-serve
~/.igniter/bin/igniter-mcp
~/.igniter/bin/tbackend
```

The installer should build from source package-locally in this checkout; no root workspace.

## Verify First

- Read P3 release binary matrix and P4 installer readiness.
- Read P6/P7 if landed.
- Confirm `igniter-repl` is still excluded unless fixed.
- Confirm `lang/igniter-compiler` still builds `igniter_compiler` and decide whether install aliases it to `igc`.
- Confirm build-time `igniter-lang` sibling requirement for compiler.
- Confirm no runtime stdlib/prelude assets are needed.
- Confirm `bin/igniter` is executable and can find staged `igweb-serve`.

## Required Behavior

- Default prefix: `~/.igniter` unless P6/P7 choose another.
- `--prefix PATH` supported.
- Build package-local release binaries:
  - compiler (`igniter_compiler`, installed as `igc` unless a real `igc` binary has landed)
  - `igniter-vm`
  - `igweb-serve`
  - `igniter-mcp`
  - `tbackend`
- Exclude `igniter-repl` with a clear reason if it is still build-broken.
- Stage `bin/igniter` as the durable front door.
- Generate a local manifest with source commit, dirty status, target triple, binary paths, feature set, and sha256 where available.
- Run a local smoke:
  - `igniter --help`
  - `igniter serve --check <todo_app>` or `igniter check <todo_app>` depending on P7.
- Never install secrets, host config with inline secrets, DB DSNs, systemd units, Docker files, or public listeners.

## Acceptance

- [x] Fresh temp prefix install succeeds from the repo checkout.
- [x] Installed `igniter` is executable and prints help.
- [x] Installed `igc` exists and invokes the compiler help/version path.
- [x] Installed `igweb-serve` supports `check <todo_app>`.
- [x] Manifest records source commit/dirty status/target triple/binary sha256/feature set.
- [x] `igniter-repl` is either excluded with a documented reason or included only if its build is fixed and proven.
- [x] Re-running install is idempotent enough for local DX (does not corrupt prefix; clear overwrite/update behavior).
- [x] No root workspace, no network, no registry, no upload, no public release.
- [x] `git diff --check` clean.

## Closed Surfaces

No public release. No tarball/.deb/Homebrew/Docker. No update server. No signing/notarization. No root
workspace. No production service install. No implicit DB or host authority.

## Closing Report

Proof doc: `lab-docs/lang/lab-distribution-bootstrap-install-p8-v0.md`. Gate: P6+P7 CLOSED.

**Added `bin/igniter-install`** (bash 3.2-safe): `--prefix PATH` (default `~/.igniter`); fails closed if
`cargo` or the `igniter-lang` sibling inventory is missing; builds package-local release binaries and stages
`<prefix>/bin/{igc←igniter_compiler, igniter-vm, igweb-serve, igniter-mcp, tbackend}` + the `igniter` front
door; writes `<prefix>/igniter-manifest.json` (source_git_commit, dirty, target_triple, public_release:false,
per-binary sha256+feature_set, excluded igniter-repl+reason); smokes `igniter --help` + `igniter check
<todo_app>`. No secrets/systemd/Docker/network. Idempotent (`cp -f`). **`igc` is an install-time copy, not a
crate rename.**

**Edited `bin/igniter`** (P7) for the staged-prefix contract: `resolve_igweb_serve` + the doctor/toolchain
fleet now prefer a **co-located** sibling (`$SCRIPT_DIR/<bin>`) so `<prefix>/bin` is self-contained (no
rebuild, no env var). Repo-dev path unchanged.

**Proof:** fresh temp-prefix install OK (5 binaries staged, shas match P3); standalone staged `igniter`
doctor/toolchain-list show all 5 `(staged)`, `igc` runs, `igniter check` uses the co-located igweb-serve;
idempotent re-run OK. `cargo test --test igniter_serve_wrapper_smoke_tests` → **10 passed** (+co-located test);
`runner_tests` 17 + `example_app_tests` 7 green; `git diff --check` clean.

**Follow-ons:** wire `igniter toolchain install|update` → igniter-install; P9 doctor; native tarball (P4
ladder); igniter-repl async-fix.

