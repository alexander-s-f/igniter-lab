# LAB-TODOAPP-API-IDEMPOTENCY-CONFLICT-P19 - prove replay conflicts fail safely

Status: CLOSED
Lane: TodoApp API / product hardening / idempotency semantics
Type: implementation or proof + docs
Delegation code: OPUS-TODOAPP-API-IDEMPOTENCY-CONFLICT-P19
Date: 2026-06-23
Skill: idd-agent-protocol

## Context

The Todo API now proves happy replay: same idempotency key + same operation performs no second mutation.
That is necessary but not enough for product trust. A client bug can reuse the same idempotency key with
a different body or different business target.

We need to know and document the behavior:

```text
same idempotency key + same payload       -> dedup ok
same idempotency key + different payload  -> conflict/refusal, never silent success
```

If the existing machine receipt layer already enforces payload/authority digest equality, this card is
mostly proof + API docs. If not, implement the smallest fix in the machine/web host seam.

## Goal

Make idempotency replay conflict behavior explicit and tested for the Todo API.

At minimum:

- create: same idempotency key, different title -> conflict/refusal, no second mutation.
- done: same idempotency key, different `todo_id` or account -> conflict/refusal, no wrong-row mutation.

## Verify first

Read:

- `runtime/igniter-machine/src/*receipt*`, `postgres_write.rs`, and write-effect replay code.
- `server/igniter-web/src/machine_runner.rs`
- `server/igniter-web/tests/todo_postgres_effect_host_tests.rs`
- `server/igniter-web/tests/todo_postgres_local_e2e_tests.rs`
- `server/igniter-web/examples/todo_postgres_app/API.md`

Before editing, answer:

1. What fields are included in the duplicate/replay digest today?
2. Does replay conflict return a distinct status/body, or a generic failure?
3. Does the Postgres `effect_receipts` layer also protect against conflict, or only the machine layer?

## Implementation bias

Prefer proof if the substrate is already strict.

If behavior is weak, keep the fix in the machine/host receipt layer, not in Todo app `.ig`. The app
should not own receipt semantics.

For HTTP status, prefer a stable client-facing conflict status (`409`) if existing taxonomy supports it.
If current host mapping cannot express `409` without broad changes, document the current status and open
a follow-up taxonomy card; do not fake precision.

## Acceptance

- [x] Closing report states current duplicate/replay digest inputs.
- [x] Same create idempotency key + same body remains dedup/no second mutation.
- [x] Same create idempotency key + different body fails safely and does not mutate DB/fake adapter.
- [x] Same done idempotency key + same target remains dedup/no second mutation.
- [x] Same done idempotency key + different `todo_id` fails safely and does not mutate the wrong row.
- [x] Fake/machine tests cover conflict behavior.
- [x] Local Postgres E2E covers at least one conflict path with DSN or skips cleanly without DSN.
- [x] API.md documents replay vs replay-conflict behavior.
- [x] `cargo test --features machine` in `server/igniter-web` passes.
- [x] `cargo test --features postgres --test todo_postgres_local_e2e_tests -- --test-threads=1`
      passes or skips cleanly without DSN.
- [x] `scripts/check_implemented_surface.sh` remains PASS.
- [x] `git diff --check` clean.

## Closing report

**Date:** 2026-06-23
**Outcome:** Proof + docs. The substrate is already strict at TWO layers — no machine/host fix needed.

### Verify-first answers

1. **Duplicate/replay digest inputs today** — two independent layers:
   - **Ingress dedup gate** (`ingress.rs::decide_duplicate`, `body_digest`): blake3 of the full effect
     intent body (the `InvokeEffect.input` WriteIntent — for `create` includes `values.title`; for
     `done` includes `key` = route `todo_id`). Keyed by `(route, idempotency-key)`. Policy is
     `dedup_strict` + `variant_payload = false`.
   - **Write-receipt gate** (`write.rs::run_write_effect`): identity binds
     `capability_id + operation + authority_digest + payload_digest`, where `payload_digest` is blake3
     of `{intent, correlation_id}`.
2. **Distinct status/body?** Yes. Ingress conflict → **409** `{"error":"conflict"}` (before any replica
   activation). Write-receipt conflict → **403** `{"status":"denied", detail:"idempotency key reused
   with a different payload"}` (before the executor). Neither is a silent success.
3. **Does the PG `effect_receipts` layer protect against conflict?** No — it is keyed by idempotency
   key ONLY, so it prevents a *second mutation* (at-most-once) but does not compare payloads. Conflict
   *detection* is the machine layer's job (ingress dedup + write-receipt digest); the PG unique key is a
   mutation-prevention backstop for a lost receipt.

For the Todo API the **ingress gate fires first** → same-key/different-body is a clean **409** before
any effect; the write-receipt 403 is defence-in-depth behind it.

### Evidence added (no production code changed)

- `tests/todo_postgres_effect_host_tests.rs` (fake, `--features machine`):
  - `create_same_key_different_body_conflicts_no_second_effect` → 409, `exec.attempts()==1`, `applied==1`.
  - `create_same_key_same_body_dedup_no_second_effect` → 200 replay, one effect.
  - `done_same_key_different_todo_id_conflicts_no_wrong_mutation` → 409, one effect (wrong row never written).
- `tests/todo_postgres_local_e2e_tests.rs` (real PG, `--features "machine postgres"`, skips w/o DSN):
  - `local_write_same_key_different_payload_conflicts_row_unchanged` → `WriteState::Denied`,
    `adapter.attempts()==1`, real `todos.title` stays the first payload's value. Verified GREEN against a
    live `igniter_todo_test` DB.
- `examples/todo_postgres_app/API.md`: new "Replay vs replay-conflict" section + 409 in the routes table.

`cargo test --features machine`: 68 lib + all integration suites green (effect-host now 10 tests).
`cargo test --features "machine postgres" --test todo_postgres_local_e2e_tests`: skips cleanly w/o DSN;
the conflict test passes against real Postgres with DSN. `check_implemented_surface.sh`: PASS.
`git diff --check`: clean.

## Closed surfaces

- No new id-generation scheme.
- No app-owned receipt logic in `.ig`.
- No weakening duplicate policy.
- No production DB assumptions.

