# LAB-TODOAPP-API-PRODUCT-SMOKE-CI-P27 - bounded CI guard for TodoApp product surface

Status: TODO
Lane: TodoApp API / product hardening / CI
Type: implementation + docs
Delegation code: OPUS-TODOAPP-API-PRODUCT-SMOKE-CI-P27
Date: 2026-06-23
Skill: idd-agent-protocol

## Context

We now have several proof commands:

- `scripts/check_implemented_surface.sh` for the runner surface;
- `cargo test --features machine` for fake/no-DB product path;
- real Postgres tests and `todo_postgres_smoke.sh`, which are operator-gated by DSN.

Agents still need one small, safe "can I trust TodoApp product surface in CI without a DB?" command.

## Goal

Add a bounded no-DB product-surface CI guard for `todo_postgres_app`.

It should not touch live Postgres, not require env vars, and not replace the local-Postgres smoke. It should
check the product app's hardening surface: routes compile, ReadThen/fake path works, error contract tests pass,
host example parses, smoke preflight refuses unsafe/no-DSN paths.

## Verify first

Read:

- `server/igniter-web/scripts/check_implemented_surface.sh`
- `server/igniter-web/scripts/todo_postgres_smoke.sh`
- `server/igniter-web/IMPLEMENTED_SURFACE.md`
- `server/igniter-web/examples/todo_postgres_app/RUNBOOK.md`
- relevant tests under `server/igniter-web/tests/todo_*`

If `check_implemented_surface.sh` already covers enough, prefer extending it or adding a sibling script with a
clear purpose; avoid duplicate noisy scripts.

## Plan

1. Define the exact no-DB command set.
2. Implement either:
   - `scripts/check_todo_product_surface.sh`, or
   - a clearly labelled Todo section in `check_implemented_surface.sh`.
3. Add a short RUNBOOK/API pointer to the guard.
4. Ensure it prints compact PASS/FAIL lines and exits non-zero on failure.
5. Ensure it does not require or read `IGNITER_TODO_PG_DSN`.

## Acceptance

- [ ] One no-DB command exists for TodoApp product-surface CI.
- [ ] It runs without `IGNITER_TODO_PG_DSN` and without `IGNITER_TODO_EFFECT_TOKEN`.
- [ ] It includes body contract, idempotency conflict, error contract, and host example parsing evidence.
- [ ] It does not attempt to start a real Postgres-backed server.
- [ ] RUNBOOK or API.md points to it.
- [ ] Real Postgres smoke remains separate and operator-gated.
- [ ] `scripts/check_implemented_surface.sh` still PASS.
- [ ] New/updated script is shellcheck-style simple and does not echo secrets.
- [ ] `git diff --check` clean.

## Closed surfaces

- No live DB.
- No production deployment.
- No new feature implementation beyond a guard script/docs/tests.

