# LAB-TODOAPP-API-PRODUCT-SURFACE-P41 - refresh implemented API surface and smoke contract

Status: TODO
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

- [ ] API.md/RUNBOOK/host_policy agree on current object body and surrogate-id semantics.
- [ ] Designed vs implemented account-existence semantics are not blurred.
- [ ] Canonical examples use `{ "title": "..." }`, not legacy string bodies.
- [ ] No stale P18/P20/P35 wording contradicts current behavior.
- [ ] No docs claim DSN/token/raw SQL can appear in app code.
- [ ] Product-surface check script catches at least one current contract marker for body/id/error docs.
- [ ] `scripts/check_todo_product_surface.sh` passes.
- [ ] Relevant no-DB Todo tests pass.
- [ ] `git diff --check` clean.

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
