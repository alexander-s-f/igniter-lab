# LAB-TODOAPP-API-PRODUCT-RUNBOOK-P22 - one-page runbook and limitation map

Status: CLOSED
Lane: TodoApp API / product hardening / docs
Type: docs + verification
Delegation code: OPUS-TODOAPP-API-PRODUCT-RUNBOOK-P22
Date: 2026-06-23
Skill: idd-agent-protocol

## Context

The Todo API stack is now real enough that agents need a single page that answers:

- how do I run it locally?
- what is implemented today?
- what is intentionally not product-ready?
- which command proves each claim?

We have pieces in `README.md`, `IMPLEMENTED_SURFACE.md`, `host_policy.md`, `API.md`, and the smoke
script, but a new agent still has to assemble the story.

## Goal

Add or update a concise product runbook for `examples/todo_postgres_app`.

Preferred location:

```text
server/igniter-web/examples/todo_postgres_app/RUNBOOK.md
```

It should be short, live-code anchored, and operator-oriented.

## Required content

1. What this app proves:
   - `.igweb` routes + `.ig` handlers,
   - `ReadThen` reads,
   - `InvokeEffect` writes,
   - host-owned Postgres authority,
   - idempotency receipts,
   - local loopback runner.
2. Run modes:
   - sync observed,
   - async machine fake/no-DB test path,
   - local Postgres path.
3. Step-by-step local run:
   - create dedicated local DB,
   - set env vars,
   - run smoke,
   - expected PASS receipt.
4. Troubleshooting:
   - missing DSN,
   - bad token,
   - denied source/field,
   - keyless mutation,
   - body shape error (if P18 landed),
   - port already in use.
5. Limitations:
   - local-only, no production,
   - no migrations,
   - no generated ids,
   - no typed row destructuring,
   - no JSON object request parser,
   - no pooling/backpressure.

## Verify first

Read live docs and code:

- `server/igniter-web/README.md`
- `server/igniter-web/IMPLEMENTED_SURFACE.md`
- `server/igniter-web/examples/todo_postgres_app/API.md`
- `server/igniter-web/examples/todo_postgres_app/host_policy.md`
- `server/igniter-web/examples/todo_postgres_app/host.example.toml`
- `server/igniter-web/scripts/todo_postgres_smoke.sh`

Do not copy stale claims from older cards. If a doc says “not implemented” but live
`IMPLEMENTED_SURFACE.md` says implemented, fix the doc wording or avoid repeating it.

## Acceptance

- [x] `RUNBOOK.md` exists or the closing report explains why `API.md` was extended instead.
- [x] It links to `API.md`, `host.example.toml`, `host_policy.md`, and `IMPLEMENTED_SURFACE.md`.
- [x] It includes exact commands for local smoke.
- [x] It states local-only / not production clearly.
- [x] It does not include inline secrets or real DSNs beyond placeholder/example local names.
- [x] It does not claim unsupported features.
- [x] It names exact verification commands.
- [x] `scripts/check_implemented_surface.sh` remains PASS.
- [x] `git diff --check` clean.

## Closing report

**Date:** 2026-06-23
**Outcome:** Docs only. New `RUNBOOK.md`; no code changed.

### What changed

- **NEW** `examples/todo_postgres_app/RUNBOOK.md` — one page, live-anchored, operator-oriented:
  1. **What it proves** — `.igweb`+`.ig`, `ReadThen`, `InvokeEffect`, host-owned Postgres authority,
     idempotency receipts (replay + 409 conflict), loopback runner.
  2. **Run modes** — sync observed / async machine (fake, no DB) / local Postgres, with the exact command per mode.
  3. **Step-by-step local run** — `createdb` → operator DDL → export the two env vars → `todo_postgres_smoke.sh`,
     with the expected PASS receipt, plus the direct `cargo run --features postgres … --host-config …` form.
  4. **Troubleshooting table** — smoke preflight exit 2; binary `[CONFIG_RESOLVE]`=3 / `[CONFIG_PARSE]`=2 /
     `[BIND_REFUSED]`=5 / `[POSTGRES_CONNECT]`=6 (DSN-redacted); HTTP 401 bad token / 403 denied source-field /
     400 keyless+body / 409 conflict.
  5. **Limitations** — local-only/not production, no migrations, no generated ids, no typed row destructuring,
     no JSON-object body parser, no pooling/backpressure, single read source.
  6. **Verification commands** — surface guard, `--features machine`, the sync error-contract test, the
     postgres e2e (skips w/o DSN), and the smoke.
- **M** `API.md` — added a one-line "New here? Start with RUNBOOK.md" pointer for discoverability.

### Verify-first / staleness note

`IMPLEMENTED_SURFACE.md` (re-verified 2026-06-23) was the source of truth. `host_policy.md` still names
the older `IGNITER_PG_DSN`/`IGNITER_PG_WRITE_DSN` env vars in its "Environment" section; the RUNBOOK uses
the **live** vars the binary + smoke actually read (`IGNITER_TODO_PG_DSN`, `IGNITER_TODO_EFFECT_TOKEN`),
not the stale names. (Left `host_policy.md` untouched — out of this card's scope; flagged for a doc sweep.)

### Acceptance

RUNBOOK exists; links API.md / host.example.toml / host_policy.md / IMPLEMENTED_SURFACE.md; exact smoke
commands; local-only stated up front; only the placeholder `dbname=igniter_todo_test` DSN (no secrets);
no unsupported feature claimed (cross-checked against IMPLEMENTED_SURFACE.md); exact verification commands
named and re-run green. `check_implemented_surface.sh` PASS; `git diff --check` clean.

## Closed surfaces

- No code changes unless a doc claim is impossible to verify without a tiny test command update.
- No new feature claims.
- No production deployment guide.
- No Docker/systemd unless already part of the live app proof.

