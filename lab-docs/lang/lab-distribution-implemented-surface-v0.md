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
| `igniter toolchain list` | live | local | reports the 5-binary v0 fleet; marks repl excluded |
| `igniter toolchain install\|update [--prefix PATH]` | live | `bin/igniter-install` | **local-source build+stage only** — NO remote/registry/solver/signing; `update` needs a prior `igniter-manifest.json`; staged-prefix is source-required (P11) |
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

**Release build recovered (P1):** `cargo build --release --bin igniter-repl --features repl` succeeds.
**NOT fleet-included** — it is an interactive TUI with no hermetic functional smoke, so P17 recommends
keeping it **opt-in / excluded from the default v0 fleet**. `ratatui`/`crossterm` are opt-in-only
(`required-features = ["repl"]`, `default = []`); they change no default dependency boundary. Promotion to
the fleet is gated on a non-interactive REPL smoke + an installer opt-in (P17 follow-ups). The installer's
default `FLEET` is correctly 5 binaries (igc, igniter-vm, igweb-serve, igniter-mcp, tbackend).

## Closed surfaces (deliberately NOT in v0)

- **Tool distribution:** no remote download, registry, version solver, signed artifacts, Homebrew, Docker,
  `.deb`/tarball channel (tarball/`.deb` have home-lab *precedent* for `tbackend` only).
- **App deployment:** no systemd install/enable, no `current` symlink swap, no reverse proxy, no TLS, no DB
  creation/migration, no secrets/DSNs/real `host.toml` in a bundle, no public bind.
- **Repo/build:** no root Cargo workspace (P5 — package-local + xtask/shell orchestration is the v0 model).
- **REPL fleet inclusion:** excluded pending P17 follow-ups.

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

Also note: `bin/igniter-install` text and one `bin/igniter` `[blocked]` label still say repl is
"build-broken (P3)". That wording is **stale** (build recovered) and is routed to a docs-hygiene relabel
(`LAB-DISTRIBUTION-REPL-LABEL-HYGIENE-P*` per P17) — the *policy* (repl excluded from the default fleet) is
unchanged and correct.

## Authority boundary

`bin/igniter` is a router; it grants nothing. Real authority lives in the owners: loopback/public-bind
refusal + request bound in `igweb-serve`; package trust + `STDLIB_VERSION` in `igc`; host config + secrets in
`--host-config`/the host environment; the install fleet policy in `bin/igniter-install`. This doc is
descriptive hygiene, not a new authority.
