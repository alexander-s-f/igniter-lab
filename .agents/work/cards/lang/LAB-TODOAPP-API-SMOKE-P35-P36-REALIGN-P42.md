# LAB-TODOAPP-API-SMOKE-P35-P36-REALIGN-P42 - realign operator smoke with object body and surrogate id

Status: DRAFT
Lane: TodoApp API / product smoke / hygiene
Type: tooling fix + proof
Date: 2026-06-24
Skill: idd-agent-protocol

## Context

`LAB-IGNITER-WEB-IMPLEMENTED-SURFACE-REFRESH-P42` confirmed a real drift:

- P35 made the canonical create body an object via `req.body_json`:

  ```json
  { "title": "Buy milk" }
  ```

- P36 decoupled the Todo resource id from the idempotency key:

  ```text
  id = "todo_" + blake3(method "\x1f" path "\x1f" idempotency_key)[..32]
  ```

- P40 kept legacy JSON-string bodies only as deprecated compatibility.

But `server/igniter-web/scripts/todo_postgres_smoke.sh` still performs the full DB smoke using the old
assumptions:

- sends legacy string body (`--data "\"title\""`);
- assumes `CREATE_KEY == created row id`;
- uses `$CREATE_KEY` for `show`, `done`, and DB truth checks.

The DB-free preflight-refusal guard is still valid; the full DB path is stale.

## Goal

Realign the operator smoke with the current Todo API product surface:

1. create uses canonical object body;
2. created row id is discovered or computed according to the current host surrogate-id policy;
3. show/done/DB checks use the actual Todo id, not the idempotency key;
4. preflight refusal tests remain valid and secret-safe.

## Verify First

Read live source before editing:

- `server/igniter-web/scripts/todo_postgres_smoke.sh`
- `server/igniter-web/scripts/check_todo_product_surface.sh`
- `server/igniter-web/tests/todo_postgres_smoke_guard_tests.rs`
- `server/igniter-web/tests/todo_postgres_local_e2e_tests.rs`
- `server/igniter-web/examples/todo_postgres_app/API.md`
- `server/igniter-web/examples/todo_postgres_app/RUNBOOK.md`
- `server/igniter-web/examples/todo_postgres_app/host.example.toml`
- `server/igniter-web/src/lib.rs` (`surrogate_id`, `build_request_input`)
- `server/igniter-web/IMPLEMENTED_SURFACE.md`

Confirm whether the smoke should discover the created id from DB/response or compute it with the same host
recipe. Prefer discovery from the product path if practical; avoid duplicating the host algorithm unless that
is the smallest reliable proof.

## Allowed Changes

- Update `scripts/todo_postgres_smoke.sh`.
- Update the DB-free guard test if the script preflight output changes.
- Update `README.md`, `API.md`, `RUNBOOK.md`, or `IMPLEMENTED_SURFACE.md` only if they directly describe
  the smoke.
- Add a small proof doc under `lab-docs/lang/` if useful.

## Closed Surfaces

- No API behavior changes.
- No route/handler changes unless verify-first proves the smoke cannot be fixed otherwise.
- No DB schema changes except test-owned DDL already inside the smoke.
- No migration runner.
- No broad removal of legacy string body support; that belongs to `LAB-TODOAPP-API-CREATE-BODY-LEGACY-REMOVAL`.
- No live DB run unless `IGNITER_TODO_PG_DSN` is explicitly present; skips/refusals must stay clean.

## Required Behavior

The full operator smoke should, when a dedicated local DB is configured:

- refuse missing/nonlocal/unsafe env before build/connect (existing behavior);
- create an account-owned todo with object body;
- replay create with the same idempotency key and perform no second mutation;
- discover/use the actual `todo_<...>` id;
- show the created todo by actual id;
- mark done by actual id;
- replay done with the same idempotency key and perform no second mutation;
- verify DB truth using the actual id and receipt counts using idempotency semantics;
- avoid echoing DSN/passport/token values.

If no local DB is available, the card can still close with:

- updated script;
- DB-free preflight tests green;
- compile/test evidence proving the canonical product path;
- exact manual command for the full DB smoke.

## Verification

Minimum:

```bash
cd server/igniter-web
cargo test --test todo_postgres_smoke_guard_tests
cargo test --test implemented_surface_guard_tests
git diff --check
```

If a local test DB is available:

```bash
cd server/igniter-web
export IGNITER_TODO_PG_DSN="host=localhost user=alex dbname=igniter_todo_test"
export IGNITER_TODO_EFFECT_TOKEN="local-smoke-token"
scripts/todo_postgres_smoke.sh
```

Optional strong proof:

```bash
cargo test --features postgres --test todo_postgres_local_e2e_tests -- --test-threads=1
```

## Acceptance

- [ ] Smoke create request uses canonical object body.
- [ ] Smoke no longer assumes row id equals idempotency key.
- [ ] Show/done/DB checks use the actual created Todo id.
- [ ] Replay checks still prove idempotency/no second mutation.
- [ ] Preflight refusal tests remain green and secret-safe.
- [ ] Docs/front-door no longer overstate the stale full smoke path.
- [ ] No API behavior changes.
- [ ] `git diff --check` clean.

## Closing Report Template

Close with:

- how actual Todo id is obtained;
- whether full DB smoke was run or only DB-free proof was possible;
- exact commands and results;
- any remaining follow-up (`CREATE-BODY-LEGACY-REMOVAL`, error-envelope, CI smoke).
