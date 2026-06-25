# LAB-DISTRIBUTION-IGNITER-ENV-READINESS-P30 - design `igniter env` and environment authority

Status: CLOSED (2026-06-25) — recommends `igniter env doctor|template` (B+C) reading host.example.toml catalogue, `.env` OUT of v0, secret-safe (names/present/empty only); first impl = P33; packet at lab-docs/lang/lab-distribution-igniter-env-readiness-p30-v0.md
Lane: distribution / env / operator config
Type: readiness / research
Date: 2026-06-25
Skill: idd-agent-protocol

## Context

Igniter now has several environment-shaped surfaces:

- `host.toml` with env-var names only (`dsn_env`, `passport_env`, etc.).
- `igniter doctor` and `doctor --json`.
- `igniter app bundle` emitting run scripts, systemd examples, `host.toml.example`, and manifests.
- `todo_postgres_app` runbook and smoke requiring DSN/token env vars.
- `igniter-agent` structured MCP envelopes, useful for machine-readable diagnostics.

The product pressure is Rails-like DX without smuggling secrets or deployment authority into `.ig` or
bundles. We need one coherent answer for `igniter env`, not a pile of ad-hoc dotenv conventions.

## Goal

Produce a readiness packet for an `igniter env` surface:

```text
igniter env doctor <app_or_bundle>
igniter env template <app_or_bundle>
igniter env check <app_or_bundle> [--host-config PATH]
```

This card must decide what v0 should do, what it must refuse, and how it relates to `host.toml`,
`host.toml.example`, systemd templates, `.env`, direnv, Docker/Compose, and MCP agent use.

## Verify First

Read live code/docs before recommending:

- `server/igniter-web/src/host_config.rs`
- `server/igniter-web/src/bin/igweb-serve.rs`
- `bin/igniter` (`doctor`, `app bundle`, `toolchain`)
- `server/igniter-web/examples/todo_postgres_app/host.example.toml`
- `server/igniter-web/examples/todo_postgres_app/RUNBOOK.md`
- `server/igniter-web/IMPLEMENTED_SURFACE.md`
- `lab-docs/lang/lab-distribution-implemented-surface-v0.md`
- P28 `igniter-agent` structured envelopes
- Home-lab distribution docs if useful:
  `/Users/alex/dev/projects/igniter-workspace/igniter-home-lab/deploy/`

## Questions To Answer

1. Is `igniter env` a new front-door subcommand, a `doctor` section, or both?
2. What is the v0 source of truth for required env vars?
   - `host.toml.example`
   - real `host.toml`
   - bundle `manifest.json`
   - run script/systemd template
3. Should v0 ever read a `.env` file? If yes, is it read-only validation or process env injection?
4. How do we avoid becoming Rails credentials / dotenv / direnv / Docker Compose all at once?
5. What exactly is secret-safe output?
   - env var names OK;
   - values never printed;
   - present/missing/empty statuses OK?
6. Should `igniter env template` generate shell exports, systemd `Environment=`, Docker `env_file`, or only a
   neutral report?
7. How should `igniter-agent` expose env checks through MCP without giving agents secret access?
8. How does `igniter env` behave for pure observed apps with no `host.toml.example`?
9. How does `igniter env` behave for app source dir vs produced app bundle?
10. What is the smallest implementation card after this readiness packet?

## Alternatives To Compare

Compare at least six:

- A. No `igniter env`; keep env checks inside `doctor`.
- B. `igniter env doctor` only: read-only missing/present report.
- C. `igniter env template`: generate a redacted operator checklist from `host.toml.example`.
- D. dotenv reader/injector (`.env`) like many web stacks.
- E. direnv/nix-shell style external environment.
- F. Docker/Compose env-file generation.
- G. systemd EnvironmentFile generation.
- H. MCP-only env diagnostics via `igniter-agent`.

## Acceptance

- [x] Readiness packet written (`lab-docs/lang/lab-distribution-igniter-env-readiness-p30-v0.md`).
- [x] Live source/docs inspected + cited by path (host_config.rs INLINE_SECRET_KEYS/`*_env`; cmd_doctor app-shape env section; igweb-serve `[CONFIG_RESOLVE]`; todo_postgres host.example.toml + RUNBOOK; app-bundle manifest `requires_machine`; P28 agent envelope).
- [x] ≥6 alternatives compared (A–H: doctor-only / env-doctor / env-template / dotenv / direnv / Compose / systemd-EnvFile / MCP-only).
- [x] Secret boundary explicit: env var NAMES reported; values NEVER; present/unset/empty allowed (mirrors doctor "value never read" + igweb-serve names-not-values).
- [x] App-dir vs bundle decided: catalogue = `host.example.toml` (app) / `host.toml.example` (bundle); `manifest.requires_machine` gates applicability.
- [x] `host.toml` vs `host.toml.example` authority split decided: example = always-present env-NAME catalogue (source of truth); real host.toml = operator binding, never required for the catalogue, never bundled.
- [x] First impl card named with bounded acceptance matrix (`LAB-DISTRIBUTION-IGNITER-ENV-IMPL-P33`: env doctor+template; 6-point matrix).
- [x] No production code changes; `git diff --check` clean.

## Closing report

1. **v0 shape:** `igniter env doctor|template <app_or_bundle>` (P31) reading the `host.example.toml` /
   `host.toml.example` env-NAME catalogue + reporting process-env present/unset/empty; `igniter env check
   [--host-config]` gate + agent `env_*` MCP tools follow in P32. A new subcommand; `doctor` keeps its
   existing inline env section.
2. **`.env`:** OUT of v0 (no read, no inject).
3. **Required-env source:** `host.example.toml`(app) / `host.toml.example`(bundle) under `host_config.rs`
   rules; `requires_machine` gates; NOT the run-script/systemd template.
4. **Safe MCP:** `igniter-agent` `env_doctor`/`env_check` shell-delegate to `igniter env`; the P28 envelope
   carries names + present/empty only — values never read, so agents cannot obtain secrets.
5. **Next card:** `LAB-DISTRIBUTION-IGNITER-ENV-IMPL-P33` (doctor+template) → `…-ENV-CHECK-AND-AGENT-P34`.

## Reporting

Report:

1. Recommended v0 command shape.
2. Whether `.env` is in or out of v0.
3. What file(s) decide required env names.
4. How MCP agents can consume env diagnostics safely.
5. The next card ID and acceptance summary.

## Closed Surfaces

No code in this card. No secret reading beyond presence/empty checks. No printing values. No deploying. No
Docker/Compose generation unless selected as future design only. No systemd install. No TLS/reverse proxy.
No DB creation/migration.
