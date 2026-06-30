# todo_postgres_app — 5-minute local DEMO

**The human-facing entrypoint.** Run the real `todo_postgres_app` product path
(`igweb-serve --features postgres --host-config`) against a dedicated local
Postgres in under five minutes — no proof packets required.

> **Status:** lab demo. **Loopback-only, dedicated local Postgres only, NOT
> production.** No stable CLI/API promise. Never point this at a production or
> SparkCRM database.

For depth once the demo makes sense, read [RUNBOOK.md](RUNBOOK.md) (one-page
operator guide), [API.md](API.md) (route/status contract), and
[EXAMPLES.md](EXAMPLES.md) (raw curl).

---

## 1. Prerequisites

You need three things on your machine:

| Tool      | Why                                  |
| --------- | ------------------------------------ |
| `cargo`   | builds the `igweb-serve` binary      |
| `psql`    | creates the demo DB + checks rows    |
| `curl`    | drives the HTTP API in `smoke`/`html`|

Plus a running **local** Postgres you can create a database in.

Two environment variables hold the only secrets — they live in your shell, never
on disk, and are never echoed by the demo:

```bash
export IGNITER_TODO_PG_DSN="host=localhost user=$USER dbname=igniter_todo_demo"
export IGNITER_TODO_EFFECT_TOKEN="dev-token"
```

Create the dedicated demo database once:

```bash
createdb igniter_todo_demo
```

> The demo refuses any DSN whose host is not loopback, or whose dbname contains
> `spark`, `prod`, or `production`.

---

## 2. Exact commands

From `server/igniter-web/`:

```bash
# 0. Verify your machine is ready (tools + env vars).
scripts/todo_demo.sh doctor

# 1. Build + start the real product server on a loopback ephemeral port.
#    Prints  BASE=http://127.0.0.1:<port>
scripts/todo_demo.sh start

# 2. Drive the full API cycle against the real Postgres.
scripts/todo_demo.sh smoke

# 3. Prove the HTML route returns escaped text/html.
scripts/todo_demo.sh html

# 4. (any time) See whether the server is up — no secrets printed.
scripts/todo_demo.sh status

# 5. Stop the server — no listener remains.
scripts/todo_demo.sh stop
```

---

## 3. What each command proves

| Command  | Proves |
| -------- | ------ |
| `doctor` | `cargo`/`curl`/`psql` present; both env vars set; DSN is loopback + not a prod/Spark name. Actionable lines for anything missing. |
| `start`  | Builds `igweb-serve --features postgres`, ensures demo-owned schema + a `acct-demo` account (idempotent DDL), starts the **real** product path bound to `127.0.0.1:<ephemeral>`, writes a small state file, prints `BASE=`. |
| `smoke`  | Real API cycle on the real DB: `health 200` → missing account `404` → existing-empty `200 []` → `create 200` → `create replay 200` (no 2nd write) → `list 200` carries title → surrogate `todo_<hash>` id discovered → `show 200` → `done 200` + replay → `delete 200` + replay → `show 404`. Cleans up its own rows. |
| `html`   | `GET /accounts/:id/todos.html` returns `200` with `Content-Type: text/html`, structural HTML, and **no raw `<script>`** (the renderer escapes by construction). |
| `status` | Prints RUNNING/NOT RUNNING + PID + BASE + log path. Never echoes DSN or token. |
| `stop`   | Terminates the server and clears the state file; no listener is left behind. |
| `reset`  | Deletes only demo-owned rows (`acct-demo` todos + `demo-*` receipts), re-seeds the `acct-demo` account. Does not touch the server. |

---

## 4. Stop & reset

```bash
scripts/todo_demo.sh stop     # stop the server
scripts/todo_demo.sh reset    # wipe demo-owned rows (server can stay up or down)
```

`reset` is row-scoped: it removes only the `acct-demo` todos and `demo-`-prefixed
receipts and re-seeds the `acct-demo` account. It never drops tables or touches
non-demo data.

To remove everything, drop the dedicated database yourself:

```bash
dropdb igniter_todo_demo
```

---

## 5. Known limitations (intentional v0)

- **Loopback / local only** — no daemon, no deploy, no hosting story. Binds
  `127.0.0.1` on an ephemeral port; a non-loopback bind is refused.
- **No schema migrations** — the demo's `start` runs explicit demo-owned
  `CREATE TABLE IF NOT EXISTS` DDL. The runner itself never migrates.
- **Bounded server** — `start` serves up to a fixed request budget
  (`--max-requests`), enough for many `smoke`/`html` runs; restart with `stop`
  then `start` if you exhaust it.
- **State file** — server PID/port live in `/tmp/igniter_todo_demo.state`; the
  server log is `/tmp/igniter_todo_demo.log`. Both are local, secret-free, and
  cleared by `stop`.
- **Surrogate ids, object create body, no pooling** — same v0 constraints as the
  product surface; see [RUNBOOK.md §5](RUNBOOK.md).
- **Read freshness needs a fresh correlation id** — the app runs with `trace = true`
  (`igweb.toml`), so when a client sends no `x-correlation-id` the host derives a
  deterministic one from `(method+path+body)`. Two *identical* GETs then share a
  correlation and the host **replays** the first read's snapshot (read replay is keyed
  on `correlation + plan`, P23). The demo's `smoke`/`html` therefore send a **unique
  `x-correlation-id` per read** so each read observes current state — this is the
  documented opt-in: a unique nonce ⇒ fresh read, a reused correlation ⇒ replay a
  retry. A naive client that re-issues the same GET twice without correlation will see
  the earlier snapshot.
- **Not the operator smoke** — for the contract-grade receipt used in CI/proofs,
  `scripts/todo_postgres_smoke.sh` still runs the full assertion set. This demo
  wraps the same product binary for human DX; it does not replace that smoke.

---

## 6. Safety boundary

- **Loopback only.** Refuses any non-`localhost`/`127.0.0.1`/`::1` host.
- **Dedicated DB only.** Default `igniter_todo_demo`; refuses dbnames containing
  `spark`, `prod`, or `production`.
- **No inline secrets.** DSN and token come from the environment; nothing is
  written to a committed file.
- **No DSN/token echo.** No command prints either value.
- **No production claim.** This is a lab demo, not a stable or hosted API.
- **Row-scoped writes only.** `reset` and `smoke` cleanup touch only
  demo-owned rows; no blanket wipes, no DDL drops.

---

## 7. If something fails

| Symptom | Likely cause | Fix |
| ------- | ------------ | --- |
| `doctor` says a tool is MISSING | `cargo`/`psql`/`curl` not on `PATH` | install it |
| `start` REFUSED at preflight | env var unset, non-loopback host, or prod/Spark dbname | fix the DSN / token env vars |
| `start` ERROR "cargo build failed" | compile error in the crate | read the printed cargo output |
| `start` ERROR "did not report a listening port" | DB unreachable / port issue | check Postgres is up; see `/tmp/igniter_todo_demo.log` |
| `smoke`/`html` "server is not running" | no `start` yet, or it was stopped | run `scripts/todo_demo.sh start` |
| a `smoke` row shows `FAIL` | product/DB mismatch | inspect `/tmp/igniter_todo_demo.log` |

(Coded server-side exit/HTTP failures are tabled in
[RUNBOOK.md §4](RUNBOOK.md).)
