# LAB-TODOAPP-API-DONE-BUSINESS-KEY-P15 - fix done intent business key semantics

Status: CLOSED
Lane: TodoApp API / product correctness / write intent
Type: implementation + proof
Delegation code: OPUS-TODOAPP-API-DONE-BUSINESS-KEY-P15
Date: 2026-06-23
Skill: idd-agent-protocol

## Context

`AccountTodoDone` currently builds a `BuildMarkTodoDoneIntent(todo_id, idempotency_key)`, but the
intent uses the idempotency key as `key`:

```ig
compute intent : WriteIntent = {
  operation: "update", target: "todos",
  key: idempotency_key, values: values, correlation_id: ""
}
```

That means the business primary key can become the idempotency key rather than the route `todo_id`.
For a product API, `POST /accounts/:account_id/todos/:todo_id/done` should mutate the todo identified
by `todo_id`; the request idempotency key should remain the effect idempotency key.

There is a second live tension: `host.example.toml` currently allows `ops = "insert,upsert"`, while
`BuildMarkTodoDoneIntent` emits `operation: "update"`. Verify the real executor semantics before
choosing the operation label.

## Goal

Make the `done` route's structured write intent product-correct:

```text
intent.key == todo_id                  # business key / target row
InvokeEffect.idempotency_key == req.idempotency_key
operation is host-policy-compatible    # update vs upsert decided by live executor semantics
values.done == "true"
```

## Verify first

Read live code:

- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`
- `server/igniter-web/examples/todo_postgres_app/host.example.toml`
- `server/igniter-web/tests/todo_postgres_api_write_tests.rs`
- `server/igniter-web/tests/todo_postgres_effect_host_tests.rs`
- `server/igniter-web/tests/todo_postgres_local_e2e_tests.rs`
- `runtime/igniter-machine/src/postgres_write.rs`
- `runtime/igniter-machine/src/postgres_real.rs`

Answer explicitly in the closing report:

- Does the real adapter distinguish `update` from `upsert`, or only gate on the policy label?
- Should v0 `done` use `operation: "upsert"` to match the current adapter, or should host policy add
  `"update"`? Pick the least surprising, tested behavior.

## Implementation bias

Likely shape (verify before applying):

```ig
pure contract BuildMarkTodoDoneIntent {
  input todo_id         : String
  input idempotency_key : String
  compute values = call_contract("MakeWriteValues", "", "", "true")
  compute intent : WriteIntent = {
    operation: "upsert", target: "todos",
    key: todo_id, values: values, correlation_id: idempotency_key
  }
  output intent : WriteIntent
}

pure contract AccountTodoDone {
  ...
  compute d : Decision = InvokeEffect {
    target: "todo-done",
    input: intent,
    idempotency_key: req.idempotency_key
  }
}
```

If live code argues for `"update"`, update `host.example.toml` and tests accordingly.

## Acceptance

- [x] Closing report states the chosen operation label and why.
- [x] `BuildMarkTodoDoneIntent(... todo_id:"todo-42", idempotency_key:"evt-2")` yields `key:"todo-42"`.
- [x] `AccountTodoDone` still sends `InvokeEffect.idempotency_key == req.idempotency_key`.
- [x] Host policy/example allows the chosen operation label for done.
- [x] Fake/machine write tests prove done reaches `MachineEffectHost` with business key = todo id.
- [x] Local Postgres E2E adds or updates a done proof: existing seeded row becomes `done == "true"`.
- [x] Replay same done idempotency key causes no second mutation/receipt duplication.
- [x] Create route behavior remains green.
- [x] `cargo test --features machine` in `server/igniter-web` passes.
- [x] `cargo test --features postgres --test todo_postgres_local_e2e_tests -- --test-threads=1` passes or skips cleanly without DSN.
- [x] `scripts/check_implemented_surface.sh` remains PASS.
- [x] `git diff --check` clean.

## Closed surfaces

- No generic PATCH semantics.
- No typed row destructuring.
- No migration runner.
- No production DB.
- No raw SQL in `.ig`/`.igweb`.

## Closing report

**Date:** 2026-06-23

### Verify-first answers (the two questions the card asked)

- **Does the real adapter distinguish `update` from `upsert`?** No. `intent.operation` is consumed
  ONLY by the executor's op-allowlist gate (`postgres_write.rs:201`). The adapter SQL
  (`postgres_real.rs::transact`) is always a single `INSERT … ON CONFLICT (<key>) DO UPDATE SET …`
  statement — i.e. an upsert — regardless of the label. The label never reaches SQL.
- **Chosen operation label: `"upsert"`.** It matches the adapter's real semantics AND the existing
  `host.example.toml` / `write_policy()` allowlist (`insert,upsert`). `"update"` would be denied by the
  op allowlist and would be a misleading label (no partial-update path exists). So no host policy /
  example change was needed.

### Old vs new behavior

- **Before:** `BuildMarkTodoDoneIntent(todo_id, idempotency_key)` set `operation:"update"`,
  `key: idempotency_key` — the business primary key became the idempotency key. `AccountTodoDone` set
  `InvokeEffect.idempotency_key = intent.key` (= the idem key, but for the wrong reason).
- **After:** `BuildMarkTodoDoneIntent(account_id, todo_id, idempotency_key)` sets `operation:"upsert"`,
  `key: todo_id` (the business row), `values = {account_id, "", "true"}`, `correlation_id: idem_key`.
  `AccountTodoDone` sets `InvokeEffect.idempotency_key = req.idempotency_key`. So:
  `intent.key == todo_id`, `InvokeEffect.idempotency_key == req.idempotency_key`, `values.done == "true"`.

### Deviation from the card's suggested shape (found during verify)

The suggested `MakeWriteValues("", "", "true")` would set `account_id = ""`, and because v0 is a
**full-row** upsert (the adapter writes every configured column), the ON CONFLICT update would set
`account_id = ""` and violate `todos_account_id_fkey`. So `account_id` is carried from `ctx.account_id`
to keep the row FK-valid. v0 does NOT preserve `title` (no partial PATCH — an explicit closed surface);
this is documented in the handler comment and asserted in the E2E.

### Files changed

- **M** `examples/todo_postgres_app/todo_handlers.ig` — `BuildMarkTodoDoneIntent` (new `account_id`
  input; key→`todo_id`; op→`upsert`); `AccountTodoDone` (passes account_id+todo_id; effect idem key →
  `req.idempotency_key`). Create unchanged.
- **M** `tests/todo_postgres_api_write_tests.rs` — `command_contracts_produce_write_intents` now asserts
  done `operation:"upsert"`, `key:"todo-42"`, `values.account_id`, `values.done`;
  `handlers_wire_command_contracts_with_no_identity` asserts both `idempotency_key: intent.key` (create)
  and `idempotency_key: req.idempotency_key` (done).
- **M** `tests/todo_postgres_effect_host_tests.rs` — `keyed_done_executes_via_machine_host` now proves
  the InvokeEffect reaching the host carries business key `"42"` (= route todo_id), `op "upsert"`,
  `values.account_id "7"`, `values.done "true"`, and effect idempotency key `"evt-2"`.
- **M** `tests/todo_postgres_local_e2e_tests.rs` — new `local_done_marks_existing_row_done`: seeds an
  existing row (done=false, real title), runs the done intent through the real write contour, asserts
  the row flips to `done="true"` with `account_id` preserved (FK intact), then replays the same key and
  asserts exactly one real mutation + one PG `effect_receipts` row (business_key = todo_id).

No `.igweb`/SQL/host-policy changes; create route untouched.

### Acceptance

- Chosen op label `upsert` + rationale stated.
- `BuildMarkTodoDoneIntent(... todo_id:"todo-42", idem:"evt-2")` → `key:"todo-42"` (asserted).
- `AccountTodoDone` sends `InvokeEffect.idempotency_key == req.idempotency_key` (asserted in effect-host).
- Host policy/example already allows `upsert` (no change).
- Machine effect-host test proves done reaches `MachineEffectHost` with business key = todo id.
- Local PG E2E: existing seeded row becomes `done == "true"`; replay → no second mutation/receipt dup.
- Create route behavior remains green (unchanged + suites pass).
- `cargo test --features machine` green; `--features postgres --test todo_postgres_local_e2e_tests
  -- --test-threads=1` → 9 pass with DSN / skips cleanly without.
- `scripts/check_implemented_surface.sh` PASS; `git diff --check` clean.

### Scope honored

No generic PATCH semantics, no typed row destructuring, no migration runner, no production DB, no raw
SQL in `.ig`/`.igweb`.
