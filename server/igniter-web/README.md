# igniter-web

`igniter-web` is the lab home for IgWeb app packaging and the generic `igweb-serve` runner.
It lets an Igniter author run a small web app from authored `.igweb` routes plus `.ig` handlers,
without writing a Rust runner per app.

This is lab v0, not a stable public CLI or canon web framework.

## Mental Model

```text
routes.igweb + handlers.ig + igweb.toml
  -> build_igweb_app(...)
  -> Arc<dyn ServerApp + Send + Sync>
  -> igniter-server loopback runner
```

The server owns transport, loop, concurrency, reload, and middleware mechanics.
The app owns routes, handler contracts, domain types, and logical effect targets.

## Quick Start

From this crate:

```bash
cargo run --bin igweb-serve -- check examples/todo_app
cargo run --bin igweb-serve -- run examples/todo_app
```

`check` dry-builds the app and exits before opening a socket.
`run` builds the app, binds a loopback listener, serves a bounded number of requests, then exits.

The older shortcut still works:

```bash
cargo run --bin igweb-serve -- examples/todo_app
```

## CLI

```text
igweb-serve run [--addr 127.0.0.1:PORT] [--max-requests N] <app_dir>
igweb-serve [--addr 127.0.0.1:PORT] [--max-requests N] <app_dir>
igweb-serve check <app_dir>
igweb-serve --help
```

Commands:

- `run`: build the app and serve a bounded loopback listener.
- `check`: build the app without opening a socket.

Run options:

- `--addr HOST:PORT`: loopback-only bind address. Default: `127.0.0.1:0`.
- `--max-requests N`: override `[server].max_requests` for this process.

Public bind addresses are rejected in v0. The runner is deliberately loopback-only.

## App Directory

Minimal shape:

```text
todo_app/
  igweb.toml
  routes.igweb
  todo_handlers.ig
```

If `[app].sources` is omitted, the runner loads all direct `*.ig` and `*.igweb` files in
deterministic sorted order. The IgWeb prelude is injected by the builder, so apps do not need to
define the shared web request/decision types themselves.

## Manifest

```toml
[app]
entry = "Serve"
# sources = ["todo_handlers.ig", "routes.igweb"]  # optional

[server]
mode = "loopback"
max_requests = 7

[middleware]
trace = true
body_limit_bytes = 65536
# auth_token_env = "TODO_TOKEN"
```

Manifest ownership:

- `[app]`: author-owned app entry and optional source list.
- `[server]`: host/operator process policy.
- `[middleware]`: host/operator wrapper policy.

The manifest cannot declare routes, public bind addresses, inline secrets, capability ids, effect
operations, scopes, or target-to-effect bindings.

## Routes

Example `.igweb`:

```text
app TodoWeb entry Serve {
  handlers TodoHandlers

  route GET  "/health"          -> Health
  route GET  "/todos/:id"       -> TodoShow
  route POST "/todos/:id/done"  -> TodoDone requires idempotency
}
```

`.igweb` lowers deterministically to ordinary `.ig` that calls handler contracts. Path parameters are
implemented through the regexp stdlib substrate; handlers receive them as `Option[String]`.

## Effects

Handlers may return logical `InvokeEffect` decisions, such as target `"todo-done"`.
That target is not capability authority. The actual mapping from logical target to capability,
operation, scope, credentials, and receipts belongs to the host side:
- **Default (Sync) Mode:** Effects are observed as protocol decisions without being executed.
- **Async Machine Mode (`--host-config`):** Real/fake database effects and staged reads are executed dynamically based on the configured policies in `host.toml`.

## Postgres Host Config (Operator)

To run `examples/todo_postgres_app` against a local Postgres, use the committed, commit-safe example
config [`examples/todo_postgres_app/host.example.toml`](examples/todo_postgres_app/host.example.toml).
It references env-var **names** only — it never contains a DSN, password, or bearer token.

```bash
export IGNITER_TODO_PG_DSN="host=localhost user=alex dbname=igniter_todo_test"
export IGNITER_TODO_EFFECT_TOKEN="some-local-bearer-token"

cargo run --features postgres --bin igweb-serve -- \
  --host-config examples/todo_postgres_app/host.example.toml \
  --addr 127.0.0.1:0 \
  --max-requests 8 \
  examples/todo_postgres_app
```

The example wires:

- `[postgres.read]` — real reads, clamped to the `todos` source / field allowlist / row limit.
- `[postgres.write]` — real writes, allowlisted to `insert,upsert` on `todos`.
- `[effects.todo-create]` / `[effects.todo-done]` — both Todo effect targets, bound to route `/w`
  with the bearer token from `IGNITER_TODO_EFFECT_TOKEN`.

**Commit safety.** `host.toml` (the example or any working copy) is commit-safe *by construction*: the
parser rejects inline secret keys (`dsn`, `password`, `secret`, `token`, `passport`, `api_key`) and
template syntax, so the file can only ever hold env-var names. The material that must **never** be
committed is the environment that backs those names — the actual DSN string and bearer token (e.g. a
`.env` file or your shell exports). Use a dedicated local test database (e.g. `igniter_todo_test`),
never a production or SparkCRM database.

### Repeatable smoke

[`scripts/todo_postgres_smoke.sh`](scripts/todo_postgres_smoke.sh) is a one-command operator smoke that
runs the real `igweb-serve --host-config` against a local Postgres and prints a PASS/FAIL receipt. It
reuses the committed `host.example.toml` (so it writes no config file), refuses to run without
`IGNITER_TODO_PG_DSN`, exercises read-found → 200 / read-empty → 404 / write → committed row + receipt /
replay → no second mutation, then cleans up its own rows and exits (bounded, no listener left running).

```bash
export IGNITER_TODO_PG_DSN="host=localhost user=alex dbname=igniter_todo_test"
server/igniter-web/scripts/todo_postgres_smoke.sh
```

This is the human-runnable companion to the in-harness P12 Cargo subprocess test.

## Current Limits

- No stable CLI promise.
- No source map from `.igweb` back to generated `.ig` diagnostics yet.
- No file watcher or auto-reload.
- No package manager or package manifest.
- No public listener mode.
- No inline secrets (secrets must be mapped from the environment; inline secrets in `host.toml` are rejected at parse time).
- Live external effect execution is limited to local Postgres or fake database capability adapters under the `--host-config` flag.

Those omissions are intentional for the lab v0 safety envelope.

## Runner & Database Status Matrix

| Component / Layer | Status | Target / Feature Gate | Description |
| :--- | :--- | :--- | :--- |
| **`igweb-serve` CLI** | **Lab Prototype** | `igweb-serve` binary | Not a stable public CLI. Loopback-only. |
| **Sync Mode** (default) | **Implemented** | Default build (no-cfg) | Bounded sync request loop using observed effects (no execution). |
| **Async Machine Mode** | **Implemented** | `--host-config <file>` + `machine` feature | Async tokio loop, parsing `host.toml`, executing raw/staged reads and writes. |
| **Extracted Core E2E** | **Proven** | Cargo tests (e.g. `todo_igweb_serve_e2e_tests`) | In-process testing of the serving/effect loop; does NOT spawn subprocesses in cargo tests. |
| **Subprocess CLI E2E** | **Proven** | `postgres` feature + `IGNITER_TODO_PG_DSN` | Cargo test spawns the compiled `igweb-serve` binary and drives read/write/replay over loopback; skips cleanly without DSN. |
| **Fake DB Adapters** | **Proven** | Default VM & Runner tests | In-memory read/write simulation of Postgres; default path for tests. |
| **Real Postgres (Read)** | **Wired + Proven** | `postgres` feature + `[postgres.read]` in `host.toml` | `igweb-serve` builds a real read executor from resolved DSN and host policy; P12 proves read found/empty through subprocess. |
| **Real Postgres (Write)** | **Wired + Proven** | `postgres` feature + `[postgres.write]` + `[effects.*]` in `host.toml` | `igweb-serve` builds a real write effect host from resolved DSN, policy, and bearer token; P12 proves write/replay through subprocess. |
