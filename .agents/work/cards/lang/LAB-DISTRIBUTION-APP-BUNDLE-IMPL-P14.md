# LAB-DISTRIBUTION-APP-BUNDLE-IMPL-P14 - implement `igniter app bundle`

Status: CLOSED (2026-06-25) — `igniter app bundle` implemented in bin/igniter; 5 focused tests green; no regression
Lane: distribution / app deployment
Type: implementation + proof
Date: 2026-06-25
Skill: idd-agent-protocol

## Context

Depends on:

- `LAB-DISTRIBUTION-APP-BUNDLE-READINESS-P13`
- `LAB-DISTRIBUTION-CONTROL-CENTER-CLI-SKELETON-P7`
- `LAB-DISTRIBUTION-DOCTOR-IMPL-P10`

P13 decided the contract: `igniter app bundle` owns **assembly only**. It produces a versioned directory
containing runner + app + run/check scripts + examples + manifest. It does not install systemd, expose a
public listener, create a DB, manage TLS, ship secrets, or mutate the host.

## Goal

Implement:

```text
igniter app bundle <app_dir> --out <dir> --version <stamp>
```

as orchestration in `bin/igniter`, matching P13.

## Verify First

- Read P13 packet.
- Read current `bin/igniter` `cmd_app` placeholder.
- Read `igweb-serve check` / `bin/igniter check` behavior.
- Read `server/igniter-web/examples/todo_app` and `examples/todo_postgres_app`.
- Read host config validator / examples:
  - `server/igniter-web/src/host_config.rs`
  - `server/igniter-web/examples/todo_postgres_app/host.example.toml`
- Read home-lab release-bundle precedent if needed:
  - `/Users/alex/dev/projects/igniter-workspace/igniter-home-lab/deploy/igniter-stack-deployment-models.md`
  - `/Users/alex/dev/projects/igniter-workspace/igniter-home-lab/deploy/pi5-lab/*`

## Required Behavior

- Command shape:
  - `igniter app bundle <app_dir> --out <dir> --version <stamp>`
  - `--help` documents assembly-only and host-owned surfaces.
- Fail closed if:
  - `<app_dir>` is missing;
  - `--out` missing;
  - `--version` missing (no clock in tool);
  - `igweb-serve check <app_dir>` fails;
  - app dir contains a real `host.toml`;
  - candidate host example contains inline secret keys;
  - non-loopback bind/mode is detected in bundled config, if such a field exists.
- Emit layout:
  ```text
  <out>/<appname>-<version>/
    bin/igweb-serve
    app/<appname>/...
    run/run-<appname>.sh
    checks/check.sh
    systemd/<appname>.service.example
    host.toml.example        # only if source app has host.example.toml
    manifest.json
  ```
- Runner is copied and sha256-pinned.
- App source files are copied verbatim and hashed in `manifest.json`.
- `manifest.json` includes at least:
  `bundle_format_version`, `tool`, `app`, `entry`, `created_utc` or caller-supplied `version`,
  runner path/sha256/target_triple/source_git_commit, app source hashes, `bind_policy:"loopback"`,
  `requires_machine`, `public_release:false`.
- Emitted `checks/check.sh` must pass on the produced bundle.
- Emitted run script defaults to loopback and delegates public-bind refusal to `igweb-serve`.
- No secrets, no real host config, no systemd install, no symlink swap.

## Acceptance

- [x] Bundling `server/igniter-web/examples/todo_app` succeeds into a temp out dir.
- [x] Bundle layout matches P13 (`bin/ app/<name>/ run/ checks/ systemd/*.example manifest.json`).
- [x] `manifest.json` validates as JSON (parsed in test) and includes runner sha256 + per-source hashes.
- [x] Copied `bin/igweb-serve` sha256 matches manifest (re-hashed in test, asserted equal).
- [x] Emitted `checks/check.sh` succeeds (run on the produced bundle in-test; also self-validated at emit time).
- [x] Equivalent dry path: the bundle ships `checks/check.sh` (runs `igweb-serve check`, opens no socket,
      passes). The emitted `run/run-<appname>.sh` binds loopback; no `--check` flag was added to it.
- [x] App containing real `host.toml` is refused; assembly is staged in `mktemp -d` and moved atomically, so
      NO partial bundle is left at the destination (asserted).
- [x] Inline secret in a host example is refused WITHOUT printing the value (sed strips after `=`; test
      asserts the secret string is in neither stdout nor stderr).
- [x] `igniter app bundle --help` names host-owned surfaces (systemd / TLS / secrets / bind).
- [x] Existing tests green: wrapper 16/16, package 9/9, doctor 6/6; new app-bundle suite 5/5.
- [x] `git diff --check` clean.

## Implementation notes

- Implemented entirely in `bin/igniter` (`app_usage` + `app_bundle` + `cmd_app` dispatch, + small
  `sha256_of`/`host_triple`/`toml_str` helpers). No crate source touched; reuses `resolve_igweb_serve` and
  `igweb-serve check`. Per P5, orchestration only — no workspace, no daemon, no new authority.
- Fail-closed ordering: all validation (args, real-`host.toml`, secret scan, loopback gate, `igweb-serve
  check`) runs BEFORE any destination dir exists; assembly stages in `mktemp -d` and `mv`s into place only
  after the emitted `checks/check.sh` passes — a refused bundle never leaves a partial directory.
- No clock in the tool: `--version` is mandatory and mirrored into `manifest.json` `created_utc`.
- Tests: `server/igniter-web/tests/igniter_app_bundle_smoke_tests.rs` (runner pinned via
  `IGNITER_IGWEB_SERVE_BIN`; no nested cargo build).
- Follow-on (out of scope): cross-arch runner bundles (v0 bundles host-arch + records the triple); a
  `.deb`/tarball wrapper around a produced bundle.

## Closed Surfaces

No systemd install. No production deploy. No public bind. No TLS/reverse proxy. No DB creation/migration.
No Docker. No secrets in bundle. No root workspace. No remote packaging/upload/signing.

