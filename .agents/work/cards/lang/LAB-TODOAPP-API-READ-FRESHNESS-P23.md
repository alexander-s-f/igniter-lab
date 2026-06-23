# LAB-TODOAPP-API-READ-FRESHNESS-P23 - staged read freshness after writes

Status: CLOSED
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

- [x] Reproduces or disproves the stale same-plan-after-write risk with live evidence.
- [x] If reproduced, fixes it at the smallest correct layer.
- [x] Same-plan read after write returns fresh rows.
- [x] Distinct-plan read replay regression from P12 stays fixed.
- [x] Explicit client `x-correlation-id` semantics are documented or tested.
- [x] `scripts/todo_postgres_smoke.sh` no longer needs a workaround comment, or the comment is updated with the new truth.
- [x] `scripts/check_implemented_surface.sh` PASS.
- [x] `cargo test --features machine` PASS.
- [x] `cargo test --features postgres --test todo_postgres_local_e2e_tests -- --test-threads=1` passes or skips cleanly without DSN.
- [x] `git diff --check` clean.

## Closed surfaces

- No new DB schema.
- No request body contract changes.
- No public production claim.
- No broad rewrite of receipts or machine idempotency unless verify-first proves it is the only safe fix.

## Closing report

**Date:** 2026-06-23

### Reproduced — by code inspection + live evidence

The stale same-plan-after-write risk was **real**. Mechanism (verify-first, live source):
- `run_effect_core` (`igniter-machine/src/capability.rs:375`) replays the cached outcome on a receipt-key
  hit — the executor is NOT re-entered.
- `StagedReadHost::execute` keyed reads as `"{correlation_id}:{plan_digest}"`, and `correlation_id`
  comes only from the `x-correlation-id` header (`host::parse_request`); absent → it fell back to the
  **constant** `"staged-read"`.
- The async runner does **not** assign a fresh per-request correlation.
⇒ Two identical-plan reads with no client correlation, sharing one `StagedReadHost` (one process),
collided on one key → the second replayed the first's rows. So `list → [] ; create ; list` replayed `[]`.

### Fix — smallest correct layer (`StagedReadHost`)

Read replay is now **opt-in via an explicit `x-correlation-id`** (`server/igniter-web/src/read_dispatch.rs`):
- **with** a non-empty correlation: key = `"{corr}:{plan_digest}"` → a genuine client retry replays.
- **without**: a monotonic per-host `AtomicU64` makes the key unique per execution
  (`"auto-{n}:{plan_digest}"`) → every read runs fresh, never replaying across requests.

Chosen at the read-host layer (not the runner) so it touches only read idempotency — write correlation
and response-echo correlation are untouched (authority split preserved). No machine/receipt rewrite.
Tradeoff: an uncorrelated read writes a fresh in-memory host receipt each time; bounded for the bounded
loopback runner (acceptable v0).

### Proof

- `tests/readthen_dispatch_tests.rs` (always-on, no DSN; `query_count()` distinguishes fresh vs replay):
  `uncorrelated_same_plan_reads_run_fresh` (==2), `explicit_same_correlation_same_plan_replays` (==1),
  `distinct_plans_never_collide` (==2, P12 regression holds).
- `tests/todo_postgres_local_e2e_tests.rs::local_read_after_write_is_fresh_same_process` (live, real
  product contour): list `fresh-p23` → 404; real `INSERT`; same list, same read host, no correlation →
  **200 carrying the new row** (would replay 404 without the fix). Skips cleanly without DSN.

### Acceptance

- Reproduced (code + live) and fixed at the smallest correct layer.
- Same-plan read after write returns fresh rows; P12 distinct-plan regression stays fixed.
- Explicit `x-correlation-id` semantics tested (`explicit_same_correlation_same_plan_replays`) and
  documented (`API.md` → "Reads & freshness").
- `scripts/todo_postgres_smoke.sh`: the "separate empty account" comment updated to the new truth (it is
  now a clarity choice, not a correctness workaround); smoke PASS.
- `scripts/check_implemented_surface.sh` PASS; `cargo test --features machine` green;
  `--features postgres --test todo_postgres_local_e2e_tests -- --test-threads=1` → 12 pass with DSN /
  skips cleanly without; `git diff --check` clean.

### Scope honored

No new DB schema, no body-contract change, no public claim; receipts/machine idempotency untouched (the
fix is a read-host key-derivation change only).

