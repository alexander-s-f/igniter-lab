# LAB-DISTRIBUTION-INSTALLER-READINESS-P4 - choose v0 installer/distribution channel

Status: CLOSED (readiness — v0 = repo-local bootstrap script; impl → LAB-DISTRIBUTION-BOOTSTRAP-INSTALL-P6)
Lane: distribution / installer readiness
Type: readiness
Date: 2026-06-24
Skill: idd-agent-protocol

## Context

Once P1 maps the ecosystem and P3 proves release builds, choose the first user-facing distribution channel.
The goal is developer ergonomics, not public release theater. The first channel should make local install
and app start boring while preserving authority boundaries.

Home-lab evidence exists for three relevant distribution shapes:

- native per-arch tarball (`artifacts/tbackend/p3`);
- `.deb` with config/data/log dirs + systemd unit (`artifacts/tbackend/p4`);
- versioned release bundle + systemd loopback service for IgWeb apps
  (`deploy/igniter-stack-deployment-models.md`, `deploy/pi5-lab/*`).

## Goal

Decide the v0 distribution channel for Igniter tools:

- `cargo install --path` per package;
- repo-local bootstrap script;
- release tarball containing selected binaries;
- Homebrew tap;
- Docker image;
- systemd/user service wrapper;
- versioned app release bundle with runner binary + app dir + checks + unit;
- language-specific package managers.

## Verify First

- Read P1 and P3 packets if available.
- Check current repo layout and absence/presence of root workspace manifest.
- Check whether binaries need runtime assets, stdlib files, app examples, or generated artifacts.
- Check host-config/secret expectations for `igweb-serve` and `tbackend`.
- Use TBackend distribution split as precedent, not as unquestioned template.
- Read `deploy/igniter-stack-deployment-models.md` and the Pi loopback service/run scripts. Pay special
  attention to rollback via versioned release dir/current symlink, loopback bind, smoke checks, and
  avoiding Docker as the first Pi-edge default.

## Required Packet

Write:

`lab-docs/lang/lab-distribution-installer-readiness-p4-v0.md`

Answer:

1. What is the first install channel and why?
2. What is intentionally deferred?
3. What files must be included beside binaries?
4. How do feature flags map to install variants?
5. How does the install story preserve loopback/public-bind and secret safety?
6. What card should implement v0?
7. Which home-lab shape should be promoted first for general Igniter: tarball, `.deb`, release bundle,
   Docker/Compose, or a staged ladder?

## Acceptance

- [x] At least 5 distribution channels are compared.
- [x] One v0 channel is recommended with a concrete implementation-card name.
- [x] Runtime asset/config requirements are listed.
- [x] Public bind, secrets, DB drivers, and optional FFI are handled explicitly.
- [x] Release-bundle + systemd is compared separately from `.deb` packaging.
- [x] No code changes.
- [x] `git diff --check` clean.

## Closed Surfaces

No implementation. No public release. No package upload. No signed binaries. No production service install.
No root workspace migration unless separately authorized.

## Closing Report

Packet: `lab-docs/lang/lab-distribution-installer-readiness-p4-v0.md`.

**v0 channel = repo-local bootstrap script** (`bin/igniter-install`): build the **5 green release binaries**
(igc/igniter-vm/igweb-serve/igniter-mcp/tbackend), stage to a PATH prefix behind the P2 `bin/igniter` wrapper,
verify the `igniter-lang` sibling, install `igniter_compiler` as `igc`, loopback smoke. No new infra, no root
workspace (P5), no cross-compile, no DB. **Impl card → `LAB-DISTRIBUTION-BOOTSTRAP-INSTALL-P6`.**

**Verify-first (live source):** binaries are **self-contained** — `stdlib/*.ig` are source sketches (read
only by Ruby proofs), stdlib symbols are compiled-in builtins, IgWeb prelude is an embedded const → **no
runtime asset to ship**. **Build prereq:** compiler `include_str!`s canon `igniter-lang/.../stdlib-inventory.json`
→ sibling checkout required at build. `igniter-repl` **excluded** (P3: build-broken, async E0308). Binary name
`igniter_compiler` ≠ `igc` (fold alignment into P6).

**Answers:** (1) bootstrap script; (2) deferred = tarball-generalization/.deb/Homebrew/Docker/pkg-mgr/signing
+ repl; (3) self-contained binaries + config *templates* + optional demo app + build-time igniter-lang
sibling; (4) pure default install, `machine`/`postgres`/`tls`/`ffi`/`repl` opt-in variants only; (5)
public-bind refused (igweb-serve gate, preserved by wrapper), secrets env-only/templates, postgres opt-in
needs DSN; (6) `LAB-DISTRIBUTION-BOOTSTRAP-INSTALL-P6`; (7) staged ladder — **tarball first for tools,
release-bundle+systemd (Model E) first for apps**, then `.deb`→Docker, never Docker as first Pi-edge default.

**≥5 channels compared (8).** Release-bundle+systemd compared **separately** from `.deb` (E = app-shaped,
user-level, symlink rollback; D = tool-shaped, system-level, apt). **No code changes; `git diff --check` clean.**
