# LAB-TODOAPP-API-CONTRACT-EXAMPLES-P48

Status: CLOSED (2026-06-26)
Route: fast_lane / product API documentation + guard
Skill: idd-agent-protocol

## Goal

Make the current Todo API contract easy to consume without archaeology.

Add a compact, runnable examples document for the implemented product API:

- health;
- list with account-existence semantics;
- show;
- create with object body only;
- replay / conflict;
- done;
- delete;
- keyset pagination via `?after=`.

This is documentation + guard work. It must not change the API, runner, DB
schema, or host policy.

## Current Authority

Read first:

- `server/igniter-web/IMPLEMENTED_SURFACE.md`
- `server/igniter-web/examples/todo_postgres_app/API.md`
- `server/igniter-web/examples/todo_postgres_app/RUNBOOK.md`
- `server/igniter-web/examples/todo_postgres_app/host.example.toml`
- `server/igniter-web/examples/todo_postgres_app/routes.igweb`
- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`
- `server/igniter-web/tests/todo_postgres_async_runner_smoke_tests.rs`
- `server/igniter-web/tests/todo_postgres_smoke_guard_tests.rs`
- `server/igniter-web/scripts/todo_postgres_smoke.sh`

Live code and tests win over old prose.

## Task

Create a product-facing examples doc, preferably:

```text
server/igniter-web/examples/todo_postgres_app/EXAMPLES.md
```

The doc should be copy/paste friendly but secret-safe:

- use `PORT`, `ACCOUNT`, `TODO_ID`, `IDEMPOTENCY_KEY` placeholders;
- show `Authorization: Bearer $IGNITER_TODO_EFFECT_TOKEN` only as an env var;
- never print a DSN or token value;
- show canonical object create body: `{ "title": "Buy milk" }`;
- explicitly show the removed legacy bare string body as rejected;
- show how to derive the next keyset cursor from the last returned `id` today;
- name that `{items,next}` is deferred to a separate product slice.

Add a tiny guard test if there is already a docs/examples guard pattern in this
crate. The guard should assert the examples doc exists and names the critical
contract points:

- object body;
- surrogate `todo_` id;
- keyset `after`;
- `RespondError` app envelope;
- no inline secrets.

If no suitable guard pattern exists, add the smallest `#[test]` in an existing
docs guard test file.

## Closed Surfaces

- No API behavior changes.
- No route changes.
- No host config changes.
- No smoke-script behavior changes except a typo fix if examples reveal one.
- No live DB requirement.
- No production/stable API claim.

## Acceptance

- [x] `EXAMPLES.md` or equivalent is added under `examples/todo_postgres_app/`.
- [x] Examples cover health/list/show/create/replay-conflict/done/delete/pagination.
- [x] Create examples use object body only; bare string body is documented as rejected.
- [x] Examples explain surrogate id vs idempotency key.
- [x] Examples explain keyset `after` and current client-derived next cursor.
- [x] Examples show app-owned error envelope shape for at least one app error.
- [x] Secret-safety: no raw DSN/token/password-like values in the doc.
- [x] A small guard test pins the doc's existence and key phrases.
- [x] Existing Todo product tests remain green.
- [x] `git diff --check` clean.

## Closing Report

Docs changed:

- `server/igniter-web/examples/todo_postgres_app/EXAMPLES.md`
- `server/igniter-web/examples/todo_postgres_app/API.md`
- `server/igniter-web/examples/todo_postgres_app/RUNBOOK.md`

Test changed:

- `server/igniter-web/tests/todo_postgres_smoke_guard_tests.rs`

Key examples added:

- Health request.
- List with account-existence semantics: existing empty account is `200 []`,
  missing account is app-owned `404`.
- Show request and app-owned `todo_not_found` envelope.
- Create with canonical object body `{ "title": "Buy milk" }`.
- Removed bare JSON string body shown as rejected.
- Replay vs conflict under the same idempotency key.
- Done and delete mutations with bearer token from
  `IGNITER_TODO_EFFECT_TOKEN`.
- Keyset pagination via `?after=$TODO_ID`, with the current client-derived
  cursor rule: use the last returned row `id`.
- `{items,next}` and client `limit` named as deferred product slice.

Guard/test commands run:

```bash
cargo test --features machine --test todo_postgres_smoke_guard_tests examples_doc_pins_current_api_contract_without_inline_secrets --quiet
cargo test --features machine --test todo_postgres_smoke_guard_tests --quiet
scripts/check_todo_product_surface.sh
rg -n "[ \t]+$" examples/todo_postgres_app/EXAMPLES.md examples/todo_postgres_app/API.md examples/todo_postgres_app/RUNBOOK.md tests/todo_postgres_smoke_guard_tests.rs
git diff --check
```

Result:

- `examples_doc_pins_current_api_contract_without_inline_secrets`: 1 passed.
- `todo_postgres_smoke_guard_tests`: 7 passed.
- `scripts/check_todo_product_surface.sh`: `todo-product: PASS`.
- Trailing whitespace sweep: no matches.
- `git diff --check`: clean.

No API behavior, runner behavior, route shape, DB schema, smoke-script behavior,
or host policy was changed by this P48 slice.

Worktree note:

- `server/igniter-web/examples/todo_postgres_app/routes.igweb` and
  `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig` have
  unrelated P21 HTML-page diffs in the current worktree; they were not edited
  for this card.

## Reporting

Close with:

- docs/tests changed;
- key examples added;
- exact guard/test command run;
- confirmation no API/runtime/host behavior changed.
