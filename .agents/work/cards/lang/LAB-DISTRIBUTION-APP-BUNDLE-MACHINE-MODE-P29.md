# LAB-DISTRIBUTION-APP-BUNDLE-MACHINE-MODE-P29 - make app bundles host-config ready

Status: CLOSED (2026-06-25) — machine-mode bundles host-config ready (run precedence + systemd HOST_CONFIG + check); pure apps byte-compat; app-bundle 7/7
Lane: distribution / app bundle
Type: implementation + proof
Date: 2026-06-25
Skill: idd-agent-protocol

## Context

P14 implemented `igniter app bundle` and P16 proved the emitted `run/run-*.sh` serves the pure
`todo_app` from inside the bundle.

The next product-shaped app is `server/igniter-web/examples/todo_postgres_app`. It ships a commit-safe
`host.example.toml` and is the real pressure surface for DB-backed apps. Today the bundler copies
`host.example.toml` to `host.toml.example` and marks `requires_machine:true`, but the emitted run/check
scripts do not yet give the operator a crisp host-config path for machine-mode startup.

This card is still **assembly/DX only**. It must not create databases, install systemd, bind publicly, or
ship real secrets.

## Goal

Make a P14 bundle ergonomic and explicit for machine-mode apps:

```text
bundle/
  host.toml.example       # commit-safe template, already copied
  host.toml               # optional host-owned real file, created by operator later; never bundled by Igniter
  run/run-<app>.sh        # passes --host-config when explicitly supplied or when bundle/host.toml exists
  checks/check.sh         # remains safe without requiring secrets/DB
```

The operator flow should be obvious:

```bash
cp host.toml.example host.toml
export IGNITER_TODO_PG_DSN=...
export IGNITER_TODO_EFFECT_TOKEN=...
run/run-todo_postgres_app.sh
```

## Verify First

- Read `bin/igniter` `app_bundle`.
- Read `server/igniter-web/tests/igniter_app_bundle_smoke_tests.rs`.
- Read `server/igniter-web/examples/todo_postgres_app/host.example.toml`.
- Read `server/igniter-web/examples/todo_postgres_app/RUNBOOK.md`.
- Verify current emitted `run/run-*.sh` does not pass `--host-config`.
- Verify `igweb-serve` still resolves host config before bind and redacts DSN/token values.

## Required Behavior

1. For bundles with `host.toml.example`, the emitted run script must support a host-config path:
   - `IGNITER_<APP>_HOST_CONFIG=/path/to/host.toml` wins if set;
   - otherwise, if `bundle/host.toml` exists, pass `--host-config bundle/host.toml`;
   - otherwise run without `--host-config` and print a short non-secret note that machine-mode config is not
     active.
2. Never pass `host.toml.example` as a real config by default.
3. The emitted systemd template should show the host-owned env var names for machine-mode apps:
   - `Environment=IGNITER_<APP>_HOST_CONFIG=%h/.../host.toml` as an editable example;
   - comments must say values live in env vars referenced by `host.toml`, not in the unit.
4. `manifest.json` should keep `requires_machine:true` for apps with `host.toml.example`; do not add secrets.
5. `checks/check.sh` should keep opening no DB/socket. It may assert `host.toml.example` exists when
   `requires_machine:true`, but it must not require a real `host.toml` or env vars.
6. Existing pure `todo_app` bundle behavior must remain byte/behavior compatible except for harmless comments.

## Acceptance

- [x] Bundling `examples/todo_postgres_app` succeeds and emits `host.toml.example`.
- [x] Manifest has `requires_machine:true`, `bind_policy:"loopback"`, and no DSN/token/passport values.
- [x] Emitted `run/run-todo_postgres_app.sh` has exactly the host-config precedence:
      `IGNITER_TODO_POSTGRES_APP_HOST_CONFIG` env override → bundle `host.toml` if present → none (+ note).
- [x] Emitted run script never passes `host.toml.example` as a config (only `--host-config $here/host.toml`
      or the env var; `.example` appears only in a human note).
- [x] Emitted systemd example names `IGNITER_TODO_POSTGRES_APP_HOST_CONFIG`, no secret values (comment says
      values live in env vars `host.toml` references, not the unit).
- [x] `checks/check.sh` passes on the produced bundle with `IGNITER_TODO_PG_DSN` removed (no DB env).
- [x] Existing pure-app tests pass incl P16 run smoke (`emitted_run_script_serves_from_bundle_on_loopback`);
      pure `todo_app` run script is unchanged (0 host-config refs).
- [x] Secret-refusal tests still pass (real `host.toml` + inline secret refused, no partial, no leak).
- [x] `igniter_agent_mcp_smoke_tests` 16/16 (the `app_bundle` envelope still parses the manifest).
- [x] `bash -n bin/igniter` + `git diff --check` clean.

## Reporting

1. **Host-config precedence (emitted run, machine-mode only):** three explicit `exec` branches —
   `IGNITER_<APP>_HOST_CONFIG` env override → `$here/host.toml` if present → no `--host-config` (prints a
   non-secret "machine-mode config not active" note). Pure apps keep the original single-line `exec`.
2. **`host.toml.example`:** copied into the bundle (env-NAMES only), but **never used as a real config** —
   the run script only feeds `--host-config` the env var or `$here/host.toml`; `.example` is named solely in
   the "copy host.toml.example → host.toml" operator note. A real `host.toml` is never bundled.
3. **Bundle files changed for machine-mode apps:** `run/run-<app>.sh` (host-config precedence),
   `systemd/<app>.service.example` (adds `Environment=IGNITER_<APP>_HOST_CONFIG=…` + secrets-in-env comment),
   `checks/check.sh` (asserts `host.toml.example` exists; still opens no socket/DB, requires no real
   host.toml/env). `manifest.json` unchanged (already `requires_machine:true`). **Pure apps:** all three
   emissions are byte/behavior-identical to P14.
4. **Test counts:** `igniter_app_bundle_smoke_tests` **7/7** (new `bundle_todo_postgres_app_is_machine_mode_ready`
   + P16 run smoke), `igniter_agent_mcp_smoke_tests` **16/16**, `igniter_serve_wrapper_smoke_tests` **17/17**.

Implementation: `bin/igniter` `app_bundle` (conditional run/check/systemd emission on `$requires_machine`).
Test: `server/igniter-web/tests/igniter_app_bundle_smoke_tests.rs`. Still assembly-only — no DB, no live
machine run, no real host.toml, no secrets.

## Closed Surfaces

No DB creation/migration. No live Postgres requirement. No systemd install/enable. No current symlink. No
public bind. No TLS/reverse proxy. No Docker. No secrets or real `host.toml` in the bundle. No deploy/apply.
