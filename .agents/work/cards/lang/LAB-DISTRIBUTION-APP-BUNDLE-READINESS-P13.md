# LAB-DISTRIBUTION-APP-BUNDLE-READINESS-P13 - define `igniter app bundle`

Status: CLOSED (2026-06-25) — packet at lab-docs/lang/lab-distribution-app-bundle-readiness-p13-v0.md
Lane: distribution / app deployment readiness
Type: readiness
Date: 2026-06-25
Skill: idd-agent-protocol

## Context

P6 reserved `igniter app bundle`, but deliberately left app deployment in the home-lab release-bundle +
systemd scripts. Before implementing a first-class command, capture exactly what belongs in Igniter and what
must stay host/operator-owned.

The desired shape is not "Igniter installs a daemon". It is "Igniter can assemble a versioned app bundle that
a host/deploy layer can run".

## Goal

Design the v0 `igniter app bundle` contract.

This is readiness only. Do not implement `app bundle` here.

## Verify First

- Read P6 control-center packet.
- Read P4 installer readiness and P5 root-workspace readiness.
- Read home-lab deployment docs:
  - `igniter-home-lab/deploy/igniter-stack-deployment-models.md`
  - relevant `deploy/pi5-lab/*` run scripts/units
- Read current `igweb-serve` app directory expectations and `igweb.toml` manifest shape.
- Check whether TodoApp API / IgWeb examples need host config templates, app dir copying, or runner binary pinning.

## Required Packet

Write:

`lab-docs/lang/lab-distribution-app-bundle-readiness-p13-v0.md`

Answer:

1. What files are in an Igniter app bundle v0?
2. Is the runner copied, symlinked, or referenced by path?
3. What manifest/provenance fields are required?
4. Where do `host.toml.example`, env names, and secret boundaries live?
5. What checks does `igniter app bundle` run before producing a bundle?
6. How does the bundle preserve loopback/public-bind safety?
7. What remains outside the bundle: systemd install, reverse proxy, TLS, DB creation, secrets, Docker?
8. What is the first implementation card?

## Acceptance

- [x] Home-lab release-bundle/systemd precedent summarized with exact boundaries (§1; Model B/E layout, what it proved vs left host-owned).
- [x] Bundle file layout specified (§2; `<appname>-<version>/{bin,app,run,checks,systemd/*.example,host.toml.example?,manifest.json}`).
- [x] Manifest/provenance fields specified (§4; runner sha256/version/triple, per-source hashes, bind_policy, requires_machine, stdlib_version, public_release:false — no secrets).
- [x] Host-owned surfaces explicitly excluded (§8: systemd enable, bind/proxy, TLS, DB, secrets, Docker, symlink swap).
- [x] Loopback/secret safety model preserved (§6 secret gate reuses `load_host_config`; §7 bind safety stays single-sourced in igweb-serve; bundle bakes no bind authority).
- [x] First implementation card named (§9: `LAB-DISTRIBUTION-APP-BUNDLE-IMPL-P14`, orchestration per P5; then wire `igniter app …` like P12's package→igc).
- [x] No code changes (design only).
- [x] `git diff --check` clean.

## Key decisions

- **Runner is COPIED + sha256-pinned** (not symlinked/path-referenced) — matches the proven mesh-status
  bundle; the `run-todo` path-reference is the non-bundle dev shortcut.
- **Secret boundary reuses the existing validator:** the bundler refuses to package a real `host.toml` or any
  inline-secret host config; only `host.toml.example` (env-NAMES only) ships.
- **No clock in the tool:** the provenance stamp is caller-supplied (`--version`) for determinism/replay.
- **app/host split honored:** `app bundle` owns ASSEMBLY only; bind/systemd/TLS/DB/secrets stay host-owned.

## Closed Surfaces

No implementation. No systemd install. No production deploy. No public bind. No TLS/reverse proxy. No DB
creation. No Docker. No secrets in bundle.
