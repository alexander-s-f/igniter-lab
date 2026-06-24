# LAB-TODOAPP-API-CREATE-BODY-LEGACY-REMOVAL-P45 - remove legacy string create body compatibility

Status: CLOSED (2026-06-24) — legacy string create body removed; object body is the only accepted shape (machine suite + real-PG e2e + smoke green)
Lane: TodoApp API / product hardening
Type: implementation + proof
Date: 2026-06-24
Skill: idd-agent-protocol

## Context

P35 moved Todo create to an object request body. P36 made row IDs host-surrogate rather than
idempotency-key-derived. P40 kept legacy string-body create as a compatibility bridge while the smoke and
docs realigned.

P44 completed DELETE and the product smoke now covers the modern object-body path. Keeping both accepted
shapes is now product noise: clients, docs, and agents must keep asking whether create body is a JSON string
or an object. This card removes the bridge and makes the object body the only supported create contract.

## Goal

Make Todo create accept only object bodies:

```json
{ "title": "Buy milk" }
```

Reject legacy JSON string bodies deterministically with the existing app error envelope.

## Verify First

Read live surfaces before editing:

- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`
- `server/igniter-web/examples/todo_postgres_app/routes.igweb`
- `server/igniter-web/examples/todo_postgres_app/API.md`
- `server/igniter-web/examples/todo_postgres_app/RUNBOOK.md`
- `server/igniter-web/scripts/todo_postgres_smoke.sh`
- `server/igniter-web/scripts/check_todo_product_surface.sh`
- `server/igniter-web/tests/*todo*`
- latest cards: P35, P36, P40, P44

Live code wins over old docs. Do not preserve legacy compatibility just because an older test mentions it.

## Requirements / Acceptance

- [x] Remove legacy string-body create support from the Todo app/host path.
- [x] Legacy body such as `"Buy milk"` returns a structured app error, not a successful create.
- [x] Object body `{ "title": "Buy milk" }` still creates with host surrogate id.
- [x] Idempotency conflict behavior remains unchanged: same key + different payload -> 409.
- [x] Operator smoke uses object body only; no stale `--data "\"title\""` form remains.
- [x] API.md/RUNBOOK/host_policy/product surface docs say object body is the only create contract.
- [x] `scripts/check_todo_product_surface.sh` rejects stale string-body markers.
- [x] Relevant Todo tests + product surface check green; `git diff --check` clean.

## Closed Surfaces

- No new endpoint.
- No DB migration.
- No new write/read substrate.
- No generated client library.
- No global protocol change.

## Expected Evidence

Run at minimum:

```sh
cd server/igniter-web
cargo test --features machine --test todo_postgres_async_runner_smoke_tests
cargo test --features postgres --test todo_postgres_local_e2e_tests -- --test-threads=1
./scripts/check_todo_product_surface.sh
git diff --check
```

If local Postgres env is unavailable, state that explicitly and still prove the DB-free async runner path.

## Closing Report (2026-06-24)

**Removed legacy behavior.** `examples/todo_postgres_app/todo_handlers.ig` — `ResolveCreateTitle` dropped
the `body_kind == "string"` branch; now title comes from `req.body_json.title` for an **object body only**.
Any non-object shape (bare string / array / number / bool / null / empty / malformed) → `""` → the
handler's `trim` guard → app-owned **400** (`RespondError{code:"invalid_body"}`, P43) before any
`InvokeEffect`. No host/runner change — `build_request_input` still classifies bodies generically
(`body_kind == "string"` stays a generic transport signal; the app simply no longer treats it as a title).

**Files changed.**
- App: `todo_handlers.ig` (`ResolveCreateTitle` + comments).
- Tests (string-body create → object body `{"title":…}`): `async_machine_runner_tests`,
  `todo_igweb_serve_e2e_tests`, `todo_postgres_async_runner_smoke_tests` (post_todo / post_todo_noauth /
  post_todo_titled), `todo_postgres_local_e2e_tests`, `todo_postgres_api_read_write_e2e_tests`,
  `todo_postgres_effect_host_runner_tests`, `todo_postgres_effect_host_tests` (app_request +
  `create_carries_object_body_title` + `titled_create`), `todo_error_contract_tests`
  (`valid_create_is_not_an_error_shape`, keyless). `todo_postgres_app_tests`: renamed
  `create_body_contract_object_only`, **moved the bare string into the REJECTED (400) list** — the
  positive proof that legacy is removed.
- Docs/checks: `API.md` (legacy → REMOVED, table row → 400, curl, `ResolveCreateTitle` prose),
  `RUNBOOK.md`, `host_policy.md`, web `IMPLEMENTED_SURFACE.md` (row → **Removed (P45)**),
  `scripts/todo_postgres_smoke.sh` comment, `scripts/check_todo_product_surface.sh` (+ `Legacy v0
  (REMOVED)` marker and a `doc_absent` for stale "legacy … accepted").

**Evidence (all green).**
- Legacy rejected: `create_body_contract_object_only` asserts the bare string `"Buy milk"` → **400**, no
  `InvokeEffect`. Object body still creates (202 / committed, surrogate id intact).
- Idempotency/conflict unchanged: `create_same_key_different_body_conflicts_no_second_effect` → 409,
  `create_same_key_same_body_dedup_no_second_effect` → dedup, `write_conflict_is_409_error_shape` → 409
  (all now use object bodies; distinct titles → distinct payload digests).
- `cargo test --features machine --no-fail-fast` → **0 failed** (whole igniter-web suite).
- `cargo test --features postgres --test todo_postgres_local_e2e_tests -- --test-threads=1` → **14/14**.
- `scripts/check_todo_product_surface.sh` → **PASS** (incl. `legacy create body removed` + `no stale
  legacy body accepted`).
- Full `scripts/todo_postgres_smoke.sh` (local DB) → **PASS** (object body only; no `--data "\"…\""`).
- `git diff --check` clean. No new endpoint / DB migration / substrate / protocol change.

**Follow-up.** The global cross-crate protocol error envelope stays deferred.
