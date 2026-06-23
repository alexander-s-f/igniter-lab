# LAB-TODOAPP-API-CREATE-BODY-P16 - carry request body into create title

Status: CLOSED
Lane: TodoApp API / product correctness / request payload
Type: implementation + proof
Delegation code: OPUS-TODOAPP-API-CREATE-BODY-P16
Date: 2026-06-23
Skill: idd-agent-protocol

## Context

`BuildCreateTodoIntent(account_id, idempotency_key)` currently emits:

```ig
values.title = ""
values.done = "false"
key = idempotency_key
```

This was enough to prove write execution and replay, but not enough to feel like a product API. A
create request should carry some user-provided title across the `.ig` -> `InvokeEffect.input` ->
Postgres write adapter seam.

Important limitation: there is no JSON body parser / typed request payload support here. Do not invent
one in this card.

## Goal

Make create carry the raw request body as the v0 todo title:

```text
POST /accounts/:account_id/todos
body: "Buy milk"
idempotency-key: create-1

=> WriteIntent.values.title == "Buy milk"
=> real DB row title == "Buy milk"
```

Keep the v0 rule explicit: body is a plain title string, not JSON.

## Verify first

Read:

- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`
- `server/igniter-web/tests/todo_postgres_api_write_tests.rs`
- `server/igniter-web/tests/todo_postgres_effect_host_tests.rs`
- `server/igniter-web/tests/todo_postgres_local_e2e_tests.rs`
- `server/igniter-web/scripts/todo_postgres_smoke.sh`
- `runtime/igniter-machine/src/postgres_write.rs`

Confirm how `Request.body` crosses into `.ig` and whether current test helpers can send non-empty body
through sync and async paths.

## Implementation bias

Likely minimal shape:

```ig
pure contract BuildCreateTodoIntent {
  input account_id      : String
  input idempotency_key : String
  input title           : String
  compute values = call_contract("MakeWriteValues", account_id, title, "false")
  ...
}

pure contract AccountTodoCreate {
  ...
  compute intent =
    call_contract("BuildCreateTodoIntent", or_else(ctx.account_id, "none"), req.idempotency_key, req.body)
  ...
}
```

If an empty body should be accepted as `""`, keep that behavior explicit. Do not add validation unless
the current app already has the necessary primitives.

## Acceptance

- [x] Closing report states the v0 body contract: JSON string literal body = title, not a JSON object.
- [x] `BuildCreateTodoIntent` accepts a title/body input.
- [x] `AccountTodoCreate` passes `req.body` into the command contract.
- [x] Structured `InvokeEffect.input.values.title` carries the request body in fake/machine tests.
- [x] Local Postgres E2E proves the real business row title equals the submitted body.
- [x] `todo_postgres_smoke.sh` sends a non-empty body and checks the DB title, or closing report explains why script remains minimal.
- [x] Replay same idempotency key remains no-second-mutation.
- [x] Existing read/show/done behavior remains green.
- [x] `cargo test --features machine` in `server/igniter-web` passes.
- [x] `cargo test --features postgres --test todo_postgres_local_e2e_tests -- --test-threads=1` passes or skips cleanly without DSN.
- [x] `scripts/check_implemented_surface.sh` remains PASS.
- [x] `git diff --check` clean.

## Closed surfaces

- No JSON parser.
- No request validation DSL.
- No generated ids beyond the existing idempotency-key-as-create-key v0.
- No schema migration runner.
- No production DB.

## Closing report

**Date:** 2026-06-23

### v0 body contract

The create request body is a **JSON string literal** whose value is the title (e.g. the wire body is
`"Buy milk"`, with quotes). It is NOT a JSON object and there is no JSON-field parser. Rationale: both
request readers (`igniter-server` socket reader and sync `host`) parse the body with
`serde_json::from_slice(...).unwrap_or(Value::Null)`, so a bare-text body (`Buy milk`, unquoted) fails
JSON parse → Null → empty title. A JSON-string body parses to `Value::String`, which is the only shape
that survives as a non-empty string. Empty/absent body → empty title.

### How `Request.body` crosses into `.ig` (verify-first finding + fix)

`build_request_input` (one source of truth for both the async runner and the sync `ServerApp::call`
adapter) previously crossed the body as `Value::String(req.body.to_string())`, which **re-serializes** —
a `Value::String("Buy milk")` would reach `.ig` as `"Buy milk"` WITH quotes. Fixed it to unwrap a JSON
string to its inner value: `String → s`, `Null → ""`, anything else → its compact JSON text. So a
`"Buy milk"` body now crosses to the prelude `Request.body` (a `String`) as `Buy milk`. Object/number
bodies are unchanged (still their JSON text), so existing `{}`-body tests are unaffected.

### Files changed

- **M** `examples/todo_postgres_app/todo_handlers.ig` — `BuildCreateTodoIntent` gains `input title`
  (`values = MakeWriteValues(account_id, title, "false")`); `AccountTodoCreate` passes `req.body` as the
  title. `key` stays the idempotency key (create v0). Done/show/index untouched.
- **M** `src/lib.rs` — `build_request_input` unwraps a JSON-string body to its inner string (above).
- **M** `tests/todo_postgres_api_write_tests.rs` — create dispatches now pass `title`; assert
  `values.title == "Buy milk"` (replacing the old `title == ""`).
- **M** `tests/todo_postgres_effect_host_tests.rs` — new `create_carries_request_body_as_title`: a POST
  with body `Value::String("Buy milk")` → `InvokeEffect.input.values.title == "Buy milk"` (machine path).
- **M** `tests/todo_postgres_local_e2e_tests.rs` — `local_write_creates` asserts the real DB row
  `title == "Buy milk"`; the real-subprocess test now POSTs a JSON-string title body
  (`"Buy milk via P16"`) and asserts the real DB row `title` equals it (HTTP body → real DB, end-to-end).
- **M** `scripts/todo_postgres_smoke.sh` — POSTs `"Buy milk via smoke"` and adds a
  `create body -> db title` receipt check.

### Acceptance

- v0 body contract stated (raw JSON-string body = title, not a JSON object).
- `BuildCreateTodoIntent` accepts a `title` input; `AccountTodoCreate` passes `req.body`.
- Structured `InvokeEffect.input.values.title` carries the body (effect-host machine test).
- Local Postgres E2E proves the real business row title equals the submitted body (direct + subprocess).
- Smoke sends a non-empty body and checks the DB title (`create body -> db title` → PASS).
- Replay same idempotency key still = no second mutation (unchanged; e2e replay green).
- Read/show/done behavior remains green.
- `cargo test --features machine` green; `--features postgres --test todo_postgres_local_e2e_tests
  -- --test-threads=1` → 9 pass with DSN / skips cleanly without.
- `scripts/check_implemented_surface.sh` PASS; `git diff --check` clean.

### Scope honored

No JSON parser, no request-validation DSL, no new id generation, no migration runner, no production DB.
