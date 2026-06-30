# LAB-TODOAPP-DEMO-DX-GUARD-P57

Status: TODO (run after P55/P56)
Route: fast_lane / TodoApp payoff / DX hygiene
Skill: idd-agent-protocol

## Goal

Prevent the new TodoApp demo DX from drifting immediately.

After P55/P56 land, add a bounded no-secret/no-DB guard for the demo surface:
the demo script should refuse unsafe/missing environment clearly, docs should
point at the current commands, and active surface docs should not describe stale
manual steps.

## Current Authority

Read first:

- P55 closing report
- P56 closing report, if landed
- `server/igniter-web/examples/todo_postgres_app/DEMO.md`
- `server/igniter-web/examples/todo_postgres_app/RUNBOOK.md`
- `server/igniter-web/examples/todo_postgres_app/API.md`
- `server/igniter-web/scripts/check_todo_product_surface.sh`
- `server/igniter-web/IMPLEMENTED_SURFACE.md`

## Task

Add a guard step to existing product-surface checks, or a small sibling script,
that verifies:

- demo script exists and is executable;
- `doctor/check` refuses missing local requirements with actionable output;
- missing DSN/token or unsafe DB names fail before any socket bind;
- docs mention the demo command and do not point users at stale manual-only
  steps as the primary path;
- no committed file contains a raw token/DSN.

Keep this DB-free. The real DB smoke remains operator/local.

## Boundary

- No product feature changes.
- No route changes.
- No Postgres requirement in CI guard.
- No generated demo artifacts committed.
- No claim that TodoApp is production-ready.

## Acceptance

- [ ] Guard script/check added.
- [ ] Guard runs without Postgres.
- [ ] It fails closed for missing env/unsafe config.
- [ ] Active docs point to the new demo path.
- [ ] `scripts/check_todo_product_surface.sh` includes or references the guard.
- [ ] `git diff --check` clean.

## Reporting

Close with:

- guard command;
- what it protects;
- what remains operator/local only;
- verification summary.

