# LAB-TODOAPP-API-PRODUCT-SMOKE-CI-P27 - bounded CI guard for TodoApp product surface

Status: CLOSED
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

- [x] One no-DB command exists for TodoApp product-surface CI.
- [x] It runs without `IGNITER_TODO_PG_DSN` and without `IGNITER_TODO_EFFECT_TOKEN`.
- [x] It includes body contract, idempotency conflict, error contract, and host example parsing evidence.
- [x] It does not attempt to start a real Postgres-backed server.
- [x] RUNBOOK or API.md points to it.
- [x] Real Postgres smoke remains separate and operator-gated.
- [x] `scripts/check_implemented_surface.sh` still PASS.
- [x] New/updated script is shellcheck-style simple and does not echo secrets.
- [x] `git diff --check` clean.

## Closing report

**Date:** 2026-06-23
**Outcome:** Implemented — new sibling guard script, no DB, no env.

### What changed

- **NEW** `scripts/check_todo_product_surface.sh` — bounded NO-DB CI guard for the Todo **product**
  surface (distinct from `check_implemented_surface.sh`, which guards the **runner machinery**). One
  `--features machine` compile profile (fake adapters), 6 steps, compact `todo-product: … ok/FAILED`
  receipt, exits non-zero on any failure:
  1. `todo_postgres_app_tests` — routes compile/build + body contract (P18) + list-empty 200 [] (P24) + loopback.
  2. `todo_error_contract_tests` — error contract (P20), no DSN/token/SQL leak.
  3. `todo_postgres_effect_host_tests` — idempotency conflict (P19) + rejected-body-before-effect-host.
  4. `todo_postgres_async_runner_smoke_tests` — ReadThen found/empty(200 [])/write/replay over fakes.
  5. `host_config` lib tests — parser fail-closed + `committed_host_example_toml_parses`.
  6. operator-smoke **preflight refusal**: runs `todo_postgres_smoke.sh` with DSN/token **cleared**
     (`env -u …`), asserts exit 2 + `REFUSED` + no `PASS` — a DB-free negative check that the operator
     smoke fails closed without a DSN.
- **M** `RUNBOOK.md` — verification-commands block now lists the product guard first, with its scope.

### Why a sibling, not an extension

`check_implemented_surface.sh` answers "does the igniter-web **runner** implement ReadThen/effect/
diagnostics?"; this answers "is the Todo **product** contract (body/conflict/error/list-empty) safe to
trust in CI without a DB?". Different audiences, different failure surfaces → a clearly-labelled sibling
avoids overloading one script.

### Verification

`check_todo_product_surface.sh` → **PASS** (6/6, run with no env set, no DB touched).
`check_implemented_surface.sh` → still **PASS**. The script never echoes secrets (it only references the
env-var names in a comment and clears them via `env -u`). Real local-Postgres smoke stays separate and
operator-gated. `git diff --check` clean.

## Closed surfaces

- No live DB.
- No production deployment.
- No new feature implementation beyond a guard script/docs/tests.

