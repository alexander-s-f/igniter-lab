# LAB-TODOAPP-API-CONTRACT-SURFACE-P17 - document the product API contract

Status: CLOSED
Lane: TodoApp API / product surface / docs hygiene
Type: documentation + evidence
Delegation code: OPUS-TODOAPP-API-CONTRACT-SURFACE-P17
Date: 2026-06-23
Skill: idd-agent-protocol

## Context

The TodoApp API has grown from shape proof into a real product-shaped example:

- routes authored in `.igweb`;
- reads through `ReadThen`;
- writes through `InvokeEffect` + `MachineEffectHost`;
- local Postgres subprocess E2E;
- operator `host.example.toml`;
- repeatable smoke script.

But the app directory does not yet have a compact API contract that says what routes exist, which mode
they require, what response status means, and what is still intentionally v0.

## Goal

Add a product-facing contract doc for `examples/todo_postgres_app` so agents and humans can understand
the Todo API without reading every test.

Preferred file:

```text
server/igniter-web/examples/todo_postgres_app/API.md
```

## Verify first

Read:

- `server/igniter-web/examples/todo_postgres_app/routes.igweb`
- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`
- `server/igniter-web/examples/todo_postgres_app/host.example.toml`
- `server/igniter-web/examples/todo_postgres_app/host_policy.md`
- `server/igniter-web/scripts/todo_postgres_smoke.sh`
- `server/igniter-web/IMPLEMENTED_SURFACE.md`
- current P14/P15/P16 status if those cards are already closed

If P14/P15/P16 are still open, document the current surface and add clear "next expected deltas" rather
than pretending they landed.

## Required content

Keep it compact:

1. **Status/boundary**: lab example, local Postgres only, loopback, not public production API.
2. **Route table**:
   - method/path;
   - contract/handler;
   - mode required (sync observed vs async machine);
   - success status;
   - not-found/denied behavior;
   - idempotency requirement for mutations.
3. **Request body contract**:
   - current create body semantics (after P16 if closed; otherwise note current blank-title v0).
4. **Host requirements**:
   - `host.example.toml`;
   - env vars;
   - dedicated local/test DB;
   - effect token.
5. **Evidence commands**:
   - `scripts/check_implemented_surface.sh`;
   - `scripts/todo_postgres_smoke.sh`;
   - cargo tests.
6. **Open product limitations**:
   - typed row destructuring;
   - validation;
   - generated ids;
   - migrations;
   - pool/backpressure/public deployment.

## Acceptance

- [x] `examples/todo_postgres_app/API.md` exists.
- [x] Route table matches live `routes.igweb`.
- [x] It distinguishes sync observed mode from async machine/Postgres mode.
- [x] It documents idempotency-key requirements for create/done.
- [x] It documents current create body/title behavior accurately.
- [x] It links to `host.example.toml`, `host_policy.md`, and `IMPLEMENTED_SURFACE.md`.
- [x] README or host policy doc points to `API.md`.
- [x] It does not claim production/public stability.
- [x] `git diff --check` clean.

## Closed surfaces

- No code changes unless needed to fix a doc/test typo.
- No new API behavior.
- No production deployment story.
- No public stability promise.

## Closing report

**Date:** 2026-06-23

P14/P15/P16 are all CLOSED, so `API.md` documents the real current surface (no "next expected deltas"
placeholders needed).

### Files changed (doc-only)

- **NEW** `examples/todo_postgres_app/API.md` — compact product contract: status/boundary (lab,
  loopback, local-Postgres-only, not public/production); two run modes (sync observed vs async machine)
  with the read/write behavior per mode; a route table built from live `routes.igweb` +
  `todo_handlers.ig` (method/path · handler · idempotency · success status · not-found/denied); the
  idempotency section (create/done require the key; create business key = idempotency key, done business
  key = todo_id — P15); the v0 create body contract (JSON-string body = title — P16; done is a full-row
  upsert that doesn't preserve title); host requirements (host.example.toml, `IGNITER_TODO_PG_DSN`,
  `IGNITER_TODO_EFFECT_TOKEN`, dedicated test DB, `--features postgres`); evidence commands; and the
  intentional v0 limitations. Links to `host.example.toml`, `host_policy.md`, and
  `../../IMPLEMENTED_SURFACE.md` (all verified to resolve).
- **M** `examples/todo_postgres_app/host_policy.md` — pointer to `API.md`.
- **M** `README.md` — pointer to `API.md` in the Postgres Host Config section.

### Acceptance

- `examples/todo_postgres_app/API.md` exists; route table matches live `routes.igweb`
  (health / index / show / create / done + 404 unmatched / 405 wrong-method).
- Distinguishes sync observed mode (ReadThen → 500, InvokeEffect → 202) from async machine/Postgres
  mode (reads 200/404, writes 200 committed/dedup).
- Documents idempotency-key requirement for create/done (keyless → 400) and the differing business keys.
- Documents the P16 create body/title behavior accurately (JSON-string body = title).
- Links to `host.example.toml`, `host_policy.md`, and `IMPLEMENTED_SURFACE.md`.
- README + host_policy.md point to `API.md`.
- No production/public stability claim (status header).
- `git diff --check` clean. No code changed.

### Scope honored

No code changes, no new API behavior, no deployment story, no public stability promise.
