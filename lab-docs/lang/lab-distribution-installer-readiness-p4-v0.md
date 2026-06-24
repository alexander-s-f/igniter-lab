# lab-distribution-installer-readiness-p4-v0 — choose the v0 installer/distribution channel

**Card:** `LAB-DISTRIBUTION-INSTALLER-READINESS-P4` · **Type:** readiness (decision input, **no code**).
**Authority: lab readiness — a recommendation, not an install.** Closed surfaces honored: no implementation,
no public release, no package upload, no signed binaries, no production service install, no root-workspace
migration.

## Bottom line

**v0 first channel = a repo-local bootstrap script** (`bin/igniter-install`) that builds the **5 working
release binaries** and stages them onto a prefix on `PATH`, with the existing `bin/igniter` wrapper as the
front door. It is the smallest "install + run boring" step that needs **no new packaging infra, no root
workspace, no cross-compile, no live DB**, and reuses the P2 wrapper. The **native release tarball** is the
immediate next rung for repo-less tool install; the **release bundle + systemd** (Model E) stays the proven
first shape for *app deployment*. `.deb`/Docker/Homebrew/registry/signing are deferred.
Implementation card: **`LAB-DISTRIBUTION-BOOTSTRAP-INSTALL-P8`**.

## Verify-first basis (this session, against live source)

- **P1 packet** (`lab-distribution-ecosystem-readiness-p1-v0.md`) — install-surface comparison A/B/C v0-reachable, D/E precedent, F/G out; Rails-`s` shape.
- **P3 packet** (`lab-distribution-release-binary-matrix-p3-v0.md`) — the binary/feature/size matrix (below).
- **P2** (`lab-distribution-rails-serve-dx-p2-v0.md`) — `bin/igniter serve` wrapper already shipped (loopback, bounded, public-bind refused, `--check`).
- **P5** (`lab-distribution-root-workspace-readiness-p5-v0.md`) — defer root workspace; integration unit = release bundle; v0 DX = xtask/shell.
- **Repo layout:** no root workspace manifest (confirmed); 14 product crates, package-local builds.
- **Runtime assets (verified):** the binaries are **self-contained** — `stdlib/*.ig` are *source sketches* read only by Ruby proofs (`README`/`verify_stdlib.rb`), **not** by the Rust binaries; stdlib symbols (`sqrt`/`det_sqrt`/`map`/…) are **compiled-in builtins** (`typechecker/stdlib_calls.rs`, emitter `STDLIB_OPS`, `NUMERIC_MEASURE_BUILTINS_V0`); the IgWeb prelude is an embedded const (`igniter_compiler::igweb::PRELUDE_SOURCE`, written to a temp build dir). **No runtime stdlib/prelude/.ig asset to ship.**
- **Build prerequisite (verified, important):** the compiler does `include_str!("…/igniter-lang/docs/spec/stdlib-inventory.json")` (`multifile.rs:536`) — the **build** needs the canon repo `igniter-lang` checked out as a sibling. Compiled-in, so not a *runtime* asset, but the bootstrap script must verify the sibling checkout exists.
- **Secret/host-config (verified):** `igweb-serve --host-config` env-expands `host.toml` and **rejects inline secrets** at parse; DSNs arrive via env only; `tbackend` ships `/etc/tbackend/tbackend.config.json` as a **conffile template** (home-lab P4), no secret values.

### Binary matrix (from P3, this checkout, aarch64-apple-darwin, rustc 1.95.0)

| Binary | Crate | Build | Features | Size | v0 |
|---|---|---|---|---|---|
| `igniter_compiler` (CLI self-names `igc`) | lang/igniter-compiler | `cargo build --release` | none | 3.5M | ✅ |
| `igniter-vm` | lang/igniter-vm | `--release` | none | 5.1M | ✅ |
| `tbackend` | runtime/igniter-tbackend | `--release --bin tbackend` | default (FFI-free) | 1.3M | ✅ (home-lab tarball+deb) |
| `igniter-mcp` | runtime/igniter-machine | `--release --bin igniter-mcp` | default `[]` | 4.3M | ✅ |
| `igweb-serve` | server/igniter-web | `--release --bin igweb-serve` | default (machine-free) | 6.2M | ✅ |
| `igniter-repl` | runtime/igniter-machine | `--release --bin igniter-repl --features repl` | `repl` | — | ❌ **build fails** (6× E0308 async `checkpoint`/`resume`) |

**v0 install set = the 5 green binaries; `igniter-repl` is excluded until its async fix lands.**

## Channels compared (8 — well over the required 5)

| # | Channel | Works today? | v0 verdict |
|---|---|---|---|
| 1 | **`cargo install --path <crate>`** (per package) | Yes (package-local) | **Fallback, not first.** No single fleet command (no workspace, P5); `igc`/`igniter_compiler` name mismatch leaks into output; needs Rust **and** the `igniter-lang` sibling at build. Fine for "I already have the toolchain" but not the boring path. |
| 2 | **Repo-local bootstrap script** (`bin/igniter-install`) | Trivial to add | **★ Recommended v0.** Builds the 5 binaries, stages to a prefix (`~/.igniter/bin` or `./dist/bin`), puts `igniter` on `PATH`, verifies the `igniter-lang` sibling, installs `igniter_compiler` as `igc`, runs a loopback smoke. No new infra, no workspace, no cross-compile, no DB. |
| 3 | **Native release tarball** (selected binaries + manifest + SHA256SUMS) | Proven for `tbackend` (home-lab P3) | **Next rung** — for repo-less *tool* install. Generalize the tbackend P3 manifest (provenance fields below) to the 5 binaries. Out of the *first* slice (needs per-arch build discipline). |
| 4 | **Homebrew tap** | None | Deferred (closed surface; public-release theater). |
| 5 | **Docker image** | Design docs only | Deferred; never the first Pi-edge default (home-lab guidance). |
| 6 | **systemd / user service wrapper** | Proven for IgWeb loopback (pi5 P14/P18) | Part of Model E, not a standalone v0 channel; the `igniter` wrapper has no shell-hidden semantics so a unit can call it later (P2 note). |
| 7 | **Versioned app release bundle + runner + unit + checks** (Model E) | **Proven active on pi5-lab** (P14) | **First shape for *app deployment*** (distinct from tool install). Integration unit per P5. Not the tool-install channel. |
| 8 | **Language-specific package managers** (the Igniter package model) | Resolver lab-stage only | Deferred; the package/swarm direction is post-v0. |

## The 7 required answers

**1. First install channel & why.** Repo-local **bootstrap script** (channel 2). It makes local install + app
start boring for a developer working from the repo, with zero new packaging infrastructure, no root-workspace
churn (P5), no cross-compilation, and it composes with the already-shipped `bin/igniter serve` (P2).

**2. Intentionally deferred.** Tarball generalization (channel 3, next), `.deb` (channel D), Homebrew, Docker,
language package manager, signing, registry, public release; **`igniter-repl`** (build-broken); a true
single-command fleet build via a Cargo workspace (P5 gate).

**3. Files beside binaries.** Verified the binaries are **self-contained** (no runtime stdlib/prelude/.ig).
The bootstrap/tarball should still carry: (a) the `igniter` wrapper; (b) **config templates** —
`host.toml.example` (igweb-serve machine-mode) and the tbackend conffile template — never with secret values;
(c) optionally a **demo app** (`examples/todo_app`) for the smoke; (d) a `manifest`/`SHA256SUMS` (provenance
below). **Build-time only:** the `igniter-lang` sibling checkout (the `stdlib-inventory.json` `include_str!`).

**4. Feature flags → install variants.** Default install = **pure binaries** (igc, igniter-vm, igweb-serve
*machine-free*, igniter-mcp, tbackend *FFI-free*) — all dep-light (P3 `cargo tree` confirmed). Documented
**opt-in add-ons, never default:** `igweb-serve --features machine` (effect host + tokio), `--features
postgres` (tokio-postgres, requires a DSN), `igniter-machine --features tls|postgres|repl`, `tbackend
--features ffi` (magnus/Ruby headers). Each is a separate, labeled variant; v0 ships pure only.

**5. Loopback / public-bind / secret safety.** Public bind stays **refused** — `igweb-serve` rejects
non-loopback `--addr` (`parse_loopback_addr`), the `igniter serve` wrapper preserves it, and the installer
ships nothing that defaults to `0.0.0.0`. Secrets are **never baked**: host.toml/tbackend config are
env-var-placeholder **templates**; `igweb-serve` rejects inline secrets at parse; DSNs are env-only
(`IGNITER_*_DSN`). DB drivers (`postgres`) are opt-in and need a live DSN — excluded from the boring path.

**6. Card to implement v0.** **`LAB-DISTRIBUTION-BOOTSTRAP-INSTALL-P8`** — the bootstrap script (build 5
binaries → stage to prefix → `igniter`/`igc` on PATH → verify `igniter-lang` sibling → loopback smoke). Fold
in the **`igc` vs `igniter_compiler` name alignment** (P1/P3 flagged) — install as `igc` (or add `[[bin]]
name = "igc"`). A separate `LAB-…-REPL-ASYNC-RESUME-FIX` unblocks `igniter-repl` later (not a v0 dependency).

**7. Which home-lab shape to promote first — staged ladder.** Promote by *target*, not one-size:
- **Tool fleet (igc/vm/igweb-serve/mcp):** bootstrap script (v0) → **native tarball** first promotion (generalize tbackend P3).
- **App deployment (IgWeb app + runner to a host):** **release bundle + systemd (Model E)** first — already proven on pi5, no Docker, symlink-swap rollback.
- Then `.deb` (managed Debian hosts) → Docker/Compose (HP control-plane only). **Never Docker as the first Pi-edge default.** Homebrew/registry/signing last.

## Release bundle + systemd (Model E) vs `.deb` (Model D) — compared separately

| | **Release bundle + systemd (E)** | **`.deb` (D)** |
|---|---|---|
| Shape | app-shaped: `bin/runner + app/ + unit + checks + manifest`, versioned dir + `current` symlink | tool-shaped: `/usr/bin/<bin>` + conffile + `/var/lib`+`/var/log` + system unit |
| Install level | **user-level** (no root), `~/lab/releases/<ts>` | **system-level** (root/apt), dpkg database |
| Rollback | symlink swap to previous versioned dir | apt downgrade / reinstall |
| Toolchain needed | none (just files + a user systemd unit) | `dpkg-deb`, debian arch, packaging step |
| Proven | **IgWeb loopback active on pi5-lab (P14), smoke pi5-lab2 (P18)** | **tbackend amd64+arm64 (home-lab P4)**, `dpkg-deb`/`systemd-analyze verify` clean |
| Best for | **deploying an Igniter app** to edge/loopback | **installing a daemon/tool** on a managed host |
| Exposure | loopback `127.0.0.1` only | unit-defined; system service |

**Verdict:** they are *not* substitutes — E is the **app-deployment** rung (recommended first for apps), D is
the **managed-host tool** rung (later). v0 needs neither; both have real home-lab precedent to generalize.

## Provenance fields (carry into the v0 bootstrap manifest, from P3 / home-lab P3-P4)

`source_git_commit` (clean tag), `version`, `target_triple`, `build_host`/`arch`, per-binary `binary_sha256`,
`feature_set` (explicit `[]`), `smoke {result, service_touched:false}`, `public_release:false`. Tarball adds
`archive_sha256`/`config_sha256`; `.deb` adds `package`/`arch`/`package_sha256`/`conffiles`/`payload` +
`dpkg/systemd` verification + provenance link to the tarball.

## Acceptance — mapping

- [x] ≥5 distribution channels compared (8 in the table).
- [x] One v0 channel recommended + concrete implementation-card name (**bootstrap script → `LAB-DISTRIBUTION-BOOTSTRAP-INSTALL-P8`**).
- [x] Runtime asset/config requirements listed (binaries self-contained; config templates + demo app + build-time `igniter-lang` sibling).
- [x] Public bind, secrets, DB drivers, optional FFI handled explicitly (§5 + §4).
- [x] Release-bundle + systemd compared **separately** from `.deb` (dedicated table).
- [x] No code changes; `git diff --check` clean.

## Closed surfaces (honored)

No implementation, no public release, no package upload, no signed binaries, no production service install, no
root-workspace migration.

---

*Lab readiness. 2026-06-24. v0 install channel = repo-local bootstrap script staging the 5 green release
binaries (igc/igniter-vm/igweb-serve/igniter-mcp/tbackend; `igniter-repl` excluded — build-broken) onto PATH
behind `bin/igniter`, no root workspace, no new infra. Binaries are self-contained (stdlib/prelude embedded);
build needs the `igniter-lang` sibling. Pure-default install; machine/postgres/tls/ffi/repl are opt-in
variants. Public-bind refused, secrets env-only. Promote tarball first for tools, release-bundle+systemd first
for apps; `.deb`/Docker/Homebrew deferred. Impl → LAB-DISTRIBUTION-BOOTSTRAP-INSTALL-P8.*
