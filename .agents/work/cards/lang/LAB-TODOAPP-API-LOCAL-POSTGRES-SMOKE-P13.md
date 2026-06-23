# LAB-TODOAPP-API-LOCAL-POSTGRES-SMOKE-P13 - repeatable local Postgres smoke

Status: CLOSED
Lane: TodoApp API / operator smoke / production hygiene
Type: implementation + proof
Delegation code: OPUS-TODOAPP-API-LOCAL-POSTGRES-SMOKE-P13
Date: 2026-06-22
Skill: idd-agent-protocol

## Context

P12 proved the product command through a real subprocess and real local Postgres when
`IGNITER_TODO_PG_DSN` is set. That proof lives in Cargo tests. The next production-hygiene need is a
repeatable operator smoke command that a human can run outside the test harness.

## Goal

Add a small repeatable local smoke path for `examples/todo_postgres_app`:

- setup/verify local schema in a dedicated test DB;
- run `igweb-serve --host-config` with bounded loopback requests;
- perform read found, read empty, write, replay checks;
- exit cleanly and cleanup test-owned data.

## Verify first

Read:

- `server/igniter-web/tests/todo_postgres_local_e2e_tests.rs`
- `server/igniter-web/examples/todo_postgres_app/`
- `server/igniter-web/src/bin/igweb-serve.rs`
- `server/igniter-web/README.md`
- `runtime/igniter-machine/src/postgres_real.rs`
- `runtime/igniter-machine/src/postgres_write.rs`

Decide whether the best artifact is:

- a shell script under `server/igniter-web/scripts/`, or
- a Rust ignored-example/helper test binary, or
- a README-only recipe that reuses Cargo test.

Prefer the smallest thing that prevents operator drift.

## Implementation bias

If script:

```text
server/igniter-web/scripts/todo_postgres_smoke.sh
```

Properties:

- uses `IGNITER_TODO_PG_DSN` only;
- refuses to run without it;
- creates temp host config using env-var names, not secret values;
- starts bounded `igweb-serve` on loopback;
- drives HTTP requests with built-in tools available on macOS (`curl`, `python3` if JSON needed);
- cleans test-owned rows by stable prefix/account;
- prints a compact PASS/FAIL receipt.

If README-only, justify why a script would be too much and include exact commands.

## Acceptance

- [x] Closing report states chosen artifact shape and why.
- [x] Smoke path does not require production DB and names a dedicated local/test DB expectation.
- [x] Smoke path refuses missing `IGNITER_TODO_PG_DSN` before starting the server.
- [x] No DSN/passport value is written to a committed file.
- [x] Smoke path proves read found -> 200.
- [x] Smoke path proves read empty -> 404.
- [x] Smoke path proves write -> committed row + receipt.
- [x] Smoke path proves replay same idempotency key -> no second mutation.
- [x] Smoke path exits deterministically and leaves no listener process.
- [x] README or host policy doc points to the smoke path.
- [x] Cargo tests that existed before remain green or documented if intentionally not run.
- [x] `git diff --check` clean.

## Closed surfaces

- No production DB.
- No Docker-compose requirement unless already present and trivial.
- No public deployment story.
- No pool/backpressure.
- No SparkCRM.
- No schema migration product feature.

## Closing report

**Date:** 2026-06-22

### Chosen artifact: shell script (+ README pointer)

`server/igniter-web/scripts/todo_postgres_smoke.sh` — the implementation-bias option, and the smallest
thing that prevents operator drift: a human runs ONE command and gets a compact PASS/FAIL receipt. A
README-only recipe was rejected because the four-behavior check + setup/seed/cleanup + bounded-server
lifecycle is too much to expect a human to paste correctly each time; a Rust ignored-test would just
re-create the P12 in-harness proof rather than the out-of-harness operator path this card asks for.

Notably the script **reuses the committed `examples/todo_postgres_app/host.example.toml` (P28)** and so
writes NO config file at all — the strongest form of "no secret in a committed file", and it also
smoke-tests the P28 example on every run.

### What it does

1. Refuses to start unless `IGNITER_TODO_PG_DSN` is set (exit 2); also checks `psql`/`curl`/`cargo`
   are present. Sets a local-only `IGNITER_TODO_EFFECT_TOKEN` (default `smoke-tok`) — env only.
2. Ensures test-owned schema (`CREATE TABLE IF NOT EXISTS`; `todos.done` is TEXT to match the app's
   string values) in the dedicated DB, then cleans + seeds one account with one todo.
3. Builds `igweb-serve --features postgres`, starts it bounded (`--addr 127.0.0.1:0 --max-requests 4`),
   discovers the bound port from stdout (`listening http://…`).
4. Drives four loopback `curl` requests in order and checks: read found → 200 (+ body has seed id),
   read empty → 404, write → 200, replay (same idempotency-key) → 200.
5. After the server self-exits, verifies DB truth: exactly one business row + one `effect_receipts`
   row for the written key (replay = no second mutation).
6. Prints the PASS/FAIL receipt; an `EXIT` trap kills any server and deletes all test-owned rows.

### Live verification

Run against dedicated `igniter_todo_test` (never SparkCRM): all 7 checks PASS, exit 0. Re-ran twice —
idempotent, clean receipt (build noise routed to a temp log, shown only on build failure), no leftover
`igweb-serve` process, zero residual rows after teardown. Missing-DSN path verified → exit 2 with
guidance.

### Acceptance

- Artifact shape + rationale stated above.
- Requires a dedicated local/test DB (`IGNITER_TODO_PG_DSN`); names that expectation; never production.
- Refuses missing `IGNITER_TODO_PG_DSN` before starting the server (exit 2).
- No DSN/passport value written to any committed file (reuses the secret-free example; secrets are env-only).
- Proves read found → 200, read empty → 404, write → committed row + receipt, replay → no 2nd mutation.
- Deterministic exit; `EXIT` trap leaves no listener and no test rows.
- README "Repeatable smoke" section points to the script.
- No Rust changed this card → pre-existing Cargo tests unaffected: `--features machine` green;
  `--features postgres --test todo_postgres_local_e2e_tests -- --test-threads=1` → 8 pass / skips
  cleanly without DSN.
- `git diff --check` clean.

### Scope honored

No production DB, no Docker-compose, no deployment story, no pool/backpressure, no SparkCRM, no schema
migration product feature.

## Next

Operator hygiene for the Todo Postgres path is now complete (committed example P28 + repeatable smoke
P13). No follow-on required unless a second app needs the same recipe generalized.
