# LAB-TODOAPP-API-OPERATOR-SMOKE-P21 - make the local Postgres smoke operator-grade

Status: CLOSED
Lane: TodoApp API / product hardening / operator workflow
Type: implementation + docs
Delegation code: OPUS-TODOAPP-API-OPERATOR-SMOKE-P21
Date: 2026-06-23
Skill: idd-agent-protocol

## Context

`scripts/todo_postgres_smoke.sh` now proves read/write/replay/title against local Postgres. It is still
a lab script. Product hardening needs the smoke to be boring, repeatable, and safe for a tired operator:

- clear preflight,
- explicit local-only guard,
- deterministic cleanup,
- compact PASS/FAIL receipt,
- no accidental production/SparkCRM DSN,
- no secret leakage.

## Goal

Turn the Todo local Postgres smoke into the one-command operator proof for the example app.

Target usage:

```bash
IGNITER_TODO_PG_DSN="host=localhost user=alex dbname=igniter_todo_test" \
IGNITER_TODO_EFFECT_TOKEN="dev-token" \
  scripts/todo_postgres_smoke.sh
```

The script should print a compact receipt that states:

- preflight ok,
- schema ready,
- server started on loopback,
- health ok,
- read empty/found/show ok,
- create title persisted,
- done persisted,
- replay no second mutation,
- cleanup done,
- PASS.

## Verify first

Read:

- `server/igniter-web/scripts/todo_postgres_smoke.sh`
- `server/igniter-web/examples/todo_postgres_app/API.md`
- `server/igniter-web/examples/todo_postgres_app/host.example.toml`
- `server/igniter-web/tests/todo_postgres_local_e2e_tests.rs`

Also check whether the script currently depends on binaries already built or runs `cargo run`.

## Implementation bias

Keep it shell-simple and deterministic.

Safety bias:

- Refuse DSNs that look non-local unless there is an explicit lab override env var.
- Refuse database names that look like `spark`, `prod`, `production`, or empty.
- Do not echo tokens or full DSNs in output.
- Use trap cleanup for server process/temp config/temp rows.
- Prefer exact HTTP status/body assertions over loose grep.

If robust DSN parsing is too much for shell, implement conservative string checks and document the
limits.

## Acceptance

- [x] Script refuses missing DSN/token with clear non-secret message.
- [x] Script refuses obvious non-local/prod/SparkCRM DSN shapes.
- [x] Script uses loopback bind only.
- [x] Script proves health, list, show, create-title, done, and replay.
- [x] Script cleanup runs on success and failure.
- [x] Script output includes a compact PASS/FAIL receipt and does not print token/full DSN.
- [x] API.md or README points to the smoke as the operator proof.
- [x] A bounded test or dry-run proof covers at least the refusal paths without requiring live DB.
- [x] Existing local Postgres E2E remains green with DSN or skips cleanly without.
- [x] `scripts/check_implemented_surface.sh` remains PASS.
- [x] `cargo test --features machine` in `server/igniter-web` passes.
- [x] `git diff --check` clean.

## Closed surfaces

- No production deployment story.
- No migrations framework.
- No public bind.
- No Docker compose unless already present and directly required.
- Do not store secrets in files.

## Closing report

**Date:** 2026-06-23

### What changed

- **M** `scripts/todo_postgres_smoke.sh` — hardened to operator-grade:
  - **Preflight (hermetic, before any tool/DB use):** requires `IGNITER_TODO_PG_DSN` AND
    `IGNITER_TODO_EFFECT_TOKEN`; extracts host+dbname (libpq `key=value` conninfo, coarse `postgres://`
    parse); refuses empty dbname, a dbname matching `spark`/`prod`/`production`, and a non-local host
    (override `IGNITER_TODO_SMOKE_ALLOW_NONLOCAL=1`). Refusals exit **2** with clear, non-secret messages.
  - **No secret leakage:** never echoes the token or full DSN; the receipt prints only the dbname + port.
  - **Expanded coverage (8 bounded loopback requests):** health → 200; list-empty → 404; create (title
    body) → 200; create replay → 200; list-found → 200 + carries title; show → 200 + title (create-title
    persisted, read back from DB); done → 200; done replay → 200. Plus DB truth: `done=true`, and exactly
    one receipt per create/done key (replay = no second mutation).
  - **Deterministic cleanup:** trap teardown kills the server + deletes test-owned rows on success AND
    failure; explicit "cleanup done" line; bounded `--max-requests` (no daemon).
- **NEW** `tests/todo_postgres_smoke_guard_tests.rs` — 6 DB-free tests that invoke the script and assert
  each preflight refusal (missing DSN / missing token / spark-ish dbname / non-local host / missing
  dbname / no-secret-leak) exits 2 with the right non-secret message. Runs on plain `cargo test`.
- **M** `README.md` — "Repeatable smoke" section updated to describe it as the one-command operator
  proof with the safety guards and the full coverage list.

### Discovered nuance (out of scope; flagged for follow-up)

The staged read host dedups identical `(plan, correlation_id)` reads within one server run. Two identical
list GETs straddling a write (empty correlation) made the second replay the first's cached empty result.
This card's closed surface forbids new API behavior, so the smoke side-steps it by reading the empty case
from a **distinct** account (distinct plan ⇒ distinct key). The underlying read-freshness behavior is
flagged for a separate card (don't dedup reads / derive correlation from the wire request).

### Acceptance

- Refuses missing DSN/token with clear non-secret message (exit 2; tested).
- Refuses non-local / prod / SparkCRM-shaped DSN (exit 2; tested).
- Loopback bind only (`--addr 127.0.0.1:0`, `ServingPolicy::loopback_only`).
- Proves health, list (empty+found), show, create-title, done, replay (live receipt PASS).
- Cleanup runs on success and failure (trap + explicit).
- Compact PASS/FAIL receipt; no token/full DSN printed (tested).
- README points to the smoke as the operator proof.
- Bounded refusal tests cover the refusal paths without a live DB.
- Local Postgres E2E green with DSN (9 pass) / skips cleanly without.
- `scripts/check_implemented_surface.sh` PASS; `cargo test --features machine` green; `git diff --check`
  clean.

### Scope honored

No production deployment story, no migrations framework, no public bind, no Docker compose, no secrets
written to files.
