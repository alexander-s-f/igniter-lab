# LAB-DISTRIBUTION-ECOSYSTEM-READINESS-P1 - distribution map for Igniter binaries and DX

Status: CLOSED (2026-06-24) — packet at lab-docs/lang/lab-distribution-ecosystem-readiness-p1-v0.md
Lane: distribution / DX
Type: readiness + inventory
Date: 2026-06-24
Skill: idd-agent-protocol

## Context

TBackend has crossed an important line: it can be built and operated as a pure Rust daemon with the Ruby
FFI split out behind an opt-in feature. The rest of the Igniter ecosystem is approaching the same pressure:
server, compiler, VM, machine, and app runners need a simple "install and run" story. The user explicitly
wants Rails-like ergonomics: a web app should feel as easy to start as `rails s`.

Current live shape to verify:

- package-local Cargo projects, no root workspace manifest;
- `lang/igniter-compiler` owns `igc`;
- `server/igniter-web` owns `igweb-serve`;
- `lang/igniter-vm` owns `igniter-vm`;
- `runtime/igniter-machine` owns `igniter-mcp` and optional `igniter-repl`;
- `runtime/igniter-tbackend` owns `tbackend` with FFI opt-in.

Private home-lab distribution evidence exists and should be mined as precedent, not copied blindly:

- `/Users/alex/dev/projects/igniter-workspace/igniter-home-lab/artifacts/tbackend/p3/` —
  native tarball proof for `x86_64-unknown-linux-gnu` and `aarch64-unknown-linux-gnu`, with
  `manifest.json`, `SHA256SUMS`, binary SHA, archive SHA, config SHA, smoke result, build host, and
  `public_release:false`.
- `/Users/alex/dev/projects/igniter-workspace/igniter-home-lab/artifacts/tbackend/p4/` —
  `.deb` proof for `amd64` and `arm64`, with payload shape (`/usr/bin/tbackend`,
  `/etc/tbackend/tbackend.config.json`, `/var/lib/tbackend/`, `/var/log/tbackend/`,
  systemd unit) and `dpkg-deb`/systemd verification.
- `/Users/alex/dev/projects/igniter-workspace/igniter-home-lab/deploy/` —
  release-bundle + systemd deployment models for IgWeb loopback apps and Docker/Compose readiness.
- `/Users/alex/dev/projects/igniter-workspace/igniter-home-lab/docs/inventory/` —
  lab device inventory (`ai-main-lab`, `pi5-lab`, `pi5-lab2`) available for future distribution
  experiments. Treat as private lab evidence; do not copy host secrets or mutate hosts from this card.

## Goal

Produce the distribution/DX map before implementing installers. The map must answer:

1. Which binaries exist today and what command builds each one?
2. Which are developer tools, app runners, daemons, MCP/agent surfaces, or experimental frontends?
3. Which are safe for default install, and which require opt-in features (`postgres`, `tls`, `repl`, `ffi`)?
4. What should the first ergonomic command be (`igniter serve`, `igweb-serve`, wrapper script, or package-local alias)?
5. What should stay out of v0 (registry, Homebrew, Docker, systemd, public listener, signing)?

## Verify First

- Inspect every `Cargo.toml` under `lang/`, `runtime/`, `server/`, `frame-ui/`, and `ide/`.
- List existing `[[bin]]` entries and implicit binaries.
- Run `cargo build --release --bin <name>` for a representative subset only if cheap; otherwise name exact
  commands without building all of them.
- Read `runtime/igniter-tbackend/Cargo.toml` for the FFI split pattern.
- Read the home-lab TBackend distribution manifests (`artifacts/tbackend/p3`, `p4`) and deployment
  docs listed above. Extract lessons, not private host config.
- Read `server/igniter-web/src/bin/igweb-serve.rs` and its help/tests to understand current runner DX.
- Check `README.md`, `MAP.md`, and `current-waves-index.md` for stale distribution claims.

## Required Packet

Write:

`lab-docs/lang/lab-distribution-ecosystem-readiness-p1-v0.md`

Required sections:

- **Binary inventory:** crate, binary name, build command, features, intended audience.
- **Install surfaces:** `cargo install --path`, release tarball, shell wrapper, Docker/systemd/Homebrew
  readiness, with verdicts.
- **TBackend lesson:** pure Rust core first, optional host bindings/adapters second.
- **Home-lab ladder:** native tarball, `.deb`, release-bundle + systemd, Docker/Compose; what each
  proved and what it did not prove.
- **Rails-s analogue:** what the v0 app-start command should feel like and what it should not hide.
- **Risks:** root workspace churn, dependency size, feature flags, config/secrets, public bind safety.
- **Recommended next cards:** max 5.

## Acceptance

- [x] Packet inventories all current Rust binaries and feature-gated binaries (§1; 14 manifests, all bins).
- [x] At least 3 install/distribution alternatives are compared (§2: A cargo-local / B tarball / C wrapper + D/E/F/G).
- [x] Recommendation names one first implementation slice for "Rails-like serve" (§5 → feeds existing card `LAB-DISTRIBUTION-RAILS-SERVE-DX-P2`).
- [x] TBackend FFI split lesson is explicitly mapped to server/compiler/machine (§3 table).
- [x] Home-lab tarball/deb/bundle evidence is summarized with exact artifact/doc paths (§4; p3/p4/deploy/inventory).
- [x] No implementation/code changes (map only).
- [x] `git diff --check` clean.

## Findings beyond the card

- **Live-shape correction:** the compiler builds as `igniter_compiler` (implicit `src/main.rs`), but
  self-names `igc` in help — no `[[bin]] name = "igc"`. Real DX gap, routed to P3 / a name-alignment card.
- **Existing wave reconciled:** P2–P5 distribution cards were already drafted; §7 sequences the REAL cards
  instead of inventing new names (one genuinely-new gap noted: binary-name alignment).

## Closed Surfaces

No root workspace migration. No installer implementation. No public release claim. No Homebrew tap, Docker
image, systemd unit, signing, registry, or binary distribution upload.
