# LAB-TODOAPP-DEMO-DX-GUARD-P57

Status: DONE
Route: fast_lane / TodoApp payoff / DX hygiene
Skill: idd-agent-protocol

## Goal

Prevent the new TodoApp demo DX from drifting immediately.

After P55/P56 land, add a bounded no-secret/no-DB guard for the demo surface:
the demo script should refuse unsafe/missing environment clearly, docs should
point at the current commands, and active surface docs should not describe stale
manual steps.

## Current Authority

Read first:

- P55 closing report
- P56 closing report, if landed
- `server/igniter-web/examples/todo_postgres_app/DEMO.md`
- `server/igniter-web/examples/todo_postgres_app/RUNBOOK.md`
- `server/igniter-web/examples/todo_postgres_app/API.md`
- `server/igniter-web/scripts/check_todo_product_surface.sh`
- `server/igniter-web/IMPLEMENTED_SURFACE.md`

## Task

Add a guard step to existing product-surface checks, or a small sibling script,
that verifies:

- demo script exists and is executable;
- `doctor/check` refuses missing local requirements with actionable output;
- missing DSN/token or unsafe DB names fail before any socket bind;
- docs mention the demo command and do not point users at stale manual-only
  steps as the primary path;
- no committed file contains a raw token/DSN.

Keep this DB-free. The real DB smoke remains operator/local.

## Boundary

- No product feature changes.
- No route changes.
- No Postgres requirement in CI guard.
- No generated demo artifacts committed.
- No claim that TodoApp is production-ready.

## Acceptance

- [x] Guard script/check added.
- [x] Guard runs without Postgres.
- [x] It fails closed for missing env/unsafe config.
- [x] Active docs point to the new demo path.
- [x] `scripts/check_todo_product_surface.sh` includes or references the guard.
- [x] `git diff --check` clean.

## Closing

**Guard command** (from `server/igniter-web/`):

```bash
scripts/check_todo_demo_surface.sh          # standalone, DB-free, no socket
scripts/check_todo_product_surface.sh       # now also runs the demo guard as step 8
```

**Delivered**

- `server/igniter-web/scripts/check_todo_demo_surface.sh` (new, executable) — a
  bounded **no-DB / no-socket** guard for the demo DX surface.
- `scripts/check_todo_product_surface.sh` — references it as step 8 (delegates,
  so both stay separately runnable).
- `examples/todo_postgres_app/RUNBOOK.md` — now points at `DEMO.md` as the
  5-minute path (companion-docs list + a "Just want to try it?" line), so the
  fresh demo path is discoverable, not buried under the manual operator steps.

**What it protects (13 checks, all DB-free, all pre-bind):**

- demo script exists + is executable;
- `doctor` refuses missing prerequisites with actionable `MISSING` output (exit 1);
- `start` fails closed (exit 2, REFUSED) **before any socket bind** for: missing
  DSN/token, a `spark`/`prod`/`production` dbname, and a non-loopback host —
  asserted by checking the output never contains `serving on`/`listening http`;
- `smoke`/`html`/`reset` also fail closed on missing env;
- active docs point at the demo path (`DEMO.md` drives `todo_demo.sh
  start|smoke|html`; `RUNBOOK.md` references `DEMO.md`);
- no committed user-facing file (app dir + `todo_demo.sh` + operator smoke)
  carries a raw token / inline-secret DSN (env-var refs + `<placeholder>` + `*_env`
  keys allowed; the CI guard scripts themselves are tooling and out of scope, since
  they legitimately quote the secret patterns).

**What remains operator/local only.** The real local-Postgres demo
(`todo_demo.sh start|smoke|html`) and `todo_postgres_smoke.sh` are unchanged and
still require a dedicated local DB + env vars — the guard never runs them, never
binds a socket, never touches a database. No product/route/feature change; no
production-readiness claim.

**Verification summary (this box):**

- `scripts/check_todo_demo_surface.sh` → 13/13 PASS (run with env scrubbed).
- `scripts/check_todo_product_surface.sh` → PASS (includes the demo guard as step 8; no DB).
- `scripts/check_implemented_surface.sh` → PASS (default tree still postgres-free).
- no trailing whitespace; `git diff --check` clean; new guard is executable.

