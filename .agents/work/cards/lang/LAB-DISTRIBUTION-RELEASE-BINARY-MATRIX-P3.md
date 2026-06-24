# LAB-DISTRIBUTION-RELEASE-BINARY-MATRIX-P3 - release-build matrix for core Igniter binaries

Status: CLOSED (2026-06-24)
Lane: distribution / release evidence
Type: proof + documentation
Date: 2026-06-24
Skill: idd-agent-protocol

## Context

Before adding installers, we need a boring fact packet: which binaries build in release mode, which
features are required, how large they are, and which dependency/feature boundaries matter. This mirrors
the TBackend lesson: prove the pure default first; opt-in heavier host bindings separately.

Home-lab precedent to reuse:

- TBackend P3 native tarballs recorded archive SHA, binary SHA, config SHA, build host, target triple,
  and loopback smoke without touching the standing service.
- TBackend P4 `.deb` manifests recorded package SHA, payload, conffiles, unit validity, extracted ELF
  architecture, and per-arch verification.

This card should not produce `.deb` packages, but its matrix should be shaped so a later packager can
turn it into tarballs or packages without losing provenance.

## Goal

Build and document the current release binary matrix for core developer/runtime tools.

Candidate binaries:

- `igc` from `lang/igniter-compiler` (implicit or explicit binary; verify actual name).
- `igweb-serve` from `server/igniter-web`.
- `igniter-vm` from `lang/igniter-vm`.
- `igniter-mcp` from `runtime/igniter-machine`.
- `igniter-repl` from `runtime/igniter-machine --features repl`.
- `tbackend` from `runtime/igniter-tbackend`.

## Verify First

- Inspect each `Cargo.toml` and `src/main.rs`/`src/bin/*`.
- Run release builds package-locally; do not invent a root workspace.
- Capture exact commands and whether they require features.
- Compare output fields against home-lab `artifacts/tbackend/p3/manifest.json` and `p4/manifest.json`;
  decide which fields belong in a generic Igniter binary matrix.
- Use `cargo tree -e normal` where useful to verify default builds do not pull optional stacks.

## Required Packet

Write:

`lab-docs/lang/lab-distribution-release-binary-matrix-p3-v0.md`

Include:

- build command;
- binary path;
- size;
- feature flags;
- default vs optional dependency notes;
- known warnings;
- whether the binary is candidate for v0 install.
- recommended provenance fields for future tarball/deb manifests (`source_git_commit`, target triple,
  binary SHA, archive/package SHA, feature set, smoke result, `public_release:false` while lab-only).

## Acceptance

- [x] Release-build matrix covers all candidate binaries above or explains omissions.
- [x] Pure defaults are distinguished from feature-gated builds.
- [x] `tbackend` default build is confirmed FFI-free.
- [x] `igniter-web` default vs `machine`/`postgres` feature story is documented.
- [x] Matrix includes future package manifest fields learned from home-lab TBackend P3/P4.
- [x] No code changes unless a trivial packaging metadata issue blocks build and is explicitly justified.
- [x] `git diff --check` clean.

## Result (2026-06-24)

Packet written: `lab-docs/lang/lab-distribution-release-binary-matrix-p3-v0.md`.

Measured on `aarch64-apple-darwin`, rustc 1.95.0, commit `a742763` (tree dirty — lab WIP). No root
workspace; every build run package-locally.

**5 of 6 candidate binaries build clean in release and smoke-pass:**

| binary file | crate | features | size | smoke |
|---|---|---|---|---|
| `igniter_compiler` | igniter-compiler | none | 3.5M | usage |
| `igniter-vm` | igniter-vm | none | 5.1M | usage |
| `tbackend` | igniter-tbackend | default (FFI-free) | 1.3M | banner/usage |
| `igniter-mcp` | igniter-machine | default `[]` | 4.3M | stdio MCP ready→clean EOF |
| `igweb-serve` | igniter-web | default (machine-free) | 6.2M | usage |

(sha256 for each recorded in the packet.)

**1 fails — documented, not fixed (per Closed Surfaces):** `igniter-repl` (`--features repl`) fails with
6× E0308 — `repl.rs` calls async `checkpoint`/`resume` without `.await` (sites: 558, 576, 894). Real
source bug, not packaging metadata. Follow-up card recommended.

Other findings:
- **Binary-name caveat:** the compiler artifact is `igniter_compiler` (no `[[bin]]` override), not `igc`;
  CLI usage self-labels `igc`. A packager shipping `igc` must rename or add `[[bin]] name="igc"`.
- Pure defaults confirmed dep-light via `cargo tree -e normal`: tbackend FFI-free (magnus=0; `ffi`→magnus);
  machine default free of ratatui/crossterm/rustls/tokio-postgres; igniter-web default free of
  tokio-postgres. `igniter-web` `machine` feature gates the igniter_server effect-host serving path (the
  `igniter_machine` lib is always linked); `postgres` ⊃ `machine` + tokio-postgres (gated e2e only).
- Provenance fields for future tarball/`.deb` manifests captured from home-lab TBackend P3/P4
  (source_git_commit, target_triple, binary/archive/package/config sha256, feature_set, smoke+service_touched,
  public_release:false; plus deb conffiles/payload/dpkg verification/systemd_analyze_verify).

Acceptance: all checked. No code changed. `git diff --check` clean (new doc untracked).

Next route: (1) `LAB-…-REPL-ASYNC-RESUME-FIX` to recover `igniter-repl`; (2) optional packager card can
consume this matrix to produce tarballs/`.deb` (still no installer/upload/signing here).

## Closed Surfaces

No installer. No binary upload. No cross-compilation. No signing/notarization. No Docker. No workspace-root
Cargo migration.
