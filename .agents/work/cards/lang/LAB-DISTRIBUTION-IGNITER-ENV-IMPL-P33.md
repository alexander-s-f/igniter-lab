# LAB-DISTRIBUTION-IGNITER-ENV-IMPL-P33 - implement `igniter env doctor|template`

Status: CLOSED (2026-06-25) — `igniter env doctor|template` live in bin/igniter (names-only, values never printed); 5 env tests green, regression clean
Lane: distribution / env / operator config
Type: implementation + proof
Date: 2026-06-25
Skill: idd-agent-protocol

## Context

P30 decided the v0 `igniter env` shape:

```text
igniter env doctor <app_or_bundle>
igniter env template <app_or_bundle>
```

The source of truth for required env var names is the commit-safe catalogue:

- app dir: `host.example.toml`
- bundle dir: `host.toml.example`

The real `host.toml` is operator-owned and must not be required for this slice. `.env` is OUT of v0.

## Goal

Implement `igniter env doctor|template` in `bin/igniter`.

`env doctor` should answer: "which env vars does this app/bundle need, and are they set in this process?"
without ever printing values.

`env template` should print a blank export skeleton an operator can fill manually.

## Verify First

Read:

- `lab-docs/lang/lab-distribution-igniter-env-readiness-p30-v0.md`
- `.agents/work/cards/lang/LAB-DISTRIBUTION-IGNITER-ENV-READINESS-P30.md`
- `bin/igniter` (`cmd_doctor`, `app_bundle`, command dispatch)
- `server/igniter-web/examples/todo_postgres_app/host.example.toml`
- `server/igniter-web/examples/todo_app`
- `server/igniter-web/tests/igniter_serve_wrapper_smoke_tests.rs`
- `server/igniter-web/tests/igniter_app_bundle_smoke_tests.rs`

Confirm live behavior before editing:

- `doctor <app_dir>` only inspects a real `host.toml`, not `host.example.toml`.
- `app bundle` copies `host.example.toml` to `host.toml.example` for machine-mode bundles.
- `bin/igniter` currently has no `env` subcommand.

## Required Behavior

Add:

```text
igniter env doctor <app_or_bundle>
igniter env template <app_or_bundle>
```

Catalogue resolution:

1. If `<path>/host.example.toml` exists, use it.
2. Else if `<path>/host.toml.example` exists, use it.
3. Else report "no machine-mode env required" and exit 0.

Env-name extraction:

- Extract values from TOML keys ending in `_env`, for example:
  - `dsn_env = "IGNITER_TODO_PG_DSN"`
  - `passport_env = "IGNITER_TODO_EFFECT_TOKEN"`
- Preserve enough context in output to identify where each name came from, at least section/key if practical.
- Deduplicate names in stable order.
- Treat empty env-name values in the catalogue as a clean error (exit non-zero).
- Do not support templates (`$`, `${...}`, `{{...}}`) as env names; report clean error if found.

`env doctor` output:

- For each env name, print status:
  - `set`
  - `unset`
  - `empty`
- Never print the env var value.
- Exit 0 even if vars are unset/empty; this is a report, not a gate.

`env template` output:

- Print blank shell exports:
  ```bash
  export IGNITER_TODO_PG_DSN=
  export IGNITER_TODO_EFFECT_TOKEN=
  ```
- Values must remain blank even if the vars are set in the current environment.
- Include short comments with section/key context if useful.

CLI dispatch:

- `igniter env --help` documents doctor/template and says `.env` is not read in v0.
- Unknown `env` verb fails closed.
- Missing path is a clean usage error.

## Acceptance

- [x] `igniter env doctor …/todo_postgres_app` names `IGNITER_TODO_PG_DSN` and `IGNITER_TODO_EFFECT_TOKEN`.
- [x] Fake exported value → `[set]`, but the value is absent from stdout/stderr (test exports `LEAKED_SECRET_XYZ`, asserts absence).
- [x] Unset/empty → `unset`/`empty`, exit 0 (a report, not a gate).
- [x] `igniter env template …/todo_postgres_app` emits blank `export IGNITER_TODO_PG_DSN=` / `export IGNITER_TODO_EFFECT_TOKEN=`.
- [x] `env template` keeps RHS blank even when the var is set (test asserts every `export` RHS is empty).
- [x] `igniter env doctor …/todo_app` → "no machine-mode env required", exit 0.
- [x] Bundle-dir input works: bundle `todo_postgres_app`, then `env doctor <bundle>` reads `host.toml.example`.
- [x] `.env` not read/required (help states it; nothing created).
- [x] Existing tests pass: doctor 6/6, app_bundle 7/7, serve_wrapper 17/17.
- [x] `bash -n bin/igniter` + `git diff --check` clean.

## Reporting

1. **Catalogue resolution order:** `<path>/host.example.toml` (app) → `<path>/host.toml.example` (bundle) →
   else "no machine-mode env required" (exit 0). Extraction = TOML keys ending `_env` (awk tracks `[section]`
   for context), dedup by NAME in stable order; empty env-name or template syntax (`$`/`${}`/`{{}}`) → clean
   non-zero error.
2. **Secret-safety:** env var NAMES only; values are NEVER read or printed — only `set`/`unset`/`empty`
   status. Proven by exporting a fake value and asserting it is absent from output; `template` RHS stays
   blank even when the var is set.
3. **unset/empty:** report-only — `env doctor` always exits 0 (a report). Usage errors (unknown verb / no
   verb / missing path / bad path / empty-name / template-syntax) exit non-zero.
4. **Tests:** new `igniter_env_smoke_tests` **5/5**; regression doctor **6/6**, app_bundle **7/7**,
   serve_wrapper **17/17**.

Implementation: `bin/igniter` (`cmd_env` + `env_usage` + `env_catalogue` awk extractor; dispatch + usage +
header). Tests: `server/igniter-web/tests/igniter_env_smoke_tests.rs`. No `.env` reader, no injection, no
real host.toml, no MCP change (the agent `env_*` tools + `env check` gate are the P32 follow-on per P30).

## Closed Surfaces

No `.env` reader. No env injection. No real `host.toml` generation. No secret value printing. No deploy. No
systemd install. No Docker/Compose generation. No DB creation/migration. No MCP changes in this card.
