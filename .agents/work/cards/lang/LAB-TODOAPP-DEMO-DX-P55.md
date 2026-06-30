# LAB-TODOAPP-DEMO-DX-P55

Status: CLOSED
Route: standard / TodoApp payoff / DX
Skill: idd-agent-protocol

## Goal

Make `todo_postgres_app` runnable as a **5-minute local DX demo** that a human can
try without reading five proof packets.

The payoff should feel like:

```bash
cd server/igniter-web
scripts/todo_demo.sh start
scripts/todo_demo.sh smoke
scripts/todo_demo.sh stop
```

or an equally simple one-command flow. The demo must use the real
`igweb-serve --features postgres --host-config` path, a dedicated local test DB,
and the committed `examples/todo_postgres_app` app. It must not point at
SparkCRM or production data.

## Current Authority

Read first:

- `server/igniter-web/examples/todo_postgres_app/RUNBOOK.md`
- `server/igniter-web/examples/todo_postgres_app/API.md`
- `server/igniter-web/examples/todo_postgres_app/EXAMPLES.md`
- `server/igniter-web/examples/todo_postgres_app/host.example.toml`
- `server/igniter-web/scripts/todo_postgres_smoke.sh`
- `server/igniter-web/scripts/check_todo_product_surface.sh`
- `server/igniter-web/examples/todo_postgres_app/routes.igweb`
- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`

Live code wins. Existing smoke/runbook are evidence; do not duplicate stale
claims.

## Task

Implement a demo entrypoint, probably:

```text
server/igniter-web/scripts/todo_demo.sh
```

Required commands:

- `doctor` or `check` — verifies `cargo`, `curl`, `psql`/Postgres access, and
  refuses unsafe DSNs.
- `start` — prepares a dedicated local demo DB/schema, starts
  `igweb-serve --features postgres` on `127.0.0.1:<port>`, writes a small local
  state file under an ignored path, and prints `BASE=...`.
- `smoke` — drives the real API cycle:
  health -> list missing/empty distinction -> create object body -> replay ->
  list -> show -> done -> delete -> show 404.
- `html` or included in `smoke` — fetches the Todo HTML route
  `/accounts/:account_id/todos.html` and proves it returns escaped `text/html`.
- `status` — prints whether the bounded local server is running, plus the base
  URL, without leaking DSN/token.
- `stop` — stops the demo server and leaves no listener behind.
- `reset` — deletes only demo-owned rows / local state.

If a single-script state machine is too heavy, keep it simpler, but the final
DX must be copy/pasteable and obvious.

Also write:

```text
server/igniter-web/examples/todo_postgres_app/DEMO.md
```

This doc should be the human-facing entrypoint:

- prerequisites;
- exact commands;
- what each command proves;
- how to stop/reset;
- known limitations;
- safety boundary.

## Safety / Boundary

- Loopback only.
- Dedicated DB only, default name such as `igniter_todo_demo`.
- Refuse DSNs/dbnames containing `spark`, `prod`, or `production`.
- No inline secrets in files.
- No token/DSN echo.
- No production/stable API claim.
- No schema migration framework; demo-owned DDL is okay and should be explicit.
- No public bind.
- No new product route unless absolutely required.
- Do not weaken `todo_postgres_smoke.sh`; reuse or wrap it where possible.

## Acceptance

- [x] `scripts/todo_demo.sh` (or equivalent) exists and is executable.
- [x] `doctor/check` gives actionable output.
- [x] `start` starts the real `igweb-serve --features postgres` product path
      on loopback.
- [x] `smoke` proves create/replay/list/show/done/delete using the real DB.
- [x] HTML route is fetched and verified as `text/html` with escaped content.
- [x] `stop` leaves no listener behind.
- [x] `reset` only touches demo-owned rows/state.
- [x] `DEMO.md` is clear enough for a human to run without prior context.
- [x] Existing `scripts/check_todo_product_surface.sh` still passes.
- [x] Existing `scripts/todo_postgres_smoke.sh` still passes when env is set
      (was RED on this box at `show after delete` due to a pre-existing
      trace=true read-replay; fixed in-place with a non-weakening unique
      `x-correlation-id` per read — see Closing).
- [x] No DSN/token printed in logs/docs.
- [x] `git diff --check` clean.

## Closing

**Delivered**

- `server/igniter-web/scripts/todo_demo.sh` (executable) — `doctor | start |
  smoke | html | status | stop | reset` over the real `igweb-serve --features
  postgres --host-config` product path, bounded loopback, dedicated DB.
- `server/igniter-web/examples/todo_postgres_app/DEMO.md` — human entrypoint.

**Commands the user runs** (from `server/igniter-web/`):

```bash
export IGNITER_TODO_PG_DSN="host=localhost user=$USER dbname=igniter_todo_demo"
export IGNITER_TODO_EFFECT_TOKEN="dev-token"
createdb igniter_todo_demo
scripts/todo_demo.sh doctor
scripts/todo_demo.sh start      # prints BASE=http://127.0.0.1:<port>
scripts/todo_demo.sh smoke      # 15/15 PASS
scripts/todo_demo.sh html       # 4/4 PASS (text/html, escaped)
scripts/todo_demo.sh stop
```

**What is proven** — the same `.igweb`+`.ig` product the operator smoke covers:
health, missing-account 404 vs empty-200, create + idempotent replay, list
(surrogate id), show, done, delete + idempotent replay, show-after-delete 404,
and the DB-backed escaped HTML view — all against a real local Postgres via the
real binary.

**Root cause found + fixed (cross-card, non-weakening).** Both this demo's
`smoke` AND the existing `todo_postgres_smoke.sh` initially failed the
list-after-create / show-after-delete reads. Cause: the app ships `trace = true`
(`igweb.toml`); the trace middleware derives a *deterministic* correlation from
`(method+path+body)` when the client sends none, and read replay is keyed on
`correlation + plan` (P23). Two identical GETs therefore replayed the first
snapshot. Fix in both scripts: send a **unique `x-correlation-id` per logical
read** (the documented opt-in — unique nonce ⇒ fresh; reused ⇒ replay-a-retry).
No assertion was removed or softened; `todo_postgres_smoke.sh` now 21/21 PASS.

**Still lab-only / not production** — loopback bind only, no daemon/deploy, no
schema migrations (demo-owned DDL), surrogate ids, object-only create body, no
pooling. The forgeable static effect passport and read-freshness-under-trace are
pre-existing engine properties, not addressed here.

**Verification summary (this box, local PG):**

- `scripts/todo_demo.sh smoke` → 15/15 PASS
- `scripts/todo_demo.sh html` → 4/4 PASS
- `scripts/check_todo_product_surface.sh` → PASS (no DB)
- `scripts/todo_postgres_smoke.sh` → 21/21 PASS
- no token in `/tmp/igniter_todo_demo.log`; state file cleared on `stop`;
  `git diff --check` clean.

## Reporting

Close with:

- exact commands the user should run;
- local prerequisites and how failures look;
- what is proven by the demo;
- what is still lab-only/not production;
- verification command output summary.
