# lab-distribution-implemented-surface-v0 — the live `igniter` distribution surface (front door)

**Type:** implemented-surface front door (hygiene; no code). **Updated:** 2026-06-25.

This is the **current-truth** index for the `igniter` control-center distribution lane. Read THIS first
during verify-first; the per-card readiness/proof packets (P1–P17) are historical evidence and several
describe earlier states (see "Superseded phrasings" below). When a packet and this doc disagree, **this doc
wins** — but verify against live `bin/igniter` / `bin/igniter-install` before acting.

## Live commands (what works today)

All verbs are dispatched by `bin/igniter` (a thin bash front door — adds NO authority of its own). Each
routes to a named owner that enforces the real policy.

| Command | Status | Owner / delegate | Notes |
|---|---|---|---|
| `igniter serve <app_dir> [--addr 127.0.0.1:PORT] [--max-requests N] [--host-config PATH]` | live | `igweb-serve` (server/igniter-web) | loopback-only, request-bounded; public bind REFUSED by igweb-serve (P2) |
| `igniter check <app_dir>` / `serve --check` | live | `igweb-serve check` | dry build/verify; opens NO socket |
| `igniter doctor` | live | local, non-mutating | env + fleet report (severities ok/warn/fail/info); P9/P10 |
| `igniter toolchain list` | live | local | reports the 5-binary default v0 fleet; marks repl optional (`[optional]`, or `[present] (optional, …)` when staged/built) |
| `igniter toolchain install\|update [--with-repl] [--prefix PATH]` | live | `bin/igniter-install` | **local-source build+stage only** — NO remote/registry/solver/signing; `update` needs a prior `igniter-manifest.json`; staged-prefix is source-required (P11); `--with-repl` also stages the optional `igniter-repl` (P21) |
| `igniter package lock\|verify\|verify-archive\|graph\|pack\|admit` | live | `igc` (igniter-compiler) | **argv routing only**, not a second resolver; `verify`=workspace, `verify-archive`=`.igpkg` archive (P12) |
| `igniter app bundle <app_dir> --out <dir> --version <stamp>` | live | local orchestration | **assembly only** (P14); see below |

### `igniter app bundle` — precise status

**Implemented (P14); assembly only.** Produces a versioned, self-contained directory
`<out>/<app>-<version>/` = `{bin/igweb-serve (copied, sha256-pinned), app/<app>/…, run/run-<app>.sh,
checks/check.sh, systemd/<app>.service.example (template), host.toml.example?, manifest.json}`. Fail-closed:
real `host.toml`, inline secrets, missing `--version`, non-loopback mode, or a failing `igweb-serve check`
all refuse with no partial bundle. The emitted `run/run-<app>.sh` actually serves a request from inside the
bundle on loopback (proven P16). It does **not** install systemd, bind public, manage TLS, create a DB, ship
secrets, or swap the `current` symlink — those stay host-owned.

### `igniter-repl` — precise status

**Release build recovered (P1)**, **headless smoke implemented (P20)**, **installer opt-in available (P21)**,
**still NOT in the default v0 fleet**:
- `cargo build --release --bin igniter-repl --features repl` succeeds.
- **Headless smoke:** `igniter-repl --script <file>` runs REPL commands non-interactively (no TUI) and
  exercises `write → checkpoint → resume → facts` (state survives the round-trip); exits `0`/`SCRIPT OK` or
  non-zero/`SCRIPT FAILED`. Tested by `runtime/igniter-machine/tests/repl_headless_smoke_tests.rs`.
- **Installer opt-in:** `igniter-install --with-repl` (and `igniter toolchain install|update --with-repl`)
  builds+stages `igniter-repl` and records it in the manifest's `optional[]` (`installed:true`,
  `feature_set:["repl"]`, `sha256`). Without the flag it is not built; the default fleet stays exactly 5.
- **Default dependency boundary unchanged:** `ratatui`/`crossterm` are opt-in-only (`required-features =
  ["repl"]`, `default = []`); `cargo tree --no-default-features` has neither. `toolchain list`/`doctor` show
  `[present] igniter-repl (optional, staged/repo build)` when built, else `[optional]`.
- The installer's default `FLEET` is 5 binaries (igc, igniter-vm, igweb-serve, igniter-mcp, tbackend);
  fleet membership for repl is a separate, still-unmade decision.

## Closed surfaces (deliberately NOT in v0)

- **Tool distribution:** no remote download, registry, version solver, signed artifacts, Homebrew, Docker,
  `.deb`/tarball channel (tarball/`.deb` have home-lab *precedent* for `tbackend` only).
- **App deployment:** no systemd install/enable, no `current` symlink swap, no reverse proxy, no TLS, no DB
  creation/migration, no secrets/DSNs/real `host.toml` in a bundle, no public bind.
- **Repo/build:** no root Cargo workspace (P5 — package-local + xtask/shell orchestration is the v0 model).
- **REPL default-fleet inclusion:** still excluded (opt-in install IS implemented via `--with-repl`, P21);
  promoting repl into the *default* fleet remains a separate, unmade decision.

## v0 install model (one-liner)

`bin/igniter-install [--prefix PATH]` builds the 5-binary fleet package-locally from THIS checkout and
stages `{igniter front door + 5 binaries}` into `<prefix>/bin` (default `~/.igniter`). Afterwards daily work
is `igniter …`. Local-source only; staged prefixes are self-contained and never rebuild from source.

## Superseded phrasings (so verify-first agents don't act on stale text)

These older packets remain valid **history**, but specific phrases are now stale. Each has a one-line
supersession note at its top pointing here:

| Old packet | Stale phrase | Current truth |
|---|---|---|
| `…control-center-readiness-p6-v0` | "`igniter app bundle` → RESERVED, deferred" | **Implemented (P14)** — see above |
| `…control-center-cli-skeleton-p7-v0` | `package`/`app`/`toolchain install` are "fail-closed placeholders" | all **live** now (P11 toolchain, P12 package, P14 app bundle) |
| `…app-bundle-readiness-p13-v0` | "design only — NO implementation" | the design it specifies is now **implemented (P14)** + run-proven (P16) |

Repl labels were relabeled by **P19** (`LAB-DISTRIBUTION-REPL-LABEL-HYGIENE`): `bin/igniter` `toolchain
list` now shows `[optional]`/`[present] (optional)` for repl, `doctor` reports it as `info`/`ok`, and
`bin/igniter-install` no longer carries a failure label for it. The *policy* (repl is opt-in, not in the
default 5-binary fleet) is unchanged and correct.

**Superseded by P20/P21:** earlier language framing the headless smoke and the installer opt-in as
still-outstanding (P17 readiness, P19 hygiene) is now stale — the headless smoke landed in **P20** and the
installer opt-in (`--with-repl`) landed in **P21**. Those closed cards stay as history; the repl status
section above is current truth.

## Authority boundary

`bin/igniter` is a router; it grants nothing. Real authority lives in the owners: loopback/public-bind
refusal + request bound in `igweb-serve`; package trust + `STDLIB_VERSION` in `igc`; host config + secrets in
`--host-config`/the host environment; the install fleet policy in `bin/igniter-install`. This doc is
descriptive hygiene, not a new authority.
