# LAB-TODOAPP-API-PRODUCT-SURFACE-P41 - refresh implemented API surface and smoke contract

Status: CLOSED (2026-06-23) — drift-prevention, NO behavior change. Verify-first: API.md/RUNBOOK/host.example.toml
already current for P35/P36/P38/P40; host_policy.md was stale and fixed (write cap IO.PostgresWrite→IO.TodoWrite,
op update→upsert, env IGNITER_PG_DSN→IGNITER_TODO_PG_DSN, done boolean→text, + surrogate/two-stage notes). Hardened
scripts/check_todo_product_surface.sh with a DB-free doc-marker step (asserts current body/id/account/error markers
present + superseded P18 string-only + idem-key-as-id absent). Wrote the single live-current surface proof
`lab-docs/lang/lab-todoapp-api-product-surface-p41-v0.md` (route table, body, id/idempotency, read impl-vs-designed,
error shapes, host env, canonical object-body curl, test commands, explicit designed-vs-implemented table). Smoke
staleness already flagged (P40 task). check script PASS; no-DB Todo tests pass; `git diff --check` clean.
Lane: TodoApp API / product polish / implemented surface
Type: documentation + CI/smoke hardening
Delegation code: OPUS-TODOAPP-API-PRODUCT-SURFACE-P41
Date: 2026-06-23
Skill: idd-agent-protocol

## Context

The Todo API moved quickly through P35/P36/P37-era hardening:

- object create body via `req.body_json`;
- host surrogate id decoupled from idempotency key;
- account-existence semantics designed and pending implementation;
- current error contract documented but not globally enveloped.

Agents now need one current product surface they can trust without re-reading every proof doc.

## Goal

Refresh the Todo API implemented-surface docs and no-DB smoke guard so future agents see the current
truth quickly.

This is not a behavior card. It is a drift-prevention card.

## Verify first

Read live code and docs:

- `server/igniter-web/examples/todo_postgres_app/API.md`
- `server/igniter-web/examples/todo_postgres_app/RUNBOOK.md`
- `server/igniter-web/examples/todo_postgres_app/host_policy.md`
- `server/igniter-web/examples/todo_postgres_app/host.example.toml`
- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`
- `server/igniter-web/examples/todo_postgres_app/routes.igweb`
- `server/igniter-web/examples/todo_postgres_app/scripts/check_todo_product_surface.sh`
- relevant Todo tests

## Work

Produce a compact, live-current surface:

- route table;
- request body contract;
- id/idempotency semantics;
- read semantics (including what is implemented vs designed);
- error body shapes;
- host env/config requirements;
- canonical curl examples for health, list, create, show, done;
- exact test commands.

Update `check_todo_product_surface.sh` only if it can cheaply catch stale docs/contract drift without a DB.

## Acceptance

- [x] API.md/RUNBOOK/host_policy agree on current object body and surrogate-id semantics.
- [x] Designed vs implemented account-existence semantics are not blurred.
- [x] Canonical examples use `{ "title": "..." }`, not legacy string bodies.
- [x] No stale P18/P20/P35 wording contradicts current behavior.
- [x] No docs claim DSN/token/raw SQL can appear in app code.
- [x] Product-surface check script catches at least one current contract marker for body/id/error docs.
- [x] `scripts/check_todo_product_surface.sh` passes.
- [x] Relevant no-DB Todo tests pass.
- [x] `git diff --check` clean.

## Proof

Preferred proof doc:

```text
lab-docs/lang/lab-todoapp-api-product-surface-p41-v0.md
```

## Closed surfaces

- No production behavior changes.
- No error-envelope implementation.
- No account-existence implementation.
- No local Postgres requirement for the product-surface guard.
