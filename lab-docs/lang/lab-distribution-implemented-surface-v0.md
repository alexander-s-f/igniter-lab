# lab-distribution-implemented-surface-v0 — the live `igniter` distribution surface (front door)

**Type:** implemented-surface front door (hygiene; no code). **Updated:** 2026-06-25.

> New here? Start with the command-oriented [igniter control-center developer guide](igniter-control-center-dev-guide-v0.md).
>
> Anti-rot guard: `tools/check_distribution_surface.sh` checks this doc's stable anchors against the live CLI
> (`--with-tests` also runs the bounded smoke suites). Run it if you suspect the doc has drifted from code.

This is the **current-truth** index for the `igniter` control-center distribution lane. Read THIS first
during verify-first; the per-card readiness/proof packets (P1–P35) are historical evidence and several
describe earlier states (see "Superseded phrasings" below). When a packet and this doc disagree, **this doc
wins** — but verify against live `bin/igniter` / `bin/igniter-install` / `igniter-agent` before acting.

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
| `igniter app admit <bundle_dir> --release-root <dir>` | live | local orchestration | **validate + copy only** (P35) — 10 gates, copies into `releases/<app>/<version>/`; NO `current` symlink, systemd, or deploy; see below |
| `igniter env doctor\|template\|check <app_or_bundle>` | live | local | env-NAME catalogue from `host.example.toml`/`host.toml.example`; names + set/unset/empty only, **values never read/printed**; no `.env` (P33/P34); see below |
| `igniter agent` | live | `igniter-agent` (stdio MCP) | command-center MCP; tools shell-delegate to this front door (P23–P26, P28, P34); see below |

### `igniter app bundle` — precise status

**Implemented (P14); assembly only.** Produces a versioned, self-contained directory
`<out>/<app>-<version>/` = `{bin/igweb-serve (copied, sha256-pinned), app/<app>/…, run/run-<app>.sh,
checks/check.sh, systemd/<app>.service.example (template), host.toml.example?, manifest.json}`. Fail-closed:
real `host.toml`, inline secrets, missing `--version`, non-loopback mode, or a failing `igweb-serve check`
all refuse with no partial bundle. The emitted `run/run-<app>.sh` actually serves a request from inside the
bundle on loopback (proven P16). It does **not** install systemd, bind public, manage TLS, create a DB, ship
secrets, or swap the `current` symlink — those stay host-owned.

### `igniter app admit` — precise status

**Implemented (P35); validate + copy ONLY.** `igniter app admit <bundle_dir> --release-root <dir>` validates
a P14 bundle through 10 fail-closed gates, then copies it (source is never moved/symlinked) into
`<release-root>/releases/<app>/<version>/`. Gates: (1) `manifest.json` present + parses (app/version/
runner.sha256), (2) `bundle_format_version == 1`, (3) `bind_policy == loopback`, (4) `public_release ==
false`, (5) runner re-hash matches `manifest.runner.sha256`, (6) every app source re-hash matches, (7) the
bundle's `checks/check.sh` passes (no socket/DB), (8) NO real `host.toml`, (9) a machine bundle
(`requires_machine`) carries `host.toml.example`, (10) duplicate destination refused (no `--force` in v0).
It does **not** touch `current`, install/enable systemd, bind, deploy, or run the app — admission is
validate+place only; activation stays host-owned.

### `igniter env` — precise status

**Implemented (P33 doctor/template, P34 check).** Source of truth = the commit-safe env-NAME catalogue
(`host.example.toml` in an app dir, `host.toml.example` in a bundle); the real `host.toml` is never read or
required. **Values are never read or printed — only env-var NAMES + set/unset/empty status.** No `.env` is
read; no injection.
- `igniter env doctor <path>` — report each required var + `set`/`unset`/`empty`; always exit 0 (a report).
- `igniter env template <path>` — blank `export NAME=` skeleton with `[section].key` comments; RHS stays
  blank even when the var is set.
- `igniter env check <path>` — the GATE: exit 0 when all required vars are set non-empty (or a pure app with
  no catalogue); exit 1 when any is unset/empty; exit 2 on an invalid catalogue (empty env-name / template
  syntax) or usage error.

### `igniter agent` — precise status

**Implemented (P23 shape → P24/P25/P26/P28/P34).** `igniter agent` launches the `igniter-agent` stdio
JSON-RPC MCP server (a DISTINCT surface from the language/machine `igniter-mcp`). Every tool **shell-delegates
to `bin/igniter`**, so it grants no authority of its own. Tools (all safe / non-mutating or bounded):
`doctor`, `toolchain_list`, `check_app`, `package_verify`, `app_bundle`, `serve_app_bounded`
(loopback + bounded ≤5, no daemon), `env_doctor`, `env_check`. Each result carries the P28 additive
envelope — `content[0]` human text + `content[1]` `{tool, ok, exit_code, stdout, stderr, parsed}`; `env_*`
tools' `parsed = {path, required_env:[{name,status}], ok}` and **never carry env values**. Missing required
args → clean tool error (`isError:true`, `ok:false`, `exit_code:null`). `tools/list` excludes
deploy/install/systemd/secret/apply/daemon/restart/bind/upload tools.

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
- **App deployment:** `igniter app admit` (validate + copy a bundle into `releases/<app>/<version>/`) IS
  live (P35), but **activation stays closed** — no `current` symlink swap, no systemd install/enable, no
  reverse proxy, no TLS, no DB creation/migration, no secrets/DSNs/real `host.toml` in a bundle, no public
  bind, no running the app.
- **Operator env:** `igniter env` (+ agent `env_*`) reports env-var NAMES and set/unset/empty only — **no
  `.env` reading, no value reading/printing, no injection, no secret management** (P33/P34).
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

**Superseded by P33/P34/P35:** any earlier framing of `igniter env`, the agent `env_*` tools, or `igniter
app admit` as reserved/deferred/readiness-only (e.g. the P30 env readiness packet, app-admit readiness) is
stale — `env doctor|template|check` (P33/P34), the agent `env_doctor`/`env_check` tools (P34), and `app
admit` (P35) are all **live**, as the sections above describe. The readiness packets stay as history.

## Authority boundary

`bin/igniter` is a router; it grants nothing. Real authority lives in the owners: loopback/public-bind
refusal + request bound in `igweb-serve`; package trust + `STDLIB_VERSION` in `igc`; host config + secrets in
`--host-config`/the host environment; the install fleet policy in `bin/igniter-install`. This doc is
descriptive hygiene, not a new authority.
