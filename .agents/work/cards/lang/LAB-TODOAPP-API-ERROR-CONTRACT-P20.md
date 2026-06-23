# LAB-TODOAPP-API-ERROR-CONTRACT-P20 - stabilize product error responses

Status: CLOSED
Lane: TodoApp API / product hardening / error taxonomy
Type: implementation + documentation
Delegation code: OPUS-TODOAPP-API-ERROR-CONTRACT-P20
Date: 2026-06-23
Skill: idd-agent-protocol

## Context

The Todo API now has real reads/writes, but its error responses are still a mix of app-owned strings,
host-denied responses, runner diagnostics, and generic JSON 500s. For product use and agent debugging,
we need a small stable contract:

```json
{ "error": { "code": "...", "message": "..." } }
```

or a documented equivalent, consistently across product paths.

This is API hardening, not a global Igniter error-spec canon.

## Goal

Define and prove the Todo API v0 error contract for:

- route miss -> 404
- method mismatch -> 405
- missing idempotency key -> 400
- invalid create body -> 400 (if P18 already landed; otherwise mark pending)
- app not found -> 404 (`account not found`, `todo not found`, `no todos`)
- host denied read/write -> 403
- host unavailable/misconfigured -> 503 or current mapped status
- internal/malformed continuation/render/unknown decision -> 500

## Verify first

Read live response mapping and tests:

- `server/igniter-server/src/host.rs`
- `server/igniter-server/src/protocol.rs`
- `server/igniter-web/src/lib.rs`
- `server/igniter-web/src/read_dispatch.rs`
- `server/igniter-web/src/machine_runner.rs`
- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`
- `server/igniter-web/examples/todo_postgres_app/API.md`
- `server/igniter-web/tests/*diagnostics*`
- Todo Postgres API tests

Produce a short table in the closing report: condition, owner (app/host/runner/server), status, body
shape, leak risk.

## Implementation bias

Keep the first slice small:

- For app-owned errors, update `.ig` handlers if needed.
- For host-owned read/write errors, prefer existing mapping if it is already stable and non-leaky.
- Do not redesign all runner diagnostics.
- Do not force a global error envelope if it breaks existing non-Todo tests. It is acceptable for this
  card to document current shape and add tests first.

If consistency requires a bigger cross-crate response protocol change, stop at readiness and open a
separate `igniter-server` / `igniter-web` card.

## Acceptance

- [x] API.md has an error section with status/body examples.
- [x] Tests assert missing idempotency key response status and body shape.
- [x] Tests assert read denied status/body shape without leaking DSN/policy internals.
- [x] Tests assert not-found status/body shape for list-empty and show-missing.
- [x] Tests assert unknown path and wrong method behavior remains 404/405.
- [x] If P18 has landed, tests assert invalid body error shape; otherwise API.md marks it as pending.
- [x] No error response leaks DSN, bearer token, raw SQL, or host config path.
- [x] `cargo test --features machine` in `server/igniter-web` passes.
- [x] `cargo test --features postgres --test todo_postgres_local_e2e_tests -- --test-threads=1`
      passes or skips cleanly without DSN.
- [x] `scripts/check_implemented_surface.sh` remains PASS.
- [x] `git diff --check` clean.

## Closing report

**Date:** 2026-06-23
**Outcome:** Document + test the CURRENT contract (the card's explicitly-acceptable path). A unified
`{"error":{"code","message"}}` envelope is a cross-crate change — deferred to readiness (see below).

### Verify-first table (condition · owner · status · body shape · leak risk)

| Condition | Owner | Status | Body shape | Leak risk |
|---|---|---|---|---|
| route miss (unknown path) | app (.igweb routing) | 404 | `{"body":"…"}` | none |
| wrong method on known pattern | app | 405 | `{"body":"…"}` | none |
| missing idempotency key | app (`requires idempotency` guard) | 400 | `{"body":"…"}` | none |
| invalid create body (P18) | app handler | 400 | `{"body":"create body must be a non-empty JSON string title"}` | none |
| account not found | app guard | 404 | `{"body":"account not found"}` | none |
| todo not found (show) | app continuation | 404 | `{"body":"todo not found"}` | none |
| list empty | app continuation | 404 | `{"body":"no todos"}` | none |
| read denied by host policy | host (`read_dispatch`→`lib.rs`) | 403 | `{"error":"…"}` | reason names the client's requested source/field/op only — no DSN/SQL |
| read host unavailable | host | 503 | `{"error":"…"}` | no DSN |
| write committed | host (`ingress::map_effect_outcome`) | 200 | `{"status":"committed","result":…}` | none |
| write denied (target/op) | host | 403 | `{"status":"denied","detail":…}` | names target/op |
| write conflict (same key, diff body) | host (ingress dedup) | 409 | `{"error":"conflict"}` | none |
| write duplicate-limit | host | 429 | `{"error":"duplicate limit reached"}` | none |
| write retryable | host | 503 | `{"status":"retry_later"}` | none |
| write permanent failure | host | 502 | `{"status":"failed","detail":…}` | none |
| write state unknown | host | 202 | `{"status":"accepted_unknown","correlation_id":…}` | none |
| unauthorized (bad/missing passport) | host (ingress) | 401 | `{"error":"unauthorized"}` | none |
| unbound effect target | host (`effect_host`) | 502 | `{"error":"unbound target","target":…}` | none |
| unknown/unmapped decision | runner (`lib.rs map_decision`) | 500 | `{"error":"unknown decision tag: …","raw":…}` | echoes the app decision (no secrets in Todo) |
| continuation/render failure | runner | 500 | `{"error":"…"}` (render: + `kind`, never the artifact) | engine error string, no DSN |

**Two body shapes by owner**: app-owned `Respond` errors carry `{"body": <message>}` (status carries
the class — same shape as success); host-owned errors carry `{"error": <message>}` or
`{"status": <word>, "detail": …}`. Documented honestly in API.md.

### Why no unified envelope (deferred)

A single `{"error":{"code","message"}}` envelope would require: a new `.ig` `Respond`-error decision
variant (or stringly JSON in `.ig`), changing `igniter-machine` ingress effect mapping (shared by ALL
effect apps), and `igniter-server`. That is the "bigger cross-crate response protocol change" the card
says to stop at readiness for. Follow-up: a `LAB-IGNITER-WEB-ERROR-ENVELOPE` readiness card.

### Changes (no production status/body changed — document + test only)

- `examples/todo_postgres_app/API.md`: new "Error contract (v0)" section — the full table, the two body
  shapes, the no-leak guarantee, and the deferred-envelope note.
- NEW `tests/todo_error_contract_tests.rs` (sync, no DB): route-miss 404, method 405, keyless 400,
  invalid-body 400 (object/number/null/empty) — each asserts status + `{"body":…}` shape + no leak; a
  valid create is asserted to carry no error shape.
- `tests/todo_postgres_async_runner_smoke_tests.rs` (machine): new `P20` tests — read-denied 403
  (`{"error":…}`, no DSN/SQL leak), write-conflict 409 (`{"error":"conflict"}`), unauthorized 401
  (`{"error":"unauthorized"}`). Not-found 404 (list-empty + show-missing) was already pinned there.

### Results

`cargo test` and `cargo test --features machine`: all green. Postgres e2e: 11 pass / skips clean w/o DSN.
`check_implemented_surface.sh` PASS. `git diff --check` clean.

## Closed surfaces

- No global canon error spec.
- No public API stability promise.
- No production observability/metrics system.
- No broad rewrite of `igniter-server` unless the closing report proves a small local slice is impossible.

