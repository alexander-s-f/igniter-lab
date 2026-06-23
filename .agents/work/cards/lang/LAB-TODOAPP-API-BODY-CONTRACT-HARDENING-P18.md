# LAB-TODOAPP-API-BODY-CONTRACT-HARDENING-P18 - fail closed on create body shape

Status: CLOSED
Lane: TodoApp API / product hardening / request validation
Type: implementation + proof
Delegation code: OPUS-TODOAPP-API-BODY-CONTRACT-HARDENING-P18
Date: 2026-06-23
Skill: idd-agent-protocol

## Context

P16 made create useful: a request body that parses as a JSON string literal crosses into `.ig` as the
todo title:

```http
POST /accounts/:account_id/todos
body: "Buy milk"
```

That is honest but still soft. Invalid JSON currently risks collapsing to `Null`/empty title depending
on the reader path, and non-string JSON shapes may cross as compact JSON text. For a product-shaped API,
the v0 contract should fail closed and be easy to explain:

```text
create body MUST be a JSON string literal.
malformed JSON / object / array / number / null / empty => 400, no effect execution.
```

## Goal

Make the create body contract enforced, not merely documented:

- JSON string literal body -> title string -> write intent.
- malformed/non-string/empty body -> product-owned 400.
- rejection happens before `MachineEffectHost` / DB mutation.

## Verify first

Read live surfaces before editing:

- `server/igniter-web/src/lib.rs` (`build_request_input`, request-body crossing)
- `server/igniter-server/src/host.rs` / protocol parsing path, if relevant
- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`
- `server/igniter-web/examples/todo_postgres_app/API.md`
- tests touching create body:
  - `tests/todo_postgres_app_tests.rs`
  - `tests/todo_postgres_effect_host_tests.rs`
  - `tests/todo_postgres_async_runner_smoke_tests.rs`
  - `tests/todo_postgres_local_e2e_tests.rs`

First answer in the closing report:

1. Which layer can still distinguish malformed JSON from `null` today?
2. Can `.ig` distinguish JSON-string body from compact object text after `build_request_input`?
3. What is the smallest layer that can enforce this without adding a JSON parser to `.ig`?

## Implementation bias

Prefer the smallest honest enforcement point.

Likely path:

- Preserve `Request.body : String` for existing `.ig` handlers.
- Add a host-side/body-crossing signal only if needed, e.g. an internal request metadata field or a
  runner-side preflight for routes that require a string body.
- If route-specific preflight is too large, implement an app-local `.ig` guard only if live stdlib can
  express it without stringly hacks.

The card may conclude with a smaller first slice if live code shows route-specific body validation needs
new syntax. If so, produce a readiness packet and no half-measure.

## Acceptance

- [x] Closing report states where malformed JSON is detected today.
- [x] `POST /accounts/acct/todos` with body `"Buy milk"` still writes title `Buy milk`.
- [x] malformed body returns 400 and no effect execution.
- [x] JSON object body returns 400 and no effect execution.
- [x] JSON array/number/null body returns 400 and no effect execution, or the closing report explains
      the exact smaller v0 boundary.
- [x] Empty/missing body behavior is explicit and tested.
- [x] Fake/machine tests prove rejected bodies do not reach `MachineEffectHost`.
- [x] Local Postgres E2E proves rejected body does not insert a business row when DSN is present
      (or skips cleanly without DSN).
- [x] `examples/todo_postgres_app/API.md` documents the enforced body contract.
- [x] `scripts/check_implemented_surface.sh` remains PASS.
- [x] `cargo test --features machine` in `server/igniter-web` passes.
- [x] `cargo test --features postgres --test todo_postgres_local_e2e_tests -- --test-threads=1`
      passes or skips cleanly without DSN.
- [x] `git diff --check` clean.

## Closing report

**Date:** 2026-06-23
**Outcome:** Implemented (no new syntax needed; a host-computed shape signal + an app `if` guard suffice).

### Verify-first answers

1. **Where malformed JSON is detected today:** only at the HTTP parse — `igniter-server` `host.rs:176`
   does `serde_json::from_slice(body).unwrap_or(Value::Null)`, so a malformed body is COLLAPSED to
   `Value::Null` and becomes indistinguishable from an absent body. Downstream nothing can tell them
   apart. Changing that is a global `igniter-server` blast radius — and unnecessary, because the contract
   rejects malformed AND empty identically, so the lost distinction does not matter.
2. **Can `.ig` distinguish a JSON-string body from compact object text after `build_request_input`?**
   No. The old crossing flattened any non-string shape to its compact JSON text and null/malformed to
   `""`, handing `.ig` only `req.body : String`. `.ig` cannot tell `"Buy milk"` from `{"x":1}`.
3. **Smallest layer that can enforce without a JSON parser in `.ig`:** the body-crossing seam in
   `igniter-web` (`build_request_input`), the last place `req.body` is still a typed `serde_json::Value`.

### Design

The host classifies the body's JSON shape into a new `req.body_kind` (`"string"` only for a NON-EMPTY
string; `"empty"` for empty/absent/malformed/json-null; otherwise `"object"`/`"array"`/`"number"`/
`"bool"`). The `AccountTodoCreate` handler guards with a plain `if req.body_kind == "string"` —
`InvokeEffect` on accept, `Respond { 400 }` otherwise. `.ig` parses no JSON; per-route validation stays
the app's decision; the JSON-shape detection stays in the host. v0 boundary: a create requires a
NON-EMPTY string title — empty string / empty body / null / malformed all 400 (the card's permitted
smaller boundary, documented).

### Changes

- `lang/igniter-compiler/src/igweb.rs`: prelude `Request` gains `body_kind : String` (additive,
  backward-compatible — other igweb apps ignore it).
- `server/igniter-web/src/lib.rs` `build_request_input`: computes `body_kind` from the `Value` shape.
- `examples/todo_postgres_app/todo_handlers.ig` `AccountTodoCreate`: guards on `body_kind`.
- `examples/todo_postgres_app/API.md`: documents the enforced contract (shape table + seam + limits).
- Tests:
  - NEW `todo_postgres_app_tests::create_body_contract_rejects_non_string_shapes` (sync, no DB): string
    → 202; object/object-nonempty/array/number/bool/null/empty/empty-string/malformed → 400, no target.
  - NEW `todo_postgres_effect_host_tests::non_string_create_body_rejected_before_effect_host` (fake
    machine): object body → 400, `executed=false`, write executor `attempts()==0`.
  - NEW `todo_postgres_local_e2e_tests::subprocess_non_string_create_body_writes_no_row` (real binary +
    real PG; skips w/o DSN): object body → 400, zero `todos` rows, zero `effect_receipts`. GREEN against
    a live `igniter_todo_test` DB.
  - Updated every create test that previously sent a `{}` (object) "don't-care" body to send a JSON
    string title (helpers in 7 test files: async_machine_runner, effect_host, effect_host_runner,
    async_runner_smoke, app_tests, api_read_write_e2e, igweb_serve_e2e, local_e2e). ctx_demo/ctx_accum/
    todo_v2 use other apps (no `body_kind` guard) and were untouched.

### Results

`cargo test` (default) and `cargo test --features machine`: all green. `cargo test --features
"machine postgres" --test todo_postgres_local_e2e_tests`: 11 pass against real PG, skips cleanly w/o DSN.
Compiler tests green. `check_implemented_surface.sh` PASS. Operator smoke (P21) still PASS.
`git diff --check` clean.

## Closed surfaces

- No JSON-object body parser.
- No generated ids.
- No schema migration runner.
- No production/public API promise.
- Do not move body validation into `igniter-server` globally unless verify-first proves it is the only
  safe seam; if so, document the blast radius and keep behavior backward-compatible for non-Todo apps.

