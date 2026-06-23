# LAB-TODOAPP-API-ACCOUNT-EXISTENCE-P38 - implement missing-account vs empty-list semantics

Status: DONE (2026-06-23) — verify-first: nested ReadThen was NOT implemented but is a small generic
loop (not a broad rewrite) → implemented the slice, no readiness delta. Generic bounded sequential
ReadThen loop + opaque `carry` on the ReadThen variant (host runner); `.ig` two-stage FindAccount →
CheckAccountThenList (empty→404 account not found, else→ListTodos→200/200[]); multi-source
`[postgres.read.<name>]` config so the real binary reads `accounts`. Server stays generic. Mapping:
denied→403, adapter failure→503, runaway chain→500 (MAX_READ_HOPS=8). Proof:
`lab-docs/lang/lab-todoapp-api-account-existence-p38-v0.md`. Evidence: machine-feature 28 suites green;
compiler green; 13/13 real-Postgres gated tests pass (`--test-threads=1`), incl. live-binary 404 for a
missing account + dedicated missing/empty matrix + bounded-loop test. All acceptance boxes checked;
`git diff --check` clean.
Lane: TodoApp API / ReadThen semantics / product polish
Type: implementation
Delegation code: OPUS-TODOAPP-API-ACCOUNT-EXISTENCE-P38
Date: 2026-06-23
Skill: idd-agent-protocol

## Depends on

- `LAB-TODOAPP-API-ACCOUNT-EXISTENCE-SEMANTICS-P37` (readiness/design)

## Context

P37 established the product semantic gap:

- existing account + zero todos -> `200 []`
- missing account -> `404`

Current behavior is not product-precise enough because `ListTodosByAccount` empty rows alone cannot
distinguish those two states. P37 recommended a two-stage read design: first prove the account exists,
then list todos. It also found that the generic runner likely needs nested/sequential `ReadThen`
support rather than product-specific host magic.

## Goal

Implement the smallest product-correct slice:

1. generic nested/sequential `ReadThen` support if live code still needs it;
2. Todo `.ig` contracts/policy for account-existence check;
3. tests proving missing account vs empty todo list.

Keep the server generic. Product meaning stays in the Todo app and host policy, not in `igniter-server`.

## Verify first

Read live code before editing:

- `lab-docs/lang/lab-todoapp-api-account-existence-semantics-p37-v0.md`
- `server/igniter-web/src/lib.rs`
- `server/igniter-web/src/read_dispatch.rs`
- `server/igniter-web/src/machine_runner.rs`
- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`
- `server/igniter-web/examples/todo_postgres_app/host*.toml`
- `server/igniter-web/examples/todo_postgres_app/API.md`
- `server/igniter-web/tests/todo_postgres_*`

First verify whether nested `ReadThen` is already implemented after P37. If yes, do not reimplement it;
just add the Todo product slice and tests.

## Implementation bias

Preferred shape from P37:

- add a read intent for account existence (`FindAccount` or equivalent);
- add a continuation that returns either `404 account not found` or a second `ReadThen` for
  `ListTodosByAccount`;
- make the runner handle sequential `ReadThen` generically, with a bounded loop/depth guard;
- keep denied account-source/field as host-owned `403`;
- keep adapter failure as host-owned `503` / current mapped infra status;
- keep empty todo rows for an existing account as app-owned `200 []`.

If nested `ReadThen` requires a broad runner rewrite, stop and produce a readiness delta rather than
shipping product-specific magic.

## Acceptance

- [x] Existing account with rows -> `200` and rows JSON.
- [x] Existing account with zero todos -> `200 []`.
- [x] Missing account -> `404` app-owned response, not host infra error.
- [x] Denied account source/field -> host-owned `403`, adapter not called.
- [x] Adapter/read failure remains host-owned infra status (document exact live mapping).
- [x] Nested/sequential `ReadThen`, if implemented, is generic and bounded (no infinite continuation loop).
- [x] No DB-specific or Todo-specific logic enters `igniter-server`.
- [x] API.md and RUNBOOK reflect the account existence semantics.
- [x] Fake/no-DB tests cover the semantic matrix.
- [x] Real/local Postgres e2e covers at least missing account and existing-empty account, or skips cleanly without DSN.
- [x] `cargo test --features machine` in `server/igniter-web` passes.
- [x] `cargo test --features "machine postgres" --test todo_postgres_local_e2e_tests -- --test-threads=1`
      passes or skips cleanly without DSN.
- [x] `git diff --check` clean.

## Proof

Preferred proof doc:

```text
lab-docs/lang/lab-todoapp-api-account-existence-p38-v0.md
```

## Closed surfaces

- No object-body/id-generation changes (P35/P36 are closed).
- No global query planner or join support.
- No hidden host interpretation of product meaning.
- No server route table.
- No schema migration unless tests already own a local fixture schema path.
