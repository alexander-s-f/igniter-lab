# LAB-TODOAPP-API-READ-FRESHNESS-P23 - staged read freshness after writes

Status: TODO
Lane: TodoApp API / product hardening / read path
Type: implementation + regression tests
Delegation code: OPUS-TODOAPP-API-READ-FRESHNESS-P23
Date: 2026-06-23
Skill: idd-agent-protocol

## Context

P18-P22 hardened the Todo API product surface. During curation we noticed an important edge:
`StagedReadHost` dedups reads by `correlation_id + plan_digest`. P12 fixed the older "different plans collide"
bug, but there may still be a **same plan after a write** freshness issue when the request has no unique
correlation id.

Example pressure:

```text
GET list account A -> []
POST create todo in account A
GET list account A -> should show the created todo, not replay []
```

The operator smoke side-steps this today by using different accounts around the empty-list check. That is
acceptable for smoke stability, but not enough for product semantics.

## Goal

Prove whether a same-plan read after a write can return stale replay inside one async runner process, then
fix the smallest correct layer and pin it with tests.

Likely fixes to evaluate:

- assign a fresh per-request correlation id in the async machine runner when the client did not supply one;
- or change staged-read receipt policy so reads are not cached across HTTP requests by default;
- or make read replay opt-in only for explicit client correlation.

Choose the smallest fix that preserves the authority split and does not break explicit correlation semantics.

## Verify first

Read live code before editing:

- `server/igniter-web/src/read_dispatch.rs`
- `server/igniter-web/src/machine_runner.rs`
- `server/igniter-web/src/lib.rs`
- `server/igniter-server/src/host.rs`
- `server/igniter-server/src/middleware.rs`
- `server/igniter-web/tests/todo_postgres_local_e2e_tests.rs`
- `server/igniter-web/scripts/todo_postgres_smoke.sh`

Confirm whether `igweb-serve` assigns a fresh correlation per incoming HTTP request in async machine mode.
If it already does, close with proof and add only a regression test.

## Required proof

Add a test that exercises the real product contour, preferably the local Postgres e2e harness:

1. list account `fresh-*` when it has no todos;
2. create todo under the same account;
3. list the same account again in the same server/process run;
4. assert the second list observes the new row.

If live Postgres is unavailable, add a machine-gated fake/socket test and explain why it proves the same
receipt/correlation path.

## Acceptance

- [ ] Reproduces or disproves the stale same-plan-after-write risk with live evidence.
- [ ] If reproduced, fixes it at the smallest correct layer.
- [ ] Same-plan read after write returns fresh rows.
- [ ] Distinct-plan read replay regression from P12 stays fixed.
- [ ] Explicit client `x-correlation-id` semantics are documented or tested.
- [ ] `scripts/todo_postgres_smoke.sh` no longer needs a workaround comment, or the comment is updated with the new truth.
- [ ] `scripts/check_implemented_surface.sh` PASS.
- [ ] `cargo test --features machine` PASS.
- [ ] `cargo test --features postgres --test todo_postgres_local_e2e_tests -- --test-threads=1` passes or skips cleanly without DSN.
- [ ] `git diff --check` clean.

## Closed surfaces

- No new DB schema.
- No request body contract changes.
- No public production claim.
- No broad rewrite of receipts or machine idempotency unless verify-first proves it is the only safe fix.

